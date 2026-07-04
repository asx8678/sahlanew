defmodule Sahla.Vault do
  @moduledoc """
  Cloak vault encrypting PII at rest (phone, CIN, full names, relevé metadata)
  per Law 09-08/CNDP and §12.

  Ciphers are configured at runtime in `config/runtime.exs`: AES-GCM-256 keyed
  from the `CLOAK_KEY` env var in prod, and a deliberately non-secret derived
  key in dev/test. The ciphers list supports multiple entries — the `:default`
  cipher encrypts new data while retired ciphers keep decrypting old rows —
  which is how key rotation works (see docs/security/key-rotation.md).
  """
  use Cloak.Vault, otp_app: :sahla
end
