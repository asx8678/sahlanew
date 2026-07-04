defmodule Sahla.Directory.Workers.ProductMatrixImport do
  @moduledoc """
  Ingests a product/guarantee matrix CSV as an Oban job (queue `:imports`,
  §10.5). Delegates to `Sahla.Directory.Import` and logs the outcome summary;
  the import is idempotent, so a retry or duplicate enqueue is safe.
  """
  use Sahla.Worker, queue: :imports

  require Logger

  alias Sahla.Directory.Import

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"csv" => csv}}) do
    summary = Import.import_csv(csv)

    Logger.info("product matrix import: #{inspect(Map.delete(summary, :errors))}")

    {:ok, summary}
  end
end
