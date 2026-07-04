defmodule Sahla.Notifications.SMSProvider.Fake do
  @moduledoc """
  In-memory SMS adapter for dev and test: it never touches the network and
  records every send in an Agent so tests can assert on what would have been
  sent. Backed by a supervised Agent (`start_link/1`).
  """
  @behaviour Sahla.Notifications.SMS

  use Agent

  alias Sahla.Notifications.SMSProvider

  @type sent_sms :: %{to: String.t(), template: term(), vars: map(), text: String.t()}

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @impl Sahla.Notifications.SMS
  def send(to, template, vars) do
    text = SMSProvider.render(template, vars)
    provider_id = "fake-" <> Integer.to_string(System.unique_integer([:positive]))
    Agent.update(__MODULE__, &[%{to: to, template: template, vars: vars, text: text} | &1])
    {:ok, %{provider_id: provider_id, cost_centimes: 0}}
  end

  @doc "All recorded sends, oldest first."
  @spec sent() :: [sent_sms()]
  def sent, do: __MODULE__ |> Agent.get(& &1) |> Enum.reverse()

  @doc "Discards all recorded sends. Call in test setup."
  @spec clear() :: :ok
  def clear, do: Agent.update(__MODULE__, fn _ -> [] end)
end
