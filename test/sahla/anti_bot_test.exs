defmodule Sahla.AntiBotTest do
  # async: false — mutates :sahla application env and the global settings cache (DB-backed).
  use Sahla.DataCase, async: false
  alias Sahla.AntiBot
  alias Sahla.AntiBot.{Fake, Turnstile}
  alias Sahla.Settings

  setup do
    Fake.clear()
    # Settings cache is shared global ETS; ensure the turnstile flag is OFF so
    # nothing leaks in (or out) of these tests.
    Settings.put_feature("turnstile", false)

    on_exit(fn ->
      Application.delete_env(:sahla, :antibot_adapter)
      Application.delete_env(:sahla, :turnstile)
    end)

    :ok
  end

  describe "provider resolution" do
    test "defaults to the Fake adapter when no secret is configured" do
      Application.put_env(:sahla, :turnstile, site_key: "sk", secret: nil)
      assert AntiBot.adapter() == Fake
    end

    test "selects the Turnstile adapter when a secret is present" do
      Application.put_env(:sahla, :turnstile, site_key: "sk", secret: "shh")
      assert AntiBot.adapter() == Turnstile
    end

    test "an explicit :antibot_adapter override wins over derived config" do
      Application.put_env(:sahla, :turnstile, secret: "shh")
      Application.put_env(:sahla, :antibot_adapter, Fake)
      assert AntiBot.adapter() == Fake
    end

    test "site_key/0 reads the configured key (nil when unset)" do
      Application.put_env(:sahla, :turnstile, site_key: "abc")
      assert AntiBot.site_key() == "abc"

      Application.put_env(:sahla, :turnstile, [])
      assert AntiBot.site_key() == nil
    end
  end

  describe "verify/1 feature flag (Fake default adapter)" do
    test "with the flag off, returns {:ok, :disabled} and never calls the adapter" do
      Settings.put_feature("turnstile", false)

      assert AntiBot.verify("any-token") == {:ok, :disabled}
      assert Fake.calls() == []
    end

    test "with the flag off, an empty token still passes through as :disabled" do
      Settings.put_feature("turnstile", false)

      assert AntiBot.verify(nil) == {:ok, :disabled}
      assert AntiBot.verify("") == {:ok, :disabled}
    end

    test "with the flag on, the Fake adapter verifies any non-empty token" do
      Settings.put_feature("turnstile", true)

      assert AntiBot.verify("ok-token") == {:ok, :verified}
      assert [%{token: "ok-token", result: {:ok, :verified}}] = Fake.calls()
    end

    test "with the flag on, an empty token short-circuits to :missing_token" do
      Settings.put_feature("turnstile", true)

      assert AntiBot.verify("") == {:error, :missing_token}
      assert AntiBot.verify(nil) == {:error, :missing_token}
      assert Fake.calls() == []
    end

    test "a forced Fake failure surfaces the error tuple" do
      Settings.put_feature("turnstile", true)
      Fake.set_result({:error, :challenge_failed})

      assert AntiBot.verify("bad-token") == {:error, :challenge_failed}
      assert [%{token: "bad-token"}] = Fake.calls()
    end
  end
end
