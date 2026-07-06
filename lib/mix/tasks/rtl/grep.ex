defmodule Mix.Tasks.Rtl.Grep do
  @shortdoc "Fail when a physical-direction Tailwind class appears in HEEx markup"
  @moduledoc """
  Guards RTL correctness (§6.3, sahla-bai.5) by refusing any physical-direction
  Tailwind utility in HEEx markup. Automatic Arabic mirroring only works when
  every template uses logical utilities, so this pass keeps that discipline
  from regressing.

  Scanned: `.ex` and `.heex` files under `lib/` and `priv/` — every place
  Phoenix renders HEEx (LiveViews, function components, embedded layouts).
  A hit is any forbidden class appearing inside a `class="..."` attribute, so
  icon names like `hero-arrow-right` and code like `put_layout html:` never
  trip the guard.

  Forbidden classes (their logical replacements):

      ml-  → ms-     (margin-inline-start)
      mr-  → me-     (margin-inline-end)
      pl-  → ps-     (padding-inline-start)
      pr-  → pe-     (padding-inline-end)
      text-left  → text-start
      text-right → text-end

  Usage:

      mix rtl.grep             # scan the project, exit 1 on any hit
      mix rtl.grep --self-test  # run against a deliberately bad sample and
                                # assert it is flagged, then exit 0

  The `--self-test` mode embeds one good and one bad `class=` and asserts the
  bad one is caught and the good one passes, so the guard is provably live.
  """

  use Mix.Task

  @class_attr_regex ~r/class="([^"]*)"/
  @forbidden ~w(ml- mr- pl- pr- text-left text-right)

  @forbidden_explanations %{
    "ml-" => "use ms- (margin-inline-start)",
    "mr-" => "use me- (margin-inline-end)",
    "pl-" => "use ps- (padding-inline-start)",
    "pr-" => "use pe- (padding-inline-end)",
    "text-left" => "use text-start",
    "text-right" => "use text-end"
  }

  @impl Mix.Task
  def run(args) do
    Mix.ensure_application!(:elixir)

    if "--self-test" in args do
      run_self_test()
    else
      run_scan()
    end
  end

  defp run_scan do
    hits = scan_files(project_roots())

    case hits do
      [] ->
        Mix.shell().info("rtl.grep: no physical-direction classes found — clean.")

      _ ->
        Mix.shell().error("rtl.grep: physical-direction Tailwind classes found:\n")

        Enum.each(hits, fn {file, line_no, line, classes} ->
          hints = Enum.map_join(classes, ", ", &"#{&1} (#{@forbidden_explanations[&1]})")
          Mix.shell().error("  #{file}:#{line_no}: #{hints}")
          Mix.shell().error("    #{String.trim(line)}")
        end)

        Mix.shell().error(
          "\nReplace each with its logical counterpart (ms-/me-/ps-/pe-/text-start/text-end)."
        )
    end

    if hits == [], do: :ok, else: exit({:shutdown, 1})
  end

  defp run_self_test do
    good = ~s(<div class="ms-2 me-3 ps-4 pe-1 text-start text-end text-center">ok</div>)
    bad = ~s(<div class="ml-2 mr-3 pl-4 pr-1 text-left text-right">bad</div>)

    good_hits = scan_string(good, "self-test-good")
    bad_hits = scan_string(bad, "self-test-bad")

    good_ok = good_hits == []

    bad_ok =
      bad_hits != [] and
        Enum.sort(classes_only(bad_hits)) == ~w(ml- mr- pl- pr- text-left text-right)

    if good_ok and bad_ok do
      Mix.shell().info("rtl.grep --self-test: PASS (good sample clean, bad sample flagged).")
      :ok
    else
      Mix.shell().error("rtl.grep --self-test: FAIL")
      Mix.shell().error("  good sample flagged (should be clean): #{inspect(good_hits)}")
      Mix.shell().error("  bad sample missed (should be flagged): #{inspect(bad_hits)}")
      exit({:shutdown, 1})
    end
  end

  defp scan_files(roots) do
    roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.{ex,exs,heex}")))
    |> Enum.reject(&String.contains?(&1, "/mix/tasks/rtl/"))
    |> Enum.flat_map(fn file ->
      file
      |> File.read!()
      |> scan_string(file)
    end)
    |> Enum.sort_by(&{elem(&1, 0), elem(&1, 1)})
  end

  # Finds every `class="..."` on a line and reports the forbidden tokens it
  # contains. Anchoring on the attribute value keeps icon names (`arrow-right`)
  # and code (`put_layout html:`) from being mistaken for classes.
  @doc false
  def scan_string(content, file) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      classes =
        @class_attr_regex
        |> Regex.scan(line, capture: :all_but_first)
        |> List.flatten()
        |> Enum.flat_map(&find_forbidden/1)
        |> Enum.uniq()

      if classes == [], do: [], else: [{file, line_no, line, classes}]
    end)
  end

  defp find_forbidden(class_value) do
    @forbidden
    |> Enum.filter(&String.contains?(class_value, &1))
  end

  defp classes_only(hits), do: Enum.flat_map(hits, fn {_, _, _, c} -> c end)

  defp project_roots do
    ["lib", "priv"]
    |> Enum.filter(&File.dir?/1)
  end
end
