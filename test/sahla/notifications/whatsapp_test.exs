defmodule Sahla.Notifications.WhatsAppTest do
  # async: false — the number is read from the shared settings cache.
  use Sahla.DataCase, async: false

  alias Sahla.Notifications.WhatsApp
  alias Sahla.Settings
  alias Sahla.Settings.Cache

  setup do
    Cache.clear()
    :ok
  end

  describe "prefilled_text/1 (pure)" do
    test "includes the token and offer ref, in French by default" do
      text = WhatsApp.prefilled_text(%{token: "T1", offer_ref: "Wafa RC"})
      assert text =~ "réf T1"
      assert text =~ "offre Wafa RC"
    end

    test "localizes to Arabic" do
      text = WhatsApp.prefilled_text(%{token: "T1", offer_ref: "Wafa", locale: "ar"})
      assert text =~ "المرجع T1"
      assert text =~ "العرض Wafa"
    end

    test "omits the offer part when no ref is given" do
      text = WhatsApp.prefilled_text(%{token: "T1"})
      assert text =~ "réf T1"
      refute text =~ "offre"
    end
  end

  describe "deeplink/1" do
    test "builds a wa.me URL with the settings number (digits only) and encoded text" do
      {:ok, _} = Settings.put("whatsapp_number", "+212 600-112233")

      url = WhatsApp.deeplink(%{token: "T1", offer_ref: "Wafa RC"})
      assert String.starts_with?(url, "https://wa.me/212600112233?text=")
    end

    test "a missing number degrades to the contact picker" do
      url = WhatsApp.deeplink(%{token: "T1"})
      assert String.starts_with?(url, "https://wa.me/?text=")
    end

    test "URL-encodes spaces and special characters in the text" do
      {:ok, _} = Settings.put("whatsapp_number", "212600000000")

      url = WhatsApp.deeplink(%{token: "T 1", offer_ref: "é & ç"})
      query = url |> String.split("?text=") |> List.last()

      refute query =~ " "
      assert query =~ "%C3%A9"
      assert query =~ "%26"
    end
  end
end
