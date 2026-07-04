defmodule Sahla.SchemaTest do
  use ExUnit.Case, async: true

  # A throwaway schema built on the shared base, used to assert the
  # conventions `use Sahla.Schema` injects.
  defmodule SampleSchema do
    use Sahla.Schema

    schema "samples" do
      field :name_fr, :string
      field :name_ar, :string
      field :price_centimes, :integer
      timestamps()
    end
  end

  test "primary key is an app-generated binary_id named :id" do
    assert SampleSchema.__schema__(:primary_key) == [:id]
    assert {:id, :id, :binary_id} = SampleSchema.__schema__(:autogenerate_id)
    assert SampleSchema.__schema__(:type, :id) == :binary_id
  end

  test "timestamps are utc_datetime (second precision)" do
    assert SampleSchema.__schema__(:type, :inserted_at) == :utc_datetime
    assert SampleSchema.__schema__(:type, :updated_at) == :utc_datetime
  end
end
