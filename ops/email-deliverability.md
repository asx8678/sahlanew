# Email deliverability (SPF / DKIM / DMARC)

Transactional email (resume link, devis PDF) is sent through **Postmark** via the
Swoosh Postmark adapter (`Swoosh.Adapters.Postmark`, api_client `Swoosh.ApiClient.Req`).
To land in the inbox rather than spam — and to protect the domain from spoofing —
the sending domain must publish SPF, DKIM and DMARC before the first live send.

Sending domain: the domain of `MAIL_FROM_EMAIL` (default `no-reply@sahla.ma`).

## 1. Postmark setup

1. Create a **Server** in Postmark; copy its **Server API Token** into the
   `POSTMARK_API_KEY` env var on the app host (read at boot by `config/runtime.exs`).
2. Add the sending domain under **Sender Signatures → Domains** and open its DNS
   records page — Postmark generates the exact DKIM and Return-Path values below.
3. Set `MAIL_FROM_EMAIL` (and optionally `MAIL_FROM_NAME`) to a signed address on
   that domain. Without `POSTMARK_API_KEY` the app falls back to the Local
   preview adapter and never hits Postmark.

## 2. DNS records to publish

All records live in the DNS zone for the sending domain.

### SPF (TXT on the root domain)

Authorizes Postmark to send for the domain. If a TXT SPF record already exists,
**merge** `include:spf.mtasts.net` into it — do not publish a second SPF record.

```
Type: TXT
Host: @
Value: v=spf1 include:spf.mtasts.net ~all
```

### DKIM (TXT — value from Postmark)

Postmark shows the exact selector host and key. It looks like:

```
Type: TXT
Host: <selector>._domainkey        # e.g. 20240101._domainkey
Value: k=rsa; p=<public-key-from-postmark>
```

### Return-Path / custom bounce domain (CNAME — from Postmark)

Aligns the envelope sender with the domain (improves DMARC alignment):

```
Type: CNAME
Host: pm-bounces        # exact host shown by Postmark
Value: pm.mtasts.net    # exact target shown by Postmark
```

### DMARC (TXT on `_dmarc`)

Start in monitor mode (`p=none`) to collect reports without affecting delivery,
then tighten to `quarantine` and finally `reject` once SPF+DKIM pass cleanly for
a week or two. Point `rua`/`ruf` at a mailbox you actually monitor.

```
Type: TXT
Host: _dmarc
Value: v=DMARC1; p=none; rua=mailto:dmarc@sahla.ma; ruf=mailto:dmarc@sahla.ma; fo=1; adkim=s; aspf=s
```

## 3. Verify before launch

- Postmark **Domains** page shows DKIM and Return-Path **Verified** (green).
- Send a test to a Gmail address; **Show original** must report
  `SPF: PASS`, `DKIM: PASS`, `DMARC: PASS`.
- Optional: check with an external tool (e.g. mail-tester) for a clean score.

## 4. Kill-switch

Live sending is gated by `config :sahla, :email_enabled` (default `true`). Flip
it to `false` at runtime (budget alarm / incident) and `Notifications.Email.deliver/1`
short-circuits to `{:error, :disabled}` without touching Postmark — mirrors the
SMS kill-switch.
