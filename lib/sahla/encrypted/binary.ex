defmodule Sahla.Encrypted.Binary do
  @moduledoc """
  Ecto type for PII columns encrypted at rest via `Sahla.Vault` (AES-GCM-256).

  Use for phone numbers, CIN, full names and relevé metadata (§8, §12). The
  ciphertext is not searchable — pair with a `Sahla.Hashed.HMAC` column when a
  value must support equality lookup (e.g. `phone` + `phone_hash`).
  """
  use Cloak.Ecto.Binary, vault: Sahla.Vault
end
