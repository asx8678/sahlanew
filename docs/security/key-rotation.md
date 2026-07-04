# Key rotation: CLOAK_KEY and HMAC_KEY

How to rotate the PII encryption keys without downtime or data loss.
Applies to `Sahla.Vault` (AES-GCM-256, `CLOAK_KEY`) and `Sahla.Hashed.HMAC`
(`HMAC_KEY`). Both live only in the production environment file
(`/etc/sahla/app.env`) — never in the repo.

## Rotating CLOAK_KEY (vault key)

Cloak vaults support multiple ciphers: the `:default` cipher encrypts new
writes, while every other listed cipher can still **decrypt** rows written
under it (each ciphertext is prefixed with its cipher's `tag`). Rotation is
therefore a three-phase, zero-downtime procedure:

### 1. Add the new key as default, keep the old one as retired

```bash
openssl rand -base64 32   # -> new key, e.g. NEWKEY...
```

In `/etc/sahla/app.env`, keep `CLOAK_KEY` (old) and add `CLOAK_KEY_V2` (new).
In `config/runtime.exs`, configure both ciphers — new first as `:default`
with a **new tag**:

```elixir
config :sahla, Sahla.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V2", key: new_key, iv_length: 12},
    retired: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: old_key, iv_length: 12}
  ]
```

Deploy. New writes now use V2; existing V1 rows still decrypt.

### 2. Re-encrypt existing data

Run the re-encrypt job (an Oban maintenance job once available; until then a
release task). Re-saving each encrypted field re-writes it under the current
`:default` cipher. For each table with encrypted columns:

```elixir
# bin/sahla eval 'Sahla.Release.reencrypt()'  — iterates tables with
# Sahla.Encrypted.* columns and re-persists each row, e.g.:
Repo.transaction(fn ->
  from(q in Quote) |> Repo.stream() |> Enum.each(&(&1 |> Ecto.Changeset.change(%{}) |> force_field_updates |> Repo.update!()))
end)
```

Verify completion: no ciphertext with the old tag remains. Cloak prefixes the
tag in cleartext, so:

```sql
SELECT count(*) FROM quotes WHERE substring(phone from 1 for 20) LIKE '%AES.GCM.V1%';
-- must be 0 for every encrypted column
```

### 3. Drop the retired cipher

Remove the `retired:` entry from runtime.exs and the old key from
`/etc/sahla/app.env`; rename `CLOAK_KEY_V2` to `CLOAK_KEY`. Deploy. Rows that
somehow escaped re-encryption would now fail to decrypt loudly — which is why
step 2's verification query must return 0 first.

## Rotating HMAC_KEY (lookup-hash key)

HMAC digests are deterministic per key — rotating the key changes **every**
hash, so this is a recompute, not a re-encrypt:

1. Deploy with both keys available (`HMAC_KEY_NEW` alongside `HMAC_KEY`).
2. Backfill every `*_hash` column by recomputing the HMAC of the decrypted
   source field under the new key (the plaintext is recoverable from its
   paired `Sahla.Encrypted.Binary` column).
3. Swap `HMAC_KEY` to the new value, remove the old; deploy.

During step 2 lookups against not-yet-backfilled rows miss; run the backfill
quickly (single UPDATE pass per table) and schedule it in a low-traffic
window. Do NOT rotate HMAC_KEY and CLOAK_KEY simultaneously — the HMAC
backfill needs the vault stable to read plaintexts.

## When to rotate

- Scheduled: yearly.
- Immediately: key exposure suspected, personnel offboarding with prod
  access, CNDP/incident requirement.
