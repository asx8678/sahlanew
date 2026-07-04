defmodule Sahla.WorkerTest do
  use Sahla.DataCase, async: true
  use Oban.Testing, repo: Sahla.Repo

  # A trivial worker built on the base convention; doubles its argument.
  defmodule Doubler do
    use Sahla.Worker, queue: :maintenance

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"n" => n}}), do: {:ok, n * 2}
  end

  test "the base convention applies a bounded default max_attempts" do
    # `use Sahla.Worker` with no override inherits the project default (3).
    assert Doubler.new(%{n: 1}).changes.max_attempts == 3
  end

  test "a worker executes via Oban.Testing.perform_job" do
    assert perform_job(Doubler, %{"n" => 21}) == {:ok, 42}
  end

  test "a job enqueues and runs inline (deterministic test env)" do
    assert {:ok, %Oban.Job{state: "completed"}} = Oban.insert(Doubler.new(%{n: 5}))
  end
end
