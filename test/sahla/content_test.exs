defmodule Sahla.ContentTest do
  use Sahla.DataCase, async: true

  alias Sahla.Accounts
  alias Sahla.Audit
  alias Sahla.Content
  alias Sahla.Content.LegalText

  @password "correct-horse-battery-staple-42"

  defp admin(role) do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "#{role}-#{System.unique_integer([:positive])}@sahla.ma",
        password: @password,
        role: role
      })

    admin
  end

  defp draft(key, actor, body \\ "Texte v") do
    {:ok, text} = Content.create_version(key, %{body_fr: body}, actor: actor)
    text
  end

  describe "authorization" do
    test "create_version and publish require the :manage_legal_texts capability" do
      ops = admin(:ops)
      assert Content.create_version(:cgu, %{body_fr: "x"}, actor: ops) == {:error, :forbidden}
      assert Content.create_version(:cgu, %{body_fr: "x"}, []) == {:error, :forbidden}
    end

    test "a superadmin can create and publish" do
      su = admin(:superadmin)
      assert {:ok, text} = Content.create_version(:cgu, %{body_fr: "CGU v1"}, actor: su)
      assert {:ok, _} = Content.publish(text, actor: su)
    end
  end

  describe "versioning (append-only)" do
    setup do
      %{su: admin(:superadmin)}
    end

    test "each create bumps the per-key version from 1", %{su: su} do
      assert draft(:cgu, su).version == 1
      assert draft(:cgu, su).version == 2
      # versions are per key, so a different key starts at 1 again
      assert draft(:privacy, su).version == 1
    end

    test "current/current_version resolve the highest published version", %{su: su} do
      v1 = draft(:cgu, su)
      v2 = draft(:cgu, su)

      # nothing published yet
      assert Content.current(:cgu) == nil
      assert Content.current_version(:cgu) == nil

      {:ok, _} = Content.publish(v1, actor: su)
      assert Content.current_version(:cgu) == 1

      {:ok, _} = Content.publish(v2, actor: su)
      assert Content.current_version(:cgu) == 2
    end

    test "publishing an already-published version is refused", %{su: su} do
      {:ok, published} = Content.publish(draft(:cgu, su), actor: su)
      assert Content.publish(published, actor: su) == {:error, :not_draft}
    end

    test "history lists every version newest-first", %{su: su} do
      draft(:cgu, su)
      draft(:cgu, su)
      assert [%LegalText{version: 2}, %LegalText{version: 1}] = Content.history(:cgu)
    end

    test "current_body prefers the locale, falling back to fr", %{su: su} do
      {:ok, text} =
        Content.create_version(:cgu, %{body_fr: "FR", body_ar: "AR"}, actor: su)

      {:ok, _} = Content.publish(text, actor: su)
      assert Content.current_body(:cgu, :ar) == "AR"
      assert Content.current_body(:cgu, :fr) == "FR"
    end
  end

  describe "auditing" do
    test "create and publish each write an audit entry" do
      su = admin(:superadmin)
      {:ok, text} = Content.create_version(:cgu, %{body_fr: "x"}, actor: su)
      {:ok, _} = Content.publish(text, actor: su)

      actions = Audit.for_entity("legal_text", text.id) |> Enum.map(& &1.action)
      assert "legal_text.create" in actions
      assert "legal_text.publish" in actions
    end
  end

  describe "consent integration" do
    test "capture_consents stamps the current published legal-text version" do
      su = admin(:superadmin)

      for key <- [:cgu, :transmission, :marketing] do
        {:ok, text} = Content.create_version(key, %{body_fr: "#{key} body"}, actor: su)
        {:ok, _} = Content.publish(text, actor: su)
        # bump each to version 2 and publish so "v2" is current
        {:ok, text2} = Content.create_version(key, %{body_fr: "#{key} body 2"}, actor: su)
        {:ok, _} = Content.publish(text2, actor: su)
      end

      {:ok, quote} = Sahla.Quoting.create_quote()
      {:ok, consents} = Sahla.Compliance.capture_consents(quote, %{cgu: true, transmission: true})

      cgu = Enum.find(consents, &(&1.kind == :cgu))
      assert cgu.text_version == "v2"
    end
  end
end
