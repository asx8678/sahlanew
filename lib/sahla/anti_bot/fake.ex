defmodule Sahla.AntiBot.Fake do
  @moduledoc """
  In-memory Turnstile adapter for dev and test: it never touches the network and
  records every verification in an Agent so tests can assert on what was
  submitted. Backed by a supervised Agent (`start_link/1`).

  Deterministic by default — `verify/1` accepts any non-empty token (the widget
  has no challenge to solve in dev/test). A test can flip the outcome via
  `set_result/1` to exercise the failure path.
  """
  @behaviour Sahla.AntiBot

  use Agent

  @type recorded :: %{token: String.t(), result: Sahla.AntiBot.result()}

  def start_link(_opts) do
    Agent.start_link(fn -> %{calls: [], result: {:ok, :verified}} end, name: __MODULE__)
  end

  @impl Sahla.AntiBot
  def verify(token) when is_binary(token) do
    result = Agent.get(__MODULE__, & &1.result)
    Agent.update(__MODULE__, &%{&1 | calls: [%{token: token, result: result} | &1.calls]})
    result
  end

  @doc "All recorded verifications, oldest first."
  @spec calls() :: [recorded()]
  def calls, do: __MODULE__ |> Agent.get(& &1.calls) |> Enum.reverse()

  @doc "Forces the next `verify/1` call to return `result` (default `{:ok, :verified}`)."
  @spec set_result(Sahla.AntiBot.result()) :: :ok
  def set_result(result), do: Agent.update(__MODULE__, &%{&1 | result: result})

  @doc "Discards recorded calls and resets the forced result. Call in test setup."
  @spec clear() :: :ok
  def clear, do: Agent.update(__MODULE__, fn _ -> %{calls: [], result: {:ok, :verified}} end)
end
