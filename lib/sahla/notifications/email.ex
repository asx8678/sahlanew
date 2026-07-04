defmodule Sahla.Notifications.Email do
  @moduledoc """
  Transactional email (§11): builds the resume-link and devis-PDF messages from
  the canonical templates and delivers them through `Sahla.Mailer`.

  Builders (`resume_link/1`, `devis_pdf/1`) are pure — they return a
  `%Swoosh.Email{}` without sending — so they are cheap to unit-test. `deliver/1`
  is the single send seam: it honors the kill-switch (`:email_enabled`) so a
  budget alarm or incident can stop all email at runtime, exactly like
  `Sahla.Notifications.SMS`.

  Bodies come from `Sahla.Notifications.Templates`, which resolves admin
  overrides and injects the brand — no subject or copy is hardcoded here.
  """
  import Swoosh.Email

  alias Sahla.Mailer
  alias Sahla.Notifications.Templates

  @type locale :: :fr | :ar
  @type attrs :: %{
          required(:to) => String.t(),
          required(:locale) => locale,
          optional(:first_name) => String.t(),
          required(:url) => String.t()
        }

  @doc """
  Builds the resume-link email (funnel re-engagement) for `attrs`
  (`:to`, `:locale`, `:first_name`, `:url`). Returns a `%Swoosh.Email{}`.
  """
  @spec resume_link(attrs) :: Swoosh.Email.t()
  def resume_link(attrs) do
    build(:resume_link_email, attrs)
  end

  @doc """
  Builds the devis-PDF email with the quote PDF attached. In addition to the
  resume-link fields, `attrs` carries `:pdf` — the PDF as a binary — and an
  optional `:filename` (default `"devis.pdf"`).
  """
  @spec devis_pdf(map()) :: Swoosh.Email.t()
  def devis_pdf(attrs) do
    filename = Map.get(attrs, :filename, "devis.pdf")

    attachment =
      Swoosh.Attachment.new({:data, Map.fetch!(attrs, :pdf)},
        filename: filename,
        content_type: "application/pdf",
        type: :attachment
      )

    :devis_pdf_email
    |> build(attrs)
    |> attachment(attachment)
  end

  @doc """
  Delivers a built `%Swoosh.Email{}`. Short-circuits to `{:error, :disabled}`
  when the kill-switch is off, without touching the mailer. Otherwise returns
  `Sahla.Mailer.deliver/1`'s `{:ok, meta}` / `{:error, reason}`.
  """
  @spec deliver(Swoosh.Email.t()) :: {:ok, term()} | {:error, term()}
  def deliver(%Swoosh.Email{} = email) do
    if enabled?() do
      Mailer.deliver(email)
    else
      {:error, :disabled}
    end
  end

  @doc "Whether transactional email is currently enabled (the kill-switch)."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:sahla, :email_enabled, true)

  # Renders `key` in the requested locale and assembles the Swoosh message.
  defp build(key, attrs) do
    locale = Map.fetch!(attrs, :locale)
    vars = Map.take(attrs, [:first_name, :url])
    rendered = Templates.render(key, locale, vars)

    new()
    |> to(Map.fetch!(attrs, :to))
    |> from(mail_from())
    |> subject(rendered.subject)
    |> html_body(rendered.html)
    |> text_body(rendered.text)
  end

  defp mail_from, do: Application.fetch_env!(:sahla, :mail_from)
end
