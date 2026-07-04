defmodule Sahla.Notifications.Template do
  @moduledoc """
  Canonical FR/AR message bodies (§5.2, §5.3, §11) for every transactional
  message: OTP, resume link, callback confirmation/reminder and the devis-PDF
  email. These are the *defaults*; admin-managed overrides (read from settings by
  `Sahla.Notifications.Templates`) take precedence at render time.

  Bodies use `{{var}}` placeholders and never hardcode the brand — `{{brand}}` is
  injected from settings. SMS keys carry a single `:text`; email keys carry
  `:subject`, `:html` and `:text`.

  Arabic bodies are authored for meaning and still need native-speaker QA before
  launch (Lessons).
  """

  @locales [:fr, :ar]

  @templates %{
    otp_code: %{
      channel: :sms,
      fr: %{
        text: "{{brand}} : votre code de vérification est {{code}}. Valable {{minutes}} minutes."
      },
      ar: %{text: "{{brand}}: رمز التحقق الخاص بك هو {{code}}. صالح لمدة {{minutes}} دقائق."}
    },
    resume_link: %{
      channel: :sms,
      fr: %{text: "{{brand}} : reprenez votre devis auto ici : {{url}}"},
      ar: %{text: "{{brand}}: تابع طلب عرض تأمين سيارتك من هنا: {{url}}"}
    },
    callback_confirmation: %{
      channel: :sms,
      fr: %{text: "{{brand}} : nous vous rappellerons le {{date}} vers {{time}}. Merci !"},
      ar: %{text: "{{brand}}: سنعاود الاتصال بك يوم {{date}} حوالي الساعة {{time}}. شكراً!"}
    },
    callback_reminder: %{
      channel: :sms,
      fr: %{text: "{{brand}} : rappel — votre appel est prévu aujourd'hui vers {{time}}."},
      ar: %{text: "{{brand}}: تذكير — مكالمتك مبرمجة اليوم حوالي الساعة {{time}}."}
    },
    resume_link_email: %{
      channel: :email,
      fr: %{
        subject: "{{brand}} — reprenez votre devis d'assurance auto",
        html:
          "<p>Bonjour {{first_name}},</p><p>Votre devis auto vous attend. Reprenez là où vous vous êtes arrêté : <a href=\"{{url}}\">{{url}}</a>.</p><p>L'équipe {{brand}}</p>",
        text:
          "Bonjour {{first_name}}, reprenez votre devis auto ici : {{url}}. L'équipe {{brand}}"
      },
      ar: %{
        subject: "{{brand}} — تابع طلب عرض تأمين سيارتك",
        html:
          "<p>مرحباً {{first_name}}،</p><p>عرض تأمين سيارتك في انتظارك. تابع من حيث توقفت: <a href=\"{{url}}\">{{url}}</a>.</p><p>فريق {{brand}}</p>",
        text: "مرحباً {{first_name}}، تابع طلب عرض تأمين سيارتك من هنا: {{url}}. فريق {{brand}}"
      }
    },
    devis_pdf_email: %{
      channel: :email,
      fr: %{
        subject: "{{brand}} — votre devis d'assurance auto",
        html:
          "<p>Bonjour {{first_name}},</p><p>Votre devis est prêt. Téléchargez-le ici : <a href=\"{{url}}\">{{url}}</a>.</p><p>L'équipe {{brand}}</p>",
        text: "Bonjour {{first_name}}, votre devis est prêt : {{url}}. L'équipe {{brand}}"
      },
      ar: %{
        subject: "{{brand}} — عرض تأمين سيارتك",
        html:
          "<p>مرحباً {{first_name}}،</p><p>عرض الأسعار الخاص بك جاهز. حمّله من هنا: <a href=\"{{url}}\">{{url}}</a>.</p><p>فريق {{brand}}</p>",
        text: "مرحباً {{first_name}}، عرض الأسعار الخاص بك جاهز: {{url}}. فريق {{brand}}"
      }
    }
  }

  @doc "All template keys."
  def keys, do: Map.keys(@templates)

  @doc "The supported locales."
  def locales, do: @locales

  @doc "The channel (`:sms` or `:email`) a key is delivered on."
  def channel(key), do: fetch!(key).channel

  @doc """
  The default body map for `key` in `locale` (`%{text: ...}` for SMS,
  `%{subject:, html:, text:}` for email). Raises for an unknown key/locale.
  """
  def default_body(key, locale) when locale in @locales do
    key |> fetch!() |> Map.fetch!(locale)
  end

  defp fetch!(key), do: Map.fetch!(@templates, key)
end
