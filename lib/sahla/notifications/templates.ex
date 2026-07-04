defmodule Sahla.Notifications.Templates do
  @moduledoc """
  Renders transactional messages (§5.3, §11): resolves the body for a key+locale
  — an admin override from settings when present, else the canonical default —
  and performs safe `{{var}}` interpolation.

  The brand display name is injected as `{{brand}}` from settings, so no message
  hardcodes it. A missing variable raises rather than emitting a literal
  `{{var}}` (errors never pass silently).

  Overrides are read from the `:notification_overrides` setting, a map keyed by
  `{key, locale}` holding a body map of the same shape as the default. This is
  the seam the settings/admin-studio layer (r5o.8, 8y3.9) writes through.
  """
  alias Sahla.Notifications.Template

  @placeholder ~r/\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

  @doc """
  Renders `key` in `locale` with `vars`, returning the rendered body map:
  `%{text: ...}` for SMS keys, `%{subject:, html:, text:}` for email keys.

  Raises `KeyError` for an unknown key/locale and `ArgumentError` for a
  placeholder with no matching variable.
  """
  def render(key, locale, vars \\ %{}) do
    body = load_override(key, locale) || Template.default_body(key, locale)
    resolved = vars |> stringify_keys() |> Map.put_new("brand", brand_name())

    Map.new(body, fn {field, string} -> {field, interpolate(string, resolved, key)} end)
  end

  defp interpolate(string, vars, key) do
    Regex.replace(@placeholder, string, fn _match, name ->
      case Map.fetch(vars, name) do
        {:ok, value} ->
          to_string(value)

        :error ->
          raise ArgumentError,
                "missing variable #{inspect(name)} while rendering template #{inspect(key)}"
      end
    end)
  end

  defp load_override(key, locale) do
    :sahla
    |> Application.get_env(:notification_overrides, %{})
    |> Map.get({key, locale})
  end

  defp brand_name, do: Application.fetch_env!(:sahla, :brand_name)

  defp stringify_keys(vars), do: Map.new(vars, fn {key, value} -> {to_string(key), value} end)
end
