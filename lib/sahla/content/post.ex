defmodule Sahla.Content.Post do
  @moduledoc """
  A bilingual content-hub post (§5.4, §8): guide, FAQ entry, or static page.

  Each locale carries its own title/body/excerpt and its **own** publish state
  (`status_fr`/`status_ar`), so an editor can publish FR while AR is still a
  draft — the public listing for a locale only ever shows posts published in
  that locale. Bodies are markdown rendered to sanitized HTML by
  `Sahla.Content.render_html/1`.

  ## Changeset discipline (Lessons)

  The user-facing `changeset/2` casts only editorial content fields — it can
  **never** flip a status or stamp `published_at`. Only `admin_changeset/2`
  may touch those, so a public form (or a future front-end editor) can never
  accidentally publish a post. This mirrors `Sahla.Directory.Insurer`'s
  `active`-flag split and `Sahla.Content.LegalText`'s publish flow.
  """
  use Sahla.Schema

  import Ecto.Changeset

  @kinds [:guide, :faq, :page]
  @statuses [:draft, :published]

  schema "posts" do
    field :slug, :string
    field :kind, Ecto.Enum, values: @kinds, default: :guide

    field :title_fr, :string
    field :title_ar, :string
    field :body_fr, :string
    field :body_ar, :string
    field :excerpt_fr, :string
    field :excerpt_ar, :string

    field :seo, :map, default: %{}

    field :status_fr, Ecto.Enum, values: @statuses, default: :draft
    field :status_ar, Ecto.Enum, values: @statuses, default: :draft
    field :published_at, :utc_datetime

    belongs_to :author, Sahla.Accounts.Admin, foreign_key: :author_admin_id

    timestamps()
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  @doc """
  Editorial content changeset (slug, kind, titles, bodies, excerpts, seo).

  Deliberately does **not** cast `status_fr`/`status_ar`/`published_at` — only
  `admin_changeset/2` may publish. An editor saving a draft through the CMS
  form cannot flip a post live by stuffing an extra field into the params.
  """
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :slug,
      :kind,
      :title_fr,
      :title_ar,
      :body_fr,
      :body_ar,
      :excerpt_fr,
      :excerpt_ar,
      :seo,
      :author_admin_id
    ])
    |> validate_required([:slug, :kind, :title_fr, :body_fr])
    |> validate_length(:slug, min: 1, max: 120)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must be lowercase letters, digits and hyphens"
    )
    |> unique_constraint(:slug, name: :posts_slug_index)
    |> check_constraint(:kind, name: :posts_kind_must_be_valid)
  end

  @doc """
  Admin changeset: everything in `changeset/2` plus the per-language publish
  states and `published_at`. Publishing stamps `published_at` when it is first
  set and never un-stamps it on a later draft (the row keeps its last-published
  timestamp so the public list ordering stays stable across edit cycles).
  """
  def admin_changeset(post, attrs) do
    post
    |> changeset(attrs)
    |> cast(attrs, [:status_fr, :status_ar, :published_at])
    |> check_constraint(:status_fr, name: :posts_status_fr_must_be_valid)
    |> check_constraint(:status_ar, name: :posts_status_ar_must_be_valid)
    |> check_constraint(:published_at, name: :posts_published_at_only_when_published)
    |> maybe_stamp_published_at()
  end

  defp maybe_stamp_published_at(changeset) do
    # Stamp published_at the first time either locale goes to :published and no
    # timestamp is already set. Leave it untouched on subsequent edits so the
    # newest-first public ordering doesn't jump when an editor fixes a typo.
    fr = get_field(changeset, :status_fr)
    ar = get_field(changeset, :status_ar)
    already = get_field(changeset, :published_at)

    if (fr == :published or ar == :published) and is_nil(already) and
         is_nil(get_change(changeset, :published_at)) do
      put_change(changeset, :published_at, DateTime.truncate(DateTime.utc_now(), :second))
    else
      changeset
    end
  end
end
