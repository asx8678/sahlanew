defmodule Sahla.Notifications.TemplatesTest do
  # async: false — some tests override the :notification_overrides app env.
  use ExUnit.Case, async: false

  alias Sahla.Notifications.{Template, Templates}

  # Superset of every placeholder used across all templates.
  @vars %{
    code: "123456",
    minutes: 5,
    url: "https://sahla.ma/r/abc",
    date: "12/07/2026",
    time: "15h30",
    first_name: "Amina"
  }

  describe "render/3 across every key and locale" do
    test "interpolates all placeholders in fr and ar (no literal {{var}} remains)" do
      for key <- Template.keys(), locale <- Template.locales() do
        rendered = Templates.render(key, locale, @vars)

        for {field, value} <- rendered do
          refute value =~ ~r/\{\{/,
                 "unresolved placeholder in #{key}/#{locale} #{field}: #{value}"

          assert value =~ "Sahla", "brand missing in #{key}/#{locale} #{field}"
        end
      end
    end

    test "email keys yield subject, html and text; sms keys yield only text" do
      email = Templates.render(:devis_pdf_email, :fr, @vars)
      assert Enum.sort(Map.keys(email)) == [:html, :subject, :text]
      assert email.subject =~ "devis"
      assert email.html =~ "<a href="

      sms = Templates.render(:otp_code, :fr, @vars)
      assert Map.keys(sms) == [:text]
    end

    test "fr sms bodies stay single-segment (<= 160 chars)" do
      for key <- Template.keys(), Template.channel(key) == :sms do
        assert String.length(Templates.render(key, :fr, @vars).text) <= 160
      end
    end
  end

  describe "brand resolution" do
    test "the default brand comes from settings/config, not a hardcoded literal" do
      # the stored default body references the placeholder, never the name
      assert Template.default_body(:otp_code, :fr).text =~ "{{brand}}"
      refute Template.default_body(:otp_code, :fr).text =~ "Sahla"

      # it is resolved at render time
      assert Templates.render(:otp_code, :fr, @vars).text =~ "Sahla"
    end

    test "an explicit brand var overrides the configured default" do
      assert Templates.render(:otp_code, :fr, Map.put(@vars, :brand, "Assur.ma")).text =~
               "Assur.ma"
    end
  end

  describe "admin overrides" do
    test "an override stored in settings takes precedence over the default body" do
      Application.put_env(:sahla, :notification_overrides, %{
        {:otp_code, :fr} => %{text: "Code {{brand}} : {{code}}"}
      })

      on_exit(fn -> Application.delete_env(:sahla, :notification_overrides) end)

      assert Templates.render(:otp_code, :fr, @vars).text == "Code Sahla : 123456"
    end

    test "with no override, the canonical default is used" do
      assert Templates.render(:otp_code, :fr, @vars).text =~ "code de vérification"
    end
  end

  describe "missing variables" do
    test "a placeholder with no matching variable raises (never emitted literally)" do
      assert_raise ArgumentError, ~r/missing variable "code"/, fn ->
        Templates.render(:otp_code, :fr, %{minutes: 5})
      end
    end
  end

  describe "unknown key or locale" do
    test "an unknown key raises" do
      assert_raise KeyError, fn -> Templates.render(:nope, :fr, @vars) end
    end

    test "an unknown locale raises" do
      assert_raise FunctionClauseError, fn -> Templates.render(:otp_code, :es, @vars) end
    end
  end
end
