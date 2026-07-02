# Sahla

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Conventions

These conventions are non-negotiable across the codebase:

* **Money** is stored as integer **centimes MAD** (never floats, never a currency type).
* **All ids** are **uuid** (`binary_id`); migrations default to `binary_id` primary/foreign keys.
* **Bilingual text** uses paired `_fr` / `_ar` columns (e.g. `name_fr` / `name_ar`), not jsonb.
* **No hackney, ever** — HTTP goes through **Req/Finch** only (idna conflict with req/mint).
* **No hardcoded brand strings** — the display name comes from settings/gettext, never a literal.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
