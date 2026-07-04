defmodule Sahla.Notifications.WhatsApp do
  @moduledoc """
  `wa.me` deep links for the one-tap WhatsApp CTA on the results page (§5.3, §11).

  MVP only — no WhatsApp Business API calls (that's Phase 2). `deeplink/1` builds
  `https://wa.me/<number>?text=<prefilled>` where the ops number comes from
  settings (no brand/number hardcode; a missing number degrades to the contact
  picker) and the text is the localized, URL-encoded `prefilled_text/1`. The text
  builder is pure and shared with the results-offers CTA UI.
  """
  alias Sahla.Settings

  @number_key "whatsapp_number"

  @doc "A `wa.me` deep link with the settings number and URL-encoded prefilled text."
  def deeplink(attrs) do
    text = attrs |> prefilled_text() |> URI.encode_www_form()
    "https://wa.me/#{number()}?text=#{text}"
  end

  @doc """
  The localized prefilled message (pure). Includes the quote `:token` and, when
  given, the `:offer_ref`. `:locale` is `"fr"` (default) or `"ar"`.
  """
  def prefilled_text(attrs) do
    locale = normalize_locale(Map.get(attrs, :locale, "fr"))
    token = to_string(Map.get(attrs, :token, ""))
    ref = Map.get(attrs, :offer_ref)
    build_text(locale, token, ref)
  end

  defp build_text("ar", token, ref) do
    "مرحباً، أرغب في استشارة حول عرض تأمين سيارتي#{ref_ar(ref)} (المرجع #{token})"
  end

  defp build_text(_fr, token, ref) do
    "Bonjour, je souhaite un conseil sur mon devis auto#{ref_fr(ref)} (réf #{token})"
  end

  defp ref_fr(nil), do: ""
  defp ref_fr(ref), do: " — offre #{ref}"

  defp ref_ar(nil), do: ""
  defp ref_ar(ref), do: " — العرض #{ref}"

  defp normalize_locale("ar"), do: "ar"
  defp normalize_locale(_locale), do: "fr"

  # International number, digits only, as wa.me requires. Blank → contact picker.
  defp number do
    @number_key |> Settings.get("") |> to_string() |> String.replace(~r/\D/, "")
  end
end
