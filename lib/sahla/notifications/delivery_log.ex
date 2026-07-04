defmodule Sahla.Notifications.DeliveryLog do
  @moduledoc """
  A persisted record of every message sent (§8, §10.7) — for compliance, cost
  tracking and exactly-once idempotency.

  The recipient is stored only as a **keyed HMAC** (`to_hash`), never raw
  (Lessons); `payload` keeps a non-PII projection (no OTP codes, phones or
  emails). `idempotency_key` is unique so a retried send is a no-op.
  """
  use Sahla.Schema

  import Ecto.Changeset

  alias Sahla.Security.SafeRaw

  @channels [:sms, :email, :whatsapp]
  @statuses [:queued, :sent, :delivered, :failed]
  @terminal_statuses [:delivered, :failed]

  schema "notifications_log" do
    field :channel, Ecto.Enum, values: @channels
    field :recipient, :string, virtual: true, redact: true
    field :to_hash, Sahla.Hashed.HMAC, redact: true
    field :template, :string
    field :payload, :map, default: %{}
    field :provider_id, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :cost_centimes, :integer
    field :sent_at, :utc_datetime
    field :idempotency_key, :string

    timestamps()
  end

  def channels, do: @channels
  def statuses, do: @statuses
  def terminal?(status), do: status in @terminal_statuses

  @doc "Records a message. Hashes the recipient and strips PII from the payload."
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :channel,
      :recipient,
      :template,
      :payload,
      :provider_id,
      :status,
      :cost_centimes,
      :sent_at,
      :idempotency_key
    ])
    |> validate_required([:channel, :recipient, :template, :idempotency_key])
    |> put_to_hash()
    |> sanitize_payload()
    |> check_constraint(:channel, name: :notifications_log_channel_must_be_valid)
    |> check_constraint(:status, name: :notifications_log_status_must_be_valid)
    |> unique_constraint(:idempotency_key)
  end

  @doc "Updates delivery status/cost/sent_at from a provider callback."
  def status_changeset(log, attrs) do
    log
    |> cast(attrs, [:status, :provider_id, :cost_centimes, :sent_at])
    |> validate_required([:status])
    |> check_constraint(:status, name: :notifications_log_status_must_be_valid)
  end

  defp put_to_hash(changeset) do
    case get_change(changeset, :recipient) do
      nil -> changeset
      recipient -> put_change(changeset, :to_hash, recipient)
    end
  end

  defp sanitize_payload(changeset) do
    case get_change(changeset, :payload) do
      nil -> changeset
      payload -> put_change(changeset, :payload, SafeRaw.safe_raw(payload))
    end
  end
end
