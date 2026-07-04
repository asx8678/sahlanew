defmodule SahlaWeb.Admin.SessionHTML do
  @moduledoc "Password (stage-one) login form."
  use SahlaWeb, :html

  def new(assigns) do
    ~H"""
    <main class="admin-auth">
      <section class="admin-auth__card">
        <h1>{gettext("Admin sign in")}</h1>

        <p :if={@error} class="admin-auth__error" role="alert">{@error}</p>

        <form method="post" action={~p"/admin/login"}>
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

          <label for="email">{gettext("Email")}</label>
          <input
            id="email"
            type="email"
            name="admin[email]"
            value={@email}
            required
            autocomplete="username"
            autofocus
          />

          <label for="password">{gettext("Password")}</label>
          <input
            id="password"
            type="password"
            name="admin[password]"
            required
            autocomplete="current-password"
          />

          <button type="submit">{gettext("Continue")}</button>
        </form>
      </section>
    </main>
    """
  end
end
