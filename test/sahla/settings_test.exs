defmodule Sahla.SettingsTest do
  # async: false — shares the global settings ETS cache and PubSub topic.
  use Sahla.DataCase, async: false

  import Ecto.Query

  alias Sahla.Settings
  alias Sahla.Settings.{Cache, Setting, Store}

  setup do
    Cache.clear()
    :ok
  end

  describe "get/2 and put/2" do
    test "round-trips arbitrary jsonb values by key" do
      assert {:ok, _} = Settings.put("obj", %{"a" => 1, "b" => [true, "x"]})
      assert Settings.get("obj") == %{"a" => 1, "b" => [true, "x"]}

      assert {:ok, _} = Settings.put("str", "casablanca")
      assert Settings.get("str") == "casablanca"

      assert {:ok, _} = Settings.put("num", 42)
      assert Settings.get("num") == 42

      assert {:ok, _} = Settings.put("flag", false)
      assert Settings.get("flag") == false
    end

    test "get returns the default for an unknown key" do
      assert Settings.get("nope") == nil
      assert Settings.get("nope", :fallback) == :fallback
    end

    test "a second write updates the value" do
      {:ok, _} = Settings.put("hours", "9-18")
      {:ok, _} = Settings.put("hours", "9-20")
      assert Settings.get("hours") == "9-20"
    end

    test "reads are served from the cache, not the DB" do
      {:ok, _} = Settings.put("brand", "Sahla")

      # mutate the row directly, bypassing put/2 (and thus the cache)
      Repo.update_all(from(s in Setting, where: s.key == "brand"),
        set: [value: %{"value" => "Other"}]
      )

      assert Settings.get("brand") == "Sahla"
    end

    test "a write persists to the DB (survives a cold cache)" do
      {:ok, _} = Settings.put("persisted", "yes")
      Cache.clear()
      # cold cache: value must come back from the store on warm/read path
      assert {"persisted", "yes"} in Store.all()
    end
  end

  describe "feature_enabled?/1" do
    test "is false for an unknown or unset flag (never silently true)" do
      refute Settings.feature_enabled?("nonexistent")
    end

    test "reflects the flag once set" do
      {:ok, _} = Settings.put_feature("sms", true)
      assert Settings.feature_enabled?("sms")

      {:ok, _} = Settings.put_feature("sms", false)
      refute Settings.feature_enabled?("sms")
    end
  end

  describe "invalidation broadcast" do
    test "a write broadcasts a change on the settings topic" do
      Phoenix.PubSub.subscribe(Sahla.PubSub, "settings")
      {:ok, _} = Settings.put("broadcast_key", "v")
      assert_receive {:settings_changed, "broadcast_key", "v"}
    end
  end

  describe "seed_defaults/0" do
    test "inserts defaults with feature flags disabled, and is idempotent" do
      assert :ok = Settings.seed_defaults()

      refute Settings.feature_enabled?("sms")
      refute Settings.feature_enabled?("whatsapp")
      refute Settings.feature_enabled?("payments")
      assert Settings.get("display_name") == "Sahla"
      assert Settings.get("disclaimer_fr") =~ "indicatif"

      # a later ops change must survive a re-seed
      {:ok, _} = Settings.put_feature("sms", true)
      assert :ok = Settings.seed_defaults()
      assert Settings.feature_enabled?("sms")
    end
  end
end
