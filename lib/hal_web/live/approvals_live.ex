defmodule HalWeb.ApprovalsLive do
  @moduledoc """
  LiveView for reviewing and approving high-impact actions.

  This is the human-in-the-loop gate for codops-impacting actions (e.g., delegating
  to Codex/Jules). Tool execution can create pending approval requests, which are
  surfaced here for explicit approval or denial.
  """

  use HalWeb, :live_view

  alias HAL.Autonomy.Approvals

  @refresh_ms 2_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_ms, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "Approvals")
     |> assign(:active_tab, :approvals)
     |> assign(:approvals, Approvals.list_pending(limit: 50))
     |> assign(:queue, Approvals.list_queue(limit: 50))
     |> assign(:recent_executions, Approvals.list_recent_executions(limit: 50))}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     socket
     |> assign(:approvals, Approvals.list_pending(limit: 50))
     |> assign(:queue, Approvals.list_queue(limit: 50))
     |> assign(:recent_executions, Approvals.list_recent_executions(limit: 50))}
  end

  @impl true
  def handle_event("approve", %{"token" => token}, socket) do
    case Approvals.approve(token) do
      {:ok, _req} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved #{token}")
         |> assign(:approvals, Approvals.list_pending(limit: 50))
         |> assign(:queue, Approvals.list_queue(limit: 50))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Approval not found")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "Approval is not pending")}
    end
  end

  @impl true
  def handle_event("deny", %{"token" => token}, socket) do
    case Approvals.deny(token, "Denied in UI") do
      {:ok, _req} ->
        {:noreply,
         socket
         |> put_flash(:info, "Denied #{token}")
         |> assign(:approvals, Approvals.list_pending(limit: 50))
         |> assign(:queue, Approvals.list_queue(limit: 50))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Approval not found")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "Approval is not pending")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-0">
      <div class="mb-6 flex space-x-4 border-b border-gray-200">
        <.link navigate={~p"/"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
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
        <.link navigate={~p"/approvals"} class="pb-2 px-1 border-b-2 border-red-500 text-sm font-medium text-red-600">
          Approvals
        </.link>
        <.link navigate={~p"/changes"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Changes
        </.link>
        <.link navigate={~p"/security"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Security
        </.link>
      </div>

      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Approvals</h1>
        <p class="mt-1 text-sm text-gray-600">
          Pending codops-impacting actions that require explicit human approval.
        </p>
      </div>

      <%= if Enum.empty?(@approvals) do %>
        <div class="text-center py-12 bg-white rounded-lg border border-gray-200">
          <.icon name="hero-check-circle" class="mx-auto h-12 w-12 text-green-500" />
          <h3 class="mt-2 text-sm font-semibold text-gray-900">No pending approvals</h3>
          <p class="mt-1 text-sm text-gray-500">
            You’re all clear.
          </p>
        </div>
      <% else %>
        <div class="overflow-hidden rounded-lg bg-white shadow-sm border border-gray-200">
          <div class="divide-y divide-gray-200">
            <%= for approval <- @approvals do %>
              <div class="p-4 sm:p-6">
                <div class="flex items-start justify-between gap-4">
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800">
                        Pending
                      </span>
                      <span class="text-sm font-mono text-gray-700"><%= approval.token %></span>
                    </div>

                    <div class="mt-2 text-sm text-gray-900">
                      <span class="font-medium"><%= approval.tool_name %></span>
                      <%= if task = approval_task(approval) do %>
                        <span class="text-gray-500">—</span>
                        <span class="text-gray-700"><%= task %></span>
                      <% end %>
                    </div>

                    <div class="mt-2 text-xs text-gray-500">
                      Requested <%= format_relative(approval.inserted_at) %>
                      <%= if approval.user do %>
                        • User: <%= approval.user.username || String.slice(approval.user.id, 0..7) %>
                      <% end %>
                    </div>
                  </div>

                  <div class="flex shrink-0 items-center gap-2">
                    <button
                      phx-click="deny"
                      phx-value-token={approval.token}
                      class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                    >
                      Deny
                    </button>
                    <button
                      phx-click="approve"
                      phx-value-token={approval.token}
                      class="inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500"
                    >
                      Approve
                    </button>
                  </div>
                </div>

                <%= if details = approval_details(approval) do %>
                  <div class="mt-4 rounded-md bg-gray-50 p-3 text-xs text-gray-700 font-mono overflow-x-auto">
                    <pre class="whitespace-pre-wrap break-words"><%= details %></pre>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if Enum.any?(@queue) do %>
        <div class="mt-10">
          <h2 class="text-lg font-semibold text-gray-900">Execution Queue</h2>
          <p class="mt-1 text-sm text-gray-600">
            Recently approved actions that are queued/running (or failed).
          </p>

          <div class="mt-4 overflow-hidden rounded-lg bg-white shadow-sm border border-gray-200">
            <div class="divide-y divide-gray-200">
              <%= for item <- @queue do %>
                <div class="p-4 sm:p-6">
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <div class="flex items-center gap-2">
                        <span class={[
                          "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                          status_badge_class(item.execution_status)
                        ]}>
                          <%= String.upcase(item.execution_status || "unknown") %>
                        </span>
                        <span class="text-sm font-mono text-gray-700"><%= item.token %></span>
                      </div>

                      <div class="mt-2 text-sm text-gray-900">
                        <span class="font-medium"><%= item.tool_name %></span>
                        <%= if task = approval_task(item) do %>
                          <span class="text-gray-500">—</span>
                          <span class="text-gray-700"><%= task %></span>
                        <% end %>
                      </div>

                      <div class="mt-2 text-xs text-gray-500">
                        Approved <%= format_relative(item.approved_at) %>
                        <%= if item.executed_at do %>
                          • Executed <%= format_relative(item.executed_at) %>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <%= if item.execution_error do %>
                    <div class="mt-4 rounded-md bg-red-50 p-3 text-xs text-red-800 font-mono overflow-x-auto">
                      <pre class="whitespace-pre-wrap break-words"><%= item.execution_error %></pre>
                    </div>
                  <% else %>
                    <%= if details = execution_result_details(item) do %>
                      <div class="mt-4 rounded-md bg-gray-50 p-3 text-xs text-gray-700 font-mono overflow-x-auto">
                        <pre class="whitespace-pre-wrap break-words"><%= details %></pre>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%= if Enum.any?(@recent_executions) do %>
        <div class="mt-10">
          <h2 class="text-lg font-semibold text-gray-900">Recent Executions</h2>
          <p class="mt-1 text-sm text-gray-600">
            Recently executed approved actions (completed or failed).
          </p>

          <div class="mt-4 overflow-hidden rounded-lg bg-white shadow-sm border border-gray-200">
            <div class="divide-y divide-gray-200">
              <%= for item <- @recent_executions do %>
                <div class="p-4 sm:p-6">
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <div class="flex items-center gap-2">
                        <span class={[
                          "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                          status_badge_class(item.execution_status)
                        ]}>
                          <%= String.upcase(item.execution_status || "unknown") %>
                        </span>
                        <span class="text-sm font-mono text-gray-700"><%= item.token %></span>
                      </div>

                      <div class="mt-2 text-sm text-gray-900">
                        <span class="font-medium"><%= item.tool_name %></span>
                        <%= if task = approval_task(item) do %>
                          <span class="text-gray-500">—</span>
                          <span class="text-gray-700"><%= task %></span>
                        <% end %>
                      </div>

                      <div class="mt-2 text-xs text-gray-500">
                        Approved <%= format_relative(item.approved_at) %>
                        <%= if item.executed_at do %>
                          • Executed <%= format_relative(item.executed_at) %>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <%= if item.execution_error do %>
                    <div class="mt-4 rounded-md bg-red-50 p-3 text-xs text-red-800 font-mono overflow-x-auto">
                      <pre class="whitespace-pre-wrap break-words"><%= item.execution_error %></pre>
                    </div>
                  <% else %>
                    <%= if details = execution_result_details(item) do %>
                      <div class="mt-4 rounded-md bg-gray-50 p-3 text-xs text-gray-700 font-mono overflow-x-auto">
                        <pre class="whitespace-pre-wrap break-words"><%= details %></pre>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp approval_task(approval) do
    case approval.args do
      %{"skill" => skill, "input" => input}
      when approval.tool_name == "hal_skill_run" and is_binary(skill) and is_binary(input) ->
        truncate("#{skill}: #{input}", 120)

      %{:skill => skill, :input => input}
      when approval.tool_name == "hal_skill_run" and is_binary(skill) and is_binary(input) ->
        truncate("#{skill}: #{input}", 120)

      %{"task" => task} when is_binary(task) ->
        truncate(task, 120)

      %{:task => task} when is_binary(task) ->
        truncate(task, 120)

      _ ->
        nil
    end
  end

  defp approval_details(approval) do
    args = approval.args || %{}
    context = approval.context || %{}

    if map_size(args) == 0 and map_size(context) == 0 do
      nil
    else
      Jason.encode!(%{args: args, context: context}, pretty: true)
    end
  end

  defp execution_result_details(%{execution_result: result}) when is_map(result) and map_size(result) > 0 do
    safe_pretty_json(result, 8_000)
  end

  defp execution_result_details(_), do: nil

  defp safe_pretty_json(value, max_chars) when is_integer(max_chars) and max_chars > 0 do
    json =
      try do
        Jason.encode!(value, pretty: true)
      rescue
        _ -> inspect(value, limit: 200, printable_limit: 8_000)
      end

    json =
      if is_binary(json) and byte_size(json) > max_chars do
        String.slice(json, 0, max_chars) <> "…"
      else
        json
      end

    String.trim(json)
  end

  defp truncate(string, length) when is_binary(string) and byte_size(string) > length do
    String.slice(string, 0, length) <> "…"
  end

  defp truncate(string, _length), do: string

  defp format_relative(nil), do: "Never"

  defp format_relative(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp status_badge_class("queued"), do: "bg-blue-100 text-blue-800"
  defp status_badge_class("running"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-800"
  defp status_badge_class("completed"), do: "bg-green-100 text-green-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
