defmodule Sahla.Repo.Migrations.CreateLegalTexts do
  use Ecto.Migration

  # Versioned legal/consent texts (§10.6, §5.2, §12): each consent records the
  # exact text_version shown, so the copy behind every grant is reconstructable.
  # History is append-only — a new wording is a new version row, never an edit of
  # a published one; publishing the highest version makes it the current text.
  def change do
    create table(:legal_texts) do
      add :key, :string, null: false
      add :version, :integer, null: false
      add :body_fr, :text, null: false
      add :body_ar, :text
      add :status, :string, null: false, default: "draft"
      add :published_at, :utc_datetime
      add :published_by_id, references(:admins, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # One row per (key, version); the next draft increments version per key.
    create unique_index(:legal_texts, [:key, :version])
    create index(:legal_texts, [:key, :status])

    create constraint(:legal_texts, :legal_texts_key_must_be_valid,
             check: "key IN ('cgu','transmission','marketing','mentions','privacy')"
           )

    create constraint(:legal_texts, :legal_texts_status_must_be_valid,
             check: "status IN ('draft','published')"
           )
  end
end
