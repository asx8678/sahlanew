defmodule Sahla.Notifications.SMSProvider.InfobipTest do
  # async: false — sets :sms config and uses a global Req.Test stub.
  use ExUnit.Case, async: false

  alias Sahla.Notifications.SMSProvider.Infobip

  setup do
    Application.put_env(:sahla, :sms,
      provider: "infobip",
      api_key: "test-api-key",
      sender: "SAHLA",
      base_url: "https://sms.test",
      cost_centimes: 42,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:sahla, :sms) end)
    :ok
  end

  test "build/2 forms the request with base URL, App auth, sender and destination" do
    {req, body} = Infobip.build("212600123456", "hello")

    assert req.options.base_url == "https://sms.test"
    assert {"authorization", "App test-api-key"} in normalize(req.headers)

    assert body == %{
             messages: [%{from: "SAHLA", destinations: [%{to: "212600123456"}], text: "hello"}]
           }
  end

  test "send/3 posts via Req and parses the messageId + configured cost" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/sms/2/text/advanced"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(raw)
      assert get_in(payload, ["messages", Access.at(0), "from"]) == "SAHLA"
      assert get_in(payload, ["messages", Access.at(0), "text"]) == "Code: 999"

      Req.Test.json(conn, %{"messages" => [%{"messageId" => "MID-123", "status" => %{}}]})
    end)

    assert {:ok, %{provider_id: "MID-123", cost_centimes: 42}} =
             Infobip.send("212600123456", "Code: %{code}", %{code: 999})
  end

  test "send/3 returns an error tuple on a non-2xx response" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"requestError" => %{}})
    end)

    assert {:error, {:http_error, 401, _}} = Infobip.send("212600123456", "x", %{})
  end

  # Req may store headers as a map of name => [values]; flatten for assertion.
  defp normalize(headers) when is_map(headers),
    do: Enum.flat_map(headers, fn {k, vs} -> Enum.map(List.wrap(vs), &{k, &1}) end)

  defp normalize(headers) when is_list(headers), do: headers
end
