defmodule SahlaWeb.Admin.DashboardHTML do
  @moduledoc "Placeholder authenticated-admin landing."
  use SahlaWeb, :html

  def index(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-2xl font-semibold text-ink">{gettext("Dashboard")}</h1>
      <p class="text-ink/70">{gettext("You are signed in.")}</p>
    </div>
    """
  end
end
