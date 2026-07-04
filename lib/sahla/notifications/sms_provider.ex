defmodule Sahla.Notifications.SMSProvider do
  @moduledoc """
  Shared helpers for SMS adapters.

  `render/2` does minimal `%{var}` interpolation so an adapter always has a text
  body. Full localized FR/AR template resolution is a separate task (tam.4);
  this keeps the provider contract usable in the meantime.
  """

  @doc """
  Renders a `template` with `vars` into a message string.

  A binary template has its `%{key}` placeholders replaced from `vars`; an atom
  template stringifies to its name (a placeholder until tam.4 supplies catalogs).
  """
  @spec render(atom() | String.t(), map()) :: String.t()
  def render(template, vars) when is_binary(template) do
    # Compare on string keys so untrusted placeholder names never mint atoms.
    string_vars = Map.new(vars, fn {key, value} -> {to_string(key), value} end)

    Regex.replace(~r/%\{([a-zA-Z_][a-zA-Z0-9_]*)\}/, template, fn whole, key ->
      case Map.fetch(string_vars, key) do
        {:ok, value} -> to_string(value)
        :error -> whole
      end
    end)
  end

  def render(template, _vars) when is_atom(template), do: to_string(template)
end
