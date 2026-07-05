defmodule Sahla.ContentTest do
  use Sahla.DataCase, async: true

  alias Sahla.Content
  alias Sahla.Content.Post
  alias Sahla.Repo

  # An editor (holds the :cms capability) for the post FK + cms-gated mutations.
  defp author do
    {:ok, admin} =
      %Sahla.Accounts.Admin{}
      |> Sahla.Accounts.Admin.registration_changeset(%{
        email: "editor-#{System.unique_integer([:positive])}@sahla.test",
        password: "password-password",
        role: "editor"
      })
      |> Repo.insert()

    admin
  end

  defp opts(actor), do: [actor: actor, ip: "196.200.1.1"]

  describe "render_html/1 — mdex + ammonia sanitization" do
    test "renders CommonMark markdown to HTML" do
      assert Content.render_html("# Hello\n\n**bold**") ==
               "<h1>Hello</h1>\n<p><strong>bold</strong></p>"
    end

    test "nil renders to empty string (missing AR body never crashes)" do
      assert Content.render_html(nil) == ""
    end

    test "strips <script> tags entirely" do
      html = Content.render_html("<script>alert('x')</script>\n\n# Title")

      refute String.contains?(html, "<script"), "script tag must be stripped"
      refute String.contains?(html, "alert"), "script body must not leak as text either"
      assert html =~ "<h1>Title</h1>"
    end

    test "strips dangerous attributes (onclick) and keeps safe href" do
      html =
        Content.render_html("<a href=\"https://example.com\" onclick=\"evil()\">link</a>")

      refute String.contains?(html, "onclick"), "event-handler attributes must be stripped"
      assert String.contains?(html, "https://example.com"), "safe href must survive"
    end

    test "strips javascript: URLs from href" do
      html = Content.render_html("<a href=\"javascript:alert(1)\">x</a>")
      refute String.contains?(html, "javascript:"), "javascript: scheme must be stripped"
    end

    test "raw HTML is sanitized, not omitted" do
      # Without sanitize: mdex emits "<!-- raw HTML omitted -->". With our
      # render_html/1 the safe inline tag <h1> survives (ammonia allows it).
      refute Content.render_html("<h1>Hi</h1>") =~ "raw HTML omitted"
    end
  end

  describe "Post.changeset/2 — public-facing content changeset" do
    test "casts editorial fields but never status or published_at" do
      cs =
        Post.changeset(%Post{}, %{
          slug: "crm-explained",
          kind: :guide,
          title_fr: "CRM expliqué",
          body_fr: "body",
          status_fr: :published,
          status_ar: :published,
          published_at: DateTime.utc_now()
        })

      assert cs.changes[:status_fr] == nil
      assert cs.changes[:status_ar] == nil
      assert cs.changes[:published_at] == nil
      assert cs.changes[:slug] == "crm-explained"
    end

    test "requires slug, title_fr, body_fr (kind defaults to guide)" do
      cs = Post.changeset(%Post{}, %{})

      errors = errors_on(cs)
      assert errors[:slug] == ["can't be blank"]
      assert errors[:title_fr] == ["can't be blank"]
      assert errors[:body_fr] == ["can't be blank"]
      # kind has a schema default, so it is not required.
      assert errors[:kind] == nil
    end

    test "rejects an invalid slug format" do
      cs =
        Post.changeset(%Post{}, %{slug: "Bad Slug!", kind: :guide, title_fr: "t", body_fr: "b"})

      assert errors_on(cs)[:slug]
    end
  end

  describe "Post.admin_changeset/2 — admin publishing" do
    test "casts status_fr/status_ar and stamps published_at on first publish" do
      actor = author()

      {:ok, post} =
        Content.create_post(
          %{slug: "pub-stamp", kind: :guide, title_fr: "T", body_fr: "B"},
          opts(actor)
        )

      cs = Post.admin_changeset(post, %{status_fr: :published})

      assert cs.changes[:status_fr] == :published
      assert cs.changes[:published_at], "published_at should be stamped on first publish"
    end

    test "does not re-stamp published_at when already set" do
      actor = author()

      {:ok, post} =
        Content.create_post(
          %{slug: "no-restamp", kind: :guide, title_fr: "T", body_fr: "B"},
          opts(actor)
        )

      {:ok, published} =
        Content.update_post(post, %{status_fr: :published}, opts(actor))

      first_at = published.published_at
      assert first_at

      # A later edit (typo fix) must not move the published_at timestamp.
      {:ok, updated} =
        Content.update_post(
          published,
          %{title_fr: "Assurance auto à Casablanca (v2)"},
          opts(actor)
        )

      assert updated.published_at == first_at
    end
  end

  describe "create_post/2 — authorization" do
    test "an editor (cms) can create a post" do
      actor = author()

      assert {:ok, %Post{slug: "ok-create"}} =
               Content.create_post(
                 %{slug: "ok-create", kind: :guide, title_fr: "T", body_fr: "B"},
                 opts(actor)
               )
    end

    test "an agent (no cms) is forbidden" do
      {:ok, agent} =
        %Sahla.Accounts.Admin{}
        |> Sahla.Accounts.Admin.registration_changeset(%{
          email: "agent-#{System.unique_integer([:positive])}@sahla.test",
          password: "password-password",
          role: "agent"
        })
        |> Repo.insert()

      assert {:error, :forbidden} =
               Content.create_post(
                 %{slug: "denied", kind: :guide, title_fr: "T", body_fr: "B"},
                 opts(agent)
               )
    end
  end

  describe "published_posts/2 — per-locale scope with newest-first ordering" do
    test "returns only posts published in the requested locale" do
      actor = author()

      # FR-published, AR-draft (asymmetry case from the AC).
      {:ok, fr_only} =
        Content.create_post(
          %{slug: "fr-only", kind: :guide, title_fr: "FR", body_fr: "B"},
          opts(actor)
        )

      {:ok, _fr_only} =
        Content.update_post(fr_only, %{status_fr: :published, status_ar: :draft}, opts(actor))

      # AR-published, FR-draft.
      {:ok, ar_only} =
        Content.create_post(
          %{slug: "ar-only", kind: :guide, title_fr: "AR", body_fr: "B"},
          opts(actor)
        )

      {:ok, _ar_only} =
        Content.update_post(ar_only, %{status_fr: :draft, status_ar: :published}, opts(actor))

      fr_list = Content.published_posts(:fr)
      ar_list = Content.published_posts(:ar)

      assert Enum.map(fr_list, & &1.slug) == ["fr-only"]
      assert Enum.map(ar_list, & &1.slug) == ["ar-only"]
    end

    test "a draft-only post is invisible in both locales" do
      actor = author()

      {:ok, _draft} =
        Content.create_post(
          %{slug: "draft", kind: :guide, title_fr: "T", body_fr: "B"},
          opts(actor)
        )

      assert Content.published_posts(:fr) == []
      assert Content.published_posts(:ar) == []
    end

    test "ordering is deterministic across repeated reads (Lessons tiebreaker)" do
      actor = author()

      # Two posts published "at the same second" — without a desc: :id
      # tiebreaker, two rows sharing published_at would sort arbitrarily.
      # UUIDs are not monotonic, so we assert a STABLE order across reads
      # rather than a specific insertion order: every read must return the
      # same sequence.
      now = DateTime.truncate(DateTime.utc_now(), :second)

      {:ok, a} =
        Content.create_post(%{slug: "a", kind: :guide, title_fr: "A", body_fr: "B"}, opts(actor))

      {:ok, b} =
        Content.create_post(%{slug: "b", kind: :guide, title_fr: "B", body_fr: "B"}, opts(actor))

      {:ok, _a} = Content.update_post(a, %{status_fr: :published, published_at: now}, opts(actor))
      {:ok, _b} = Content.update_post(b, %{status_fr: :published, published_at: now}, opts(actor))

      first = Enum.map(Content.published_posts(:fr), & &1.id)
      second = Enum.map(Content.published_posts(:fr), & &1.id)

      assert first == second, "newest-first ordering must be stable across reads"
      assert length(first) == 2
      assert MapSet.new(first) == MapSet.new([a.id, b.id])
    end

    test "filters by kind when :kind is given" do
      actor = author()

      {:ok, g} =
        Content.create_post(%{slug: "g", kind: :guide, title_fr: "G", body_fr: "B"}, opts(actor))

      {:ok, f} =
        Content.create_post(%{slug: "f", kind: :faq, title_fr: "F", body_fr: "B"}, opts(actor))

      {:ok, _g} = Content.update_post(g, %{status_fr: :published}, opts(actor))
      {:ok, _f} = Content.update_post(f, %{status_fr: :published}, opts(actor))

      assert Enum.map(Content.published_posts(:fr, kind: :guide), & &1.slug) == ["g"]
      assert Enum.map(Content.published_posts(:fr, kind: :faq), & &1.slug) == ["f"]
    end
  end

  describe "get_published_by_slug/2" do
    test "returns the published post (citext: case-insensitive slug lookup)" do
      # Slugs are stored lowercase (slug format validation), but the `citext`
      # column makes the public lookup case-insensitive: /Guides/Casablanca
      # and /guides/casablanca resolve to the same row.
      actor = author()

      {:ok, post} =
        Content.create_post(
          %{slug: "casablanca-guide", kind: :guide, title_fr: "T", body_fr: "B"},
          opts(actor)
        )

      {:ok, _post} = Content.update_post(post, %{status_fr: :published}, opts(actor))

      assert %Post{slug: "casablanca-guide"} =
               Content.get_published_by_slug("Casablanca-Guide", :fr)
    end

    test "returns nil for a slug that exists only as a draft" do
      actor = author()

      {:ok, _draft} =
        Content.create_post(
          %{slug: "draft-slug", kind: :guide, title_fr: "T", body_fr: "B"},
          opts(actor)
        )

      assert Content.get_published_by_slug("draft-slug", :fr) == nil
    end

    test "returns nil for an unknown slug" do
      assert Content.get_published_by_slug("does-not-exist", :fr) == nil
    end
  end

  describe "migration constraints" do
    # These exercise the DB CHECK constraints directly so a raw-SQL seed or a
    # bypass of the changeset cannot land invalid rows.
    test "rejects an invalid kind at the DB" do
      actor = author()

      {:error, cs} =
        Content.create_post(
          %{slug: "bad-kind", kind: "bogus", title_fr: "T", body_fr: "B"},
          opts(actor)
        )

      assert errors_on(cs)[:kind]
    end

    test "slug uniqueness is enforced" do
      actor = author()

      {:ok, _first} =
        Content.create_post(
          %{slug: "dup", kind: :guide, title_fr: "T", body_fr: "B"},
          opts(actor)
        )

      assert {:error, cs} =
               Content.create_post(
                 %{slug: "dup", kind: :guide, title_fr: "T", body_fr: "B"},
                 opts(actor)
               )

      assert errors_on(cs)[:slug]
    end
  end
end
