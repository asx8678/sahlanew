defmodule Sahla.Encrypted.Map do
  @moduledoc """
  Ecto type for map columns encrypted at rest via `Sahla.Vault` (AES-GCM-256).

  Used for PII metadata that must not sit plaintext in the database, such as
  the original filename and content type of an uploaded relevé d'information.
  """
  use Cloak.Ecto.Map, vault: Sahla.Vault
end
