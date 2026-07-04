defmodule Sahla.Notifications.Workers.EmailWorker do
  @moduledoc """
  Delivers a queued transactional email as an Oban job (queue `:email`, §7.3).
  Unique per `idempotency_key`; the send/log/retry logic lives in
  `Sahla.Notifications.run_email/2`.
  """
  use Sahla.Worker, queue: :email, unique: [keys: [:idempotency_key], period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job), do: Sahla.Notifications.run_email(args, job)
end
