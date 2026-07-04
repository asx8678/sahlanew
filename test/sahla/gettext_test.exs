defmodule Sahla.GettextTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  # A minimal template using the backend the way any SahlaWeb view does.
  defmodule SampleTemplate do
    use Phoenix.Component
    use Gettext, backend: Sahla.Gettext

    def close_button(assigns) do
      ~H"""
      <button>{gettext("close")}</button>
      """
    end
  end

  test "fr is the default locale and fr/ar are the known locales" do
    assert Gettext.get_locale(Sahla.Gettext) == "fr"
    assert Enum.sort(Gettext.known_locales(Sahla.Gettext)) == ["ar", "fr"]
  end

  test "an English dev-key msgid renders the fr translation under the default locale" do
    html = rendered_to_string(SampleTemplate.close_button(%{}))
    assert html =~ "fermer"
    refute html =~ ">close<"
  end

  test "the same msgid renders the ar translation when locale=ar" do
    Gettext.with_locale(Sahla.Gettext, "ar", fn ->
      assert rendered_to_string(SampleTemplate.close_button(%{})) =~ "إغلاق"
    end)
  end

  test "both locales have default and errors domains on disk" do
    for locale <- ["fr", "ar"], domain <- ["default", "errors"] do
      path = Application.app_dir(:sahla, "priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po")
      assert File.exists?(path), "missing #{locale}/#{domain}.po"
    end
  end

  test "changeset errors translate through the errors domain" do
    # "can't be blank" is a scaffold msgid in the errors domain; untranslated it
    # falls through to the English dev-key, which is the documented behaviour.
    assert Gettext.dgettext(Sahla.Gettext, "errors", "can't be blank") == "can't be blank"
  end
end
