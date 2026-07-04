defmodule Sahla.Notifications.LogTest do
  use Sahla.DataCase, async: true

  alias Sahla.Notifications.{DeliveryLog, Log}

  defp record(attrs) do
    Log.record(
      Map.merge(
        %{
          channel: :sms,
          recipient: "212612345678",
          template: "otp_code",
          idempotency_key: "idem-#{System.unique_integer([:positive])}"
        },
        Map.new(attrs)
      )
    )
  end

  describe "record/1" do
    test "hashes the recipient (keyed HMAC) and never persists the raw value" do
      {:ok, log} = record(%{})
      reloaded = Repo.get!(DeliveryLog, log.id)

      assert reloaded.to_hash
      # deterministic keyed HMAC, not the raw phone
      assert reloaded.to_hash ==
               :crypto.mac(
                 :hmac,
                 :sha256,
                 Application.fetch_env!(:sahla, Sahla.Hashed.HMAC)[:secret],
                 "212612345678"
               )

      %{rows: [[raw]]} =
        Repo.query!("SELECT to_hash FROM notifications_log WHERE id = $1", [
          Ecto.UUID.dump!(log.id)
        ])

      refute String.contains?(raw, "212612345678")
    end

    test "payload stores only a safe projection (no OTP code or raw phone)" do
      {:ok, log} =
        record(%{payload: %{"code" => "123456", "phone" => "212612345678", "expires_in" => 300}})

      assert log.payload == %{"expires_in" => 300}
      refute Map.has_key?(log.payload, "code")
      refute Map.has_key?(log.payload, "phone")
    end

    test "a duplicate idempotency_key is rejected" do
      {:ok, _} = record(%{idempotency_key: "dup-key"})
      assert {:error, changeset} = record(%{idempotency_key: "dup-key"})
      assert %{idempotency_key: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects an invalid channel" do
      assert {:error, changeset} = record(%{channel: :carrier_pigeon})
      assert %{channel: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "update_status/3" do
    test "resolves by provider_id and advances the status" do
      {:ok, _} = record(%{provider_id: "prov-1", status: :sent})

      assert {:ok, updated} = Log.update_status("prov-1", :delivered, %{cost_centimes: 30})
      assert updated.status == :delivered
      assert updated.cost_centimes == 30
    end

    test "a terminal status is a no-op" do
      {:ok, _} = record(%{provider_id: "prov-2", status: :failed})

      assert {:ok, log} = Log.update_status("prov-2", :delivered)
      assert log.status == :failed
    end

    test "an unknown provider_id returns an error" do
      assert {:error, :not_found} = Log.update_status("nope", :delivered)
    end
  end
end
