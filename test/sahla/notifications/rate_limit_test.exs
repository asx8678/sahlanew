defmodule Sahla.Notifications.RateLimitTest do
  # async: false — the ETS buckets and the :rate_limits config are global.
  use ExUnit.Case, async: false

  alias Sahla.Notifications.RateLimit

  # Unique per-test identity so buckets never collide across tests.
  defp uid, do: "t#{System.unique_integer([:positive])}"

  setup do
    on_exit(fn -> Application.delete_env(:sahla, :rate_limits) end)
    :ok
  end

  test "staying under the limit returns {:allow}" do
    ip = uid()
    Application.put_env(:sahla, :rate_limits, otp_per_ip_per_day: 3)

    assert RateLimit.otp_per_ip(ip) == {:allow}
    assert RateLimit.otp_per_ip(ip) == {:allow}
  end

  test "exceeding the limit returns {:deny, retry_after} in seconds" do
    phone = uid()
    Application.put_env(:sahla, :rate_limits, otp_per_phone_per_day: 2)

    assert RateLimit.otp_per_phone(phone) == {:allow}
    assert RateLimit.otp_per_phone(phone) == {:allow}
    assert {:deny, retry_after} = RateLimit.otp_per_phone(phone)
    assert retry_after > 0
  end

  test "repeated hits increment the same bucket (deny after limit reached)" do
    ip = uid()
    Application.put_env(:sahla, :rate_limits, funnel_starts_per_ip_per_hour: 5)

    results = for _ <- 1..7, do: RateLimit.funnel_start_per_ip(ip)
    allows = Enum.count(results, &(&1 == {:allow}))
    denies = Enum.count(results, &match?({:deny, _}, &1))

    assert allows == 5
    assert denies == 2
  end

  test "buckets are independent across keys and dimensions" do
    a = uid()
    b = uid()
    Application.put_env(:sahla, :rate_limits, admin_logins_per_15min: 1)

    assert RateLimit.admin_login(a, "x@e.ma") == {:allow}
    # different email under the same ip is a different bucket
    assert RateLimit.admin_login(a, "y@e.ma") == {:allow}
    # different ip too
    assert RateLimit.admin_login(b, "x@e.ma") == {:allow}
    # exhausting the first bucket denies only it
    assert {:deny, _} = RateLimit.admin_login(a, "x@e.ma")
  end

  test "safe hardcoded defaults apply when settings are absent" do
    phone = uid()
    # default otp_per_phone_per_day is 5
    for _ <- 1..5, do: assert(RateLimit.otp_per_phone(phone) == {:allow})
    assert {:deny, _} = RateLimit.otp_per_phone(phone)
  end
end
