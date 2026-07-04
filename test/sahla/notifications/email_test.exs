defmodule Sahla.Notifications.EmailTest do
  # async: false — deliver/1 asserts against the process mailbox (Test adapter)
  # and toggles the global :email_enabled kill-switch.
  use ExUnit.Case, async: false

  import Swoosh.TestAssertions

  alias Sahla.Notifications.Email

  @resume %{
    to: "amina@example.ma",
    locale: :fr,
    first_name: "Amina",
    url: "https://sahla.ma/r/abc"
  }

  describe "resume_link/1" do
    test "builds a resume-link email from the fr template" do
      email = Email.resume_link(@resume)

      assert email.to == [{"", "amina@example.ma"}]
      assert email.from == {"Sahla", "no-reply@sahla.ma"}
      assert email.subject =~ "reprenez votre devis"
      assert email.html_body =~ "https://sahla.ma/r/abc"
      assert email.html_body =~ "Amina"
      assert email.text_body =~ "https://sahla.ma/r/abc"
      assert email.attachments == []
    end

    test "renders the ar template with the Arabic subject" do
      email = Email.resume_link(%{@resume | locale: :ar})
      assert email.subject =~ "تابع"
    end
  end

  describe "devis_pdf/1" do
    test "attaches the PDF binary as application/pdf" do
      email =
        Email.devis_pdf(Map.merge(@resume, %{pdf: "%PDF-1.7 fake", filename: "devis-123.pdf"}))

      assert [attachment] = email.attachments
      assert attachment.filename == "devis-123.pdf"
      assert attachment.content_type == "application/pdf"
      assert email.subject =~ "votre devis"
    end

    test "defaults the filename to devis.pdf" do
      email = Email.devis_pdf(Map.put(@resume, :pdf, "%PDF"))
      assert [%{filename: "devis.pdf"}] = email.attachments
    end
  end

  describe "deliver/1" do
    test "sends through the mailer when the kill-switch is on" do
      assert {:ok, _} = @resume |> Email.resume_link() |> Email.deliver()
      assert_email_sent(subject: Email.resume_link(@resume).subject)
    end

    test "short-circuits to {:error, :disabled} when the kill-switch is off" do
      Application.put_env(:sahla, :email_enabled, false)
      on_exit(fn -> Application.put_env(:sahla, :email_enabled, true) end)

      assert {:error, :disabled} = @resume |> Email.resume_link() |> Email.deliver()
      assert_no_email_sent()
    end
  end
end
