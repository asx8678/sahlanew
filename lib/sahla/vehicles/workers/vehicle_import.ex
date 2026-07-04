defmodule Sahla.Vehicles.Workers.VehicleImport do
  @moduledoc """
  Ingests a vehicle-catalog CSV as an Oban job (queue `:imports`, §7.3).
  Delegates to `Sahla.Vehicles.Import` and logs the outcome summary; the import
  is idempotent, so a retry or duplicate enqueue is safe.
  """
  use Sahla.Worker, queue: :imports

  require Logger

  alias Sahla.Vehicles.Import

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"csv" => csv}}) do
    summary = Import.import_csv(csv)

    Logger.info("vehicle catalog import: #{inspect(Map.delete(summary, :errors))}")

    {:ok, summary}
  end
end
