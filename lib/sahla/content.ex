defmodule Sahla.Content do
  @moduledoc """
  The content context (§5.4, §8, §10.6, §12): bilingual posts and the
  versioned legal/consent-text manager.

  ## Posts

  `Content.Post` backs the public content hub (guides, FAQ, pages) and the
  admin content studio. Each locale publishes independently (`status_fr`/
  `status_ar`); the public read API only ever returns posts published in the
  requested locale. Bodies are markdown rendered to sanitized HTML by
  `render_html/1` (mdex + ammonia — `<script>` and dangerous attributes are
  stripped). Mutations are admin-gated and audited.

  ## Legal texts

  Each consent records the exact `text_version` shown to the user, so the
  wording behind every grant is reconstructable. Versions are **append-only**
  — a new wording is a new draft version, never an edit of a published one —
  and publishing the highest version makes it the current text for that key.

  Mutations (`create_version/2`, `publish/2`) are superadmin-gated via
  `Policy.can?(role, :manage_legal_texts)` and audited through `Sahla.Audit`.
  The consent-capture API (`Sahla.Compliance`) reads `current_version/1` to
  stamp the version — it integrates with this manager rather than duplicating
  it.
  """
  import Ecto.Query, only: [from: 2]

  alias Sahla.Accounts.{Admin, Policy}
  alias Sahla.Audit
  alias Sahla.Content.{LegalText, Post}
  alias Sahla.Repo

  # -- posts (§5.4, §8) -------------------------------------------------------

  @doc """
  Renders a markdown body to **sanitized** HTML safe for inline display.

  mdex parses CommonMark + GFM (tables, strikethrough, autolink, task lists);
  ammonia then strips `<script>`, event-handler attributes, `javascript:`
  URLs and any tag outside its conservative allowlist. `nil` input renders to
  `""` so a missing AR body never crashes the FR/AR rendering path.

  The output is safe to insert via `Phoenix.HTML.raw/1` in a template; it is
  **not** safe to interpolate into an attribute (ammonia escapes quotes, but
  the call site should still use a dedicated attribute helper).
  """
  def render_html(nil), do: ""

  def render_html(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      render: [unsafe: true],
      sanitize: MDEx.Document.default_sanitize_options(),
      extension: [autolink: true, table: true, strikethrough: true, tasklist: true]
    )
  end

  @doc """
  Posts published in `locale` (`:fr`/`:ar`), newest first.

  Newest-first uses `desc: :published_at` with a `desc: :id` tiebreaker so two
  posts published in the same second never sort arbitrarily (Lessons, §8).
  Optional `:kind` filters to `:guide`/`:faq`/`:page`.
  """
  def published_posts(locale, opts \\ []) do
    status_field = status_field(locale)
    kind = Keyword.get(opts, :kind)

    Repo.all(
      from p in Post,
        where: field(p, ^status_field) == ^published_atom(locale),
        order_by: [desc: p.published_at, desc: p.id],
        preload: [:author]
    )
    |> maybe_filter_kind(kind)
  end

  @doc "The newest published post lists, one query per locale (helpers for views)."
  def list_published(locale, opts \\ []), do: published_posts(locale, opts)

  @doc """
  Fetches the post with `slug` if it is published in `locale`, else `nil`.

  `slug` is `citext` so the lookup is case-insensitive at the DB. A draft-only
  post is invisible to the public path even if its slug is known.
  """
  def get_published_by_slug(slug, locale) when is_binary(slug) do
    status_field = status_field(locale)

    Repo.one(
      from p in Post,
        where: p.slug == ^slug and field(p, ^status_field) == ^published_atom(locale),
        preload: [:author]
    )
  end

  @doc "Every post (admin studio list), newest by id — drafts included."
  def list_all do
    Repo.all(from p in Post, order_by: [desc: p.id], preload: [:author])
  end

  @doc "Fetch a post by id (admin studio editor)."
  def get_post!(id), do: Repo.get!(Post, id) |> Repo.preload(:author)

  @doc """
  Creates a post from admin `attrs` using the admin changeset (so statuses and
  `published_at` are cast). `opts` requires `:actor` (`%Admin{}` with the
  `:cms` capability); the create is audited.

  Returns `{:ok, post}`, `{:error, :forbidden}` or `{:error, changeset}`.
  """
  def create_post(attrs, opts) do
    with :ok <- authorize_cms(opts) do
      attrs = Map.put(Map.new(attrs), :author_admin_id, Keyword.fetch!(opts, :actor).id)

      Repo.transaction(fn ->
        post = insert_or_rollback(Post.admin_changeset(%Post{}, attrs))
        audit_post!(opts, "post.create", post)
        post
      end)
    end
  end

  @doc """
  Updates a post from admin `attrs` using the admin changeset. `opts` requires
  `:actor` (`%Admin{}` with the `:cms` capability); the update is audited.

  Returns `{:ok, post}`, `{:error, :forbidden}` or `{:error, changeset}`.
  """
  def update_post(%Post{} = post, attrs, opts) do
    with :ok <- authorize_cms(opts) do
      Repo.transaction(fn ->
        updated = update_or_rollback(Post.admin_changeset(post, attrs))
        audit_post!(opts, "post.update", updated)
        updated
      end)
    end
  end

  defp published_atom(:fr), do: "published"
  defp published_atom(:ar), do: "published"
  defp status_field(:fr), do: :status_fr
  defp status_field(:ar), do: :status_ar

  defp maybe_filter_kind(posts, nil), do: posts

  defp maybe_filter_kind(posts, kind) when kind in [:guide, :faq, :page] do
    Enum.filter(posts, &(&1.kind == kind))
  end

  defp authorize_cms(opts) do
    case Keyword.get(opts, :actor) do
      %Admin{role: role} ->
        if Policy.can?(role, :cms), do: :ok, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp audit_post!(opts, action, %Post{} = post) do
    result =
      Audit.log(%{
        admin_id: Keyword.fetch!(opts, :actor).id,
        action: action,
        entity: "post",
        entity_id: post.id,
        after: %{"slug" => post.slug, "kind" => to_string(post.kind)},
        ip: Keyword.get(opts, :ip)
      })

    case result do
      {:ok, _entry} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc "The legal-text keys this manager tracks."
  def keys, do: LegalText.keys()

  @doc """
  Creates the next **draft** version for `key` with the given bodies. `attrs`:
  `:body_fr` (required), `:body_ar`. `opts` requires `:actor` (a superadmin
  `%Admin{}`); the create is audited.

  Returns `{:ok, legal_text}`, `{:error, :forbidden}`, or `{:error, changeset}`.
  """
  def create_version(key, attrs, opts) do
    with :ok <- authorize(opts) do
      attrs =
        attrs
        |> Map.new()
        |> Map.put(:key, key)
        |> Map.put(:version, next_version(key))

      Repo.transaction(fn ->
        legal_text = insert_or_rollback(LegalText.changeset(%LegalText{}, attrs))

        audit!(opts, "legal_text.create", legal_text, %{
          "key" => to_string(key),
          "version" => legal_text.version
        })

        legal_text
      end)
    end
  end

  @doc """
  Publishes a **draft** version, making it the current text for its key. `opts`
  requires `:actor` (a superadmin `%Admin{}`); the publish is audited.

  Returns `{:ok, legal_text}`, `{:error, :forbidden}`, `{:error, :not_draft}`
  (already published), or `{:error, changeset}`.
  """
  def publish(%LegalText{status: :published}, _opts), do: {:error, :not_draft}

  def publish(%LegalText{status: :draft} = legal_text, opts) do
    with :ok <- authorize(opts) do
      actor = Keyword.fetch!(opts, :actor)
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.transaction(fn ->
        published =
          update_or_rollback(LegalText.publish_changeset(legal_text, actor.id, now))

        audit!(opts, "legal_text.publish", published, %{
          "key" => to_string(published.key),
          "version" => published.version
        })

        published
      end)
    end
  end

  @doc "The current (highest-version published) text for `key`, or `nil`."
  def current(key) do
    Repo.one(
      from t in LegalText,
        where: t.key == ^key and t.status == :published,
        order_by: [desc: t.version],
        limit: 1
    )
  end

  @doc "The current published version number for `key`, or `nil` if none is published."
  def current_version(key) do
    case current(key) do
      nil -> nil
      %LegalText{version: version} -> version
    end
  end

  @doc "The current published body for `key` in `locale` (`:fr`/`:ar`), or `nil`."
  def current_body(key, locale) do
    case current(key) do
      nil -> nil
      text -> body_for(text, locale)
    end
  end

  @doc "Every version for `key`, newest first (append-only history)."
  def history(key) do
    Repo.all(from t in LegalText, where: t.key == ^key, order_by: [desc: t.version])
  end

  def get_version!(id), do: Repo.get!(LegalText, id)

  # -- internals --------------------------------------------------------------

  defp next_version(key) do
    max = Repo.one(from t in LegalText, where: t.key == ^key, select: max(t.version))
    (max || 0) + 1
  end

  defp body_for(%LegalText{body_ar: body}, :ar) when is_binary(body), do: body
  defp body_for(%LegalText{body_fr: body}, _locale), do: body

  defp authorize(opts) do
    case Keyword.get(opts, :actor) do
      %Admin{role: role} ->
        if Policy.can?(role, :manage_legal_texts), do: :ok, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp audit!(opts, action, %LegalText{} = text, after_map) do
    result =
      Audit.log(%{
        admin_id: Keyword.fetch!(opts, :actor).id,
        action: action,
        entity: "legal_text",
        entity_id: text.id,
        after: after_map,
        ip: Keyword.get(opts, :ip)
      })

    case result do
      {:ok, entry} -> entry
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
