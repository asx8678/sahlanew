defmodule Sahla.Leads.ContextTest do
  # async: false — subscribes to the shared "leads" PubSub topic.
  use Sahla.DataCase, async: false

  alias Sahla.Leads
  alias Sahla.Quoting
  alias Sahla.Quoting.Offer
  alias Sahla.Rating

  defp quote_fixture(attrs \\ %{}) do
    {:ok, quote} = Quoting.create_quote(attrs)
    quote
  end

  defp offer_fixture(quote) do
    run =
      Repo.insert!(
        Rating.Run.changeset(%Rating.Run{}, %{quote_id: quote.id, engine_version: "v1"})
      )

    Repo.insert!(
      Offer.changeset(%Offer{}, %{
        rating_run_id: run.id,
        quote_id: quote.id,
        formula: :rc,
        annual_premium_centimes: 500_000
      })
    )
  end

  # nouveau -> contacte -> gagne
  defp won_lead do
    {:ok, lead} = Leads.create_from_quote(quote_fixture())
    {:ok, lead} = Leads.transition_status(lead, :contacte)
    {:ok, lead} = Leads.transition_status(lead, :gagne)
    lead
  end

  describe "create_from_quote/2" do
    test "persists a lead, snapshots source and offer_id, and emits :created + a creation activity" do
      Leads.subscribe()
      quote = quote_fixture()
      offer = offer_fixture(quote)

      assert {:ok, lead} =
               Leads.create_from_quote(quote, %{offer_id: offer.id, source: "google"})

      assert lead.status == :nouveau
      assert lead.source == "google"
      assert lead.offer_id == offer.id

      assert_receive {:lead, :created, id}
      assert id == lead.id

      assert [activity] = Leads.list_activities(lead)
      assert activity.kind == :statut
      assert activity.metadata["to"] == "nouveau"
      assert activity.metadata["event"] == "created"
    end

    test "falls back to the quote's utm source when :source is not given" do
      quote = quote_fixture(%{utm: %{"utm_source" => "facebook"}})
      assert {:ok, lead} = Leads.create_from_quote(quote)
      assert lead.source == "facebook"
    end

    test "defaults source to \"site\" with no utm" do
      assert {:ok, lead} = Leads.create_from_quote(quote_fixture())
      assert lead.source == "site"
    end

    test "rejects a second lead for the same quote" do
      quote = quote_fixture()
      assert {:ok, _} = Leads.create_from_quote(quote)
      assert {:error, changeset} = Leads.create_from_quote(quote)
      assert %{quote_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "transition_status/3" do
    test "a legal transition updates status, logs a statut activity and broadcasts :updated" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())
      Leads.subscribe()

      assert {:ok, moved} = Leads.transition_status(lead, :contacte, note: "Appel sortant")
      assert moved.status == :contacte

      assert_receive {:lead, :updated, id}
      assert id == lead.id

      transition_activity =
        Enum.find(Leads.list_activities(moved), &(&1.metadata["to"] == "contacte"))

      assert transition_activity.kind == :statut
      assert transition_activity.body == "Appel sortant"
      assert transition_activity.metadata == %{"from" => "nouveau", "to" => "contacte"}
    end

    test "rejects an illegal transition" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())

      assert {:error, {:illegal_transition, :nouveau, :gagne}} =
               Leads.transition_status(lead, :gagne)
    end

    test "perdu requires a loss_reason" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())

      assert {:error, changeset} = Leads.transition_status(lead, :perdu)
      assert %{loss_reason: ["can't be blank"]} = errors_on(changeset)

      assert {:ok, lost} = Leads.transition_status(lead, :perdu, loss_reason: "trop cher")
      assert lost.status == :perdu
      assert lost.loss_reason == "trop cher"
    end

    test "same status is an idempotent no-op with no new activity" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())
      before = Leads.list_activities(lead)

      assert {:ok, ^lead} = Leads.transition_status(lead, :nouveau)
      assert Leads.list_activities(lead) == before
    end

    test "a terminal lead refuses to leave its status but no-ops on re-apply" do
      lead = won_lead()
      assert Leads.terminal?(lead.status)

      assert {:ok, ^lead} = Leads.transition_status(lead, :gagne)
      assert {:error, :terminal} = Leads.transition_status(lead, :contacte)
    end
  end

  describe "log_message_event/2 (Notifications boundary)" do
    test "appends a system SMS activity and broadcasts" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())
      Leads.subscribe()

      assert {:ok, activity} =
               Leads.log_message_event(lead, %{
                 kind: :sms,
                 body: "OTP envoyé",
                 metadata: %{"provider" => "fake"}
               })

      assert activity.kind == :sms
      assert activity.admin_id == nil
      assert_receive {:lead, :updated, _id}
    end

    test "accepts a lead id as well as a struct" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())

      assert {:ok, activity} =
               Leads.log_message_event(lead.id, %{kind: :whatsapp, body: "Bonjour"})

      assert activity.lead_id == lead.id
    end

    test "rejects a non-event kind" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())

      assert_raise ArgumentError, fn ->
        Leads.log_message_event(lead, %{kind: :statut, body: "x"})
      end
    end
  end

  describe "log_activity/2" do
    test "inserts a note activity and broadcasts :updated" do
      {:ok, lead} = Leads.create_from_quote(quote_fixture())
      Leads.subscribe()

      assert {:ok, activity} = Leads.log_activity(lead, %{kind: :note, body: "Client rappelé"})
      assert activity.kind == :note
      assert_receive {:lead, :updated, _id}
    end
  end
end
