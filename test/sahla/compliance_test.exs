defmodule Sahla.ComplianceTest do
  # async: false — Settings-sourced text_version touches the shared settings cache.
  use Sahla.DataCase, async: false

  alias Sahla.Compliance
  alias Sahla.Quoting
  alias Sahla.Settings.Cache

  setup do
    Cache.clear()
    {:ok, quote} = Quoting.create_quote()
    %{quote: quote}
  end

  defp by_kind(consents), do: Map.new(consents, &{&1.kind, &1})

  describe "capture_consents/2" do
    test "records one row per kind with version, flags, ip and timestamp", %{quote: quote} do
      assert {:ok, consents} =
               Compliance.capture_consents(quote, %{
                 cgu: true,
                 transmission: true,
                 marketing: true,
                 ip: "196.200.1.1"
               })

      assert length(consents) == 3
      map = by_kind(consents)

      assert map[:cgu].granted and map[:transmission].granted and map[:marketing].granted
      assert map[:cgu].text_version == "v1"
      assert map[:cgu].ip == "196.200.1.1"
      assert map[:cgu].granted_at
      assert length(Compliance.consents_for(quote)) == 3
    end

    test "marketing is optional and its refusal is recorded", %{quote: quote} do
      assert {:ok, consents} =
               Compliance.capture_consents(quote, %{cgu: true, transmission: true})

      map = by_kind(consents)
      assert map[:marketing].granted == false
      assert length(consents) == 3
    end

    test "rejects a missing required consent and writes nothing", %{quote: quote} do
      assert {:error, :consent_required} =
               Compliance.capture_consents(quote, %{cgu: true, transmission: false})

      assert {:error, :consent_required} =
               Compliance.capture_consents(quote, %{cgu: false, transmission: true})

      assert Compliance.consents_for(quote) == []
    end

    test "accepts the funnel step's consent_* keys", %{quote: quote} do
      assert {:ok, _} =
               Compliance.capture_consents(quote, %{
                 consent_cgu: true,
                 consent_transmission: true,
                 consent_marketing: false
               })
    end

    test "an extra map is stored only after SafeRaw strips PII", %{quote: quote} do
      {:ok, consents} =
        Compliance.capture_consents(quote, %{
          cgu: true,
          transmission: true,
          extra: %{"utm_source" => "google", "phone" => "212612345678"}
        })

      metadata = by_kind(consents)[:cgu].metadata
      assert metadata == %{"utm_source" => "google"}
      refute Map.has_key?(metadata, "phone")
    end

    test "re-capturing upserts, keeping one row per kind with the latest value", %{quote: quote} do
      {:ok, _} =
        Compliance.capture_consents(quote, %{cgu: true, transmission: true, marketing: false})

      {:ok, _} =
        Compliance.capture_consents(quote, %{cgu: true, transmission: true, marketing: true})

      consents = Compliance.consents_for(quote)
      assert length(consents) == 3
      assert by_kind(consents)[:marketing].granted == true
    end

    test "resolves text_version from settings when provided", %{quote: quote} do
      {:ok, _} = Sahla.Settings.put("consent_text_version", "cgu-2026-01")

      {:ok, consents} = Compliance.capture_consents(quote, %{cgu: true, transmission: true})
      assert by_kind(consents)[:cgu].text_version == "cgu-2026-01"
    end

    test "an explicit text_version overrides the default", %{quote: quote} do
      {:ok, consents} =
        Compliance.capture_consents(quote, %{
          cgu: true,
          transmission: true,
          text_version: "explicit-9"
        })

      assert by_kind(consents)[:cgu].text_version == "explicit-9"
    end
  end
end
