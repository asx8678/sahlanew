defmodule Sahla.Notifications.SMSProvider.Infobip do
  @moduledoc """
  Live SMS adapter for Infobip (the aggregator chosen in Phase 0), built on
  **Req** — no hackney, avoiding the idna conflict (Lessons).

  Secrets come from the `:sms` runtime config (`SMS_API_KEY`, `SMS_SENDER`):
  the API key authenticates as `Authorization: App <key>` and the Moroccan
  alphanumeric sender-ID becomes the message `from`. The endpoint base URL and
  extra Req options are configurable so tests can stub the HTTP layer.

  Infobip's synchronous response returns a `messageId` but not a price (that
  arrives later via delivery reports), so `cost_centimes` is a configured
  per-message estimate until the reporting pipeline lands.
  """
  @behaviour Sahla.Notifications.SMS

  alias Sahla.Notifications.SMSProvider

  @path "/sms/2/text/advanced"
  @default_base_url "https://api.infobip.com"
  @default_cost_centimes 30

  @impl Sahla.Notifications.SMS
  def send(to, template, vars) do
    text = SMSProvider.render(template, vars)

    request()
    |> Req.post(url: @path, json: body(to, text))
    |> handle_response()
  end

  @doc "Builds the Req request (base URL, auth header, JSON body) without sending it."
  @spec build(String.t(), String.t()) :: {Req.Request.t(), map()}
  def build(to, text), do: {request(), body(to, text)}

  defp request do
    Req.new(
      [
        base_url: config(:base_url, @default_base_url),
        headers: [
          {"authorization", "App #{config(:api_key, "")}"},
          {"accept", "application/json"}
        ]
      ] ++ config(:req_options, [])
    )
  end

  defp body(to, text) do
    %{
      messages: [
        %{
          from: config(:sender, ""),
          destinations: [%{to: to}],
          text: text
        }
      ]
    }
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    case get_in(body, ["messages", Access.at(0), "messageId"]) do
      nil -> {:error, {:unexpected_response, body}}
      message_id -> {:ok, %{provider_id: to_string(message_id), cost_centimes: cost()}}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}), do: {:error, reason}

  defp cost, do: config(:cost_centimes, @default_cost_centimes)

  defp config(key, default), do: Keyword.get(Application.get_env(:sahla, :sms, []), key, default)
end
