defmodule Sahla.Hashed.HMAC do
  @moduledoc """
  Ecto type producing a **keyed** HMAC-SHA256 digest for lookup columns such as
  `quotes.phone_hash` — never a bare SHA256 (Lessons, §12): without the key, a
  phone number's hash cannot be precomputed from the small MA number space.

  The key comes from the `HMAC_KEY` env var in prod (`config :sahla,
  Sahla.Hashed.HMAC` in runtime.exs) and is separate from the vault key, so
  rotating one does not invalidate the other. Deterministic by design: the same
  input always yields the same digest, enabling `WHERE phone_hash = $1` lookups.
  """
  use Cloak.Ecto.HMAC, otp_app: :sahla
end
