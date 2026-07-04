defmodule Sahla.Worker do
  @moduledoc """
  Base convention for Oban workers (§7.3, §12). `use Sahla.Worker` in place of
  `use Oban.Worker` so every background job shares project defaults (a bounded
  `max_attempts` so a poison job can't retry forever) while still accepting any
  `Oban.Worker` option — `queue:`, `unique:`, `max_attempts:`, etc.

  Concrete jobs (OTP send, email, follow-up reminders, imports, retention
  purges) live in their owning domains; this module only fixes the convention.

  ## Example

      defmodule Sahla.Notifications.OtpWorker do
        use Sahla.Worker, queue: :sms, max_attempts: 5

        @impl Oban.Worker
        def perform(%Oban.Job{args: %{"phone" => phone}}) do
          # ...
          :ok
        end
      end
  """

  @default_max_attempts 3

  defmacro __using__(opts) do
    opts = Keyword.put_new(opts, :max_attempts, @default_max_attempts)

    quote do
      use Oban.Worker, unquote(opts)
    end
  end
end
