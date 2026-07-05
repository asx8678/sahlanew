defmodule SahlaWeb.DevisLive do
  @moduledoc """
  Resumable quote funnel shell (§5.2, §6.2, §7.3).

  - Mount loads or creates a quote by token and resumes at its current step.
  - phx-change autosaves the active step through `Quoting.upsert_step/3`.
  - Continuer/Retour navigate between steps; current_step only advances.
  - Expired quotes render a guarded state outside any stream container.
  """
  use SahlaWeb, :live_view

  alias Sahla.Quoting

  @steps Quoting.steps()
  @step_count length(@steps)

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Quoting.get_quote_for_resume(token) do
        {:error, :not_found} ->
          {:ok, quote} = Quoting.create_quote(locale: socket.assigns.locale)
          redirect(socket, to: ~p"/devis/#{quote.token}")

        {:error, :expired, quote} ->
          socket
          |> assign(:expired, true)
          |> assign(:quote, quote)
          |> assign(:current_step, nil)
          |> assign(:step, nil)
          |> assign(:changeset, nil)

        {:ok, quote} ->
          step = step_atom(quote.current_step)

          socket
          |> assign(:expired, false)
          |> assign(:quote, quote)
          |> assign(:current_step, quote.current_step)
          |> assign(:step, step)
          |> assign(:changeset, nil)
      end

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    {:ok, quote} = Quoting.create_quote(locale: socket.assigns.locale)
    {:ok, redirect(socket, to: ~p"/devis/#{quote.token}")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("autosave", %{"step" => params}, socket) do
    step = socket.assigns.step
    quote = socket.assigns.quote

    case Quoting.upsert_step(quote, step, params) do
      {:ok, quote} ->
        {:noreply,
         socket
         |> assign(:quote, quote)
         |> assign(:current_step, quote.current_step)
         |> assign(:changeset, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("continue", _params, socket) do
    current = socket.assigns.current_step

    if current < @step_count do
      next_step = current + 1
      {:ok, quote} = update_step(socket.assigns.quote, next_step)

      {:noreply,
       socket
       |> assign(:current_step, next_step)
       |> assign(:step, step_atom(next_step))
       |> assign(:quote, quote)
       |> assign(:changeset, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("back", _params, socket) do
    current = socket.assigns.current_step

    if current > 1 do
      prev_step = current - 1
      {:ok, quote} = update_step(socket.assigns.quote, prev_step)

      {:noreply,
       socket
       |> assign(:current_step, prev_step)
       |> assign(:step, step_atom(prev_step))
       |> assign(:quote, quote)
       |> assign(:changeset, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[60vh]">
      <%= if @expired do %>
        <section class="py-16 text-center">
          <h1 class="text-2xl font-bold text-ink">{gettext("This quote link has expired")}</h1>
          <p class="mt-4 text-ink/70">
            {gettext("Please start a new quote to get an up-to-date price estimate.")}
          </p>
          <div class="mt-8">
            <.link navigate={~p"/devis/new"} class="btn btn-primary">
              {gettext("Start a new quote")}
            </.link>
          </div>
        </section>
      <% else %>
        <section>
          <.progress current_step={@current_step} />

          <.card class="mt-6">
            <.step_form step={@step} changeset={@changeset} current_step={@current_step} />
          </.card>

          <div class="mt-6 flex items-center justify-between gap-4">
            <.button
              variant="ghost"
              phx-click="back"
              disabled={@current_step == 1}
            >
              {gettext("Back")}
            </.button>

            <.button
              variant="primary"
              phx-click="continue"
              disabled={@current_step == 4}
            >
              {gettext("Continue")}
            </.button>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  attr :current_step, :integer, required: true

  defp progress(assigns) do
    steps = Quoting.steps()
    total = length(steps)

    assigns =
      assign(assigns,
        steps: steps,
        total: total
      )

    ~H"""
    <div class="flex items-center justify-center gap-2" aria-label={gettext("Quote progress")}>
      <div :for={{name, number} <- @steps} class="flex items-center gap-2">
        <div class={[
          "flex size-10 items-center justify-center rounded-full border-2 font-semibold",
          @current_step >= number && "border-primary bg-primary text-white",
          @current_step < number && "border-ink/20 bg-surface text-ink/50"
        ]}>
          {number}
        </div>
        <span class={[
          "hidden text-sm sm:inline",
          @current_step >= number && "font-medium text-ink",
          @current_step < number && "text-ink/50"
        ]}>
          {step_label(name)}
        </span>
        <span :if={number != @total} class="me-2 ms-2 hidden h-0.5 w-8 bg-ink/10 sm:inline-block" />
      </div>
    </div>
    """
  end

  attr :step, :atom, required: true
  attr :changeset, :any, default: nil
  attr :current_step, :integer, required: true

  defp step_form(%{step: :vehicle} = assigns) do
    ~H"""
    <form phx-change="autosave" class="space-y-4">
      <h2 class="text-xl font-semibold text-ink">{gettext("Your vehicle")}</h2>
      <.input
        name="step[plate]"
        label={gettext("Licence plate")}
        value={field_value(@changeset, :plate)}
      />
      <p class="text-sm text-ink/60">
        {gettext("Step %{step} placeholder — vehicle form coming next.", step: @current_step)}
      </p>
    </form>
    """
  end

  defp step_form(%{step: :driver} = assigns) do
    ~H"""
    <form phx-change="autosave" class="space-y-4">
      <h2 class="text-xl font-semibold text-ink">{gettext("Driver profile")}</h2>
      <.input
        name="step[birth_date]"
        type="date"
        label={gettext("Birth date")}
        value={field_value(@changeset, :birth_date)}
      />
      <p class="text-sm text-ink/60">
        {gettext("Step %{step} placeholder — driver form coming next.", step: @current_step)}
      </p>
    </form>
    """
  end

  defp step_form(%{step: :coverage} = assigns) do
    ~H"""
    <form phx-change="autosave" class="space-y-4">
      <h2 class="text-xl font-semibold text-ink">{gettext("Coverage")}</h2>
      <.input
        name="step[formula]"
        type="select"
        label={gettext("Formula")}
        options={[Tiers: "tiers", "Tiers+": "tiers_plus", "Tous risques": "tous_risques"]}
        value={field_value(@changeset, :formula)}
      />
      <p class="text-sm text-ink/60">
        {gettext("Step %{step} placeholder — coverage form coming next.", step: @current_step)}
      </p>
    </form>
    """
  end

  defp step_form(%{step: :contact} = assigns) do
    ~H"""
    <form phx-change="autosave" class="space-y-4">
      <h2 class="text-xl font-semibold text-ink">{gettext("Contact details")}</h2>
      <.input
        name="step[phone]"
        type="tel"
        label={gettext("Phone")}
        value={field_value(@changeset, :phone)}
      />
      <p class="text-sm text-ink/60">
        {gettext("Step %{step} placeholder — contact form coming next.", step: @current_step)}
      </p>
    </form>
    """
  end

  defp step_form(assigns) do
    ~H"""
    <p class="text-ink/70">{gettext("Unknown step")}</p>
    """
  end

  defp step_label(:vehicle), do: gettext("Vehicle")
  defp step_label(:driver), do: gettext("Driver")
  defp step_label(:coverage), do: gettext("Coverage")
  defp step_label(:contact), do: gettext("Contact")

  defp field_value(nil, _field), do: ""

  defp field_value(changeset, field) do
    Ecto.Changeset.get_field(changeset, field) || ""
  end

  defp step_atom(number) when is_integer(number) and number > 0 do
    @steps
    |> Enum.find(fn {_atom, n} -> n == number end)
    |> elem(0)
  end

  defp update_step(quote, next_step) do
    quote
    |> Ecto.Changeset.change(current_step: next_step)
    |> Sahla.Repo.update()
  end
end
