defmodule HalWeb.SessionsLive do
  @moduledoc """
  LiveView for displaying all sessions with filtering and pagination.
  """

  use HalWeb, :live_view

  alias Hal.Dashboard
  alias HalWeb.DashboardComponents

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Dashboard.subscribe_to_sessions()
    end

    {:ok,
     socket
     |> assign(:page_title, "Sessions")
     |> assign(:active_tab, :sessions)
     |> assign(:channel_filter, "all")
     |> assign(:search_query, "")
     |> assign(:page, 1)
     |> load_sessions()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = String.to_integer(params["page"] || "1")
    channel = params["channel"] || "all"
    search = params["search"] || ""

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:channel_filter, channel)
     |> assign(:search_query, search)
     |> load_sessions()}
  end

  defp load_sessions(socket) do
    %{page: page, channel_filter: channel, search_query: search} = socket.assigns

    sessions =
      Dashboard.list_active_sessions(
        channel_type: channel,
        search: search,
        limit: @per_page,
        offset: (page - 1) * @per_page
      )

    total = Dashboard.count_active_sessions(channel_type: channel)
    total_pages = max(1, ceil(total / @per_page))

    socket
    |> assign(:sessions, sessions)
    |> assign(:total, total)
    |> assign(:total_pages, total_pages)
  end

  @impl true
  def handle_event("filter_channel", %{"channel" => channel}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/sessions?#{%{channel: channel, search: socket.assigns.search_query, page: 1}}"
     )}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/sessions?#{%{channel: socket.assigns.channel_filter, search: query, page: 1}}"
     )}
  end

  @impl true
  def handle_event("view_session", %{"id" => session_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/sessions/#{session_id}")}
  end

  @impl true
  def handle_info({:session_created, _session}, socket) do
    {:noreply, load_sessions(socket)}
  end

  @impl true
  def handle_info({:session_updated, session}, socket) do
    sessions =
      Enum.map(socket.assigns.sessions, fn s ->
        if s.id == session.id, do: session, else: s
      end)

    {:noreply, assign(socket, :sessions, sessions)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-0">
      <!-- Page Header -->
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Sessions</h1>
        <p class="mt-1 text-sm text-gray-600">
          View and manage all conversation sessions
        </p>
      </div>

      <!-- Filters -->
      <div class="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <!-- Search -->
        <form phx-change="search" class="relative flex-1 max-w-md">
          <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <.icon name="hero-magnifying-glass" class="h-4 w-4 text-gray-400" />
          </div>
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search by channel ID or username..."
            class="block w-full rounded-md border-0 py-2 pl-10 pr-3 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-red-600 sm:text-sm"
            phx-debounce="300"
          />
        </form>

        <!-- Channel Filter -->
        <div class="flex items-center space-x-2">
          <.icon name="hero-funnel" class="h-4 w-4 text-gray-400" />
          <select
            phx-change="filter_channel"
            name="channel"
            class="rounded-md border-0 py-2 pl-3 pr-10 text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-red-600 sm:text-sm"
            aria-label="Filter by channel"
          >
            <option value="all" selected={@channel_filter == "all"}>All Channels</option>
            <option value="telegram" selected={@channel_filter == "telegram"}>Telegram</option>
            <option value="slack" selected={@channel_filter == "slack"}>Slack</option>
            <option value="discord" selected={@channel_filter == "discord"}>Discord</option>
          </select>
        </div>
      </div>

      <!-- Results Count -->
      <div class="mb-4 text-sm text-gray-500">
        Showing <%= length(@sessions) %> of <%= @total %> sessions
      </div>

      <!-- Sessions Grid -->
      <%= if Enum.empty?(@sessions) do %>
        <div class="text-center py-16 bg-white rounded-lg border border-gray-200">
          <.icon name="hero-inbox-stack" class="mx-auto h-12 w-12 text-gray-400" />
          <h3 class="mt-4 text-sm font-semibold text-gray-900">No sessions found</h3>
          <p class="mt-2 text-sm text-gray-500">
            <%= if @search_query != "" or @channel_filter != "all" do %>
              Try adjusting your filters or search query.
            <% else %>
              Sessions will appear here when users start conversations.
            <% end %>
          </p>
        </div>
      <% else %>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          <%= for session <- @sessions do %>
            <DashboardComponents.session_card
              session={session}
              on_click={JS.push("view_session", value: %{id: session.id})}
            />
          <% end %>
        </div>

        <!-- Pagination -->
        <%= if @total_pages > 1 do %>
          <nav class="mt-8 flex items-center justify-between border-t border-gray-200 pt-4" aria-label="Pagination">
            <div>
              <p class="text-sm text-gray-700">
                Page <span class="font-medium"><%= @page %></span> of <span class="font-medium"><%= @total_pages %></span>
              </p>
            </div>
            <div class="flex flex-1 justify-end gap-2">
              <%= if @page > 1 do %>
                <.styled_link
                  patch={~p"/sessions?#{%{channel: @channel_filter, search: @search_query, page: @page - 1}}"}
                  class="relative inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                >
                  Previous
                </.styled_link>
              <% else %>
                <span class="relative inline-flex items-center rounded-md bg-gray-100 px-3 py-2 text-sm font-semibold text-gray-400 ring-1 ring-inset ring-gray-300 cursor-not-allowed">
                  Previous
                </span>
              <% end %>

              <%= if @page < @total_pages do %>
                <.styled_link
                  patch={~p"/sessions?#{%{channel: @channel_filter, search: @search_query, page: @page + 1}}"}
                  class="relative inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                >
                  Next
                </.styled_link>
              <% else %>
                <span class="relative inline-flex items-center rounded-md bg-gray-100 px-3 py-2 text-sm font-semibold text-gray-400 ring-1 ring-inset ring-gray-300 cursor-not-allowed">
                  Next
                </span>
              <% end %>
            </div>
          </nav>
        <% end %>
      <% end %>
    </div>
    """
  end
end
