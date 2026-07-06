defmodule Sahla.Telemetry.FunnelTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Sahla.Telemetry.Funnel

  # Each test attaches a unique handler id so concurrent async tests don't
  # collide on the global telemetry handler table. The handler closes over the
  # test pid (`self/0`) so it can deliver the event to this mailbox.
  defp capture(event) do
    id = {__MODULE__, event, make_ref()}
    parent = self()

    :telemetry.attach(
      id,
      [:sahla, :funnel, event],
      fn _name, measurements, metadata, _config ->
        send(parent, {event, measurements, metadata})
      end,
      nil
    )

    id
  end

  defp detach(id), do: :telemetry.detach(id)

  describe "step_completed/4" do
    test "emits [:sahla, :funnel, :step_completed] with non-PII metadata" do
      id = capture(:step_completed)

      Funnel.step_completed("quote-token-123", :vehicle, 1, "fr")

      assert_received {:step_completed, measurements, metadata}
      assert measurements == %{count: 1}

      assert metadata == %{
               token: "quote-token-123",
               step: :vehicle,
               step_number: 1,
               locale: "fr"
             }

      detach(id)
    end

    test "metadata carries no phone or name fields" do
      id = capture(:step_completed)

      Funnel.step_completed("t", :contact, 4, "ar")

      assert_received {:step_completed, _measurements, metadata}
      refute Map.has_key?(metadata, :phone)
      refute Map.has_key?(metadata, :first_name)
      refute Map.has_key?(metadata, :last_name)
      refute Map.has_key?(metadata, :email)

      detach(id)
    end
  end

  describe "otp_verified/2" do
    test "emits [:sahla, :funnel, :otp_verified] with token and locale only" do
      id = capture(:otp_verified)

      Funnel.otp_verified("quote-token-456", "fr")

      assert_received {:otp_verified, measurements, metadata}
      assert measurements == %{count: 1}
      assert metadata == %{token: "quote-token-456", locale: "fr"}

      detach(id)
    end

    test "metadata exposes no phone" do
      id = capture(:otp_verified)

      Funnel.otp_verified("t", "ar")

      assert_received {:otp_verified, _measurements, metadata}
      refute Map.has_key?(metadata, :phone)

      detach(id)
    end
  end

  describe "lead_created/3" do
    test "emits [:sahla, :funnel, :lead_created] with lead id, quote id and source" do
      id = capture(:lead_created)

      Funnel.lead_created("lead-id-1", "quote-id-1", "google")

      assert_received {:lead_created, measurements, metadata}
      assert measurements == %{count: 1}
      assert metadata == %{lead_id: "lead-id-1", quote_id: "quote-id-1", source: "google"}

      detach(id)
    end

    test "metadata carries no phone or name fields" do
      id = capture(:lead_created)

      Funnel.lead_created("lead-1", "quote-1", "site")

      assert_received {:lead_created, _measurements, metadata}
      refute Map.has_key?(metadata, :phone)
      refute Map.has_key?(metadata, :first_name)
      refute Map.has_key?(metadata, :last_name)
      refute Map.has_key?(metadata, :email)

      detach(id)
    end
  end
end
