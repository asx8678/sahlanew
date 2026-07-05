defmodule Sahla.Leads.Filter do
  @moduledoc """
  Schema-less filter form backing the admin kanban filter bar.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :assigned_admin_id, :string
    field :source, :string
    field :city_id, :string
    field :formula, :string
    field :priority, :string
    field :from, :string
    field :to, :string
  end

  def changeset(filter, attrs) do
    cast(filter, attrs, [:assigned_admin_id, :source, :city_id, :formula, :priority, :from, :to])
  end
end
