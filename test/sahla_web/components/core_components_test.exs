defmodule SahlaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import SahlaWeb.CoreComponents

  describe "button/1" do
    test "renders primary variant with correct classes" do
      assigns = %{}

      html =
        ~H"""
        <.button variant="primary" size="md">Save</.button>
        """
        |> rendered_to_string()

      assert html =~ "btn"
      assert html =~ "btn-primary"
      assert html =~ "btn-md"
      assert html =~ "Save"
    end

    test "renders all supported variants" do
      for variant <- ~w(primary secondary outline ghost danger) do
        assigns = %{variant: variant}

        html =
          ~H"""
          <.button variant={@variant}>Label</.button>
          """
          |> rendered_to_string()

        expected_class =
          if(variant == "danger",
            do: "btn-error",
            else: "btn-#{String.replace(variant, "_", "-")}"
          )

        assert html =~ expected_class
      end
    end

    test "renders loading spinner" do
      assigns = %{}

      html =
        ~H"""
        <.button loading>Submit</.button>
        """
        |> rendered_to_string()

      assert html =~ "hero-arrow-path"
      assert html =~ "opacity-80"
      assert html =~ "pointer-events-none"
    end
  end

  describe "card/1" do
    test "renders surface card with rounded corners and shadow" do
      assigns = %{}

      html =
        ~H"""
        <.card>Content</.card>
        """
        |> rendered_to_string()

      assert html =~ "rounded-card"
      assert html =~ "bg-surface"
      assert html =~ "shadow-soft"
      assert html =~ "p-6"
      assert html =~ "Content"
    end

    test "accepts extra classes" do
      assigns = %{}

      html =
        ~H"""
        <.card class="border border-ink/10">Content</.card>
        """
        |> rendered_to_string()

      assert html =~ "border-ink/10"
    end
  end

  describe "badge/1" do
    test "renders all supported variants" do
      for variant <- ~w(default best_value promo info success warning error) do
        assigns = %{variant: variant}

        html =
          ~H"""
          <.badge variant={@variant}>Label</.badge>
          """
          |> rendered_to_string()

        assert html =~ "inline-flex"
        assert html =~ "rounded-full"

        case variant do
          "best_value" -> assert html =~ "bg-accent"
          "promo" -> assert html =~ "bg-warm"
          "error" -> assert html =~ "bg-error"
          _ -> :ok
        end
      end
    end
  end

  describe "option_card/1" do
    test "renders a radio input and selected visual state" do
      assigns = %{}

      html =
        ~H"""
        <.option_card name="formula" value="tiers" label="Tiers" selected />
        """
        |> rendered_to_string()

      assert html =~ ~S(type="radio")
      assert html =~ "name=\"formula\""
      assert html =~ "value=\"tiers\""
      assert html =~ "checked"
      assert html =~ "border-primary"
    end

    test "renders an unselected visual state by default" do
      assigns = %{}

      html =
        ~H"""
        <.option_card name="formula" value="tous_risques" label="Tous risques" />
        """
        |> rendered_to_string()

      refute html =~ "checked"
      assert html =~ "border-ink/10"
    end
  end

  describe "price/1" do
    test "formats cents as MAD with tabular figures" do
      assigns = %{}

      html =
        ~H"""
        <.price cents={2_940_00} />
        """
        |> rendered_to_string()

      assert html =~ "tabular-nums"
      assert html =~ "2 940,00"
      assert html =~ "MAD"
    end

    test "can hide decimals" do
      assigns = %{}

      html =
        ~H"""
        <.price cents={294_000} show_decimals={false} />
        """
        |> rendered_to_string()

      assert html =~ "2 940"
      refute html =~ "2 940,00"
    end
  end
end
