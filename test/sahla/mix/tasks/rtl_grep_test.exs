defmodule SahlaWeb.Mix.Tasks.RtlGrepTest do
  use ExUnit.Case, async: false

  # The guard is a CI-facing mix task, so we exercise it through Mix.Task.run
  # and the public scan function rather than shelling out. Self-test mode
  # embeds a known-good and known-bad sample and asserts both directions.

  describe "--self-test" do
    test "passes on the bundled good/bad samples" do
      # Mix.Task.run reuses the loaded task module; capture its exit/success.
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert Mix.Task.run("rtl.grep", ["--self-test"]) == :ok
        end)

      assert output =~ "PASS"
    end
  end

  describe "scan_string/2" do
    test "flags ml-/mr-/pl-/pr-/text-left/text-right inside class=" do
      bad = ~s(<div class="ml-2 mr-3 pl-4 pr-1 text-left text-right">x</div>)
      hits = Mix.Tasks.Rtl.Grep.scan_string(bad, "fake.heex")

      [{_, _, _, classes}] = hits
      assert Enum.sort(classes) == ~w(ml- mr- pl- pr- text-left text-right)
    end

    test "ignores logical utilities and icon names" do
      good = ~s(<.icon name="hero-arrow-right" class="ms-2 me-3 ps-4 pe-1 text-start text-end" />)
      assert Mix.Tasks.Rtl.Grep.scan_string(good, "fake.heex") == []
    end

    test "ignores code that only resembles a class" do
      code = ~s(  plug :put_layout, html: {SahlaWeb.Layouts, :app})
      assert Mix.Tasks.Rtl.Grep.scan_string(code, "router.ex") == []
    end
  end
end
