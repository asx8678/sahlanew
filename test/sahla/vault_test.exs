defmodule Sahla.VaultTest do
  use Sahla.DataCase, async: true

  alias Sahla.Encrypted
  alias Sahla.Hashed

  describe "Encrypted.Binary" do
    test "round-trips a value through dump and load" do
      plaintext = "0612345678"

      assert {:ok, ciphertext} = Encrypted.Binary.dump(plaintext)
      assert {:ok, ^plaintext} = Encrypted.Binary.load(ciphertext)
    end

    test "the bytes stored in Postgres are not the plaintext" do
      plaintext = "AB123456"
      {:ok, ciphertext} = Encrypted.Binary.dump(plaintext)

      # Store and read back through a real Postgres bytea column.
      Repo.query!("CREATE TEMP TABLE pii_roundtrip (val bytea)")
      Repo.query!("INSERT INTO pii_roundtrip (val) VALUES ($1)", [ciphertext])
      %{rows: [[stored]]} = Repo.query!("SELECT val FROM pii_roundtrip")

      refute stored == plaintext
      refute String.contains?(stored, plaintext)
      assert {:ok, ^plaintext} = Encrypted.Binary.load(stored)
    end

    test "encrypting the same value twice yields different ciphertexts (random IV)" do
      {:ok, a} = Encrypted.Binary.dump("same value")
      {:ok, b} = Encrypted.Binary.dump("same value")
      refute a == b
    end
  end

  describe "Hashed.HMAC" do
    test "is deterministic: same input, same digest" do
      assert {:ok, digest} = Hashed.HMAC.dump("0612345678")
      assert {:ok, ^digest} = Hashed.HMAC.dump("0612345678")
    end

    test "is a keyed HMAC-SHA256, not a bare SHA256" do
      value = "0612345678"
      {:ok, digest} = Hashed.HMAC.dump(value)

      secret = Application.fetch_env!(:sahla, Sahla.Hashed.HMAC)[:secret]
      assert digest == :crypto.mac(:hmac, :sha256, secret, value)
      refute digest == :crypto.hash(:sha256, value)
    end

    test "a different HMAC key produces a different digest" do
      value = "0612345678"
      secret = Application.fetch_env!(:sahla, Sahla.Hashed.HMAC)[:secret]

      assert :crypto.mac(:hmac, :sha256, secret, value) !=
               :crypto.mac(:hmac, :sha256, "another-key", value)
    end
  end
end
