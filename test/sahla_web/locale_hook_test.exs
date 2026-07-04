defmodule SahlaWeb.LocaleHookTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias SahlaWeb.LocaleHook

  test "assigns the session locale and direction, and sets the Gettext locale" do
    assert {:cont, socket} = LocaleHook.on_mount(:default, %{}, %{"locale" => "ar"}, %Socket{})
    assert socket.assigns.locale == "ar"
    assert socket.assigns.dir == "rtl"
    assert Gettext.get_locale() == "ar"
  end

  test "falls back to fr for a missing or invalid session locale" do
    assert {:cont, socket} = LocaleHook.on_mount(:default, %{}, %{}, %Socket{})
    assert socket.assigns.locale == "fr"
    assert socket.assigns.dir == "ltr"

    assert {:cont, socket} =
             LocaleHook.on_mount(:default, %{}, %{"locale" => "xx"}, %Socket{})

    assert socket.assigns.locale == "fr"
  end
end
