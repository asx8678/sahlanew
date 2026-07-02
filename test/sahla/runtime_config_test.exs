defmodule Sahla.RuntimeConfigTest do
  # Mutates the process-global environment — must not run concurrently.
  use ExUnit.Case, async: false

  @runtime_config Path.expand("config/runtime.exs")

  @required %{
    "DATABASE_URL" => "ecto://sahla:secret@127.0.0.1/sahla_cfg_test",
    "SECRET_KEY_BASE" => String.duplicate("s", 64),
    "PHX_HOST" => "sahla.example",
    "CLOAK_KEY" => Base.encode64(:binary.copy(<<1>>, 32))
  }

  @optional %{
    "PHX_SERVER" => "true",
    "PORT" => "4100",
    "POOL_SIZE" => "7",
    "SMS_PROVIDER" => "infobip",
    "SMS_API_KEY" => "sms-api-key",
    "SMS_SENDER" => "SENDERID",
    "POSTMARK_API_KEY" => "pm-key",
    "TURNSTILE_SITE_KEY" => "ts-site",
    "TURNSTILE_SECRET" => "ts-secret",
    "UPLOADS_DIR" => "/tmp/sahla-uploads-test",
    "SENTRY_DSN" => "https://public@sentry.example/1",
    "PLAUSIBLE_DOMAIN" => "sahla.example"
  }

  @all_vars Map.keys(@required) ++ Map.keys(@optional)

  setup do
    snapshot = Map.new(@all_vars, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(snapshot, fn
        {var, nil} -> System.delete_env(var)
        {var, value} -> System.put_env(var, value)
      end)
    end)

    :ok
  end

  defp put_all_env do
    System.put_env(@required)
    System.put_env(@optional)
  end

  defp read_prod_config do
    Config.Reader.read!(@runtime_config, env: :prod)
  end

  test "prod runtime config parses the full Appendix B env set" do
    put_all_env()

    config = read_prod_config()
    sahla = Keyword.fetch!(config, :sahla)

    endpoint = Keyword.fetch!(sahla, SahlaWeb.Endpoint)
    assert endpoint[:server] == true
    assert get_in(endpoint, [:http, :port]) == 4100
    assert get_in(endpoint, [:url, :host]) == "sahla.example"
    assert get_in(endpoint, [:url, :scheme]) == "https"
    assert endpoint[:secret_key_base] == @required["SECRET_KEY_BASE"]

    repo = Keyword.fetch!(sahla, Sahla.Repo)
    assert repo[:url] == @required["DATABASE_URL"]
    assert repo[:pool_size] == 7

    assert sahla[:cloak_key] == @required["CLOAK_KEY"]

    assert sahla[:sms] == [provider: "infobip", api_key: "sms-api-key", sender: "SENDERID"]
    assert sahla[:postmark_api_key] == "pm-key"
    assert sahla[:turnstile] == [site_key: "ts-site", secret: "ts-secret"]
    assert sahla[:uploads_dir] == "/tmp/sahla-uploads-test"
    assert sahla[:sentry_dsn] == "https://public@sentry.example/1"
    assert sahla[:plausible_domain] == "sahla.example"
  end

  test "optional integration vars fall back to safe defaults" do
    put_all_env()
    Enum.each(Map.keys(@optional), &System.delete_env/1)

    config = read_prod_config()
    sahla = Keyword.fetch!(config, :sahla)

    assert get_in(sahla, [:sms, :provider]) == "fake"
    assert get_in(sahla, [:sms, :api_key]) == nil
    assert sahla[:uploads_dir] == "/opt/sahla/shared/uploads"
    assert Keyword.fetch!(sahla, Sahla.Repo)[:pool_size] == 15
    refute Keyword.fetch!(sahla, SahlaWeb.Endpoint)[:server]
  end

  for var <- Map.keys(@required) do
    test "missing #{var} raises a clear error naming the variable" do
      put_all_env()
      System.delete_env(unquote(var))

      assert_raise RuntimeError, ~r/#{unquote(var)} is missing/, fn ->
        read_prod_config()
      end
    end
  end
end
