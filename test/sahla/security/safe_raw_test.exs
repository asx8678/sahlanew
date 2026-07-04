defmodule Sahla.Security.SafeRawTest do
  use ExUnit.Case, async: true

  alias Sahla.Security.SafeRaw

  # Collects every key (stringified) at any depth.
  defp all_keys(map) when is_map(map) do
    Enum.flat_map(map, fn {k, v} -> [to_string(k) | all_keys(v)] end)
  end

  defp all_keys(list) when is_list(list), do: Enum.flat_map(list, &all_keys/1)
  defp all_keys(_scalar), do: []

  defp no_pii?(value) do
    Enum.all?(all_keys(value), fn key ->
      not MapSet.member?(SafeRaw.denylist(), String.downcase(key))
    end)
  end

  describe "safe_raw/1 (denylist)" do
    test "drops known PII keys at the top level" do
      input = %{
        "phone" => "212612345678",
        "email" => "a@b.ma",
        "cin" => "AB1234",
        "first_name" => "Amina",
        "last_name" => "El Fassi",
        "otp" => "123456",
        "code" => "999999",
        "token" => "secrettoken",
        "utm_source" => "google",
        "expires_in" => 300
      }

      result = SafeRaw.safe_raw(input)
      assert result == %{"utm_source" => "google", "expires_in" => 300}
    end

    test "drops PII nested at any depth, including inside lists" do
      input = %{
        "meta" => %{"provider" => "infobip", "recipient" => "212600000000"},
        "events" => [
          %{"status" => "delivered", "phone" => "212611111111"},
          %{"status" => "failed", "email" => "x@y.ma"}
        ]
      }

      result = SafeRaw.safe_raw(input)

      assert no_pii?(result)
      assert result["meta"] == %{"provider" => "infobip"}
      assert result["events"] == [%{"status" => "delivered"}, %{"status" => "failed"}]
    end

    test "keeps look-alike keys that are not PII (exact match only)" do
      input = %{"status_code" => 200, "country_code" => "MA", "provider_code" => "OK"}
      assert SafeRaw.safe_raw(input) == input
    end

    test "stringifies atom keys" do
      assert SafeRaw.safe_raw(%{status: "ok", phone: "212600000000"}) == %{"status" => "ok"}
    end

    test "passes scalars and lists through unchanged" do
      assert SafeRaw.safe_raw("hello") == "hello"
      assert SafeRaw.safe_raw([1, 2, 3]) == [1, 2, 3]
    end
  end

  describe "safe_raw/2 (allowlist)" do
    test "keeps only permitted top-level keys and drops the rest" do
      input = %{"utm_source" => "fb", "phone" => "2126", "note" => "secret", "status" => "ok"}

      assert SafeRaw.safe_raw(input, ["utm_source", "status"]) == %{
               "utm_source" => "fb",
               "status" => "ok"
             }
    end

    test "still scrubs PII nested inside a kept key" do
      input = %{"payload" => %{"status" => "sent", "phone" => "2126"}, "drop_me" => 1}
      assert SafeRaw.safe_raw(input, ["payload"]) == %{"payload" => %{"status" => "sent"}}
    end

    test "accepts atom keys in the allowlist" do
      assert SafeRaw.safe_raw(%{"a" => 1, "b" => 2}, [:a]) == %{"a" => 1}
    end
  end

  describe "property: no denylisted key survives at any depth (randomized)" do
    test "random nested structures are always scrubbed" do
      :rand.seed(:exsss, {17, 42, 99})
      safe_keys = ~w(utm status_code template_id provider_id expires_in region amount)
      pii_keys = MapSet.to_list(SafeRaw.denylist())
      pool = safe_keys ++ pii_keys

      for _ <- 1..200 do
        input = gen(3, pool)
        result = SafeRaw.safe_raw(input)
        assert no_pii?(result), "PII survived in: #{inspect(result)} from #{inspect(input)}"
      end
    end
  end

  # Random jsonb-ish value up to `depth` levels deep, drawing map keys from `pool`.
  defp gen(0, _pool), do: Enum.random(["str", 1, true, nil])

  defp gen(depth, pool) do
    case :rand.uniform(3) do
      1 -> Enum.random(["str", 7, false])
      2 -> for _ <- 1..:rand.uniform(3), do: gen(depth - 1, pool)
      3 -> for _ <- 1..:rand.uniform(4), into: %{}, do: {Enum.random(pool), gen(depth - 1, pool)}
    end
  end
end
