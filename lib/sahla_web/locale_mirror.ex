defmodule SahlaWeb.LocaleMirror do
  @moduledoc """
  Path mirroring between the French (`/`) and Arabic (`/ar`) route scopes
  (§5.1, §6.3). The language switcher uses it to redirect a request to the
  equivalent route in the other locale while preserving every path segment —
  so a funnel/offers token (`/devis/:token`, `/offres/:token`) survives the
  switch unchanged, as do insurer and guide slugs.

  ## Examples

      iex> LocaleMirror.to("/devis/abc-123", "ar")
      "/ar/devis/abc-123"
      iex> LocaleMirror.to("/ar/devis/abc-123", "fr")
      "/devis/abc-123"
      iex> LocaleMirror.to("/ar/offres/xyz", "fr")
      "/offres/xyz"
      iex> LocaleMirror.to("/", "ar")
      "/ar"
  """

  @ar_prefix "/ar"

  @doc """
  Returns the mirror of `path` for `target_locale` (`"fr"` or `"ar"`).

  `path` is the request path as Phoenix sees it (no query string). The result
  is a path string with the `/ar` prefix added or removed so the same route
  handler serves it in the other locale. Query strings are preserved as-is.
  """
  @spec to(String.t(), String.t()) :: String.t()
  def to(path, target_locale) when is_binary(path) and is_binary(target_locale) do
    {base, query} = split_query(path)
    mirrored = mirror_base(base, target_locale)

    case query do
      "" -> mirrored
      q -> mirrored <> "?" <> q
    end
  end

  defguardp ar_prefixed(base) when binary_part(base, 0, byte_size(@ar_prefix)) == @ar_prefix

  # Mirrors the path (minus query) by adding or removing the `/ar` prefix.
  defp mirror_base(base, "ar") when ar_prefixed(base), do: base

  defp mirror_base(base, "ar"), do: join(@ar_prefix, base)

  defp mirror_base(@ar_prefix, "fr"), do: "/"

  defp mirror_base(base, "fr") when ar_prefixed(base) do
    String.slice(base, byte_size(@ar_prefix)..-1//1)
  end

  defp mirror_base(base, _target), do: base

  defp split_query(path) do
    case String.split(path, "?", parts: 2) do
      [base] -> {base, ""}
      [base, query] -> {base, query}
    end
  end

  # Joining "/ar" with "/" yields "/ar" (not "/ar/"); joining with "/devis/x"
  # yields "/ar/devis/x".
  defp join(prefix, "/"), do: prefix
  defp join(prefix, rest), do: prefix <> rest
end
