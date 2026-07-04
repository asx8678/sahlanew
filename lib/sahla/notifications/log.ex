defmodule Sahla.Notifications.Log do
  @moduledoc """
  Boundary for the delivery log (§10.7): record a message and update its status
  from provider callbacks. Terminal statuses are immutable.
  """
  alias Sahla.Notifications.DeliveryLog
  alias Sahla.Repo

  @doc "Records (or queues) a message. Returns `{:error, changeset}` on a duplicate idempotency key."
  def record(attrs) do
    %DeliveryLog{}
    |> DeliveryLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a logged message's status by `provider_id`. A message already in a
  terminal status (`delivered`/`failed`) is left unchanged.
  """
  def update_status(provider_id, status, attrs \\ %{}) do
    case Repo.get_by(DeliveryLog, provider_id: provider_id) do
      nil ->
        {:error, :not_found}

      %DeliveryLog{status: current} = log ->
        if DeliveryLog.terminal?(current) do
          {:ok, log}
        else
          log
          |> DeliveryLog.status_changeset(Map.put(attrs, :status, status))
          |> Repo.update()
        end
    end
  end
end
