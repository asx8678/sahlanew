defmodule Sahla.AntiBot.TurnstileTest do
  # async: false — sets :turnstile config and uses a global Req.Test stub.
  use ExUnit.Case, async: false

  alias Sahla.AntiBot.Turnstile

  setup do
    Application.put_env(:sahla, :turnstile,
      site_key: "0xTEST",
      secret: "test-secret",
      base_url: "https://turnstile.test",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:sahla, :turnstile) end)
    :ok
  end

  test "build/1 forms the siteverify request with the secret and response token" do
    {req, body} = Turnstile.build("tok-123")

    assert req.options.base_url == "https://turnstile.test"

    assert [{"accept", "application/json"}] = normalize(req.headers)

    assert body[:secret] == "test-secret"
    assert body[:response] == "tok-123"
  end

  test "verify/1 posts and parses success:true into {:ok, :verified}" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/siteverify"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert "secret=test-secret" in String.split(raw, "&")
      assert "response=tok-123" in String.split(raw, "&")

      Req.Test.json(conn, %{"success" => true, "challenge_ts" => "2026-01-01T00:00:00Z"})
    end)

    assert Turnstile.verify("tok-123") == {:ok, :verified}
  end

  test "verify/1 returns a challenge_failed error when success is false" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"success" => false, "error-codes" => ["invalid-input-response"]})
    end)

    assert {:error, {:challenge_failed, _}} = Turnstile.verify("bad-tok")
  end

  test "verify/1 returns an http_error on a non-2xx response" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"success" => false})
    end)

    assert {:error, {:http_error, 500, _}} = Turnstile.verify("tok")
  end

  test "verify/1 returns an unexpected_response error when success is absent" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"unexpected" => true})
    end)

    assert {:error, {:unexpected_response, _}} = Turnstile.verify("tok")
  end

  # Req may store headers as a map of name => [values]; flatten for assertion.
  defp normalize(headers) when is_map(headers),
    do: Enum.flat_map(headers, fn {k, vs} -> Enum.map(List.wrap(vs), &{k, &1}) end)

  defp normalize(headers) when is_list(headers), do: headers
end
