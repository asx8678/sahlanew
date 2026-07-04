defmodule Sahla.Notifications.Workers.SMSWorker do
  @moduledoc """
  Delivers a queued SMS as an Oban job (queue `:sms`, §7.3). Jobs are unique per
  `idempotency_key` so a duplicate enqueue never double-sends; the actual
  send/log/retry logic lives in `Sahla.Notifications.run_sms/2`.
  """
  use Sahla.Worker, queue: :sms, unique: [keys: [:idempotency_key], period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job), do: Sahla.Notifications.run_sms(args, job)
end
