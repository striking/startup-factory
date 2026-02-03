defmodule HalWeb.AgentStateLive do
  use HalWeb, :live_view
  alias HAL.AgentState
  alias HAL.EventLog

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 5 seconds
      :timer.send_interval(5000, self(), :refresh)
    end

    socket = assign_data(socket)
    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign_data(socket)}
  end

  @impl true
  def handle_event("clear_completed", _params, socket) do
    # In a real implementation, would archive completed tasks
    {:noreply, socket}
  end

  defp assign_data(socket) do
    context = AgentState.get_context()
    recent_events = EventLog.recent(limit: 20)
    stats = EventLog.stats()

    socket
    |> assign(:current_tasks, context.current_tasks)
    |> assign(:completed_tasks, Enum.take(context.recent_completions, 5))
    |> assign(:failed_tasks, Enum.take(context.recent_failures, 5))
    |> assign(:learned_facts, context.learned_facts)
    |> assign(:strategies, context.strategies)
    |> assign(:goals, context.goals)
    |> assign(:recent_events, recent_events)
    |> assign(:stats, stats)
    |> assign(:last_action, context.last_action)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 p-8">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-4xl font-bold text-gray-900 mb-2">🧠 HAL Agent State</h1>
          <p class="text-gray-600">Event sourcing + autonomous learning</p>
        </div>

        <!-- Stats Overview -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-gray-600 text-sm">Total Events</p>
                <p class="text-3xl font-bold text-gray-900"><%= @stats.total_events %></p>
              </div>
              <div class="text-4xl">📊</div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-gray-600 text-sm">Current Tasks</p>
                <p class="text-3xl font-bold text-blue-600"><%= length(@current_tasks) %></p>
              </div>
              <div class="text-4xl">⚡</div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-gray-600 text-sm">Learned Facts</p>
                <p class="text-3xl font-bold text-purple-600"><%= length(@learned_facts) %></p>
              </div>
              <div class="text-4xl">🧠</div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-gray-600 text-sm">Active Goals</p>
                <p class="text-3xl font-bold text-green-600"><%= length(@goals) %></p>
              </div>
              <div class="text-4xl">🎯</div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <!-- Current Tasks -->
          <div class="bg-white rounded-lg shadow">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-xl font-semibold text-gray-900">⚡ Current Tasks</h2>
            </div>
            <div class="p-6">
              <%= if Enum.empty?(@current_tasks) do %>
                <p class="text-gray-500 italic">No tasks in progress</p>
              <% else %>
                <ul class="space-y-3">
                  <%= for task <- @current_tasks do %>
                    <li class="flex items-start">
                      <span class="text-blue-500 mr-2">▶</span>
                      <div class="flex-1">
                        <p class="font-medium text-gray-900"><%= task %></p>
                        <%= if strategy = @strategies[task] do %>
                          <p class="text-sm text-gray-600">Strategy: <%= strategy %></p>
                        <% end %>
                      </div>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>

          <!-- Learned Facts -->
          <div class="bg-white rounded-lg shadow">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-xl font-semibold text-gray-900">🧠 Learned Facts</h2>
            </div>
            <div class="p-6 max-h-96 overflow-y-auto">
              <%= if Enum.empty?(@learned_facts) do %>
                <p class="text-gray-500 italic">No facts learned yet</p>
              <% else %>
                <ul class="space-y-2">
                  <%= for fact <- Enum.take(@learned_facts, 10) do %>
                    <li class="flex items-start">
                      <span class="text-purple-500 mr-2">💡</span>
                      <p class="text-gray-700"><%= fact %></p>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Recent Activity -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <h2 class="text-xl font-semibold text-gray-900">📜 Recent Events</h2>
            <span class="text-sm text-gray-500">
              Last updated: <%= if @last_action, do: Calendar.strftime(@last_action, "%H:%M:%S"), else: "Never" %>
            </span>
          </div>
          <div class="p-6">
            <div class="space-y-2">
              <%= for event <- @recent_events do %>
                <div class="flex items-start py-2 border-b border-gray-100 last:border-0">
                  <div class="flex-shrink-0 w-24 text-sm text-gray-500">
                    <%= format_timestamp(event["timestamp"]) %>
                  </div>
                  <div class="flex-shrink-0 w-40">
                    <span class={"px-2 py-1 rounded text-xs font-medium #{event_type_color(event["event"])}"}>
                      <%= event["event"] %>
                    </span>
                  </div>
                  <div class="flex-1 text-sm text-gray-700">
                    <%= format_event_data(event["data"]) %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Completed & Failed Tasks -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <!-- Recently Completed -->
          <div class="bg-white rounded-lg shadow">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-xl font-semibold text-gray-900">✅ Recently Completed</h2>
            </div>
            <div class="p-6">
              <%= if Enum.empty?(@completed_tasks) do %>
                <p class="text-gray-500 italic">No completed tasks yet</p>
              <% else %>
                <ul class="space-y-3">
                  <%= for task <- @completed_tasks do %>
                    <li class="border-l-4 border-green-500 pl-3">
                      <p class="font-medium text-gray-900"><%= task[:task] || task["task"] %></p>
                      <p class="text-sm text-gray-600"><%= task[:outcome] || task["outcome"] %></p>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>

          <!-- Failed Tasks -->
          <div class="bg-white rounded-lg shadow">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-xl font-semibold text-gray-900">❌ Recent Failures</h2>
            </div>
            <div class="p-6">
              <%= if Enum.empty?(@failed_tasks) do %>
                <p class="text-gray-500 italic">No failures (great!)</p>
              <% else %>
                <ul class="space-y-3">
                  <%= for task <- @failed_tasks do %>
                    <li class="border-l-4 border-red-500 pl-3">
                      <p class="font-medium text-gray-900"><%= task[:task] || task["task"] %></p>
                      <p class="text-sm text-red-600"><%= task[:reason] || task["reason"] %></p>
                      <%= if retry_count = task[:retry_count] || task["retry_count"] do %>
                        <p class="text-xs text-gray-500">Retries: <%= retry_count %></p>
                      <% end %>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Event Log Stats -->
        <div class="mt-8 bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold text-gray-900 mb-4">📊 Event Log Statistics</h2>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <%= for {event_type, count} <- Enum.sort_by(Map.get(@stats, :by_type, %{}), fn {_, count} -> -count end) |> Enum.take(8) do %>
              <div class="bg-gray-50 rounded p-3">
                <p class="text-sm text-gray-600"><%= event_type %></p>
                <p class="text-2xl font-bold text-gray-900"><%= count %></p>
              </div>
            <% end %>
          </div>
          <div class="mt-4 pt-4 border-t border-gray-200">
            <p class="text-sm text-gray-600">
              Event log size: <span class="font-medium"><%= @stats.file_size_kb %> KB</span>
              <%= if date_range = @stats.date_range do %>
                · Date range: <%= format_date_range(date_range) %>
              <% end %>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    timestamp
    |> String.slice(11, 8)
  end

  defp event_type_color("task_started"), do: "bg-blue-100 text-blue-800"
  defp event_type_color("task_completed"), do: "bg-green-100 text-green-800"
  defp event_type_color("task_failed"), do: "bg-red-100 text-red-800"
  defp event_type_color("approval_requested"), do: "bg-yellow-100 text-yellow-800"
  defp event_type_color("approval_approved"), do: "bg-green-100 text-green-800"
  defp event_type_color("approval_denied"), do: "bg-red-100 text-red-800"
  defp event_type_color("approval_execution_enqueued"), do: "bg-blue-100 text-blue-800"
  defp event_type_color("approval_execution_enqueue_failed"), do: "bg-red-100 text-red-800"
  defp event_type_color("approval_execution_started"), do: "bg-blue-100 text-blue-800"
  defp event_type_color("approval_execution_completed"), do: "bg-green-100 text-green-800"
  defp event_type_color("approval_execution_failed"), do: "bg-red-100 text-red-800"
  defp event_type_color("action_taken"), do: "bg-indigo-100 text-indigo-800"
  defp event_type_color("action_failed"), do: "bg-orange-100 text-orange-800"
  defp event_type_color("learned"), do: "bg-purple-100 text-purple-800"
  defp event_type_color("strategy_adjusted"), do: "bg-yellow-100 text-yellow-800"
  defp event_type_color("decision_made"), do: "bg-cyan-100 text-cyan-800"
  defp event_type_color(_), do: "bg-gray-100 text-gray-800"

  defp format_event_data(data) when is_map(data) do
    cond do
      task = data["task"] ->
        task

      action = data["action"] ->
        action

      fact = data["fact"] ->
        fact

      decision = data["decision"] ->
        decision

      true ->
        inspect(data)
    end
  end

  defp format_event_data(_), do: "—"

  defp format_date_range({start_dt, end_dt}) do
    start = Calendar.strftime(start_dt, "%Y-%m-%d")
    end_date = Calendar.strftime(end_dt, "%Y-%m-%d")
    "#{start} to #{end_date}"
  end

  defp format_date_range(_), do: "—"
end
