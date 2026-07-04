defmodule SahlaWeb.Admin.DashboardHTML do
  @moduledoc "Placeholder authenticated-admin landing."
  use SahlaWeb, :html

  def index(assigns) do
    ~H"""
    <main class="admin-auth">
      <section class="admin-auth__card">
        <h1>{gettext("Admin")}</h1>
        <p>{gettext("You are signed in.")}</p>

        <form method="post" action={~p"/admin/logout"}>
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <input type="hidden" name="_method" value="delete" />
          <button type="submit">{gettext("Sign out")}</button>
        </form>
      </section>
    </main>
    """
  end
end
