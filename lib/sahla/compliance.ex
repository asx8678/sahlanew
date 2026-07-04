defmodule Sahla.Compliance do
  @moduledoc """
  Consent capture for the funnel's lead gate (§5.2 step 4, §8, §12).

  `capture_consents/2` records one row per consent kind (CGU+privacy,
  transmission, marketing) with the current legal text version, the request IP
  and a timestamp. The two required consents (CGU and transmission) must be
  granted or it returns `{:error, :consent_required}` and writes nothing — this
  is the gate the lead creation depends on. Only non-PII is stored; any extra
  map is passed through `Sahla.Security.SafeRaw`.
  """
  import Ecto.Query, only: [from: 2]

  alias Sahla.Accounts.{Admin, Policy}
  alias Sahla.Audit
  alias Sahla.Compliance.Consent
  alias Sahla.Content
  alias Sahla.Hashed.HMAC
  alias Sahla.Notifications.DeliveryLog
  alias Sahla.Quoting.Quote
  alias Sahla.Repo
  alias Sahla.Security.SafeRaw
  alias Sahla.Settings

  @default_text_version "v1"

  # PII columns nulled on erasure; structural/rating fields stay as anonymous
  # stats and `phone_hash` stays as a one-way pseudonym so the tombstone remains
  # findable and re-erasure is idempotent.
  @scrubbed_pii [
    :phone_enc,
    :first_name,
    :last_name,
    :email,
    :plate,
    :releve_doc_path,
    :ip,
    :user_agent,
    :phone_verified_at
  ]

  @doc """
  Records the user's consent choices for `quote`. `attrs` carries the grant flags
  (`:cgu`/`:consent_cgu`, `:transmission`/`:consent_transmission`,
  `:marketing`/`:consent_marketing`), plus optional `:ip`, `:text_version` and a
  non-PII `:extra` map.

  Returns `{:ok, [consent]}` once the required consents are granted, or
  `{:error, :consent_required}` (nothing written) otherwise.
  """
  def capture_consents(%Quote{} = quote, attrs) do
    attrs = Map.new(attrs)
    grants = grants(attrs)

    if Enum.all?(Consent.required_kinds(), &grants[&1]) do
      do_capture(quote, grants, attrs)
    else
      {:error, :consent_required}
    end
  end

  @doc "All recorded consents for a quote."
  def consents_for(%Quote{id: id}) do
    Repo.all(from c in Consent, where: c.quote_id == ^id)
  end

  @doc """
  Data-subject erasure (§12, §10.3): scrubs every trace of `phone`'s PII across
  quotes, consents and the notifications log in one transaction, then writes an
  audit entry recording who erased which target hash.

  `phone` is the plaintext number (the caller decrypts `phone_enc` to display the
  record, so it has it); the keyed HMAC handles the cross-table lookup. Encrypted
  and free-text PII columns are nulled while anonymous stats (status, vehicle,
  rating inputs, message counts) are retained; each quote is stamped `erased_at`
  as a tombstone. Re-running is a safe no-op.

  `opts`: `:actor` (the `%Admin{}` performing it — **required**, authorized via
  `Policy.can?(role, :erase_person)`; superadmin/ops only) and `:ip`.

  Returns `{:ok, %{quotes:, consents:, messages:, target_hash:}}`,
  `{:error, :forbidden}` for an unauthorized (or missing) actor, or
  `{:error, reason}` on rollback.
  """
  def erase_person(phone, opts \\ []) when is_binary(phone) do
    actor = Keyword.get(opts, :actor)

    if authorized?(actor) do
      do_erase(phone, actor, opts)
    else
      {:error, :forbidden}
    end
  end

  defp authorized?(%Admin{role: role}), do: Policy.can?(role, :erase_person)
  defp authorized?(_), do: false

  defp do_erase(phone, actor, opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    {:ok, digest} = HMAC.dump(phone)
    target_hash = Base.encode16(digest, case: :lower)

    Repo.transaction(fn ->
      quote_ids = Repo.all(from q in Quote, where: q.phone_hash == ^phone, select: q.id)

      {quotes, _} =
        Repo.update_all(
          from(q in Quote, where: q.phone_hash == ^phone),
          set: scrub_set(now)
        )

      {consents, _} =
        Repo.update_all(
          from(c in Consent, where: c.quote_id in ^quote_ids),
          set: [ip: nil, updated_at: now]
        )

      {messages, _} =
        Repo.update_all(
          from(l in DeliveryLog, where: l.to_hash == ^phone),
          set: [to_hash: nil, updated_at: now]
        )

      counts = %{quotes: quotes, consents: consents, messages: messages}
      audit_erasure!(actor, target_hash, counts, opts)

      Map.put(counts, :target_hash, target_hash)
    end)
  end

  defp scrub_set(now) do
    Enum.map(@scrubbed_pii, &{&1, nil}) ++ [erased_at: now, updated_at: now]
  end

  defp audit_erasure!(actor, target_hash, counts, opts) do
    result =
      Audit.log(%{
        admin_id: actor && actor.id,
        action: "erase_person",
        entity: "person",
        entity_id: target_hash,
        after: %{
          "quotes" => counts.quotes,
          "consents" => counts.consents,
          "messages" => counts.messages
        },
        ip: Keyword.get(opts, :ip)
      })

    case result do
      {:ok, entry} -> entry
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp do_capture(quote, grants, attrs) do
    ip = attrs[:ip]
    metadata = SafeRaw.safe_raw(Map.get(attrs, :extra, %{}))
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.transaction(fn ->
      Enum.map(grants, fn {kind, granted} ->
        %Consent{}
        |> Consent.changeset(%{
          quote_id: quote.id,
          kind: kind,
          text_version: consent_version(kind, attrs),
          granted: granted,
          ip: ip,
          granted_at: now,
          metadata: metadata
        })
        |> Repo.insert!(
          on_conflict:
            {:replace, [:granted, :text_version, :ip, :granted_at, :metadata, :updated_at]},
          conflict_target: [:quote_id, :kind]
        )
      end)
    end)
  end

  defp grants(attrs) do
    %{
      cgu: truthy(attrs[:cgu] || attrs[:consent_cgu]),
      transmission: truthy(attrs[:transmission] || attrs[:consent_transmission]),
      marketing: truthy(attrs[:marketing] || attrs[:consent_marketing])
    }
  end

  defp truthy(true), do: true
  defp truthy(_), do: false

  # The version stamped on a consent: an explicit override, else the current
  # published legal-text version for that kind (rao.11), else the Settings default.
  defp consent_version(kind, attrs) do
    cond do
      version = attrs[:text_version] -> version
      version = Content.current_version(kind) -> "v#{version}"
      true -> text_version()
    end
  end

  defp text_version, do: Settings.get("consent_text_version", @default_text_version)
end
