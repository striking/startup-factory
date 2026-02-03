defmodule HalWeb.MissionControlLive do
  @moduledoc """
  Mission Control — a shared “control plane” UI for HAL.

  Inspired by OpenClaw/Mission Control dashboards:
  - Agent presence (runtime)
  - Task board (durable)
  - Approvals (durable)
  - Live feed (event log)
  """

  use HalWeb, :live_view

  alias HAL.AgentRegistry
  alias HAL.Autonomy.Approvals
  alias HAL.Heartbeat
  alias Hal.MissionControl

  @refresh_ms 2_500

  @columns [
    %{key: :inbox, label: "Inbox", statuses: ["pending"]},
    %{key: :in_progress, label: "In Progress", statuses: ["running"]},
    %{key: :review, label: "Review", statuses: ["paused"]},
    %{key: :done, label: "Done", statuses: ["completed"]},
    %{key: :blocked, label: "Blocked", statuses: ["failed"]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      AgentRegistry.subscribe()
      :timer.send_interval(@refresh_ms, self(), :refresh)
    end

    snapshot = MissionControl.snapshot()

    {:ok,
     socket
     |> assign(:page_title, "Mission Control")
     |> assign(:active_tab, :mission_control)
     |> assign(:columns, @columns)
     |> assign(:snapshot, snapshot)
     |> assign(:board, build_board(snapshot.tasks))
     |> assign(:heartbeat_status, Heartbeat.get_status())}
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
  def handle_event("approve", %{"token" => token}, socket) do
    case Approvals.approve(token) do
      {:ok, _req} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved #{token}")
         |> refresh_snapshot()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Approval not found")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "Approval is not pending")}
    end
  end

  @impl true
  def handle_event("deny", %{"token" => token}, socket) do
    case Approvals.deny(token, "Denied in Mission Control") do
      {:ok, _req} ->
        {:noreply,
         socket
         |> put_flash(:info, "Denied #{token}")
         |> refresh_snapshot()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Approval not found")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "Approval is not pending")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    snapshot = MissionControl.snapshot()

    {:noreply,
     socket
     |> assign(:snapshot, snapshot)
     |> assign(:board, build_board(snapshot.tasks))
     |> assign(:heartbeat_status, Heartbeat.get_status())}
  end

  @impl true
  def handle_info({:agent_joined, _info}, socket), do: {:noreply, refresh_snapshot(socket)}

  @impl true
  def handle_info({:agent_left, _agent_id, _reason}, socket),
    do: {:noreply, refresh_snapshot(socket)}

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
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-0">
      <div class="mb-6 flex space-x-4 border-b border-gray-200">
        <.link navigate={~p"/"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Dashboard
        </.link>
        <.link navigate={~p"/mission-control"} class="pb-2 px-1 border-b-2 border-red-500 text-sm font-medium text-red-600">
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

      <div class="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Mission Control</h1>
          <p class="mt-1 text-sm text-gray-600">
            One place to monitor agents, tasks, approvals, and activity.
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

      <div class="grid gap-6 lg:grid-cols-12">
        <!-- Agents -->
        <div class="lg:col-span-3">
          <div class="rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-gray-900">Agents</h2>
              <span class="text-xs text-gray-500"><%= length(@snapshot.agents) %> online</span>
            </div>

            <%= if Enum.empty?(@snapshot.agents) do %>
              <div class="p-4 text-sm text-gray-600">No agents are currently registered.</div>
            <% else %>
              <div class="divide-y divide-gray-100">
                <%= for agent <- @snapshot.agents do %>
                  <div class="px-4 py-3 flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-gray-900 truncate"><%= agent.agent_id %></div>
                      <div class="mt-0.5 text-xs text-gray-500">
                        <%= agent.metadata["role"] || agent.metadata[:role] || "agent" %>
                        <%= if status = (agent.metadata["status"] || agent.metadata[:status]) do %>
                          • <span class="font-mono"><%= status %></span>
                        <% end %>
                      </div>
                    </div>
                    <span class="inline-flex h-2 w-2 rounded-full bg-green-500 mt-2" title="online"></span>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <div class="mt-6 rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-gray-900">Approvals</h2>
              <span class="text-xs text-gray-500">
                <%= length(@snapshot.approvals) %> pending
                <%= if Enum.any?(@snapshot.queue) do %>
                  • <%= length(@snapshot.queue) %> queued
                <% end %>
              </span>
            </div>

            <%= if Enum.empty?(@snapshot.approvals) and Enum.empty?(@snapshot.queue) and Enum.empty?(@snapshot.recent_approvals) do %>
              <div class="p-4 text-sm text-gray-600">No approval activity.</div>
            <% else %>
              <%= if Enum.any?(@snapshot.approvals) do %>
                <div class="divide-y divide-gray-100">
                  <%= for approval <- @snapshot.approvals do %>
                    <div class="px-4 py-3">
                      <div class="flex items-start justify-between gap-3">
                        <div class="min-w-0">
                          <div class="text-xs font-mono text-gray-700 truncate"><%= approval.token %></div>
                          <div class="mt-1 text-sm text-gray-900 truncate">
                            <%= approval.tool_name %>
                          </div>
                          <%= if summary = approval_summary(approval) do %>
                            <div class="mt-0.5 text-xs text-gray-500 truncate"><%= summary %></div>
                          <% end %>
                        </div>
                        <div class="flex shrink-0 gap-2">
                          <button
                            phx-click="deny"
                            phx-value-token={approval.token}
                            class="inline-flex items-center rounded-md bg-white px-2 py-1 text-xs font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                          >
                            Deny
                          </button>
                          <button
                            phx-click="approve"
                            phx-value-token={approval.token}
                            class="inline-flex items-center rounded-md bg-red-600 px-2 py-1 text-xs font-semibold text-white shadow-sm hover:bg-red-500"
                          >
                            Approve
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if Enum.any?(@snapshot.queue) do %>
                <div class="border-t border-gray-100">
                  <div class="px-4 py-2 text-[11px] font-semibold text-gray-500 uppercase tracking-wide">
                    Execution queue
                  </div>
                  <div class="divide-y divide-gray-100">
                    <%= for item <- Enum.take(@snapshot.queue, 6) do %>
                      <div class="px-4 py-3">
                        <div class="flex items-start justify-between gap-3">
                          <div class="min-w-0">
                            <div class="flex items-center gap-2">
                              <span class={[
                                "inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-semibold",
                                execution_status_badge_class(item.execution_status)
                              ]}>
                                <%= String.upcase(item.execution_status || "unknown") %>
                              </span>
                              <div class="text-[11px] font-mono text-gray-700 truncate"><%= item.token %></div>
                            </div>

                            <div class="mt-1 text-sm text-gray-900 truncate"><%= item.tool_name %></div>

                            <%= if summary = approval_summary(item) do %>
                              <div class="mt-0.5 text-xs text-gray-500 truncate"><%= summary %></div>
                            <% end %>

                            <%= if preview = approval_execution_preview(item) do %>
                              <div class={[
                                "mt-2 text-xs font-mono whitespace-pre-wrap break-words",
                                if(item.execution_error, do: "text-red-700", else: "text-gray-700")
                              ]}>
                                <%= preview %>
                              </div>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if Enum.any?(@snapshot.recent_approvals) do %>
                <div class="border-t border-gray-100">
                  <div class="px-4 py-2 text-[11px] font-semibold text-gray-500 uppercase tracking-wide">
                    Recent
                  </div>
                  <div class="divide-y divide-gray-100">
                    <%= for item <- Enum.take(@snapshot.recent_approvals, 4) do %>
                      <div class="px-4 py-3">
                        <div class="flex items-start justify-between gap-3">
                          <div class="min-w-0">
                            <div class="flex items-center gap-2">
                              <span class={[
                                "inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-semibold",
                                execution_status_badge_class(item.execution_status)
                              ]}>
                                <%= String.upcase(item.execution_status || "unknown") %>
                              </span>
                              <div class="text-[11px] font-mono text-gray-700 truncate"><%= item.token %></div>
                            </div>

                            <div class="mt-1 text-sm text-gray-900 truncate"><%= item.tool_name %></div>

                            <%= if summary = approval_summary(item) do %>
                              <div class="mt-0.5 text-xs text-gray-500 truncate"><%= summary %></div>
                            <% end %>

                            <%= if preview = approval_execution_preview(item) do %>
                              <div class={[
                                "mt-2 text-xs font-mono whitespace-pre-wrap break-words",
                                if(item.execution_error, do: "text-red-700", else: "text-gray-700")
                              ]}>
                                <%= preview %>
                              </div>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <div class="px-4 py-3 border-t border-gray-100 text-xs">
                <.link navigate={~p"/approvals"} class="text-red-700 hover:text-red-900 underline">
                  View approvals →
                </.link>
              </div>
            <% end %>
          </div>

          <div class="mt-6 rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-gray-900">Budget</h2>
              <%= if @snapshot.budget do %>
                <span class="text-xs text-gray-500">daily + monthly</span>
              <% else %>
                <span class="text-xs text-gray-500">no user</span>
              <% end %>
            </div>

            <%= if budget = @snapshot.budget do %>
              <div class="p-4 text-sm text-gray-700 space-y-2">
                <div class="flex items-center justify-between">
                  <span class="text-gray-600">Daily remaining</span>
                  <span class="font-mono text-gray-900"><%= format_dollars(budget.daily_remaining_cents) %></span>
                </div>
                <div class="flex items-center justify-between">
                  <span class="text-gray-600">Monthly remaining</span>
                  <span class="font-mono text-gray-900"><%= format_dollars(budget.monthly_remaining_cents) %></span>
                </div>
              </div>
            <% else %>
              <div class="p-4 text-sm text-gray-600">
                No default user budget found yet.
              </div>
            <% end %>
          </div>

          <div class="mt-6 rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-gray-900">Changes</h2>
              <span class="text-xs text-gray-500"><%= length(@snapshot.changes) %> recent</span>
            </div>

            <%= if Enum.empty?(@snapshot.changes) do %>
              <div class="p-4 text-sm text-gray-600">No change requests yet.</div>
            <% else %>
              <div class="divide-y divide-gray-100">
                <%= for req <- Enum.take(@snapshot.changes, 6) do %>
                  <div class="px-4 py-3 flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-gray-900 truncate"><%= req.title %></div>
                      <div class="mt-0.5 text-xs text-gray-500 font-mono truncate"><%= req.id %></div>
                    </div>
                    <span class={[
                      "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                      change_status_badge_class(req.status)
                    ]}>
                      <%= String.upcase(req.status || "unknown") %>
                    </span>
                  </div>
                <% end %>
              </div>

              <div class="px-4 py-3 border-t border-gray-100 text-xs">
                <.link navigate={~p"/changes"} class="text-red-700 hover:text-red-900 underline">
                  View all changes →
                </.link>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Board -->
        <div class="lg:col-span-6">
          <div class="rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-gray-900">Mission Queue</h2>
              <span class="text-xs text-gray-500"><%= length(@snapshot.tasks) %> tasks</span>
            </div>

            <div class="p-4 overflow-x-auto">
              <div class="min-w-[900px] grid grid-cols-5 gap-4">
                <%= for col <- @columns do %>
                  <div class="rounded-lg bg-gray-50 border border-gray-200">
                    <div class="px-3 py-2 border-b border-gray-200 flex items-center justify-between">
                      <div class="text-xs font-semibold text-gray-700 uppercase tracking-wide">
                        <%= col.label %>
                      </div>
                      <div class="text-xs text-gray-500 font-mono">
                        <%= length(Map.get(@board, col.key, [])) %>
                      </div>
                    </div>

                    <div class="p-3 space-y-3">
                      <%= for task <- Map.get(@board, col.key, []) do %>
                        <div class="rounded-md bg-white border border-gray-200 shadow-sm p-3">
                          <div class="text-sm font-medium text-gray-900">
                            <%= task.title %>
                          </div>
                          <div class="mt-1 text-xs text-gray-500 truncate">
                            <%= task.original_request %>
                          </div>
                          <div class="mt-2 flex items-center justify-between gap-2 text-xs">
                            <span class={[
                              "inline-flex items-center rounded-full px-2 py-0.5 font-medium",
                              priority_badge_class(task.priority)
                            ]}>
                              <%= String.upcase(task.priority || "normal") %>
                            </span>
                            <span class="text-gray-500">
                              <%= if task.user do %>
                                <%= task.user.username || String.slice(task.user.id, 0..7) %>
                              <% else %>
                                unknown user
                              <% end %>
                            </span>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <!-- Live feed -->
        <div class="lg:col-span-3">
          <div class="rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-gray-900">Live Feed</h2>
              <span class="text-xs text-gray-500"><%= length(@snapshot.events) %></span>
            </div>

            <%= if Enum.empty?(@snapshot.events) do %>
              <div class="p-4 text-sm text-gray-600">No recent events.</div>
            <% else %>
              <div class="divide-y divide-gray-100 max-h-[720px] overflow-y-auto">
                <%= for event <- @snapshot.events do %>
                  <div class="px-4 py-3">
                    <div class="text-xs text-gray-500">
                      <%= format_event_time(event["timestamp"]) %>
                    </div>
                    <div class="mt-1 text-sm font-medium text-gray-900">
                      <%= event["event"] %>
                    </div>
                    <%= if data = event["data"] do %>
                      <div class="mt-1 text-xs text-gray-700 font-mono whitespace-pre-wrap break-words">
                        <%= summarize_event_data(data) %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp refresh_snapshot(socket) do
    snapshot = MissionControl.snapshot()

    socket
    |> assign(:snapshot, snapshot)
    |> assign(:board, build_board(snapshot.tasks))
  end

  defp build_board(tasks) do
    Enum.reduce(@columns, %{}, fn col, acc ->
      items = Enum.filter(tasks, &(&1.status in col.statuses))
      Map.put(acc, col.key, items)
    end)
  end

  defp format_event_time(nil), do: "unknown"

  defp format_event_time(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} ->
        seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

        cond do
          seconds < 60 -> "#{seconds}s ago"
          seconds < 3600 -> "#{div(seconds, 60)}m ago"
          seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
          true -> "#{div(seconds, 86_400)}d ago"
        end

      _ ->
        timestamp
    end
  end

  defp summarize_event_data(data) when is_map(data) do
    data
    |> Enum.take(8)
    |> Enum.map(fn {k, v} ->
      value =
        cond do
          is_binary(v) and byte_size(v) > 140 -> String.slice(v, 0, 140) <> "…"
          true -> inspect(v, limit: 80)
        end

      "#{k}=#{value}"
    end)
    |> Enum.join(" • ")
  end

  defp summarize_event_data(_), do: ""

  defp format_dollars(cents) when is_integer(cents) do
    "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  defp format_dollars(_), do: "$0.00"

  defp approval_summary(%{
         tool_name: "hal_skill_run",
         args: %{"skill" => skill, "input" => input}
       })
       when is_binary(skill) and is_binary(input) do
    truncate("#{skill}: #{input}", 80)
  end

  defp approval_summary(%{tool_name: "hal_skill_run", args: %{:skill => skill, :input => input}})
       when is_binary(skill) and is_binary(input) do
    truncate("#{skill}: #{input}", 80)
  end

  defp approval_summary(%{args: %{"task" => task}}) when is_binary(task), do: truncate(task, 80)
  defp approval_summary(%{args: %{:task => task}}) when is_binary(task), do: truncate(task, 80)
  defp approval_summary(_), do: nil

  defp approval_execution_preview(%{execution_error: error})
       when is_binary(error) and byte_size(error) > 0 do
    truncate(error, 220)
  end

  defp approval_execution_preview(%{execution_result: result}) when is_map(result) do
    output = deep_get(result, [:result, :output]) || deep_get(result, [:result, "output"])
    message = deep_get(result, [:message]) || deep_get(result, ["message"])

    cond do
      is_binary(output) and String.trim(output) != "" ->
        truncate(String.trim(output), 220)

      is_binary(message) and String.trim(message) != "" ->
        truncate(String.trim(message), 220)

      true ->
        nil
    end
  end

  defp approval_execution_preview(_), do: nil

  defp truncate(string, length) when is_binary(string) and byte_size(string) > length do
    String.slice(string, 0, length) <> "…"
  end

  defp truncate(string, _length), do: string

  defp priority_badge_class(priority) do
    case priority do
      "urgent" -> "bg-red-100 text-red-800"
      "high" -> "bg-amber-100 text-amber-800"
      "normal" -> "bg-gray-100 text-gray-700"
      "low" -> "bg-blue-100 text-blue-800"
      _ -> "bg-gray-100 text-gray-700"
    end
  end

  defp change_status_badge_class(status) do
    case status do
      "pending" -> "bg-gray-100 text-gray-800"
      "generating" -> "bg-blue-100 text-blue-800"
      "ready" -> "bg-green-100 text-green-800"
      "failed" -> "bg-red-100 text-red-800"
      "applied" -> "bg-purple-100 text-purple-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp execution_status_badge_class(status) do
    case status do
      "queued" -> "bg-blue-100 text-blue-800"
      "running" -> "bg-yellow-100 text-yellow-800"
      "failed" -> "bg-red-100 text-red-800"
      "completed" -> "bg-green-100 text-green-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp deep_get(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, map, fn key, acc ->
      if is_map(acc) do
        case map_get(acc, key) do
          nil -> {:halt, nil}
          value -> {:cont, value}
        end
      else
        {:halt, nil}
      end
    end)
  end

  defp deep_get(_, _), do: nil

  defp map_get(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      try do
        Map.get(map, String.to_existing_atom(key))
      rescue
        ArgumentError -> nil
      end
  end

  defp map_get(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
