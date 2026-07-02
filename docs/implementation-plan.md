# Sahla — Implementation Plan (bd epic/task map)

**Source spec:** [`docs/fplansahla.md`](fplansahla.md) (v1.0, July 2026) — the full functional/architectural plan for the Moroccan insurance comparison platform (Phoenix 1.8 · LiveView · PostgreSQL 16 · native VPS deploy, no Docker).

**This document** maps that spec onto the bd issue tracker: 17 epics, 183 tasks, 475 blocking dependencies. It was produced 2026-07-02 by a 13-analyst multi-agent breakdown (one Opus analyst per domain, each reading the full spec) followed by a planner synthesis pass that removed 4 duplicate tasks, resolved ~35 dependency issues, and added 8 milestone gates. The bd issues are the source of truth for work items; this file is the orientation map.

## Naming decision

The OTP app/module is **`sahla` / `Sahla`** (code-level name). The marketing brand is deliberately TBD (`phase0.brand-name-domain`): no brand strings are hardcoded anywhere — display name, agrément number, phone/WhatsApp numbers and disclaimers all resolve from Settings/gettext.

## Epic map

| bd ID | Epic | Tasks | Phase |
|---|---|---|---|
| `sahla-k2x` | Phase 0: Business, legal & brand foundations | 11 | 0 |
| `sahla-r5o` | Project foundation & core plumbing | 11 | 1 |
| `sahla-ll9` | Design system & UI kit | 9 | 1 |
| `sahla-bai` | Internationalization: FR/AR & RTL | 7 | 1 |
| `sahla-ni1` | Domain data: insurers, products, vehicles, cities, seeds | 9 | 1 |
| `sahla-8vo` | Rating & offers engine | 10 | 1 |
| `sahla-oxe` | Quote funnel (devis) | 13 | 1 |
| `sahla-7du` | Results & offers experience | 9 | 1 |
| `sahla-0of` | Admin: leads workspace, dashboard & exports | 11 | 1 |
| `sahla-8y3` | Admin: rating studio, directory, settings & audit UI | 11 | 1 |
| `sahla-rao` | Content hub, CMS & SEO | 13 | 1 |
| `sahla-tam` | Notifications, messaging & anti-abuse | 10 | 1 |
| `sahla-lrs` | Security, privacy & compliance | 9 | 1 |
| `sahla-8kd` | Deployment, infrastructure & observability | 11 | 1 |
| `sahla-jxp` | Launch hardening, analytics & beta | 14 | 1 |
| `sahla-ww3` | Phase 2: Buy online — accounts, payments, renewals, verticals | 17 | 2 |
| `sahla-im0` | Phase 3: Expansion | 8 | 3 |

Every task carries: a why+what description citing spec sections (§), acceptance criteria (tests included — no separate "write tests" tasks), design notes with the relevant hard-won gotchas, an estimate, and blocking deps. Labels: `phase-0/1/2/3` + epic slug (inherited), plus `human` (business/legal, non-code), `content`, `design`, `gate`.

## Build order — the six milestone gates

Verification happens at **phase boundaries** (gates), not per ticket. Each gate (`bd list -l gate`) runs the full suite — `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix sobelow --exit`, `deps.audit`/`hex.audit`, full `mix test` — plus hand verification of that milestone's DoD:

1. **M1 `sahla-jxp.9` — foundation skeleton** (≈ §14 wk 0–2): app-init, router/health, admin auth + TOTP 2FA + authz, audit, Oban, settings, CI, design tokens + ui-kit, gettext + locale plug, schema conventions, cloak.
2. **M2 `sahla-jxp.10` — catalog + funnel steps 1–3** (wk 3–5): directory/vehicles/cities schemas + autocomplete + seeds, DevisLive shell + autosave/resume, steps 1–3.
3. **M3 `sahla-jxp.11` — quote-to-lead spine** (wk 5–7): rating engine + tables + placeholder grids + golden tests, OTP flow, step 4 + consents, completion → offers page → callback → lead in kanban data <1s. **The money-path gate.**
4. **M4 `sahla-jxp.12` — admin back-office** (wk 7–9): kanban, lead detail (<4 clicks), dashboard, rating studio (edit → simulate → publish), directory admin, abandon follow-ups.
5. **M5 `sahla-jxp.13` — public site, i18n & hardening** (wk 9–11): homepage, guides/insurers/glossary/legal/city pages, sitemap, full FR+AR catalogs (native AR QA), RTL pass, quality floor, Turnstile, retention jobs, security review.
6. **M6 `sahla-jxp.14` — launch go/no-go** (wk 11–12): CI deploy + rollback rehearsal, backup restore drill, monitoring live, k6 load test, 50-user beta ≥95%, DoD checklist, ACAPS dossier ready-to-file, brand/domain/TLS live.

**Phase 2 is hard-gated** behind `phase2.gate-kickoff` (MVP launched + first-100-leads signal — the §15 feature-creep guard); Phase 3 behind `phase3.gate-kickoff` (Phase 2 proven). Nothing in phases 2–3 appears in `bd ready` until those gates are deliberately closed.

Engineering never blocks on business work: the rating engine ships with **realistic placeholder grids** (`rating-engine.placeholder-grids`, calibrated to §3.1 price ranges); real broker barèmes (`phase0.rate-grids`, human) replace them through the rating studio without a deploy.

## Key architecture decisions carried from the previous build

These are baked into task design notes; they are non-negotiable conventions:

- **No hackney, ever** (idna conflict with req/mint). HTTP = Req/Finch; Sentry uses a custom Finch transport.
- **PII discipline:** cloak AES-GCM for phone/CIN/names/relevé metadata; **keyed-HMAC** hash columns for lookup (never bare SHA256); `safe_raw/1` non-PII projections for every jsonb payload (consents, notifications_log, audit before/after, rating inputs); admin-only booleans never `cast/3` from public changesets.
- **OTP:** hashed codes, 5-min TTL, 3 attempts, per-phone AND per-IP limits, +212 allowlist; verification bound to the exact phone — editing it resets verification (previous bypass bug).
- **External providers** (SMS, Turnstile, later CMI/WhatsApp): behaviour + deterministic Fake default, config-swapped via `Application.get_env`, secrets only via `runtime.exs`, webhooks CSRF-exempt + signature-verified in the context (`secure_compare`), applied exactly-once in `Repo.transaction`, all flag-gated (flags default OFF).
- **LiveView gotchas:** empty-states OUTSIDE `phx-update="stream"` containers behind a count assign; `desc: :id` tiebreaker on every newest-first query; everything referenced as `@x` in HEEx is a socket assign; one-tap option cards over native `<select>` for small enums; SEO/meta renders into `<head>` via the layout head slot.
- **i18n:** English dev-key msgids; complete FR + AR catalogs are explicit tasks (AR gets native-speaker QA — gate M5 fails on empty msgstr); locale resolution path→cookie→session→header→default(fr); Tailwind logical utilities only, enforced by a grep guard; Western digits in both locales.
- **Money** = integer centimes MAD; **ids** = uuid; **FR/AR text** = paired `_fr`/`_ar` columns; **Oban migration** version-agnostic; rating engine is **pure** (no DB) and every displayed price is reproducible from its immutable `rating_run` snapshot.

## Working the plan

```bash
bd ready                      # what's unblocked now
bd show <id>                  # full task spec (description, acceptance, design, deps)
bd list -l gate               # the milestone gates
bd list -l human              # business/legal tasks (mostly phase0)
bd update <id> --claim        # take work
bd close <id> --suggest-next  # close + see what it unblocked
```

Current ready roots: `foundation.app-init` (`sahla-r5o.1`) starts the build; `deploy-ops.provision-script` and the Phase-0 human tasks (broker partnership, CNDP, brand, SMS provider, KPI plan) run in parallel on the business track.

The slug→ID map for all 200+ issues is committed at [`docs/build-plan-id-map.json`](build-plan-id-map.json); `bd search <keyword>` finds tasks fast. One follow-up is filed as `sahla-jxp.15`: an independent adversarial completeness re-check of this plan against the spec (the original critic agents were cut short by a session limit; the dependency/overlap review was completed manually by the planner).
