defmodule Sahla.NotificationsTest do
  # async: false — exercises the global Fake SMS agent and app-env kill-switches.
  use Sahla.DataCase, async: false
  import Swoosh.TestAssertions

  alias Sahla.Notifications
  alias Sahla.Notifications.DeliveryLog
  alias Sahla.Notifications.SMSProvider.Fake

  # A provider that always fails, to drive the retry/terminal paths.
  defmodule FailingSMS do
    @behaviour Sahla.Notifications.SMS
    @impl true
    def send(_to, _template, _vars), do: {:error, :provider_down}
  end

  @sms_args %{
    "to" => "+212600000000",
    "template" => "otp",
    "vars" => %{"code" => "1234"},
    "idempotency_key" => "sms-1"
  }

  @email_args %{
    "to" => "sara@example.com",
    "kind" => "resume_link",
    "args" => %{"locale" => "fr", "url" => "https://sahla.ma/resume/abc", "first_name" => "Sara"},
    "idempotency_key" => "email-1"
  }

  setup do
    Fake.clear()
    Application.put_env(:sahla, :sms_enabled, true)
    Application.put_env(:sahla, :email_enabled, true)

    on_exit(fn ->
      Application.delete_env(:sahla, :sms_adapter)
      Application.put_env(:sahla, :sms_enabled, true)
      Application.put_env(:sahla, :email_enabled, true)
    end)

    :ok
  end

  # A bare Oban.Job for the synchronous core; attempt/max drive the retry branch.
  defp job(attempt \\ 1, max \\ 3), do: %Oban.Job{attempt: attempt, max_attempts: max, args: %{}}

  defp log_for(key), do: Repo.get_by!(DeliveryLog, idempotency_key: key)

  describe "run_sms/2" do
    test "queues a DeliveryLog then marks it sent with provider_id and cost" do
      assert :ok = Notifications.run_sms(@sms_args, job())

      log = log_for("sms-1")
      assert log.channel == :sms
      assert log.status == :sent
      assert log.provider_id =~ "fake-"
      assert log.cost_centimes == 0
      assert log.sent_at
      assert length(Fake.sent()) == 1
    end

    test "a duplicate delivery with the same idempotency_key does not double-send" do
      assert :ok = Notifications.run_sms(@sms_args, job())
      assert :ok = Notifications.run_sms(@sms_args, job())

      assert length(Fake.sent()) == 1
      assert Repo.aggregate(DeliveryLog, :count) == 1
      assert log_for("sms-1").status == :sent
    end

    test "the kill-switch short-circuits to failed without calling the provider" do
      Application.put_env(:sahla, :sms_enabled, false)

      assert {:cancel, :disabled} = Notifications.run_sms(@sms_args, job())
      assert Fake.sent() == []
      assert log_for("sms-1").status == :failed
    end

    test "a non-Moroccan recipient is rejected without a retry" do
      args = %{@sms_args | "to" => "+33600000000", "idempotency_key" => "sms-intl"}

      assert {:cancel, :recipient_not_allowed} = Notifications.run_sms(args, job())
      assert Fake.sent() == []
      assert log_for("sms-intl").status == :failed
    end

    test "a transient provider error retries, then fails on the final attempt" do
      Application.put_env(:sahla, :sms_adapter, FailingSMS)

      # Not the last attempt -> hand the error back to Oban for a backoff retry.
      assert {:error, :provider_down} = Notifications.run_sms(@sms_args, job(1, 3))
      assert log_for("sms-1").status == :queued

      # Last attempt -> mark failed and stop retrying.
      assert {:cancel, :provider_down} = Notifications.run_sms(@sms_args, job(3, 3))
      assert log_for("sms-1").status == :failed
    end

    test "a terminal success stays idempotent even if the provider later breaks" do
      assert :ok = Notifications.run_sms(@sms_args, job())
      assert length(Fake.sent()) == 1

      # A re-run never reaches the (now failing) provider — the log is already sent.
      Application.put_env(:sahla, :sms_adapter, FailingSMS)
      assert :ok = Notifications.run_sms(@sms_args, job())
      assert length(Fake.sent()) == 1
    end
  end

  describe "run_email/2" do
    test "delivers the email and logs it sent" do
      assert :ok = Notifications.run_email(@email_args, job())

      assert_email_sent()
      log = log_for("email-1")
      assert log.channel == :email
      assert log.status == :sent
    end

    test "the kill-switch short-circuits to failed without sending" do
      Application.put_env(:sahla, :email_enabled, false)

      assert {:cancel, :disabled} = Notifications.run_email(@email_args, job())
      assert log_for("email-1").status == :failed
      assert_no_email_sent()
    end
  end

  describe "deliver_sms/1 (Oban enqueue)" do
    test "enqueues and delivers exactly once for a given idempotency_key" do
      params = %{to: "+212600000000", template: :otp, vars: %{code: "9"}, idempotency_key: "obk"}

      assert {:ok, _} = Notifications.deliver_sms(params)
      assert {:ok, _} = Notifications.deliver_sms(params)

      # Whether Oban dedupes the enqueue or the log guard no-ops the second run,
      # the recipient is contacted once and there is a single sent log.
      assert length(Fake.sent()) == 1
      assert Repo.aggregate(DeliveryLog, :count) == 1
      assert log_for("obk").status == :sent
    end
  end
end
