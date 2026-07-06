defmodule Sahla.Repo.Migrations.AddReleveDocMetaEncToQuotes do
  use Ecto.Migration

  def change do
    alter table(:quotes) do
      # Cloak-encrypted metadata for the optional relevé d'information upload
      # (original filename, sniffed content type, size, stored path). The file
      # itself lives in :uploads_dir; this column keeps its PII metadata at rest.
      add :releve_doc_meta_enc, :binary
    end
  end
end
