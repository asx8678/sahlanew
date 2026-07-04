defmodule Sahla.CSV do
  @moduledoc """
  A minimal RFC-4180-subset CSV reader for the bareme/matrix imports (§10.5).

  Supports a comma delimiter, double-quote quoting and `""` escapes, and both
  `\\n` and `\\r\\n` line endings. Embedded newlines inside quoted fields are
  **not** supported — the structured matrices we ingest never contain them, and
  avoiding it keeps this a dependency-free line-oriented parser. If richer CSV is
  ever needed, swap this for `nimble_csv`.
  """

  @doc """
  Parses `text` into a list of row maps keyed by the (trimmed) header names.
  Blank lines are skipped; an empty input yields `[]`.
  """
  @spec parse(String.t()) :: [%{String.t() => String.t()}]
  def parse(text) when is_binary(text) do
    text
    |> String.split(~r/\r\n|\r|\n/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> case do
      [] ->
        []

      [header_line | data_lines] ->
        headers = header_line |> parse_line() |> Enum.map(&String.trim/1)
        Enum.map(data_lines, fn line -> headers |> Enum.zip(parse_line(line)) |> Map.new() end)
    end
  end

  # Splits one line into fields, honouring double-quote quoting and "" escapes.
  defp parse_line(line), do: line |> String.to_charlist() |> take([], [], false)

  # take(chars, current_field_rev, fields_rev, in_quotes?)
  defp take([], current, fields, _quoted), do: Enum.reverse([field(current) | fields])

  # Escaped quote ("") inside a quoted field -> a literal quote.
  defp take([?", ?" | rest], current, fields, true), do: take(rest, [?" | current], fields, true)

  # Quote toggles in/out of quoted mode.
  defp take([?" | rest], current, fields, true), do: take(rest, current, fields, false)
  defp take([?" | rest], current, fields, false), do: take(rest, current, fields, true)

  # An unquoted comma ends the field.
  defp take([?, | rest], current, fields, false),
    do: take(rest, [], [field(current) | fields], false)

  defp take([char | rest], current, fields, quoted),
    do: take(rest, [char | current], fields, quoted)

  defp field(current), do: current |> Enum.reverse() |> List.to_string() |> String.trim()
end
