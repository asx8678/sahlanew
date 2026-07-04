defmodule Sahla.LeadsTest do
  use Sahla.DataCase, async: true

  alias Sahla.Leads.{Activity, Lead}
  alias Sahla.Quoting.Quote

  defp quote_fixture do
    %Quote{} |> Quote.create_changeset(%{}) |> Repo.insert!()
  end

  defp lead_fixture(attrs \\ %{}) do
    quote = quote_fixture()

    %Lead{}
    |> Lead.changeset(Map.merge(%{quote_id: quote.id}, Map.new(attrs)))
    |> Repo.insert!()
  end

  describe "lead creation" do
    test "creates a lead with defaults" do
      lead = lead_fixture()
      assert lead.status == :nouveau
      assert lead.priority == 0
      assert lead.commission_centimes == nil
    end

    test "quote_id is unique (one lead per quote)" do
      quote = quote_fixture()
      %Lead{} |> Lead.changeset(%{quote_id: quote.id}) |> Repo.insert!()

      assert {:error, changeset} =
               %Lead{} |> Lead.changeset(%{quote_id: quote.id}) |> Repo.insert()

      assert %{quote_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "creation changeset does not cast admin-only fields" do
      quote = quote_fixture()

      changeset =
        Lead.changeset(%Lead{}, %{
          quote_id: quote.id,
          status: :gagne,
          assigned_admin_id: Ecto.UUID.generate(),
          commission_centimes: 999
        })

      assert get_change(changeset, :status) == nil
      assert get_change(changeset, :assigned_admin_id) == nil
      assert get_change(changeset, :commission_centimes) == nil
    end
  end

  describe "status transitions and the loss_reason guard" do
    test "rejects an invalid status" do
      changeset = Lead.status_changeset(%Lead{}, %{status: :vendu})
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "requires loss_reason when status is perdu" do
      lead = lead_fixture()
      changeset = Lead.status_changeset(lead, %{status: :perdu})
      assert %{loss_reason: ["can't be blank"]} = errors_on(changeset)

      ok = Lead.status_changeset(lead, %{status: :perdu, loss_reason: "prix trop élevé"})
      assert ok.valid?
    end

    test "rejects loss_reason for a non-perdu status" do
      lead = lead_fixture()
      changeset = Lead.status_changeset(lead, %{status: :gagne, loss_reason: "oops"})
      assert %{loss_reason: ["is only allowed when status is perdu"]} = errors_on(changeset)
    end

    test "the DB CHECK also enforces the guard" do
      lead = lead_fixture()

      # bypass the changeset to prove the DB backstop
      assert_raise Postgrex.Error, ~r/leads_loss_reason_guard/, fn ->
        Repo.query!(
          "UPDATE leads SET status = 'perdu', loss_reason = NULL WHERE id = $1",
          [Ecto.UUID.dump!(lead.id)]
        )
      end
    end
  end

  describe "activities" do
    test "creates an activity with an auto happened_at" do
      lead = lead_fixture()

      {:ok, activity} =
        %Activity{}
        |> Activity.changeset(%{lead_id: lead.id, kind: :note, body: "called client"})
        |> Repo.insert()

      assert activity.kind == :note
      assert activity.happened_at
    end

    test "rejects an invalid kind" do
      lead = lead_fixture()
      changeset = Activity.changeset(%Activity{}, %{lead_id: lead.id, kind: :carrier_pigeon})
      assert %{kind: ["is invalid"]} = errors_on(changeset)
    end

    test "deleting a lead cascades to its activities" do
      lead = lead_fixture()

      {:ok, activity} =
        %Activity{} |> Activity.changeset(%{lead_id: lead.id, kind: :note}) |> Repo.insert()

      Repo.delete!(lead)
      refute Repo.get(Activity, activity.id)
    end
  end
end
