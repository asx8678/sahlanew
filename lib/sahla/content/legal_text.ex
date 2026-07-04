defmodule Sahla.Content.LegalText do
  @moduledoc """
  A single version of a legal/consent text (§10.6, §12). Versions are
  **append-only**: `changeset/2` creates a new draft (never edits a published
  body) and `publish_changeset/2` only flips a draft to `published`, stamping
  who/when. The current text for a key is the highest-`version` published row.
  """
  use Sahla.Schema

  import Ecto.Changeset

  @keys [:cgu, :transmission, :marketing, :mentions, :privacy]
  @statuses [:draft, :published]

  schema "legal_texts" do
    field :key, Ecto.Enum, values: @keys
    field :version, :integer
    field :body_fr, :string
    field :body_ar, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :published_at, :utc_datetime
    field :published_by_id, :binary_id

    timestamps()
  end

  def keys, do: @keys
  def statuses, do: @statuses

  @doc "Changeset for a new draft version (body only; version is assigned by the context)."
  def changeset(legal_text, attrs) do
    legal_text
    |> cast(attrs, [:key, :version, :body_fr, :body_ar])
    |> validate_required([:key, :version, :body_fr])
    |> put_change(:status, :draft)
    |> unique_constraint([:key, :version], name: :legal_texts_key_version_index)
    |> check_constraint(:key, name: :legal_texts_key_must_be_valid)
  end

  @doc "Changeset that publishes a draft, stamping `published_at`/`published_by_id`."
  def publish_changeset(legal_text, published_by_id, published_at) do
    legal_text
    |> change(status: :published, published_at: published_at, published_by_id: published_by_id)
    |> check_constraint(:status, name: :legal_texts_status_must_be_valid)
  end
end
