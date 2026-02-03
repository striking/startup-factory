defmodule HalWeb.DashboardLive do
  @moduledoc """
  LiveView for the main HAL dashboard.

  Displays:
  - Real-time statistics (active sessions, messages today, channels)
  - List of active sessions with click-to-view
  - System health indicators

  Subscribes to PubSub topics for real-time updates.
  """

  use HalWeb, :live_view

  alias Hal.Dashboard
  alias HalWeb.DashboardComponents
  alias HAL.Heartbeat
  alias HAL.Identity.Personality
  alias HAL.Goals.Manager, as: GoalManager
  alias HAL.Costs.Budget

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to session events for real-time updates
      Dashboard.subscribe_to_sessions()
      # Schedule periodic stats refresh
      :timer.send_interval(30_000, self(), :refresh_stats)
    end

    stats = Dashboard.get_stats()
    sessions = Dashboard.list_active_sessions(limit: 10)

    # Load Replicant data (personality, goals, budget)
    # For now, use a demo user_id - in production this would come from session
    demo_user_id = get_demo_user_id()
    personality = load_personality(demo_user_id)
    goals = load_goals(demo_user_id)
    budget = load_budget(demo_user_id)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_tab, :dashboard)
     |> assign(:stats, stats)
     |> assign(:sessions, sessions)
     |> assign(:channel_filter, "all")
     |> assign(:search_query, "")
     |> assign(:personality, personality)
     |> assign(:goals, goals)
     |> assign(:budget, budget)
     |> assign(:heartbeat_status, Heartbeat.get_status())}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_channel", %{"channel" => channel}, socket) do
    sessions = Dashboard.list_active_sessions(channel_type: channel, limit: 10)

    {:noreply,
     socket
     |> assign(:channel_filter, channel)
     |> assign(:sessions, sessions)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    sessions =
      Dashboard.list_active_sessions(
        channel_type: socket.assigns.channel_filter,
        search: query,
        limit: 10
      )

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:sessions, sessions)}
  end

  @impl true
  def handle_event("view_session", %{"id" => session_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/sessions/#{session_id}")}
  end

  @impl true
  def handle_event("run_heartbeat", _params, socket) do
    self_pid = self()

    Task.start(fn ->
      result = Heartbeat.check_for_work()
      send(self_pid, {:heartbeat_ran, result})
    end)

    {:noreply, put_flash(socket, :info, "Heartbeat started…")}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    stats = Dashboard.get_stats()

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:heartbeat_status, Heartbeat.get_status())}
  end

  @impl true
  def handle_info({:session_created, session}, socket) do
    # Add new session to the top of the list
    sessions = [session | Enum.take(socket.assigns.sessions, 9)]
    stats = Dashboard.get_stats()

    {:noreply,
     socket
     |> assign(:sessions, sessions)
     |> assign(:stats, stats)}
  end

  @impl true
  def handle_info({:session_updated, session}, socket) do
    # Update session in the list
    sessions =
      Enum.map(socket.assigns.sessions, fn s ->
        if s.id == session.id, do: session, else: s
      end)

    {:noreply, assign(socket, :sessions, sessions)}
  end

  @impl true
  def handle_info({:message_received, _message}, socket) do
    # Refresh stats when a message is received
    stats = Dashboard.get_stats()
    {:noreply, assign(socket, :stats, stats)}
  end

  @impl true
  def handle_info({:heartbeat_ran, result}, socket) do
    message =
      case result do
        :ok -> "Heartbeat finished"
        :skip -> "Heartbeat skipped"
        :error -> "Heartbeat failed"
        other -> "Heartbeat result: #{inspect(other)}"
      end

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> assign(:heartbeat_status, Heartbeat.get_status())}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper functions for loading Replicant data

  defp get_demo_user_id do
    # In production, get from session. For now, return nil for graceful fallback
    nil
  end

  defp load_personality(nil), do: nil

  defp load_personality(user_id) do
    case Personality.get_for_user(user_id) do
      personality when is_struct(personality) ->
        remaining = Personality.remaining_modifications(personality)
        Map.put(personality, :remaining_modifications, remaining)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp load_goals(nil), do: []

  defp load_goals(user_id) do
    case GoalManager.get_active_goals(user_id) do
      # Show top 5
      {:ok, goals} -> Enum.take(goals, 5)
      _ -> []
    end
  rescue
    _ -> []
  end

  defp load_budget(nil), do: nil

  defp load_budget(user_id) do
    Budget.get_remaining(user_id)
  rescue
    _ -> nil
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-0">
      <!-- Navigation -->
      <div class="mb-6 flex space-x-4 border-b border-gray-200">
        <.link navigate={~p"/"} class="pb-2 px-1 border-b-2 border-red-500 text-sm font-medium text-red-600">
          Dashboard
        </.link>
        <.link navigate={~p"/mission-control"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Mission Control
        </.link>
        <.link navigate={~p"/chat"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          💬 Chat
        </.link>
        <.link navigate={~p"/agent"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          🧠 Agent State
        </.link>
        <.link navigate={~p"/sessions"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Sessions
        </.link>
        <.link navigate={~p"/approvals"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Approvals
        </.link>
        <.link navigate={~p"/changes"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Changes
        </.link>
        <.link navigate={~p"/security"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Security
        </.link>
      </div>

      <!-- Page Header -->
      <div class="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Dashboard</h1>
          <p class="mt-1 text-sm text-gray-600">
            Monitor your HAL assistant in real-time
          </p>
        </div>

        <div class="flex items-center gap-3">
          <div class="hidden sm:block text-right">
            <div class="text-xs text-gray-500">Autonomy</div>
            <div class="text-sm font-medium text-gray-900">
              <%= if @heartbeat_status[:can_work] do %>
                Ready
              <% else %>
                Quiet
              <% end %>
            </div>
          </div>

          <button
            phx-click="run_heartbeat"
            class="inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500"
          >
            Run heartbeat
          </button>
        </div>
      </div>

      <!-- Stats Panel -->
      <DashboardComponents.stats_panel stats={@stats} />

      <!-- Replicant Status Section -->
      <div class="mt-8">
        <h2 class="text-lg font-semibold text-gray-900 mb-4">Replicant Status</h2>
        <div class="grid gap-6 md:grid-cols-3">
          <DashboardComponents.personality_panel personality={@personality} />
          <DashboardComponents.goals_panel goals={@goals} />
          <DashboardComponents.costs_panel budget={@budget} />
        </div>
      </div>

      <!-- Sessions Section -->
      <div class="mt-8">
        <div class="sm:flex sm:items-center sm:justify-between">
          <h2 class="text-lg font-semibold text-gray-900">Active Sessions</h2>
          <div class="mt-4 sm:mt-0 sm:flex sm:items-center sm:space-x-4">
            <!-- Search -->
            <form phx-change="search" class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass" class="h-4 w-4 text-gray-400" />
              </div>
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search sessions..."
                class="block w-full rounded-md border-0 py-1.5 pl-10 pr-3 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-red-600 sm:text-sm sm:leading-6"
                phx-debounce="300"
              />
            </form>

            <!-- Channel Filter -->
            <div class="mt-2 sm:mt-0">
              <select
                phx-change="filter_channel"
                name="channel"
                class="block w-full rounded-md border-0 py-1.5 pl-3 pr-10 text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-red-600 sm:text-sm sm:leading-6"
                aria-label="Filter by channel"
              >
                <option value="all" selected={@channel_filter == "all"}>All Channels</option>
                <option value="telegram" selected={@channel_filter == "telegram"}>Telegram</option>
                <option value="slack" selected={@channel_filter == "slack"}>Slack</option>
                <option value="discord" selected={@channel_filter == "discord"}>Discord</option>
              </select>
            </div>
          </div>
        </div>

        <!-- Sessions List -->
        <div class="mt-4">
          <%= if Enum.empty?(@sessions) do %>
            <div class="text-center py-12 bg-white rounded-lg border border-gray-200">
              <.icon name="hero-inbox-stack" class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-sm font-semibold text-gray-900">No active sessions</h3>
              <p class="mt-1 text-sm text-gray-500">
                Sessions will appear here when users start conversations.
              </p>
            </div>
          <% else %>
            <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <%= for session <- @sessions do %>
                <DashboardComponents.session_card
                  session={session}
                  on_click={JS.push("view_session", value: %{id: session.id})}
                />
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- View All Link -->
        <%= if length(@sessions) >= 10 do %>
          <div class="mt-6 text-center">
            <.styled_link navigate={~p"/sessions"} class="text-sm font-medium text-red-600 hover:text-red-500">
              View all sessions
              <span aria-hidden="true"> &rarr;</span>
            </.styled_link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
