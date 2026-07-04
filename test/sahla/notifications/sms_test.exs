defmodule Sahla.Notifications.SMSTest do
  # async: false — mutates :sahla application env (adapter, kill-switch, :sms).
  use ExUnit.Case, async: false

  alias Sahla.Notifications.SMS
  alias Sahla.Notifications.SMSProvider.{Fake, Infobip}

  setup do
    Fake.clear()

    on_exit(fn ->
      Application.delete_env(:sahla, :sms_adapter)
      Application.put_env(:sahla, :sms_enabled, true)
      Application.delete_env(:sahla, :sms)
    end)

    :ok
  end

  describe "provider resolution" do
    test "defaults to the Fake adapter when nothing is configured" do
      assert SMS.adapter() == Fake
    end

    test "an explicit :sms_adapter override wins" do
      Application.put_env(:sahla, :sms_adapter, Infobip)
      assert SMS.adapter() == Infobip
    end

    test "provider=infobip with an API key selects the live adapter" do
      Application.put_env(:sahla, :sms, provider: "infobip", api_key: "k", sender: "SAHLA")
      assert SMS.adapter() == Infobip
    end

    test "provider=infobip WITHOUT an API key falls back to Fake (secret required)" do
      Application.put_env(:sahla, :sms, provider: "infobip", api_key: nil, sender: "SAHLA")
      assert SMS.adapter() == Fake
    end
  end

  describe "kill-switch" do
    test "returns {:error, :disabled} without calling the provider when disabled" do
      Application.put_env(:sahla, :sms_enabled, false)

      assert SMS.send("212600000000", "hi", %{}) == {:error, :disabled}
      assert Fake.sent() == []
    end
  end

  describe "Moroccan +212 allowlist" do
    test "accepts +212, 212 and local 0 forms (ignoring spaces/dashes)" do
      assert SMS.ma_allowed?("+212612345678")
      assert SMS.ma_allowed?("212612345678")
      assert SMS.ma_allowed?("0612345678")
      assert SMS.ma_allowed?("+212 6-12-34-56-78")
    end

    test "rejects foreign numbers and junk" do
      refute SMS.ma_allowed?("+33612345678")
      refute SMS.ma_allowed?("+1 202 555 0100")
      refute SMS.ma_allowed?("hello")
      refute SMS.ma_allowed?(nil)
    end

    test "send/3 rejects a foreign number before any provider call" do
      assert SMS.send("+33612345678", "hi", %{}) == {:error, :recipient_not_allowed}
      assert Fake.sent() == []
    end
  end

  describe "Fake adapter" do
    test "records sends and returns a provider id" do
      assert {:ok, %{provider_id: "fake-" <> _, cost_centimes: 0}} =
               SMS.send("212611111111", "Your code is %{code}", %{code: "123456"})

      assert [record] = Fake.sent()
      assert record.to == "212611111111"
      assert record.text == "Your code is 123456"
      assert record.vars == %{code: "123456"}
    end
  end
end
