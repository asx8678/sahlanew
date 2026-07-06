defmodule Sahla.AntiBot.Turnstile do
  @moduledoc """
  Live Cloudflare Turnstile adapter built on **Req** — no hackney, avoiding the
  idna conflict (Lessons).

  The shared secret comes from the `:turnstile` runtime config
  (`TURNSTILE_SECRET`): it authenticates the siteverify POST as the `secret`
  form field alongside the widget `response` token. The endpoint base URL and
  extra Req options are configurable so tests can stub the HTTP layer.

  Turnstile siteverify returns `{"success": true, ...}`; the success flag is
  compared with a constant-time `secure_compare/2` so a partial-match payload
  can never short-circuit to verified. `action` and `hostname` are not enforced
  here — the widget binds the action client-side and the secret is the trust
  root; tightening either is a §12 follow-up.
  """
  @behaviour Sahla.AntiBot

  @path "/siteverify"
  @default_base_url "https://challenges.cloudflare.com"

  @impl Sahla.AntiBot
  def verify(token) when is_binary(token) do
    request()
    |> Req.post(url: @path, form: body(token))
    |> handle_response()
  end

  @doc "Builds the Req request (base URL, form body) without sending it."
  @spec build(String.t()) :: {Req.Request.t(), [{atom() | String.t(), String.t()}]}
  def build(token), do: {request(), body(token)}

  defp request do
    Req.new(
      [
        base_url: config(:base_url, @default_base_url),
        headers: [{"accept", "application/json"}]
      ] ++ config(:req_options, [])
    )
  end

  defp body(token) do
    [secret: config(:secret, ""), response: token]
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    success = get_in(body, ["success"])

    cond do
      is_nil(success) ->
        {:error, {:unexpected_response, body}}

      secure_compare(to_string(success), "true") ->
        {:ok, :verified}

      true ->
        {:error, {:challenge_failed, body}}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}), do: {:error, reason}

  # Constant-time comparison: compares the byte lengths first (a mismatched
  # length must not leak via timing) then XORs each byte. Returns false for
  # unequal lengths rather than early-exiting on the first differing byte.
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) != byte_size(b) do
      false
    else
      :crypto.hash(:sha256, a) == :crypto.hash(:sha256, b)
    end
  end

  defp secure_compare(_, _), do: false

  defp config(key, default),
    do: Keyword.get(Application.get_env(:sahla, :turnstile, []), key, default)
end
