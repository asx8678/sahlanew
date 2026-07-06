defmodule Sahla.Leads do
  @moduledoc """
  The authoritative Leads API (§7.2, §10.2). Every admin LiveView and real-time
  tile calls this context — never the Repo directly.

  Responsibilities:

    * `create_from_quote/2` — turn a completed quote (+ chosen offer) into a lead,
      snapshotting source and `offer_id` and logging a creation activity.
    * `transition_status/3` — move a lead through the legal state graph, enforcing
      terminal states and the `perdu`/`loss_reason` rule.
    * `log_activity/2` and `log_message_event/2` — append timeline entries; the
      latter is the documented boundary Notifications uses for inbound
      SMS/WhatsApp/callback events (no Repo reach-in from other contexts).

  Every mutation is wrapped in a transaction and, on commit, broadcasts
  `{:lead, :created | :updated, id}` on the `"leads"` topic and the assigned
  agent's topic so kanban/dashboard views update live.
  """
  import Ecto.Query, only: [from: 2]

  alias Phoenix.PubSub
  alias Sahla.Leads.{Activity, Lead, Pipeline}
  alias Sahla.Quoting.Quote
  alias Sahla.Repo
  alias Sahla.Telemetry.Funnel, as: FunnelTelemetry

  @pubsub Sahla.PubSub
  @topic "leads"

  # Data-driven legal transitions (§10.2). Terminal statuses have no successors.
  @transitions %{
    nouveau: [:contacte, :rdv_planifie, :devis_envoye, :relance, :perdu],
    contacte: [:rdv_planifie, :devis_envoye, :relance, :gagne, :perdu],
    rdv_planifie: [:contacte, :devis_envoye, :relance, :gagne, :perdu],
    devis_envoye: [:rdv_planifie, :relance, :gagne, :perdu],
    relance: [:contacte, :rdv_planifie, :devis_envoye, :gagne, :perdu],
    gagne: [],
    perdu: []
  }

  @terminal for {status, []} <- @transitions, into: MapSet.new(), do: status

  # Activity kinds a notification/event boundary may append.
  @event_kinds [:sms, :whatsapp, :appel, :email, :rdv]

  @doc "The legal transition graph (`%{status => [allowed_next]}`)."
  def transitions, do: @transitions

  @doc "The terminal statuses (no outgoing transitions)."
  def terminal_statuses, do: MapSet.to_list(@terminal)

  @doc "Whether `status` is terminal."
  def terminal?(status), do: MapSet.member?(@terminal, status)

  @doc "Fetches a lead by id, raising if absent."
  def get_lead!(id), do: Repo.get!(Lead, id)

  @doc "Fetches a lead by id or returns nil."
  def get_lead(id), do: Repo.get(Lead, id)

  @doc "A lead's timeline, most recent first."
  def list_activities(%Lead{id: id}) do
    Repo.all(
      from a in Activity, where: a.lead_id == ^id, order_by: [desc: a.happened_at, desc: a.id]
    )
  end

  @doc """
  Creates a lead from `quote`, snapshotting `:source` (falling back to the
  quote's UTM source) and `:offer_id`. Emits a `:created` broadcast and a
  creation activity. Returns `{:ok, lead}` or `{:error, changeset}` (e.g. a
  quote that already has a lead).
  """
  def create_from_quote(%Quote{} = quote, attrs \\ %{}) do
    attrs = Map.new(attrs)

    lead_attrs = %{
      quote_id: quote.id,
      offer_id: Map.get(attrs, :offer_id),
      source: Map.get(attrs, :source) || derive_source(quote),
      priority: Map.get(attrs, :priority, 0),
      callback_at: Map.get(attrs, :callback_at)
    }

    transaction(fn ->
      lead = insert_or_rollback(Lead.changeset(%Lead{}, lead_attrs))

      insert_activity!(lead, %{
        kind: :statut,
        admin_id: Map.get(attrs, :admin_id),
        metadata: %{"event" => "created", "from" => nil, "to" => to_string(lead.status)}
      })

      lead
    end)
    |> emit(:created)
    |> maybe_auto_assign()
  end

  defp maybe_auto_assign({:ok, lead}), do: Pipeline.auto_assign(lead)
  defp maybe_auto_assign(other), do: other

  @doc "Broadcasts an `:updated` event for `lead` (used by the assignment pipeline)."
  def broadcast_update(%Lead{} = lead), do: broadcast(:updated, lead)

  @doc """
  Transitions `lead` to `new_status`, enforcing the legal graph and the
  `perdu`/`loss_reason` rule. Same-status is an idempotent no-op; leaving a
  terminal status is refused.

  `opts`: `:loss_reason` (required for `perdu`), `:admin_id`, `:note`.

  Returns `{:ok, lead}`, `{:error, {:illegal_transition, from, to}}`,
  `{:error, :terminal}`, or `{:error, changeset}` (e.g. missing loss_reason).
  """
  def transition_status(%Lead{} = lead, new_status, opts \\ []) do
    cond do
      new_status == lead.status ->
        {:ok, lead}

      terminal?(lead.status) ->
        {:error, :terminal}

      new_status not in Map.fetch!(@transitions, lead.status) ->
        {:error, {:illegal_transition, lead.status, new_status}}

      true ->
        do_transition(lead, new_status, opts)
    end
  end

  defp do_transition(lead, new_status, opts) do
    from_status = lead.status

    transaction(fn ->
      updated = update_or_rollback(Lead.status_changeset(lead, status_attrs(new_status, opts)))

      insert_activity!(updated, %{
        kind: :statut,
        admin_id: Keyword.get(opts, :admin_id),
        body: Keyword.get(opts, :note),
        metadata: %{"from" => to_string(from_status), "to" => to_string(new_status)}
      })

      updated
    end)
    |> emit(:updated)
  end

  @doc """
  Appends a timeline `Activity` to `lead` and broadcasts `:updated`. `attrs`
  carries `:kind` (required) and optionally `:body`, `:metadata`, `:admin_id`.
  """
  def log_activity(%Lead{} = lead, attrs) do
    attrs = attrs |> Map.new() |> Map.put(:lead_id, lead.id)

    case %Activity{} |> Activity.changeset(attrs) |> Repo.insert() do
      {:ok, activity} ->
        broadcast(:updated, lead)
        {:ok, activity}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Documented boundary for Notifications: append an inbound message/event
  (`:sms | :whatsapp | :appel | :email | :rdv`) to a lead's timeline as a
  system-generated (`admin_id: nil`) activity. Accepts a `%Lead{}` or a lead id.
  """
  def log_message_event(lead, attrs) do
    attrs = Map.new(attrs)
    kind = Map.fetch!(attrs, :kind)

    unless kind in @event_kinds do
      raise ArgumentError,
            "log_message_event/2 kind must be one of #{inspect(@event_kinds)}, got #{inspect(kind)}"
    end

    lead |> resolve_lead() |> log_activity(Map.put(attrs, :admin_id, nil))
  end

  @doc "Subscribes the caller to the global `\"leads\"` topic."
  def subscribe, do: PubSub.subscribe(@pubsub, @topic)

  @doc "Subscribes the caller to a single agent's lead topic."
  def subscribe_agent(admin_id), do: PubSub.subscribe(@pubsub, agent_topic(admin_id))

  # --- internals ---

  defp status_attrs(:perdu, opts),
    do: %{status: :perdu, loss_reason: Keyword.get(opts, :loss_reason)}

  defp status_attrs(status, _opts), do: %{status: status}

  defp derive_source(%Quote{utm: utm}) when is_map(utm), do: Map.get(utm, "utm_source", "site")
  defp derive_source(_quote), do: "site"

  defp resolve_lead(%Lead{} = lead), do: lead
  defp resolve_lead(id) when is_binary(id), do: get_lead!(id)

  defp insert_activity!(lead, attrs) do
    %Activity{}
    |> Activity.changeset(Map.put(attrs, :lead_id, lead.id))
    |> Repo.insert!()
  end

  defp transaction(fun), do: Repo.transaction(fun)

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

  defp emit({:ok, lead}, :created) do
    FunnelTelemetry.lead_created(
      to_string(lead.id),
      to_string(lead.quote_id),
      to_string(lead.source || "site")
    )

    broadcast(:created, lead)
    {:ok, lead}
  end

  defp emit({:ok, lead}, event) do
    broadcast(event, lead)
    {:ok, lead}
  end

  defp emit({:error, reason}, _event), do: {:error, reason}

  defp broadcast(event, %Lead{} = lead) do
    message = {:lead, event, lead.id}
    PubSub.broadcast(@pubsub, @topic, message)

    if lead.assigned_admin_id do
      PubSub.broadcast(@pubsub, agent_topic(lead.assigned_admin_id), message)
    end

    :ok
  end

  defp agent_topic(admin_id), do: "#{@topic}:agent:#{admin_id}"
end
