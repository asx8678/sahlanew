defmodule SahlaWeb.OffersLive do
  @moduledoc """
  Results page for a completed quote (§9.1, §9.3).

  Mount loads the quote by token, fetches the immutable rating run and its
  persisted offers, and displays them ranked. A missing/incomplete quote or a
  missing run renders a guarded state rather than crashing.
  """
  use SahlaWeb, :live_view

  alias Sahla.Quoting
  alias Sahla.Rating

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Quoting.get_quote_for_resume(token) do
        {:ok, %{status: :completed, rating_run_id: run_id} = quote} when is_binary(run_id) ->
          run = Rating.get_run_with_offers(run_id)
          offers = Enum.sort_by(run.offers, fn offer -> offer.annual_premium_centimes end, :desc)

          socket
          |> assign(:quote, quote)
          |> assign(:run, run)
          |> assign(:offers, offers)
          |> assign(:error, nil)

        {:ok, _quote} ->
          socket
          |> assign(:quote, nil)
          |> assign(:run, nil)
          |> assign(:offers, [])
          |> assign(:error, gettext("This quote has not been completed yet."))

        _ ->
          socket
          |> assign(:quote, nil)
          |> assign(:run, nil)
          |> assign(:offers, [])
          |> assign(:error, gettext("Quote not found."))
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[60vh]">
      <%= if @error do %>
        <section class="py-16 text-center">
          <h1 class="text-2xl font-bold text-ink">{gettext("Offers unavailable")}</h1>
          <p class="mt-4 text-ink/70">{@error}</p>
          <div class="mt-8">
            <.link navigate={~p"/devis/new"} class="btn btn-primary">
              {gettext("Start a new quote")}
            </.link>
          </div>
        </section>
      <% else %>
        <section class="space-y-6">
          <h1 class="text-2xl font-bold text-ink">{gettext("Your offers")}</h1>

          <div
            :if={@offers == []}
            class="rounded-card border border-ink/10 bg-surface p-6 text-center"
          >
            <p class="text-ink/70">{gettext("No offers match your profile right now.")}</p>
          </div>

          <div :for={offer <- @offers} class="rounded-card border border-ink/10 bg-surface p-4">
            <div class="flex items-center justify-between">
              <span class="font-semibold text-ink">{offer.insurer && offer.insurer.name_fr}</span>
              <span class="text-lg font-bold text-primary">
                <.price cents={offer.annual_premium_centimes} />
              </span>
            </div>
            <p class="mt-1 text-sm text-ink/60">{formula_label(offer.formula)}</p>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  defp formula_label(:rc), do: gettext("Civil liability")
  defp formula_label(:tiers_etendu), do: gettext("Third-party extended")
  defp formula_label(:tous_risques), do: gettext("All risks")
end
