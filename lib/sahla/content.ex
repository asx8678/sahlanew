defmodule Sahla.Content do
  @moduledoc """
  Content context (§10.6, §12): the versioned legal/consent-text manager.

  Each consent records the exact `text_version` shown to the user, so the wording
  behind every grant is reconstructable. Versions are **append-only** — a new
  wording is a new draft version, never an edit of a published one — and
  publishing the highest version makes it the current text for that key.

  Mutations (`create_version/2`, `publish/2`) are superadmin-gated via
  `Policy.can?(role, :manage_legal_texts)` and audited through `Sahla.Audit`. The
  consent-capture API (`Sahla.Compliance`) reads `current_version/1` to stamp the
  version — it integrates with this manager rather than duplicating it.
  """
  import Ecto.Query, only: [from: 2]

  alias Sahla.Accounts.{Admin, Policy}
  alias Sahla.Audit
  alias Sahla.Content.LegalText
  alias Sahla.Repo

  @doc "The legal-text keys this manager tracks."
  def keys, do: LegalText.keys()

  @doc """
  Creates the next **draft** version for `key` with the given bodies. `attrs`:
  `:body_fr` (required), `:body_ar`. `opts` requires `:actor` (a superadmin
  `%Admin{}`); the create is audited.

  Returns `{:ok, legal_text}`, `{:error, :forbidden}`, or `{:error, changeset}`.
  """
  def create_version(key, attrs, opts) do
    with :ok <- authorize(opts) do
      attrs =
        attrs
        |> Map.new()
        |> Map.put(:key, key)
        |> Map.put(:version, next_version(key))

      Repo.transaction(fn ->
        legal_text = insert_or_rollback(LegalText.changeset(%LegalText{}, attrs))

        audit!(opts, "legal_text.create", legal_text, %{
          "key" => to_string(key),
          "version" => legal_text.version
        })

        legal_text
      end)
    end
  end

  @doc """
  Publishes a **draft** version, making it the current text for its key. `opts`
  requires `:actor` (a superadmin `%Admin{}`); the publish is audited.

  Returns `{:ok, legal_text}`, `{:error, :forbidden}`, `{:error, :not_draft}`
  (already published), or `{:error, changeset}`.
  """
  def publish(%LegalText{status: :published}, _opts), do: {:error, :not_draft}

  def publish(%LegalText{status: :draft} = legal_text, opts) do
    with :ok <- authorize(opts) do
      actor = Keyword.fetch!(opts, :actor)
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.transaction(fn ->
        published =
          update_or_rollback(LegalText.publish_changeset(legal_text, actor.id, now))

        audit!(opts, "legal_text.publish", published, %{
          "key" => to_string(published.key),
          "version" => published.version
        })

        published
      end)
    end
  end

  @doc "The current (highest-version published) text for `key`, or `nil`."
  def current(key) do
    Repo.one(
      from t in LegalText,
        where: t.key == ^key and t.status == :published,
        order_by: [desc: t.version],
        limit: 1
    )
  end

  @doc "The current published version number for `key`, or `nil` if none is published."
  def current_version(key) do
    case current(key) do
      nil -> nil
      %LegalText{version: version} -> version
    end
  end

  @doc "The current published body for `key` in `locale` (`:fr`/`:ar`), or `nil`."
  def current_body(key, locale) do
    case current(key) do
      nil -> nil
      text -> body_for(text, locale)
    end
  end

  @doc "Every version for `key`, newest first (append-only history)."
  def history(key) do
    Repo.all(from t in LegalText, where: t.key == ^key, order_by: [desc: t.version])
  end

  def get_version!(id), do: Repo.get!(LegalText, id)

  # -- internals --------------------------------------------------------------

  defp next_version(key) do
    max = Repo.one(from t in LegalText, where: t.key == ^key, select: max(t.version))
    (max || 0) + 1
  end

  defp body_for(%LegalText{body_ar: body}, :ar) when is_binary(body), do: body
  defp body_for(%LegalText{body_fr: body}, _locale), do: body

  defp authorize(opts) do
    case Keyword.get(opts, :actor) do
      %Admin{role: role} ->
        if Policy.can?(role, :manage_legal_texts), do: :ok, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp audit!(opts, action, %LegalText{} = text, after_map) do
    result =
      Audit.log(%{
        admin_id: Keyword.fetch!(opts, :actor).id,
        action: action,
        entity: "legal_text",
        entity_id: text.id,
        after: after_map,
        ip: Keyword.get(opts, :ip)
      })

    case result do
      {:ok, entry} -> entry
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
