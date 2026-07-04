defmodule Sahla.Quoting.StepsTest do
  use ExUnit.Case, async: true

  alias Sahla.Quoting.Steps
  alias Sahla.Quoting.Steps.{Contact, Coverage, Driver, Vehicle}

  # Fixed "today" so date checks are deterministic.
  @today ~D[2026-07-04]

  defp errors(changeset), do: Steps.field_errors(changeset)

  describe "Vehicle (step 1)" do
    @valid %{
      fiscal_power: 6,
      fuel: :diesel,
      usage: :personnel,
      city_id: Ecto.UUID.generate(),
      parking: :garage
    }

    test "valid when all required fields are present and no valuing formula" do
      cs = Vehicle.changeset(%Vehicle{}, @valid, today: @today, formula: :rc)
      assert cs.valid?
    end

    test "missing required fields each get exactly one keyed message" do
      cs = Vehicle.changeset(%Vehicle{}, %{}, today: @today, formula: :rc)
      refute cs.valid?

      assert %{
               fiscal_power: "can't be blank",
               fuel: "can't be blank",
               usage: "can't be blank",
               city_id: "can't be blank",
               parking: "can't be blank"
             } = errors(cs)
    end

    test "rejects a non-positive fiscal power" do
      cs = Vehicle.changeset(%Vehicle{}, %{@valid | fiscal_power: 0}, today: @today)
      assert errors(cs).fiscal_power =~ "must be greater than 0"
    end

    test "rejects a future first registration date" do
      attrs = Map.put(@valid, :first_registration, Date.add(@today, 1))
      cs = Vehicle.changeset(%Vehicle{}, attrs, today: @today)
      assert errors(cs).first_registration == "cannot be in the future"
    end

    test "accepts a past first registration date" do
      attrs = Map.put(@valid, :first_registration, ~D[2020-01-01])
      cs = Vehicle.changeset(%Vehicle{}, attrs, today: @today, formula: :rc)
      assert cs.valid?
    end

    test "vehicle_value is NOT required for a non-valuing formula (RC)" do
      cs = Vehicle.changeset(%Vehicle{}, @valid, today: @today, formula: :rc)
      assert cs.valid?
    end

    test "vehicle_value IS required for a valuing formula (Tous risques)" do
      cs = Vehicle.changeset(%Vehicle{}, @valid, today: @today, formula: :tous_risques)
      refute cs.valid?
      assert errors(cs).vehicle_value_centimes == "can't be blank"
    end

    test "vehicle_value required for Tiers étendu, and must be positive" do
      cs =
        Vehicle.changeset(%Vehicle{}, Map.put(@valid, :vehicle_value_centimes, 0),
          today: @today,
          formula: :tiers_etendu
        )

      assert errors(cs).vehicle_value_centimes =~ "must be greater than 0"

      ok =
        Vehicle.changeset(%Vehicle{}, Map.put(@valid, :vehicle_value_centimes, 15_000_000),
          today: @today,
          formula: :tiers_etendu
        )

      assert ok.valid?
    end
  end

  describe "Driver (step 2)" do
    @driver %{birth_date: ~D[2000-06-15], license_date: ~D[2019-06-15]}

    test "valid with sane dates" do
      assert Driver.changeset(%Driver{}, @driver, today: @today).valid?
    end

    test "birth and licence dates are required, one message each" do
      cs = Driver.changeset(%Driver{}, %{}, today: @today)
      assert %{birth_date: "can't be blank", license_date: "can't be blank"} = errors(cs)
    end

    test "rejects a future birth date" do
      cs =
        Driver.changeset(%Driver{}, %{@driver | birth_date: Date.add(@today, 1)}, today: @today)

      assert errors(cs).birth_date == "cannot be in the future"
    end

    test "rejects a future licence date" do
      cs =
        Driver.changeset(%Driver{}, %{@driver | license_date: Date.add(@today, 1)}, today: @today)

      assert errors(cs).license_date == "cannot be in the future"
    end

    test "rejects a licence issued before the legal driving age (boundary: 18th birthday minus one day)" do
      attrs = %{birth_date: ~D[2000-06-15], license_date: ~D[2018-06-14]}
      cs = Driver.changeset(%Driver{}, attrs, today: @today)
      assert errors(cs).license_date =~ "legal driving age"
    end

    test "accepts a licence issued exactly on the 18th birthday (boundary)" do
      attrs = %{birth_date: ~D[2000-06-15], license_date: ~D[2018-06-15]}
      assert Driver.changeset(%Driver{}, attrs, today: @today).valid?
    end

    test "crm outside 0.50–2.50 is rejected at both edges; the band and blank are accepted" do
      refute Driver.changeset(%Driver{}, Map.put(@driver, :crm, Decimal.new("0.49")),
               today: @today
             ).valid?

      refute Driver.changeset(%Driver{}, Map.put(@driver, :crm, Decimal.new("2.51")),
               today: @today
             ).valid?

      assert Driver.changeset(%Driver{}, Map.put(@driver, :crm, Decimal.new("0.50")),
               today: @today
             ).valid?

      assert Driver.changeset(%Driver{}, Map.put(@driver, :crm, Decimal.new("2.50")),
               today: @today
             ).valid?

      # "je ne sais pas" — crm omitted
      assert Driver.changeset(%Driver{}, @driver, today: @today).valid?
    end

    test "rejects a negative at-fault claim count" do
      cs = Driver.changeset(%Driver{}, Map.put(@driver, :at_fault_claims_36m, -1), today: @today)
      assert errors(cs).at_fault_claims_36m =~ "must be greater than or equal to 0"
    end
  end

  describe "Coverage (step 3)" do
    test "formula is required" do
      cs = Coverage.changeset(%Coverage{}, %{}, today: @today)
      assert errors(cs).formula == "can't be blank"
    end

    test "valid with a formula and known option codes" do
      cs =
        Coverage.changeset(%Coverage{}, %{formula: :tous_risques, options: ~w(vol incendie)},
          today: @today
        )

      assert cs.valid?
    end

    test "rejects an unknown option code" do
      cs = Coverage.changeset(%Coverage{}, %{formula: :rc, options: ~w(vol bogus)}, today: @today)
      assert Map.has_key?(errors(cs), :options)
    end

    test "rejects an effect date in the past" do
      attrs = %{formula: :rc, effect_date: Date.add(@today, -1)}
      cs = Coverage.changeset(%Coverage{}, attrs, today: @today)
      assert errors(cs).effect_date == "cannot be in the past"
    end

    test "accepts an effect date of today or later" do
      assert Coverage.changeset(%Coverage{}, %{formula: :rc, effect_date: @today}, today: @today).valid?

      assert Coverage.changeset(%Coverage{}, %{formula: :rc, effect_date: Date.add(@today, 30)},
               today: @today
             ).valid?
    end
  end

  describe "Contact (step 4)" do
    @contact %{
      first_name: "Amina",
      last_name: "El Fassi",
      phone: "+212612345678",
      consent_cgu: true,
      consent_transmission: true
    }

    test "valid with names, a Moroccan phone and both required consents" do
      assert Contact.changeset(%Contact{}, @contact).valid?
    end

    test "name and phone are required" do
      cs = Contact.changeset(%Contact{}, %{})
      e = errors(cs)
      assert e.first_name == "can't be blank"
      assert e.last_name == "can't be blank"
      assert e.phone == "can't be blank"
    end

    test "accepts the local 0-prefixed form and tolerates spaces" do
      assert Contact.changeset(%Contact{}, %{@contact | phone: "0612345678"}).valid?
      assert Contact.changeset(%Contact{}, %{@contact | phone: "06 12 34 56 78"}).valid?
    end

    test "rejects a non-Moroccan or malformed phone" do
      refute Contact.changeset(%Contact{}, %{@contact | phone: "+33612345678"}).valid?
      refute Contact.changeset(%Contact{}, %{@contact | phone: "12345"}).valid?

      assert errors(Contact.changeset(%Contact{}, %{@contact | phone: "12345"})).phone =~
               "Moroccan"
    end

    test "the two mandatory consents must be accepted; marketing is optional" do
      refute Contact.changeset(%Contact{}, %{@contact | consent_cgu: false}).valid?
      refute Contact.changeset(%Contact{}, %{@contact | consent_transmission: false}).valid?
      # marketing omitted → still valid
      assert Contact.changeset(%Contact{}, @contact).valid?

      assert errors(Contact.changeset(%Contact{}, %{@contact | consent_cgu: false})).consent_cgu ==
               "must be accepted"
    end

    test "an email, when given, must be well formed" do
      refute Contact.changeset(%Contact{}, Map.put(@contact, :email, "nope")).valid?
      assert Contact.changeset(%Contact{}, Map.put(@contact, :email, "a@b.co")).valid?
    end
  end

  describe "field_errors/1" do
    test "returns exactly one message per invalid field, keyed by field" do
      cs = Vehicle.changeset(%Vehicle{}, %{}, today: @today, formula: :tous_risques)
      result = Steps.field_errors(cs)

      # one message (a string) per invalid field
      assert Enum.all?(result, fn {field, msg} -> is_atom(field) and is_binary(msg) end)

      # every invalid field is represented, none more than once
      invalid_fields = cs.errors |> Keyword.keys() |> Enum.uniq()
      assert Enum.sort(Map.keys(result)) == Enum.sort(invalid_fields)
    end

    test "interpolates message placeholders (e.g. count/number bounds)" do
      cs = Driver.changeset(%Driver{}, Map.put(@driver, :crm, Decimal.new("9.99")), today: @today)
      refute Steps.field_errors(cs)[:crm] =~ "%{"
    end
  end
end
