defmodule SahlaWeb.LocaleMirrorTest do
  use ExUnit.Case, async: true

  alias SahlaWeb.LocaleMirror

  describe "to/2" do
    test "mirrors root to the Arabic scope" do
      assert LocaleMirror.to("/", "ar") == "/ar"
    end

    test "mirrors Arabic root back to French root" do
      assert LocaleMirror.to("/ar", "fr") == "/"
    end

    test "preserves a /devis/:token segment when switching fr → ar" do
      assert LocaleMirror.to("/devis/abc-123", "ar") == "/ar/devis/abc-123"
    end

    test "preserves a /devis/:token segment when switching ar → fr" do
      assert LocaleMirror.to("/ar/devis/abc-123", "fr") == "/devis/abc-123"
    end

    test "preserves an /offres/:token segment both ways" do
      assert LocaleMirror.to("/offres/xyz-789", "ar") == "/ar/offres/xyz-789"
      assert LocaleMirror.to("/ar/offres/xyz-789", "fr") == "/offres/xyz-789"
    end

    test "preserves slugs and nested segments" do
      assert LocaleMirror.to("/assureurs/wafacal", "ar") == "/ar/assureurs/wafacal"

      assert LocaleMirror.to("/guides/choisir-son-assurance", "ar") ==
               "/ar/guides/choisir-son-assurance"
    end

    test "preserves query strings" do
      assert LocaleMirror.to("/devis/abc-123?step=2", "ar") == "/ar/devis/abc-123?step=2"
      assert LocaleMirror.to("/?ref=home", "ar") == "/ar?ref=home"
    end

    test "is idempotent when the target scope already matches" do
      assert LocaleMirror.to("/ar/devis/x", "ar") == "/ar/devis/x"
      assert LocaleMirror.to("/devis/x", "fr") == "/devis/x"
    end

    test "leaves an unknown path untouched when switching to French" do
      assert LocaleMirror.to("/mentions-legales", "fr") == "/mentions-legales"
    end
  end
end
