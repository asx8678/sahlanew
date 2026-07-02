# Implementation Plan — Insurance Comparison Platform for Morocco
### Working title: **"Moucompare"** (alternatives: Taamine.ma, Assurly.ma, Moukarana.ma — validate name + .ma domain in Phase 0)

**Stack:** Elixir · Phoenix (LiveView) · PostgreSQL · native Linux deployment (no Docker)
**Model:** mubi.pl / rankomat.pl adapted to the Moroccan market (auto insurance first)
**Document version:** 1.0 — July 2026

---

## Table of contents

1. Executive summary
2. Benchmark — what mubi.pl and rankomat.pl actually offer
3. Morocco adaptation — market, regulation, and what must change
4. Product scope and phasing (MVP → V2 → V3)
5. Functional specification — public website
6. UX / UI design direction
7. System architecture (Phoenix)
8. Data model (PostgreSQL / Ecto)
9. The rating & offers engine
10. Admin panel specification
11. Integrations (payments, SMS, WhatsApp, email, analytics)
12. Security, privacy and regulatory compliance
13. Native deployment runbook (no Docker)
14. Delivery plan, team and timeline
15. Risks and mitigations
16. Appendices (repo layout, env vars, funnel field dictionary)

---

## 1. Executive summary

We are building a **bilingual (French / Arabic) insurance comparison and distribution platform for Morocco**, starting with **compulsory auto insurance (Responsabilité Civile)** and its voluntary extensions (tiers étendu, tous risques, assistance…), following the product playbook proven by mubi.pl and rankomat.pl in Poland: a free, fast multi-step calculator → a comparison table of offers → purchase online or with a human advisor → a customer panel, renewal reminders and a content hub that drives SEO traffic.

**The one structural difference vs. Poland**, and the most important design decision in this whole plan: Polish comparators receive **live, binding prices through insurer APIs**. Moroccan insurers (Wafa, RMA, Sanlam, AXA Maroc, AtlantaSanad, Allianz Maroc, MAMDA-MCMA…) do not expose public quoting APIs today. Therefore:

- **MVP (Phase 1):** the platform computes **indicative premiums from a versioned, admin-managed rating engine** (based on the regulated RC tariff structure + per-insurer commercial positioning) and converts visitors into **qualified, OTP-verified leads** that a licensed intermediary (partner courtier, later our own agrément) closes by phone/WhatsApp. This is exactly the model already used by the few Moroccan players (mesassurances.ma, assure.ma, topassur.ma) — but none of them has mubi-grade UX, accounts, automation or an operations back-office. That is the gap we exploit.
- **Phase 2:** for insurers where a partnership is signed, add **binding quotes + online payment (CMI) + e-attestation delivery**, i.e. the full mubi experience, insurer by insurer.

**Business model:** free for users; revenue = intermediation commission on placed policies (paid by insurer to the courtier) + later: renewals book, ancillary verticals (moto, travel, habitation, santé complémentaire).

**Legal wrapper (decide in Phase 0):** either (a) partner with an ACAPS-licensed courtier who legally "presents" the insurance operations while we run the tech + marketing, or (b) obtain our own intermediary agrément. Recommendation: **launch with (a), pursue (b) in parallel** — details in §12.

> Note on "cloning": we replicate the *feature set and business model* of mubi/rankomat. All branding, copy, illustrations and content must be original — no copying of their texts, design assets or trademarks.

---

## 2. Benchmark — what mubi.pl and rankomat.pl actually offer

Feature inventory compiled from their public sites and third-party reviews (July 2026). ✅ = present, ◐ = partial.

| # | Feature | mubi.pl | rankomat.pl | Notes for our build |
|---|---------|---------|-------------|---------------------|
| 1 | Multi-step quote form ("kalkulator"), ~3–5 min | ✅ | ✅ | 2 macro-steps (vehicle → driver/history), field-level tooltips |
| 2 | Prefill vehicle data from plate / VIN registry | ✅ | ✅ | PL has CEP/Info-Ekspert registries; Morocco has no public equivalent → autocomplete catalog instead |
| 3 | Live offers from 14–19+ insurers | ✅ | ✅ | Via insurer integrations; our MVP = rating engine, V2 = per-insurer integrations |
| 4 | Results table: price + scope, filter & sort (price, coverage, insurer rating) | ✅ | ✅ | Must-have |
| 5 | Curated ranking badges: "cheapest / best value / expert pick" with reasons | ◐ | ✅ | Rankomat's 2026 ranking feature — great trust device, cheap to build |
| 6 | Side-by-side compare tray for selected offers | ✅ | ✅ | Cap at 3 offers |
| 7 | Full policy conditions (OWU) accessible from offer | ✅ | ✅ | We attach Conditions Générales PDFs per product |
| 8 | Buy online (pay + policy by email in minutes) | ✅ | ✅ | Phase 2 for us (CMI + partner insurers) |
| 9 | Buy by phone with an advisor / callback | ✅ | ✅ | MVP core conversion path (+ WhatsApp for Morocco) |
| 10 | Installment payment of premium | ✅ | ◐ | Common in MA via insurer/broker facilities — flag on offers |
| 11 | Customer panel: saved data, auto-refill next calculation, documents | ✅ | ✅ | Phase 2 |
| 12 | Renewal reminders before policy expiry | ✅ | ✅ | Phase 2 (huge LTV lever — échéance date captured in funnel) |
| 13 | Cashback / referral program (100–150 zł back) | ✅ | ◐ | Phase 2/3; works well in MA too, needs fraud controls |
| 14 | Content hub: expert guides, dictionaries, insurer reviews | ✅ | ✅ | MVP — main SEO engine; FR + AR |
| 15 | User reviews & ratings of insurers/platform | ✅ | ✅ | Phase 2, with moderation |
| 16 | Consent management (GDPR-style granular checkboxes) | ✅ | ✅ | MVP — Law 09-08 / CNDP equivalent |
| 17 | Autosave / resume the form | ✅ | ◐ | MVP — trivial with LiveView + persisted quote row |
| 18 | Human advisor army (rankomat: ~200 agents) | ◐ | ✅ | Our "agent workspace" in the admin panel from day 1 |
| 19 | Other verticals: travel, home, life, health, finance | ◐ | ✅ | Our Phase 3 |
| 20 | 30-day distance-selling withdrawal, transparent legal footer | ✅ | ✅ | Mirror with Moroccan Law 31-08 consumer rules |

**What actually makes them convert** (to preserve at all costs): speed (a price in ~3 minutes), zero jargon with inline explanations, price + scope shown together (never price alone), a human fallback one tap away, and no fee for the user.

---

## 3. Morocco adaptation — market, regulation, and what must change

### 3.1 Market snapshot

- Auto **RC (responsabilité civile) is compulsory** under Law 17-99 (Code des assurances); driving uninsured is an offence. ~5M vehicles in circulation.
- **Main non-life insurers to represent:** Wafa Assurance, RMA, Sanlam Maroc, AXA Assurance Maroc, AtlantaSanad, Allianz Maroc, MAMDA-MCMA, MATU/CAT. Seven or eight brands cover most of the retail auto market.
- **Typical annual premiums:** roughly 1,600–2,500 MAD for RC-only on an older car up to 25,000+ MAD for tous risques on a premium vehicle; a median profile (Dacia/Renault, Casablanca, experienced driver) lands ~3,500–5,500 MAD in tous risques. Prices trend up 4–6%/yr. (Calibrate all of this with the partner broker in Phase 0.)
- **Formulas customers know:** *RC seule* → *Tiers étendu* (RC + vol, incendie, bris de glace…) → *Tous risques*; plus options: personnes transportées (PTA), défense & recours, assistance/dépannage, individuelle conducteur, événements climatiques.
- Since **Law 110-14 (in force 2020), coverage of catastrophic events (EVCAT)** is a mandatory component attached to RC contracts — the engine must always add this line.
- **Bonus-malus (CRM — coefficient de réduction-majoration):** new driver starts at 1.00; commonly described as −10%/claim-free year (×0.90) down to a 0.50 floor, +20% (×1.20) per at-fault claim capped at 2.50; the coefficient is portable between insurers via the *relevé d'information*. **Verify the exact current ACAPS parameters in Phase 0** and make them configurable, never hard-coded.
- **Primary RC rating factors:** *puissance fiscale* (fiscal horsepower — the dominant factor), vehicle type/fuel, usage (personal / professional / taxi…), city, driver age & licence seniority, CRM/claims history. AC-type covers add vehicle value, age, franchise level, parking (garage fermé vs street).
- **Public-sector employees (fonctionnaires)** get dedicated discounted offers at several insurers — worth a funnel question.

### 3.2 Regulatory constraints (design inputs, not afterthoughts)

- **Only ACAPS-licensed intermediaries** (agents / courtiers, Law 17-99 art. 289 & 306) may "present insurance operations to the public." Our entity must either hold an agrément or contractually operate under a licensed courtier.
- **Online selling of insurance is legal (since 2007)** and specifically framed by **ACAPS Instruction P.IN.02/2022** on electronic online-sale devices. Two regimes matter to us:
  - *Quote/advertising-only device* (our MVP): notify ACAPS with a device description **within 15 days of go-live**.
  - *Full online subscription device* (Phase 2): **file the dossier with ACAPS before launch** — device URL, detailed subscription process, CGV, consent mechanics, etc. Any later modification must be re-notified.
- ACAPS has announced **automated web-scraping surveillance of online insurance offers** — non-compliant wording (e.g., presenting indicative prices as firm offers, or selling without agrément) will be detected. Every indicative price on our site carries an explicit "prime indicative — devis ferme confirmé par le courtier/assureur" label.
- **Personal data: Law 09-08 + CNDP** — prior declaration/authorization of processing, purpose limitation, consent records, data-subject rights. (§12.)
- **Consumer protection Law 31-08** for distance selling (information duties, withdrawal where applicable).

### 3.3 Product-level adaptations vs. the Polish blueprint

| Topic | Poland (mubi/rankomat) | Our Moroccan version |
|---|---|---|
| Price source | Live insurer APIs, binding | Versioned rating engine (indicative) → per-insurer binding integrations in Phase 2 |
| Vehicle identification | Plate/VIN registry prefill | Marque/modèle/version autocomplete catalog + *puissance fiscale*; plate optional (format `12345-A-67` or `WW` for new cars) |
| Languages | Polish | **French + Arabic (full RTL)**; Darija-flavored marketing copy; Western digits in both |
| Conversion channel | Online payment + call center | **Phone + WhatsApp first**, online payment (CMI) in Phase 2 |
| Payments | Cards, installments | CMI cards; pay-at-agency / broker-collected as fallback; installment flag |
| Identity | PESEL | CIN optional at quote stage (encrypted at rest), required only at policy issuance |
| Compliance | RODO/GDPR, KNF | Law 09-08/CNDP, ACAPS instruction P.IN.02/2022, Law 17-99, Law 31-08 |
| Bonus system | Zniżki history questions | CRM coefficient + relevé d'information upload (photo) to speed broker confirmation |
| Trust builders | TV ambassadors, reviews | ACAPS-agrément display, insurer logos, Google reviews, human advisor photos, physical address |

---

## 4. Product scope and phasing

### Phase 0 — Foundations (2–3 weeks, parallel to design)
Broker partnership signed (or agrément path started) · rate grids obtained from broker/insurer barèmes · ACAPS device classification decided + dossier drafted · CNDP declaration prepared · naming, domain (.ma), brand identity · analytics plan & KPI definitions (quote-start rate, quote-completion rate, lead rate, lead→policy rate, CAC, commission/policy).

### Phase 1 — MVP "Compare & Callback" (10–12 weeks of build)
**Public:** home + auto funnel (FR/AR) → indicative offers page → lead capture with **SMS OTP** → callback scheduling + WhatsApp handoff → confirmation; content hub (guides, insurer pages, FAQ, glossary); legal pages; SEO foundations; Plausible/GA4 analytics; Turnstile anti-bot.
**Admin:** authentication + 2FA, roles; **lead workspace (kanban + timeline)**; quotes explorer; rating-table management with simulator; insurer/product/vehicle-catalog CRUD; CMS; settings; audit log.
**Engine:** rating v1 for RC / Tiers étendu / Tous risques + options, EVCAT + configurable taxes/fees lines, per-insurer positioning coefficients, versioned grids with effective dates.
**Out of scope for MVP:** online payment, user accounts, reviews, referral, non-auto verticals.

### Phase 2 — "Buy Online" (8–10 weeks)
Customer accounts (magic-link + OTP) with saved profiles/vehicles, documents, quote history, **renewal reminders**; CMI online payment + policy-issuance workflow with the first partnered insurer(s) (e-attestation by email/WhatsApp, hard-copy logistics where required); ACAPS full-online-device dossier; reviews & ratings; referral/cashback; **moto** and **travel (incl. Schengen-visa insurance — a proven Moroccan traffic magnet)** verticals; WhatsApp Business API templated notifications.

### Phase 3 — Expansion
Habitation, santé complémentaire (mutuelle), vie/épargne (lead-gen to advisors); B2B fleet quotes; per-insurer API/extranet integrations as they appear; PWA polish or thin mobile app; possible white-label for banks/dealerships.

---
## 5. Functional specification — public website

### 5.1 Sitemap

```
/                         Home (hero = quick-start of the auto funnel)
/assurance-auto           Auto vertical landing (SEO) → funnel
/devis/:token             The funnel (LiveView, resumable via tokenized URL)
/offres/:token            Results / comparison page
/offres/:token/:offer_id  Offer detail (garanties, franchises, plafonds, CG PDF)
/rappel/:token            Callback confirmation + slot picking
/guides, /guides/:slug    Content hub (FR/AR)
/assureurs, /assureurs/:slug   Insurer profile pages (SEO + trust)
/lexique                  Insurance glossary FR/AR
/a-propos, /contact, /mentions-legales, /politique-confidentialite, /cgu
/ar/...                   Arabic mirror of every route (RTL)
```

### 5.2 The funnel (the product's heart)

One LiveView, 4 steps, single-column card, progress indicator, every answer persisted server-side on change (autosave). Target: **≤ 3 minutes, ≤ 25 questions, phone-first ergonomics**. Every field has a "?" tooltip in plain language (FR/AR). A quote gets a `token`; the resume link is sent by SMS/email if the user abandons (Oban job, +2h and +24h).

**Step 1 — Le véhicule**
immatriculation (optional; format helper `12345-A-67`, `WW` toggle for brand-new) · marque → modèle → version (autocomplete, pg_trgm) · *puissance fiscale* auto-filled but editable · carburant · date de 1ère mise en circulation · usage (personnel / trajet domicile-travail / professionnel / taxi-VTC) · ville de circulation · stationnement la nuit (garage fermé / parking surveillé / rue) · valeur actuelle estimée (asked only if user later picks Tiers étendu/Tous risques — conditional).

**Step 2 — Le conducteur**
date de naissance · date d'obtention du permis · fonctionnaire ? (oui/non → unlocks dedicated offers) · assureur actuel (select, incl. "aucun / première assurance") · date d'échéance du contrat actuel (feeds renewal reminders) · sinistres responsables sur 36 mois (0/1/2+) · CRM si connu (slider 0.50–2.50 with "je ne sais pas") · option: upload photo du relevé d'information (stored, speeds broker confirmation).

**Step 3 — La couverture**
formule: RC seule / Tiers étendu / Tous risques (3 cards with plain-language scope diagrams) · options toggles: bris de glace, vol, incendie, PTA, défense & recours, assistance 0 km, individuelle conducteur, événements climatiques · niveau de franchise (basse/standard/élevée) when applicable · date d'effet souhaitée (default = échéance or today).

**Step 4 — Vos coordonnées (lead gate)**
prénom, nom · téléphone +212 (**OTP SMS, 4 digits, 3 attempts, rate-limited**) · email (optional, incentivized: "recevez vos devis en PDF") · ville · consent checkboxes: (1) CGU + privacy **required**, (2) transmission du dossier au courtier/assureurs partenaires pour établir les devis **required**, (3) communications commerciales **optional**. Consent text versions + timestamp + IP are stored.

### 5.3 Results page (`/offres/:token`)

- Offer cards sorted by annual premium by default: insurer logo, formula name, **annual + monthly-equivalent price (tabular figures, MAD)**, 4–6 coverage badges, franchise, "détails" link, and two CTAs: **"Être rappelé"** and **"WhatsApp"** (Phase 2 adds **"Souscrire en ligne"** where binding).
- Ranking badges à la rankomat: *La moins chère* / *Meilleur rapport garanties-prix* / *Choix de l'expert* — each with a one-line justification.
- Filters: formula, insurer, price range, options included, installment available. Compare tray (max 3) → side-by-side table.
- Persistent disclaimer strip: *"Primes indicatives calculées selon les barèmes en vigueur — devis ferme confirmé par nos conseillers (courtier agréé ACAPS n° X)."*
- Offer detail: garanties table (plafonds, franchises), exclusions summary, Conditions Générales PDF, insurer profile link.
- Callback flow: pick a slot (30-min windows, working hours, Africa/Casablanca TZ) → creates a Lead with status `rdv_planifié` → SMS confirmation → appears instantly in the agent kanban (PubSub).
- WhatsApp CTA (MVP): `wa.me/<number>?text=<prefilled: token + chosen offer>` deep link → conversation lands on the ops WhatsApp; Phase 2 upgrades to WhatsApp Business API with templates.

### 5.4 Content hub & SEO (MVP)

Guides ("Combien coûte l'assurance auto à Casablanca ?", "CRM/bonus-malus expliqué", "Que faire en cas d'accident — le constat amiable", "Assurance auto pour fonctionnaires"…), insurer profile pages, glossary, FAQ with FAQPage schema.org, city landing pages (Casablanca, Rabat, Marrakech, Tanger, Agadir…). Full FR/AR parity, `hreflang`, sitemap.xml, OpenGraph. Editorial workflow lives in the admin CMS (§10).

---

## 6. UX / UI design direction

**Personality:** a confident, modern Moroccan fintech — *clean like a European insurtech, warm like a Moroccan brand*. It must feel trustworthy to a 45-year-old Casablanca driver **and** effortless to a 25-year-old on a phone. One deliberate aesthetic risk, everything else disciplined.

### 6.1 Design tokens

| Token | Value | Use |
|---|---|---|
| `--color-primary` | **Majorelle blue `#4F5DE1`** | CTAs, links, progress — a blue that is unmistakably Moroccan (Jardin Majorelle), not generic insurance navy |
| `--color-ink` | `#1B1B29` | Text |
| `--color-bg` | `#FAF8F4` (warm sand) | Page background |
| `--color-surface` | `#FFFFFF` | Cards |
| `--color-accent` | Zellige teal `#0E7C6B` | Success, savings highlights, "best value" badge |
| `--color-warm` | Terracotta `#C6552B` | Sparse highlights, promo tags only |
| Radius / shadow | 14px cards, soft single-layer shadow | Friendly, not bubbly |

**Typography (must render FR + AR as one voice):** use the **IBM Plex superfamily** — *IBM Plex Sans* (Latin) + *IBM Plex Sans Arabic*, same optical rhythm, excellent free licensing. Display headings: Plex Sans SemiBold, tight tracking, large sizes (no second display family — Arabic parity beats novelty here). Prices: Plex Sans with **tabular numerals**, the biggest element on any offer card. Utility/labels: Plex Sans 13–14px, letter-spaced caps for eyebrows (Latin only; Arabic eyebrows use weight instead of caps).

**Signature element (the memorable thing):** an **eight-point zellige star** used as a functional motif — it is the funnel's progress marker (each completed step fills one facet), the list bullet in guarantees tables, and a faint oversized outline in the hero background. One motif, three jobs, zero clip-art camels.

### 6.2 Key screens (wireframes)

**Home / hero — the thesis is "your price in 3 minutes":**
```
┌──────────────────────────────────────────────────────────────┐
│  logo            Guides   Assureurs   العربية   ☎ 05 22 …     │
├──────────────────────────────────────────────────────────────┤
│   Assurez votre voiture au juste prix.                       │
│   Comparez les offres de 7 assureurs en 3 minutes.           │
│                                                              │
│   ┌────────────────────────────┐  ┌────────────────────┐     │
│   │ Immatriculation  12345-A-6 │  │  Comparer  →       │     │
│   └────────────────────────────┘  └────────────────────┘     │
│   ( Je n'ai pas encore la voiture / WW )                      │
│                                                              │
│   [Wafa][RMA][Sanlam][AXA][Atlanta][Allianz][MAMDA] logos    │
│   ✓ Gratuit  ✓ Sans engagement  ✓ Conseiller dédié           │
└──────────────────────────────────────────────────────────────┘
   below: 3 proof cards (économie moyenne · avis · agrément) →
   how-it-works (3 steps) → guides teaser → FAQ → footer légal
```

**Funnel step (mobile-first, one column):**
```
┌───────────────────────────────┐
│ ✦✦✧✧   Étape 2/4 · Conducteur │   ← zellige-star progress
│                               │
│  Votre date de naissance      │
│  [ 12 ] [ 03 ] [ 1988 ]       │
│                               │
│  Permis obtenu en…      (?)   │
│  [ 2009            ▾ ]        │
│                               │
│  ┌───────────┐ ┌───────────┐  │
│  │  Retour   │ │ Continuer │  │
│  └───────────┘ └───────────┘  │
│  🔒 Données protégées · CNDP  │
└───────────────────────────────┘
```

**Results (desktop: filters left; mobile: filter sheet):**
```
┌────────────┬────────────────────────────────────────────────┐
│ Filtres    │  ★ La moins chère                              │
│ Formule ▾  │ ┌────────────────────────────────────────────┐ │
│ Assureur ▾ │ │ [logo RMA]  Tiers étendu                   │ │
│ Options ▾  │ │ 2 940 MAD/an   (≈245 MAD/mois)             │ │
│ Prix ─────○│ │ ✓RC ✓Vol ✓Incendie ✓Bris de glace  Fr. 500 │ │
│            │ │ [Être rappelé] [WhatsApp] [Détails]  ⊕Comp │ │
│ Comparer(2)│ └────────────────────────────────────────────┘ │
│            │  … more offer cards …                          │
└────────────┴────────────────────────────────────────────────┘
      sticky footer: "Primes indicatives — courtier agréé ACAPS"
```

### 6.3 Bilingual & RTL rules

- `<html lang="fr" dir="ltr">` vs `lang="ar" dir="rtl"` set at the layout root from the locale; language switch preserves funnel state (same token).
- **Tailwind logical utilities only** (`ms-*`, `me-*`, `ps-*`, `pe-*`, `text-start/end`) — never `ml/mr/pl/pr` — so RTL mirroring is automatic. Directional icons (arrows, chevrons) flip via `rtl:rotate-180`.
- Numbers, prices, plates stay in Western digits in both languages (Moroccan convention). Dates localized via `ex_cldr`.
- i18n via **Gettext** (`fr` default, `ar`); all CMS content is dual-field (fr/ar) with per-language publishing states.

### 6.4 Quality floor

Responsive down to 360px · visible keyboard focus rings · WCAG AA contrast · `prefers-reduced-motion` respected · LiveView-rendered HTML = fast first paint on 3G; total JS budget < 120KB · skeleton loaders while offers compute (they compute in <100ms, but perceived work builds trust — add a 1.2s staged "interrogation des barèmes…" animation, capped).

---

## 7. System architecture (Phoenix)

### 7.1 Shape: a modular monolith

One Phoenix app (`moucompare`), no umbrella, no microservices, no Redis, no Node in production. PostgreSQL is the only stateful dependency (data, Oban jobs, sessions if needed, search via `pg_trgm`). This is the sweet spot for a 2-dev team and a single-VPS native deployment.

```
                    ┌────────────────────────── VPS ──────────────────────────┐
 Browser ── HTTPS ──►  nginx (TLS, gzip, static, WS upgrade)                  │
 (LiveView WS)      │      │                                                  │
                    │      ▼                                                  │
                    │  Phoenix release (BEAM)                                 │
                    │  ├─ Endpoint + Router                                   │
                    │  ├─ LiveViews: Funnel, Offers, Admin.*                  │
                    │  ├─ Contexts (below)                                    │
                    │  ├─ Oban queues: sms, email, followups, imports         │
                    │  └─ Phoenix.PubSub (lead events → admin kanban)         │
                    │      │                                                  │
                    │      ▼                                                  │
                    │  PostgreSQL 16 (data · Oban · pg_trgm search)           │
                    └──────────────────────────────────────────────────────────┘
 External: SMS gateway API · SMTP/Postmark · CMI (Ph2) · WhatsApp (Ph2) · Turnstile
```

### 7.2 Contexts (bounded domains)

| Context | Owns | Key modules |
|---|---|---|
| `Accounts` | admins, roles, 2FA TOTP, customer users (Ph2), OTP codes | `Accounts.Admin`, `Accounts.OTP` |
| `Directory` | insurers, products, guarantees, CG documents, agencies | `Directory.Insurer`, `Directory.Product` |
| `Vehicles` | marque/modèle/version catalog, puissance fiscale data | `Vehicles.Catalog` (pg_trgm autocomplete) |
| `Quoting` | quote sessions, answers, computed offers, tokens, resume links | `Quoting.Quote`, `Quoting.Offer` |
| `Rating` | **pure functional rating engine** + versioned rate tables | `Rating.Engine`, `Rating.Table` |
| `Leads` | lead lifecycle, assignment, activities, callback slots | `Leads.Lead`, `Leads.Pipeline` |
| `Policies` (Ph2) | issued policies, documents, renewals | `Policies.Policy` |
| `Payments` (Ph2) | CMI sessions, callbacks, reconciliation | `Payments.CMI` |
| `Content` | posts, pages, FAQs, glossary, reviews (Ph2) — all fr/ar | `Content.Post` |
| `Notifications` | SMS/email/WhatsApp adapters + templates + delivery log | `Notifications.SMS` (behaviour + provider adapters) |
| `Audit` | append-only audit trail of admin actions & consents | `Audit.Entry` |

Rules: LiveViews call contexts only; contexts don't call each other's Repo directly; cross-context reactions via PubSub events (`{:lead, :created, id}`) or explicit function calls at the boundary. The **Rating engine is a pure module** — `Rating.Engine.run(inputs, tables) :: [Offer.t()]` — no DB, no side effects → property-tested and trivially simulated from the admin.

### 7.3 Key mechanics

- **Funnel LiveView:** one `DevisLive` with `step` in assigns; each step is a function component; every `phx-change` validates via an Ecto embedded schema per step and upserts the `quotes` row (autosave). Refresh/resume = load by token. No JS beyond Phoenix hooks (plate input mask, OTP auto-advance).
- **Offer computation:** on step-4 completion → `Rating.Engine.run/2` (<100ms, in-process) → offers persisted (immutable snapshot: inputs + table versions + results) → redirect to `/offres/:token`. Snapshots make every shown price reproducible for compliance.
- **OTP:** `Notifications.SMS` behaviour with `SMSProvider.Fake` (dev/test) and a real adapter (§11); codes hashed, 5-min TTL, per-phone and per-IP rate limits (`Hammer` on ETS).
- **Admin real-time:** kanban subscribes to `leads:*` PubSub topics; new lead cards appear without refresh; presence shows which agent views a lead (avoids double-calling).
- **Background jobs (Oban):** `sms` / `email` (delivery + retries), `followups` (abandon +2h/+24h, callback reminders, échéance reminders in Ph2), `imports` (rate-table CSV ingestion), `maintenance` (data-retention purges §12). Oban Cron replaces system cron for app-level schedules.
- **Telemetry:** `:telemetry` → PromEx (Prometheus) metrics + structured JSON logs; Sentry (or AppSignal) for exceptions, including LiveView crashes.

### 7.4 Library shortlist

`phoenix ~> 1.8` + LiveView · `ecto_sql` + `postgrex` · `oban` · `gettext` · `ex_cldr{,_numbers,_dates}` · `swoosh` (email) · `req` (HTTP client for SMS/CMI/WhatsApp) · `hammer` (rate limiting) · `cloak_ecto` (field encryption: CIN, phone) · `nimble_totp` + `eqrcode` (admin 2FA) · `earmark`/`mdex` (CMS markdown) · `image` or `thumbor`-less `vix` (upload thumbnails) · `ex_machina` + `mox` + `phoenix_test` (tests) · `tailwind` + `esbuild` mix-managed binaries (no Node needed at runtime; assets compiled at build time).

---
## 8. Data model (PostgreSQL / Ecto)

All tables: `id uuid pk default gen_random_uuid()`, `inserted_at/updated_at`. Money in **integer centimes (MAD)**. Enums as Ecto.Enum-backed strings + CHECK constraints. FR/AR text pairs as `name_fr` / `name_ar` columns (simple, indexable) rather than jsonb.

### Core catalog

```
insurers            slug, name_fr, name_ar, logo_path, acaps_ref, phone,
                    rating numeric(2,1), active bool, position int
products            insurer_id fk, kind (auto|moto|voyage|habitation…),
                    formula (rc|tiers_etendu|tous_risques), name_fr/ar,
                    cg_document_path, installments_available bool, active bool
guarantees          code (rc, vol, incendie, bris_glace, pta, defense_recours,
                    assistance, individuelle, evenements_climatiques, evcat),
                    name_fr/ar, description_fr/ar
product_guarantees  product_id fk, guarantee_code, included bool,
                    ceiling_centimes, franchise_centimes, notes_fr/ar
vehicle_makes       name, popular bool
vehicle_models      make_id fk, name
vehicle_versions    model_id fk, name, fiscal_power int, fuel, seats,
                    new_value_centimes, years int4range
cities              name_fr/ar, region, risk_zone (1..3)
```

### Quoting & leads

```
quotes           token citext unique, status (draft|completed|expired),
                 current_step int, locale,
                 -- vehicle
                 plate, is_new_ww bool, make_id, model_id, version_id,
                 fiscal_power, fuel, first_registration date,
                 vehicle_value_centimes, usage, city_id, parking,
                 -- driver
                 birth_date, license_date, is_public_servant bool,
                 current_insurer_id, current_expiry date,
                 at_fault_claims_36m int, crm numeric(3,2), releve_doc_path,
                 -- coverage
                 formula, options text[], franchise_pref, effect_date,
                 -- contact (nullable until step 4)
                 first_name, last_name, phone_enc (cloak), phone_hash,
                 email citext, phone_verified_at,
                 utm jsonb, ip inet, user_agent,
                 rating_run_id fk
rating_runs      quote_id fk, engine_version, table_versions jsonb,
                 inputs jsonb, duration_us int          -- immutable snapshot
offers           rating_run_id fk, quote_id fk, insurer_id, product_id,
                 formula, annual_premium_centimes, monthly_equiv_centimes,
                 breakdown jsonb (rc, options[], evcat, taxes, fees),
                 badges text[] (cheapest|best_value|expert_pick),
                 rank int, selected_at
otp_codes        phone_hash, code_hash, attempts int, expires_at, used_at
leads            quote_id fk unique, offer_id fk null, status
                 (nouveau|rdv_planifie|contacté|devis_envoyé|relance|
                  gagné|perdu), loss_reason, assigned_admin_id fk,
                 callback_at timestamptz, source, priority int,
                 converted_policy_ref, commission_centimes null
lead_activities  lead_id fk, admin_id fk null, kind
                 (note|appel|sms|whatsapp|email|statut|rdv), body,
                 metadata jsonb, happened_at
consents         quote_id fk, kind (cgu|transmission|marketing),
                 text_version, granted bool, ip inet, granted_at
```

### Rating

```
rate_tables      code (rc_base|usage_factor|city_factor|crm|option_pricing|
                 insurer_positioning|taxes_fees), version int,
                 status (draft|published|archived), effective_from date,
                 data jsonb, checksum, published_by fk, notes
-- data examples:
--  rc_base: {"bands":[{"cv_min":1,"cv_max":6,"fuel":"essence",
--            "annual_centimes":198000}, …]}
--  insurer_positioning: {"wafa":{"rc":1.06,"tous_risques":0.97}, …}
--  taxes_fees: {"tax_rate":0.14,"fixed_fees_centimes":5000,
--               "evcat":{"rate":0.05,"min_centimes":…}}   (values from broker)
```

### Content, accounts, ops

```
admins           email citext unique, password_hash, role
                 (superadmin|ops|agent|editor|finance), totp_secret_enc,
                 active bool, last_login_at
users (Ph2)      phone_enc/hash, email, name, locale
posts            slug, kind (guide|faq|page), title_fr/ar, body_fr/ar (md),
                 excerpt_fr/ar, seo jsonb, status per-lang, published_at,
                 author_admin_id
reviews (Ph2)    insurer_id null, rating 1..5, body, author_name,
                 status (pending|approved|rejected), lead_id fk null
notifications_log  channel (sms|email|whatsapp), to_hash, template,
                   payload jsonb, provider_id, status, cost_centimes, sent_at
audit_entries    admin_id, action, entity, entity_id, before jsonb,
                 after jsonb, ip, at   -- append-only, no updates/deletes
settings         key unique, value jsonb   (feature flags, phone numbers,
                 working hours, disclaimer texts fr/ar)
```

**Indexes that matter:** `quotes(token)`, `quotes(phone_hash)`, `leads(status, assigned_admin_id)`, `leads(callback_at)`, `offers(quote_id)`, trigram GIN on `vehicle_models.name` and `vehicle_versions.name`, `posts(slug)`, partial index `leads WHERE status NOT IN ('gagné','perdu')`.

---

## 9. The rating & offers engine

### 9.1 Formula (auto, v1)

```
for each active insurer × eligible product(formula):

  base_rc     = rc_base[band(fiscal_power, fuel, vehicle_kind)]
  premium_rc  = base_rc × usage_factor × city_factor × crm
  options_sum = Σ option_price(option, vehicle_value, franchise_pref)
  evcat       = evcat_rule(premium_rc, guarantees)          # Law 110-14, always on
  subtotal    = (premium_rc + options_sum + evcat) × insurer_positioning[insurer][formula]
  total       = subtotal × (1 + tax_rate) + fixed_fees      # rates configurable
  offer       = %Offer{annual: round_to_dirham(total), breakdown: …}
```

- **Everything numeric lives in `rate_tables` jsonb** — zero business numbers in code. The engine only knows the *shape* of the computation.
- CRM: if user knows it → use it; else derive an estimate from `license_date` + `at_fault_claims_36m` using the configured CRM ladder, and mark the offer "à confirmer avec votre relevé d'information."
- Output includes a full `breakdown` per offer → rendered in the detail sheet and stored in the immutable `rating_run` (compliance: we can reproduce any price ever displayed).
- Badges: cheapest = min(total); best value = max(coverage_score/price) where coverage_score is a weighted sum of included guarantees; expert pick = admin-pinnable per segment.

### 9.2 Governance & quality

- Tables are **versioned**: edit as `draft` → run the **simulator** (admin pastes a profile or picks a saved persona set) → side-by-side diff of premiums old vs new → `publish` with `effective_from`. Engine always resolves "latest published table effective ≤ today."
- **Golden tests:** a committed fixture set of ~40 real profiles with expected premiums (validated with the partner broker); CI fails on drift > threshold.
- **Calibration loop:** when an agent records the *actual* premium a lead signed at (field on the `gagné` transition), a weekly report compares displayed vs signed prices per insurer/formula → ops adjusts positioning coefficients. This is how indicative prices become trustworthy.
- Property tests: monotonicity (more claims ⇒ never cheaper; higher CV ⇒ RC never cheaper), no negative lines, totals = Σ breakdown.

### 9.3 Phase 2: per-insurer binding integrations

Introduce `Quoting.Source` behaviour: `RatingEngineSource` (default) and `InsurerAPISource`/`ExtranetSource` per partner. Offers gain `binding: true/false`; binding offers unlock the "Souscrire en ligne" CTA and the CMI payment flow. The funnel and results UI don't change — only the source mix does.

---

## 10. Admin panel specification

Same Phoenix app under `/admin` (separate router pipeline, session, layout). LiveView throughout. **Login + TOTP 2FA mandatory**, per-role authorization plug, optional IP allowlist, all mutations audited.

### Roles

| Role | Can |
|---|---|
| `superadmin` | everything + admin/user management + settings + publishing rate tables |
| `ops` | leads (all), quotes, rate-table drafts + simulator, insurers/products, exports, reports |
| `agent` | leads (assigned + pool), activities, callback calendar, read-only quotes/offers |
| `editor` | CMS (posts, FAQ, glossary, insurer page content), media |
| `finance` | conversions, commissions, notification costs, exports; read-only elsewhere |

### Modules & key screens

1. **Dashboard** — today/7d/30d KPIs: funnel starts, completion %, leads, OTP success %, callback show-rate, leads gagnés, estimated commissions; live tiles via PubSub; conversion funnel chart (start → step2 → step3 → OTP → lead → gagné).
2. **Leads workspace** — the money screen. Kanban by status with drag-drop; filters (agent, source, city, formula, date, priority); **lead detail**: quote snapshot (all answers + offers shown), contact card with click-to-call `tel:` and WhatsApp link, activity timeline (auto-logged SMS/status events + manual notes), callback scheduler, status transitions with required loss reasons, "signed premium + insurer" capture on `gagné` (feeds calibration + commission), SLA badges (e.g., new lead untouched > 15 min turns red). Round-robin auto-assignment with per-agent caps; presence indicator to prevent double-calls.
3. **Quotes explorer** — search by token/phone-hash/plate; inspect any historical rating_run breakdown; resend resume link; GDPR-style "purge this person" action (§12).
4. **Rating studio** — list of tables with versions; jsonb-schema-validated editor + **CSV import** (template per table); simulator (single profile or persona batch) with old-vs-new diff; publish flow (superadmin) with effective date; full version history.
5. **Directory** — insurers (logos, ACAPS ref, rating, ordering), products & guarantees matrix editor, CG PDF uploads, cities/risk zones, vehicle catalog browser + CSV import + "unmatched vehicle" queue fed by funnel free-text entries.
6. **Content studio** — posts/FAQ/glossary with **side-by-side FR | AR editor**, per-language draft/publish, markdown preview, SEO fields, media library; legal-text manager (consent texts are versioned here; publishing a new version bumps `text_version` recorded on future consents).
7. **Notifications** — template editor (FR/AR) with variable placeholders, delivery log with provider status + unit cost, monthly SMS budget alarm.
8. **Reviews (Ph2)** — moderation queue, reply-as-platform.
9. **Settings** — working hours & callback slots, phone/WhatsApp numbers, feature flags (e.g., `online_payment:insurer_x`), tax/fee display toggles, data-retention windows.
10. **Audit log** — filterable append-only trail (who/what/before/after/IP); exportable.
11. **Exports** — CSV of leads/quotes/conversions per period (finance + partner-broker reporting).

---
## 11. Integrations

| Concern | MVP | Phase 2+ | Notes |
|---|---|---|---|
| **SMS (OTP + notifications)** | One provider behind a `Notifications.SMS` behaviour | Second provider as fallback | Use an aggregator with Moroccan sender-ID support (e.g., Infobip/Vonage or a local Moroccan SMS gateway — pick on price/deliverability in Phase 0). Adapter pattern = swap without code changes elsewhere. Log per-message cost. |
| **Email** | Swoosh + Postmark/SES (transactional: resume link, devis PDF) | Renewal sequences | SPF/DKIM/DMARC on the domain from day 1. |
| **WhatsApp** | `wa.me` deep links into ops number | **WhatsApp Business API** (Meta direct or via Twilio/360dialog): templated devis, callback confirmations, renewal reminders | WhatsApp is a primary channel in Morocco — treat as first-class, not a gimmick. |
| **Payments (Ph2)** | — | **CMI e-payment gateway** (the interbank gateway used for MAD card payments online). Flow: create order → redirect/hosted page → server-to-server callback → verify → mark paid → trigger policy issuance workflow. | Requires a merchant contract via an acquiring bank; sandbox first. Keep a `Payments.Gateway` behaviour so an alternative PSP can be added. Always offer "payer à l'agence / au conseiller" fallback. |
| **Anti-bot** | Cloudflare Turnstile on step 1 + OTP rate limits | — | Protects SMS budget from pump fraud. |
| **Analytics** | Plausible (self-hosted or cloud) + server-side funnel events table | GA4 optional for marketing team | Track: funnel_step_completed, offers_viewed, offer_selected, otp_verified, lead_created, callback_booked. |
| **Maps** | Static city select | Agency locator if physical presence grows | — |

---

## 12. Security, privacy and regulatory compliance

**Regulatory checklist (owner: ops lead, started in Phase 0):**
1. Intermediation: contract with ACAPS-licensed courtier (their agrément number displayed sitewide) — or our own agrément (Law 17-99 art. 289/306; exam + conditions apply).
2. ACAPS Instruction **P.IN.02/2022**: MVP = quote/advertising device → notify ACAPS ≤ 15 days after launch with the device description; Phase 2 online subscription = full dossier (URLs, subscription process walkthrough, CGV, consent flow) **before** launch; re-notify on any change.
3. **CNDP (Law 09-08)**: declaration/authorization of processing (prospection + contract management purposes), privacy policy FR/AR, consent capture with stored text-version/timestamp/IP, DPO-like contact.
4. Consumer law 31-08 mentions for distance selling; clear pre-contractual information on every offer.
5. Wording discipline: indicative prices always labeled; never present the platform as an insurer.

**Technical security:**
- TLS everywhere (HSTS), secure/HttpOnly/SameSite cookies, CSRF (Phoenix default), strict CSP, `force_ssl` in endpoint.
- **Field-level encryption (cloak_ecto, AES-GCM)** for phone, CIN, uploaded relevé documents' metadata; searchable via separate HMAC hash columns (`phone_hash`). Key in env, rotated procedure documented.
- Argon2 password hashing for admins; TOTP 2FA mandatory; session invalidation on role change; login throttling.
- Rate limiting (Hammer): OTP send (per phone/IP/day), funnel starts per IP, admin login.
- Uploads: served from a private dir via authenticated controller only, content-type sniffed, images re-encoded, PDFs size-capped; never user-controlled paths.
- Postgres: app user with least privilege; no superuser in app; `log_min_duration_statement` for slow-query review.
- **Data retention (Oban maintenance jobs):** draft quotes purged after 90 days; completed quotes without lead → anonymized after 12 months; OTP rows after 24h; notification payloads trimmed after 6 months; audit log retained 5 years. One-click "erase this person" in admin (hash-lookup → scrub PII, keep anonymous stats).
- Backups encrypted at rest (age/gpg) before leaving the server (§13.6). Restore drill monthly.
- Dependency hygiene: `mix hex.audit`, `mix deps.audit`, Dependabot; `sobelow` in CI.

---

## 13. Native deployment runbook (no Docker)

**Philosophy:** build a self-contained **`mix release`** (bundles ERTS — the server needs *no* Erlang/Elixir/Node installed), ship a tarball over SSH, run it under **systemd**, front it with **nginx + certbot**, keep PostgreSQL native on the same box until load says otherwise.

### 13.1 Topology

- **Start:** 1 VPS — 4 vCPU / 8 GB RAM / 80 GB NVMe, **Ubuntu 24.04 LTS**. App + Postgres + nginx. This comfortably serves thousands of quotes/day (LiveView is cheap; rating is in-process).
- **Hosting:** an EU provider (Hetzner/OVH/Scaleway) gives the best price/perf with ~40–60ms to Morocco; Moroccan datacenters (e.g., N+ONE, inwi/Maroc Telecom cloud) are an option if data-residency posture matters commercially — Law 09-08 doesn't flatly forbid EU hosting, but declare transfers correctly with CNDP (legal review in Phase 0).
- **Grow path:** ① move Postgres to a second box (managed or self-run) → ② two app VPSes behind a small nginx/HAProxy LB (BEAM clustering optional; PubSub via `Phoenix.PubSub.PG2` + libcluster over private network) → ③ read replica for reporting.

### 13.2 Server bootstrap (once, ~30 min, script it as `provision.sh`)

```bash
# as root on a fresh Ubuntu 24.04
adduser --system --group --home /opt/moucompare deploy
apt update && apt install -y nginx postgresql-16 postgresql-contrib-16 \
    certbot python3-certbot-nginx ufw unattended-upgrades fail2ban age
ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw enable

# PostgreSQL
sudo -u postgres psql <<'SQL'
CREATE USER moucompare WITH PASSWORD '…strong…';
CREATE DATABASE moucompare_prod OWNER moucompare;
\c moucompare_prod
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;
SQL
# tune /etc/postgresql/16/main/postgresql.conf (8GB box):
#   shared_buffers=2GB  effective_cache_size=5GB  work_mem=16MB
#   maintenance_work_mem=256MB  wal_compression=on  max_connections=60

mkdir -p /opt/moucompare/{releases,shared/uploads} /etc/moucompare
chown -R deploy:deploy /opt/moucompare
```

`/etc/moucompare/app.env` (chmod 600, owner deploy):

```
PHX_HOST=moucompare.ma
PORT=4000
SECRET_KEY_BASE=…
DATABASE_URL=ecto://moucompare:…@127.0.0.1/moucompare_prod
POOL_SIZE=15
CLOAK_KEY=…            # base64 32B
SMS_PROVIDER=infobip   SMS_API_KEY=…   SMS_SENDER=MOUCOMPARE
POSTMARK_API_KEY=…
TURNSTILE_SITE_KEY=…   TURNSTILE_SECRET=…
UPLOADS_DIR=/opt/moucompare/shared/uploads
```

### 13.3 Building the release (CI, matching OS)

Because releases bundle ERTS compiled for the build OS, **build on Ubuntu 24.04 in CI** (GitHub Actions `runs-on: ubuntu-24.04`) — never on a Mac. Pin toolchain in `.tool-versions` (e.g., `erlang 27.x`, `elixir 1.18.x-otp-27`).

```yaml
# .github/workflows/deploy.yml (essence)
- uses: erlef/setup-beam@v1
  with: { version-file: .tool-versions, version-type: strict }
- run: mix deps.get --only prod
- run: MIX_ENV=prod mix assets.deploy      # tailwind+esbuild binaries, no Node
- run: MIX_ENV=prod mix release
- run: tar -czf moucompare-${{ github.sha }}.tar.gz -C _build/prod/rel moucompare
- run: scp + ssh deploy.sh   (key-based, deploy user)
```

Runtime config lives in `config/runtime.exs` reading `System.get_env/1` — the same tarball works on staging and prod. Add `rel/overlays/bin/migrate` and a `MyApp.Release.migrate/0` module (standard Phoenix pattern) so migrations run from the release without Mix.

### 13.4 systemd unit — `/etc/systemd/system/moucompare.service`

```ini
[Unit]
Description=Moucompare (Phoenix)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=exec
User=deploy
Group=deploy
WorkingDirectory=/opt/moucompare/current
EnvironmentFile=/etc/moucompare/app.env
ExecStart=/opt/moucompare/current/bin/moucompare start
ExecStop=/opt/moucompare/current/bin/moucompare stop
Restart=on-failure
RestartSec=3
LimitNOFILE=65536
# hardening
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/opt/moucompare/shared

[Install]
WantedBy=multi-user.target
```

### 13.5 Deploy script (runs on server, called by CI) — `deploy.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
SHA=$1
REL=/opt/moucompare/releases/$SHA
mkdir -p "$REL" && tar -xzf /tmp/moucompare-$SHA.tar.gz -C "$REL"
ln -sfn /opt/moucompare/shared/uploads "$REL/moucompare/uploads"

set -a; source /etc/moucompare/app.env; set +a
"$REL/moucompare/bin/moucompare" eval "Moucompare.Release.migrate()"

ln -sfn "$REL/moucompare" /opt/moucompare/current
sudo systemctl restart moucompare
# health check, else rollback
sleep 3
curl -fsS http://127.0.0.1:4000/health || { echo "UNHEALTHY — rolling back";
  ln -sfn "$(ls -1dt /opt/moucompare/releases/*/moucompare | sed -n 2p)" \
     /opt/moucompare/current; sudo systemctl restart moucompare; exit 1; }
ls -1dt /opt/moucompare/releases/* | tail -n +6 | xargs rm -rf   # keep 5
```

Restart downtime is 1–3 seconds; **LiveView clients auto-reconnect** and the funnel state is server-persisted (token), so users don't lose progress. True zero-downtime later: run two instances on ports 4000/4001, flip an nginx upstream (blue-green) — same tarball mechanism, add when traffic justifies it.

### 13.6 nginx — `/etc/nginx/sites-available/moucompare`

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
  listen 443 ssl http2;
  server_name moucompare.ma www.moucompare.ma;
  # certs via: certbot --nginx -d moucompare.ma -d www.moucompare.ma

  client_max_body_size 8m;            # relevé uploads
  gzip on; gzip_types text/css application/javascript application/json image/svg+xml;

  location /live {                    # LiveView websocket
    proxy_pass http://127.0.0.1:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_read_timeout 120s;
  }
  location / {
    proxy_pass http://127.0.0.1:4000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
  }
}
server { listen 80; server_name moucompare.ma www.moucompare.ma;
         return 301 https://$host$request_uri; }
```

### 13.7 Backups, cron, monitoring

- **DB backup** (systemd timer, daily 02:30 + before every deploy):
  `pg_dump -Fc moucompare_prod | age -r <pubkey> > /backups/db-$(date +%F).dump.age`
  then `rclone copy /backups remote:moucompare-backups` (S3-compatible bucket, 30 daily + 12 monthly retention). Uploads dir synced likewise. **Monthly restore drill on staging is part of the ops calendar.**
- **App-level schedules:** all in **Oban Cron** (follow-ups, purges, reports) → no crontab drift. System cron/timers only for: backups, `certbot renew` (installed by certbot), `apt` unattended-upgrades.
- **Monitoring:** journald for logs (`journalctl -u moucompare`); PromEx → Grafana Cloud free tier (BEAM memory, LiveView connects, Oban queue depth, HTTP latency) or AppSignal if you prefer one paid tool; Sentry for exceptions; UptimeRobot/BetterStack hitting `/health` (checks DB with a `SELECT 1`); alert on: health fail, Oban `sms` queue backlog, disk > 80%, backup job failure.
- **Staging:** a small 2GB VPS, same scripts, `staging.moucompare.ma`, seeded with fake data + `SMSProvider.Fake`.

---

## 14. Delivery plan, team and timeline

**Team:** 2 Elixir/Phoenix developers (one senior — can be you) · 1 product designer (heavy weeks 1–6, then part-time) · 1 insurance ops lead (broker liaison, rate grids, agent process — critical hire) · FR/AR content writer (freelance) · 2 sales agents at launch.

| Weeks | Track A — Product/Eng | Track B — Ops/Legal |
|---|---|---|
| 0–2 | Repo, CI, provision staging+prod, auth+roles+audit skeleton, design tokens & funnel UI kit | Broker LOI/contract, obtain rate grids, CNDP file, name+domain |
| 3–5 | Vehicle catalog + import, funnel steps 1–3 (FR), quotes autosave/resume | Grids → rate_tables format, persona set for golden tests |
| 5–7 | Rating engine + simulator + golden tests, offers page, OTP + lead creation | ACAPS device notification drafted, consent texts FR/AR |
| 7–9 | Admin: leads kanban+detail+activities, dashboard, notifications (SMS/email), WhatsApp deep links | Agent playbook & scripts, SLA definitions |
| 9–11 | Arabic locale + RTL pass, CMS + 12 seed guides, SEO/meta/sitemaps, rating studio publish flow, hardening (Turnstile, rate limits, sobelow) | Insurer/product data entry, CG PDFs, legal pages review |
| 11–12 | Load test (k6: 200 concurrent funnels), backup/restore drill, private beta (50 users), fix list | Notify ACAPS (≤15 days post-launch window), train agents |
| 12 | **Public launch (Casablanca-first marketing)** | Paid + WhatsApp referral campaigns |
| 13–22 | Phase 2: accounts, CMI payment + first binding insurer, renewals, reviews, moto/voyage | CMI merchant contract, ACAPS full-online dossier |

**Definition of done for MVP launch:** ≥95% funnel completion without errors in beta · rating within agreed tolerance of broker quotes on the persona set · lead appears in kanban < 1s after OTP · agent can go from new lead → logged call outcome in < 4 clicks · AR pages fully mirrored · backup restore proven.

---

## 15. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Indicative prices drift from real quotes → trust damage | High | Show ranges when confidence is low; weekly calibration loop from signed premiums (§9.2); "confirmé par un conseiller" framing everywhere |
| Broker/insurer partnership delays | High | Launch is legally possible as quote-device under a partner courtier; keep two broker candidates warm; own agrément track in parallel |
| ACAPS objects to wording/device | High | Conservative labeling, dossier pre-reviewed by an insurance lawyer, quick-change CMS for all legal texts |
| SMS pumping fraud / OTP cost blowout | Medium | Turnstile, per-IP+phone velocity caps, MA-prefix allowlist, daily budget alarm, provider-side blocking |
| Low SEO traction early | Medium | Paid search + social + WhatsApp referral at launch; SEO compounds from month 3; city pages + Schengen-visa guide are proven magnets |
| Single-server outage | Medium | systemd auto-restart, 5-release rollback, tested restore ≤ 30 min RTO; blue-green + second node when revenue justifies |
| Elixir hiring pool in MA | Low/Med | Stack is small and standard (Phoenix defaults, no exotic libs); remote-friendly; this document doubles as onboarding |
| Feature creep before PMF | Medium | Phase gates above; nothing outside MVP list ships before first 100 leads |

---

## 16. Appendices

### A. Repository layout

```
moucompare/
├─ .tool-versions            # erlang 27.x / elixir 1.18.x-otp-27
├─ config/{config,dev,prod,runtime,test}.exs
├─ lib/moucompare/           # contexts: accounts, directory, vehicles,
│                            # quoting, rating, leads, content, notifications, audit
├─ lib/moucompare_web/
│  ├─ live/devis_live/       # funnel (step components)
│  ├─ live/offres_live.ex
│  ├─ live/admin/            # dashboard, leads, rating_studio, cms, settings
│  ├─ components/            # ui kit (buttons, cards, star_progress, offer_card)
│  └─ controllers/           # health, uploads, sitemap, webhooks (cmi Ph2)
├─ priv/gettext/{fr,ar}/
├─ priv/repo/{migrations,seeds}/
├─ priv/rating_fixtures/     # golden-test personas + expected premiums
├─ rel/overlays/bin/migrate
├─ ops/{provision.sh,deploy.sh,backup.sh,moucompare.service,nginx.conf}
└─ .github/workflows/{ci.yml,deploy.yml}
```

### B. Environment variables (prod)

`PHX_HOST` `PORT` `SECRET_KEY_BASE` `DATABASE_URL` `POOL_SIZE` `CLOAK_KEY` `SMS_PROVIDER` `SMS_API_KEY` `SMS_SENDER` `POSTMARK_API_KEY` `TURNSTILE_SITE_KEY` `TURNSTILE_SECRET` `UPLOADS_DIR` `SENTRY_DSN` `PLAUSIBLE_DOMAIN` — Phase 2 adds `CMI_MERCHANT_ID` `CMI_STORE_KEY` `CMI_ENDPOINT` `WHATSAPP_TOKEN` `WHATSAPP_PHONE_ID`.

### C. Funnel field dictionary (FR / AR) — excerpt

| Field | FR label | AR label |
|---|---|---|
| plate | Immatriculation | رقم التسجيل |
| fiscal_power | Puissance fiscale (CV) | القوة الجبائية |
| first_registration | Date de 1ère mise en circulation | تاريخ أول استعمال |
| usage | Usage du véhicule | استعمال السيارة |
| formula | Formule d'assurance | صيغة التأمين |
| franchise | Franchise | التحمل (الفرانشيز) |
| effect_date | Date d'effet souhaitée | تاريخ بداية التأمين |
| callback | Être rappelé | اتصلوا بي |

*(Full dictionary to be completed with the content writer; Darija phrasing for marketing surfaces, standard Arabic for legal/contractual text.)*

### D. First-90-days KPI targets (to refine in Phase 0)

Funnel completion ≥ 45% of starts · OTP verification ≥ 85% of step-4 · leads/day ≥ 30 by day 60 · lead→signed ≥ 12% · displayed-vs-signed premium gap ≤ 8% median · agent first-touch < 15 min in working hours.

---

*End of plan — v1.0. Next concrete action: Phase 0 kickoff checklist (broker shortlist, rate grids request letter, CNDP + ACAPS drafts, brand sprint).*
