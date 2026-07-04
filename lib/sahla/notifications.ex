defmodule Sahla.Notifications do
  @moduledoc """
  Reliable, exactly-once outbound delivery (§7.3, §8, §10.7).

  Every SMS and email is sent through an Oban job rather than inline, so sends
  are retried with backoff and never lost. `deliver_sms/1` and `deliver_email/1`
  enqueue those jobs (unique per `idempotency_key`, so a duplicate enqueue is a
  no-op). The workers call back into `run_sms/2` / `run_email/2`, which share one
  pipeline:

    1. record (or reload) a `queued` `DeliveryLog` keyed by `idempotency_key`;
    2. short-circuit if it is already `sent`/terminal — the exactly-once guard;
    3. honour the kill-switch/allowlist (a denial cancels the job, no retry storm);
    4. invoke the provider/mailer, then apply the outcome
       (`sent` + `provider_id`/`cost` or `failed`) atomically in a transaction.

  A transient provider error is returned to Oban so it retries with backoff; only
  once attempts are exhausted is the log marked `failed`.
  """
  alias Sahla.Notifications.{DeliveryLog, Email, Log, SMS}
  alias Sahla.Notifications.Workers.{EmailWorker, SMSWorker}
  alias Sahla.Repo

  @type enqueue_result :: {:ok, Oban.Job.t()} | {:error, term()}

  # --- async enqueue entrypoints ---------------------------------------------

  @doc """
  Enqueues an SMS for delivery. `params` needs `:to`, `:template` and
  `:idempotency_key`, plus optional `:vars`. Returns `Oban.insert/1`'s result;
  a second call with the same `idempotency_key` returns the existing job.
  """
  @spec deliver_sms(map()) :: enqueue_result()
  def deliver_sms(%{to: to, template: template, idempotency_key: key} = params) do
    %{
      "to" => to,
      "template" => to_string(template),
      "vars" => stringify(Map.get(params, :vars, %{})),
      "idempotency_key" => key
    }
    |> SMSWorker.new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a transactional email. `params` needs `:to`, `:kind` (e.g.
  `:resume_link`) and `:idempotency_key`; remaining keys (`:locale`, `:url`,
  `:first_name`, …) are carried to the builder.
  """
  @spec deliver_email(map()) :: enqueue_result()
  def deliver_email(%{to: to, kind: kind, idempotency_key: key} = params) do
    args = params |> Map.drop([:to, :kind, :idempotency_key]) |> stringify()

    %{"to" => to, "kind" => to_string(kind), "args" => args, "idempotency_key" => key}
    |> EmailWorker.new()
    |> Oban.insert()
  end

  # --- worker entrypoints (synchronous delivery core) ------------------------

  @doc false
  def run_sms(%{"to" => to, "template" => template, "idempotency_key" => key} = args, job) do
    vars = Map.get(args, "vars", %{})

    deliver(
      %{channel: :sms, recipient: to, template: template, payload: vars, idempotency_key: key},
      job,
      fn -> SMS.send(to, template, vars) end
    )
  end

  @doc false
  def run_email(%{"to" => to, "kind" => kind, "idempotency_key" => key} = args, job) do
    email_args = Map.get(args, "args", %{})

    deliver(
      %{
        channel: :email,
        recipient: to,
        template: kind,
        payload: email_args,
        idempotency_key: key
      },
      job,
      fn -> send_email(kind, to, email_args) end
    )
  end

  # --- the pipeline ----------------------------------------------------------

  defp deliver(log_attrs, %Oban.Job{} = job, send_fun) do
    with {:ok, log} <- ensure_queued(log_attrs) do
      cond do
        settled?(log) ->
          # Already sent or terminal — the exactly-once no-op.
          :ok

        not channel_enabled?(log_attrs.channel) ->
          fail(log)
          {:cancel, :disabled}

        true ->
          dispatch(log, send_fun.(), job)
      end
    end
  end

  # Records the queued log, or reloads the one a previous attempt left behind
  # (its unique idempotency_key makes the re-insert a conflict, not a duplicate).
  defp ensure_queued(attrs) do
    case Log.record(attrs) do
      {:ok, log} ->
        {:ok, log}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :idempotency_key) do
          {:ok, Repo.get_by!(DeliveryLog, idempotency_key: attrs.idempotency_key)}
        else
          error
        end
    end
  end

  defp dispatch(log, {:ok, %{provider_id: provider_id, cost_centimes: cost}}, _job) do
    finalize(log, :sent, %{provider_id: provider_id, cost_centimes: cost, sent_at: now()})
    :ok
  end

  # Kill-switch / allowlist denials are permanent for this send: cancel, no retry.
  defp dispatch(log, {:error, reason}, _job) when reason in [:disabled, :recipient_not_allowed] do
    fail(log)
    {:cancel, reason}
  end

  # Any other provider error is transient: retry via Oban until attempts run out.
  defp dispatch(log, {:error, reason}, %Oban.Job{attempt: attempt, max_attempts: max}) do
    if attempt >= max do
      fail(log)
      {:cancel, reason}
    else
      {:error, reason}
    end
  end

  # Applies a status transition exactly once: a log already in a terminal status
  # is left untouched even if two paths race to finalize it.
  defp finalize(log, status, attrs) do
    Repo.transaction(fn ->
      current = Repo.get!(DeliveryLog, log.id)

      if DeliveryLog.terminal?(current.status) do
        current
      else
        {:ok, updated} =
          current
          |> DeliveryLog.status_changeset(Map.put(attrs, :status, status))
          |> Repo.update()

        updated
      end
    end)
  end

  defp fail(log), do: finalize(log, :failed, %{})

  defp settled?(%DeliveryLog{status: :sent}), do: true
  defp settled?(%DeliveryLog{status: status}), do: DeliveryLog.terminal?(status)

  defp channel_enabled?(:sms), do: SMS.enabled?()
  defp channel_enabled?(:email), do: Email.enabled?()

  # Builds and delivers the email, normalising the mailer result to the same
  # `{:ok, %{provider_id:, cost_centimes:}}` shape the SMS provider returns.
  defp send_email(kind, to, args) do
    case Email.deliver(build_email(kind, to, args)) do
      {:ok, meta} -> {:ok, %{provider_id: email_provider_id(meta), cost_centimes: 0}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_email("resume_link", to, args), do: Email.resume_link(email_attrs(to, args))

  defp email_attrs(to, args) do
    %{to: to, locale: locale(args["locale"]), url: args["url"]}
    |> maybe_put(:first_name, args["first_name"])
  end

  defp locale(nil), do: :fr
  defp locale(loc) when loc in ["fr", "ar"], do: String.to_existing_atom(loc)
  defp locale(_), do: :fr

  defp email_provider_id(meta) when is_map(meta) do
    case Map.get(meta, :id) do
      nil -> nil
      id -> to_string(id)
    end
  end

  defp email_provider_id(_meta), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
