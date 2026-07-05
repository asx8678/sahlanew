defmodule Sahla.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  # Content hub store (§5.4, §8): versioned bilingual posts (guides, FAQ, pages)
  # that back the public site's SEO surfaces and the admin content studio (§10.6).
  #
  # Per-language publishing states (`status_fr`/`status_ar`) let editors publish
  # FR and AR independently — FR-published/AR-draft asymmetry is expected. The
  # paired `_fr`/`_ar` columns (not jsonb) keep each locale directly indexable
  # (§8). `slug` is `citext` so `/guides/Casablanca` and `/guides/casablanca`
  # resolve to the same row without a casefold dance.
  def change do
    create table(:posts) do
      add :slug, :citext, null: false
      add :kind, :string, null: false, default: "guide"

      # Bilingual content (markdown bodies, plain excerpts, titles).
      add :title_fr, :text, null: false
      add :title_ar, :text
      add :body_fr, :text, null: false
      add :body_ar, :text
      add :excerpt_fr, :text
      add :excerpt_ar, :text

      # SEO payload (OpenGraph, meta description, canonical, hreflang hints).
      add :seo, :map, null: false, default: %{}

      # Independent per-language publish state.
      add :status_fr, :string, null: false, default: "draft"
      add :status_ar, :string, null: false, default: "draft"
      add :published_at, :utc_datetime

      add :author_admin_id, references(:admins, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # posts(slug) — a unique citext index covers both uniqueness and the public
    # slug lookup (§8 index inventory); no separate equality index needed.
    create unique_index(:posts, [:slug])

    create constraint(:posts, :posts_kind_must_be_valid, check: "kind IN ('guide','faq','page')")

    create constraint(:posts, :posts_status_fr_must_be_valid,
             check: "status_fr IN ('draft','published')"
           )

    create constraint(:posts, :posts_status_ar_must_be_valid,
             check: "status_ar IN ('draft','published')"
           )

    # A post is "published" in a locale only when its status column says so;
    # `published_at` is the newest-first ordering key for the public list and is
    # stamped by the admin changeset at publish time. Reject a published_at set
    # without at least one locale published to keep the public listing honest.
    create constraint(:posts, :posts_published_at_only_when_published,
             check: "published_at IS NULL OR status_fr = 'published' OR status_ar = 'published'"
           )
  end
end
