defmodule HalWeb.ChangeRequestsLive do
  @moduledoc """
  LiveView for reviewing codops ChangeRequests.

  ChangeRequests are generated in an isolated worktree and can be applied only
  after explicit human approval.
  """

  use HalWeb, :live_view

  alias HAL.SelfImprovement.ChangeRequests

  @refresh_ms 2_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_ms, self(), :refresh)
    end

    change_requests = ChangeRequests.list_recent(limit: 50)

    {:ok,
     socket
     |> assign(:page_title, "Changes")
     |> assign(:active_tab, :changes)
     |> assign(:change_requests, change_requests)
     |> assign(:selected_id, List.first(change_requests) && List.first(change_requests).id)
     |> assign(:selected, List.first(change_requests))}
  end

  @impl true
  def handle_info(:refresh, socket) do
    change_requests = ChangeRequests.list_recent(limit: 50)
    selected_id = socket.assigns.selected_id

    selected =
      if selected_id, do: ChangeRequests.get(selected_id), else: List.first(change_requests)

    {:noreply,
     socket
     |> assign(:change_requests, change_requests)
     |> assign(:selected, selected)}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_id, id)
     |> assign(:selected, ChangeRequests.get(id))}
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
        <.link navigate={~p"/approvals"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Approvals
        </.link>
        <.link navigate={~p"/changes"} class="pb-2 px-1 border-b-2 border-red-500 text-sm font-medium text-red-600">
          Changes
        </.link>
        <.link navigate={~p"/security"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Security
        </.link>
      </div>

      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Changes</h1>
        <p class="mt-1 text-sm text-gray-600">
          Review codops ChangeRequests (diff + tests) and apply via the Approvals flow.
        </p>
      </div>

      <div class="grid gap-6 lg:grid-cols-12">
        <div class="lg:col-span-4">
          <div class="rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-gray-900">Recent</h2>
              <span class="text-xs text-gray-500"><%= length(@change_requests) %></span>
            </div>

            <%= if Enum.empty?(@change_requests) do %>
              <div class="p-4 text-sm text-gray-600">No change requests yet.</div>
            <% else %>
              <div class="divide-y divide-gray-100">
                <%= for req <- @change_requests do %>
                  <button
                    phx-click="select"
                    phx-value-id={req.id}
                    class={[
                      "w-full text-left px-4 py-3 hover:bg-gray-50 transition-colors",
                      if(@selected_id == req.id, do: "bg-red-50", else: "bg-white")
                    ]}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div class="min-w-0">
                        <div class="text-sm font-medium text-gray-900 truncate"><%= req.title %></div>
                        <div class="mt-0.5 text-xs text-gray-500 truncate"><%= req.id %></div>
                      </div>
                      <span class={[
                        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                        status_badge_class(req.status)
                      ]}>
                        <%= String.upcase(req.status || "unknown") %>
                      </span>
                    </div>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <div class="lg:col-span-8">
          <%= if @selected do %>
            <div class="rounded-lg bg-white border border-gray-200 shadow-sm overflow-hidden">
              <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
                <div>
                  <div class="text-sm font-semibold text-gray-900"><%= @selected.title %></div>
                  <div class="mt-0.5 text-xs text-gray-500 font-mono"><%= @selected.id %></div>
                </div>
                <span class={[
                  "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                  status_badge_class(@selected.status)
                ]}>
                  <%= String.upcase(@selected.status || "unknown") %>
                </span>
              </div>

              <div class="p-4 space-y-4">
                <div class="text-sm text-gray-700 whitespace-pre-wrap"><%= @selected.request %></div>

                <div class="grid gap-4 sm:grid-cols-2">
                  <div class="rounded-md bg-gray-50 p-3 text-xs text-gray-700">
                    <div class="font-semibold text-gray-900 mb-1">Tests</div>
                    <div>Command: <span class="font-mono"><%= @selected.test_command || "mix test" %></span></div>
                    <div>
                      Exit: <span class="font-mono"><%= if is_nil(@selected.test_exit_code), do: "—", else: @selected.test_exit_code %></span>
                    </div>
                  </div>

                  <div class="rounded-md bg-gray-50 p-3 text-xs text-gray-700">
                    <div class="font-semibold text-gray-900 mb-1">Approval</div>
                    <%= if @selected.approval_token do %>
                      <div>Token: <span class="font-mono"><%= @selected.approval_token %></span></div>
                      <div class="mt-2">
                        <.link navigate={~p"/approvals"} class="text-red-700 hover:text-red-900 underline">
                          Go to approvals →
                        </.link>
                      </div>
                    <% else %>
                      <div class="text-gray-600">No apply approval requested yet.</div>
                    <% end %>
                  </div>
                </div>

                <%= if is_list(@selected.changed_files) and length(@selected.changed_files) > 0 do %>
                  <div class="rounded-md bg-gray-50 p-3 text-xs text-gray-700">
                    <div class="font-semibold text-gray-900 mb-1">Files Changed</div>
                    <div class="font-mono whitespace-pre-wrap"><%= Enum.join(@selected.changed_files, "\n") %></div>
                  </div>
                <% end %>

                <%= if @selected.error_message do %>
                  <div class="rounded-md bg-red-50 p-3 text-xs text-red-800">
                    <div class="font-semibold mb-1">Error</div>
                    <div class="font-mono whitespace-pre-wrap break-words"><%= @selected.error_message %></div>
                  </div>
                <% end %>

                <%= if @selected.test_output do %>
                  <div class="rounded-md bg-gray-50 p-3 text-xs text-gray-700">
                    <div class="font-semibold text-gray-900 mb-1">Test Output</div>
                    <pre class="font-mono whitespace-pre-wrap break-words max-h-64 overflow-y-auto"><%= @selected.test_output %></pre>
                  </div>
                <% end %>

                <%= if @selected.diff do %>
                  <div class="rounded-md bg-gray-50 p-3 text-xs text-gray-700">
                    <div class="font-semibold text-gray-900 mb-1">Diff</div>
                    <pre class="font-mono whitespace-pre-wrap break-words max-h-[32rem] overflow-y-auto"><%= @selected.diff %></pre>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="text-sm text-gray-600">Select a change request to view details.</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge_class("pending"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("generating"), do: "bg-blue-100 text-blue-800"
  defp status_badge_class("ready"), do: "bg-green-100 text-green-800"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-800"
  defp status_badge_class("applied"), do: "bg-purple-100 text-purple-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
