defmodule Sahla.Quoting.Steps do
  @moduledoc """
  Per-step validation for the funnel (§5.2). Each step is a pure `embedded_schema`
  (`Steps.Vehicle`, `Steps.Driver`, `Steps.Coverage`, `Steps.Contact`) that
  validates independently — no Repo, no side effects — so the LiveView can gate
  one step at a time and property/golden-test the rules in isolation.

  This module holds cross-step helpers: the field-error projection the UI renders
  and the shared date/phone validators the steps reuse.
  """
  import Ecto.Changeset

  # Moroccan legal driving age (§5.2 conducteur).
  @legal_driving_age 18

  # +212 6…/7… mobile, or the local 06…/07… form the user typically types.
  @ma_phone_regex ~r/^(?:\+212|0)[5-7]\d{8}$/

  @doc """
  Projects a changeset's errors to **exactly one message per invalid field**,
  keyed by field, with interpolations applied. This is what the funnel component
  renders next to each input; a field never shows more than one message.
  """
  @spec field_errors(Ecto.Changeset.t()) :: %{atom() => String.t()}
  def field_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> traverse_errors(fn {msg, opts} -> interpolate(msg, opts) end)
    |> Map.new(fn {field, [message | _rest]} -> {field, message} end)
  end

  defp interpolate(msg, opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  @doc "Validates that `field`, when set, is a date not in the future (relative to `today`)."
  def validate_not_future(changeset, field, today) do
    validate_change(changeset, field, fn ^field, %Date{} = date ->
      if Date.compare(date, today) == :gt, do: [{field, "cannot be in the future"}], else: []
    end)
  end

  @doc "Validates that `field`, when set, is a date not in the past (relative to `today`)."
  def validate_not_past(changeset, field, today) do
    validate_change(changeset, field, fn ^field, %Date{} = date ->
      if Date.compare(date, today) == :lt, do: [{field, "cannot be in the past"}], else: []
    end)
  end

  @doc """
  Validates the driver was at least the legal driving age on `license_field`
  relative to `birth_field`. Only runs when both dates are present and valid.
  """
  def validate_licensed_of_age(changeset, birth_field, license_field) do
    birth = get_field(changeset, birth_field)
    license = get_field(changeset, license_field)

    with %Date{} <- birth,
         %Date{} <- license,
         true <- age_on(birth, license) < @legal_driving_age do
      add_error(changeset, license_field, "must be on or after the legal driving age (%{age})",
        age: @legal_driving_age
      )
    else
      _ -> changeset
    end
  end

  # Full years elapsed from `birth` to `on`, without constructing intermediate dates.
  defp age_on(%Date{} = birth, %Date{} = on) do
    had_birthday? = {on.month, on.day} >= {birth.month, birth.day}
    on.year - birth.year - if(had_birthday?, do: 0, else: 1)
  end

  @doc "Validates a Moroccan phone number format (+212… or local 0…). Whitespace-tolerant."
  def validate_ma_phone(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      normalized = value |> to_string() |> String.replace(~r/\s/, "")

      if Regex.match?(@ma_phone_regex, normalized),
        do: [],
        else: [{field, "is not a valid Moroccan phone number"}]
    end)
  end

  @doc "Validates that a required consent boolean was accepted (`true`)."
  def validate_accepted(changeset, field) do
    if get_field(changeset, field) == true,
      do: changeset,
      else: add_error(changeset, field, "must be accepted")
  end

  def legal_driving_age, do: @legal_driving_age
end
