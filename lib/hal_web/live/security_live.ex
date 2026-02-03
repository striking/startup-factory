defmodule HalWeb.SecurityLive do
  @moduledoc """
  LiveView for managing inbound trust gating.

  Supports OpenClaw-style DM pairing:
  - New DM users receive a pairing code
  - Operator approves/denies in this UI
  - Approved users are marked as paired (`users.paired_at`)
  """

  use HalWeb, :live_view

  alias Hal.Security

  @refresh_ms 2_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_ms, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "Security")
     |> assign(:active_tab, :security)
     |> assign(:dm_policy, Security.dm_policy())
     |> assign(:group_policy, Security.group_policy())
     |> assign(:dm_allowlist, Security.dm_allowlist())
     |> assign(:group_allowlist, Security.group_allowlist())
     |> assign(:pairings, Security.list_pending_pairings(limit: 50))}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :pairings, Security.list_pending_pairings(limit: 50))}
  end

  @impl true
  def handle_event("approve_pairing", %{"code" => code}, socket) do
    case Security.approve_pairing(code) do
      {:ok, _req} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved pairing #{code}")
         |> assign(:pairings, Security.list_pending_pairings(limit: 50))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Pairing request not found")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "Pairing request is not pending")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to approve pairing: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("approve_pairing_owner", %{"code" => code}, socket) do
    case Security.approve_pairing(code, role: "owner") do
      {:ok, _req} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved pairing #{code} (owner)")
         |> assign(:pairings, Security.list_pending_pairings(limit: 50))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Pairing request not found")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "Pairing request is not pending")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to approve pairing: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("deny_pairing", %{"code" => code}, socket) do
    case Security.deny_pairing(code, "Denied in UI") do
      {:ok, _req} ->
        {:noreply,
         socket
         |> put_flash(:info, "Denied pairing #{code}")
         |> assign(:pairings, Security.list_pending_pairings(limit: 50))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Pairing request not found")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "Pairing request is not pending")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to deny pairing: #{inspect(reason)}")}
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
        <.link navigate={~p"/approvals"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Approvals
        </.link>
        <.link navigate={~p"/changes"} class="pb-2 px-1 border-b-2 border-transparent text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300">
          Changes
        </.link>
        <.link navigate={~p"/security"} class="pb-2 px-1 border-b-2 border-red-500 text-sm font-medium text-red-600">
          Security
        </.link>
      </div>

      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Security</h1>
        <p class="mt-1 text-sm text-gray-600">
          Inbound trust gating and pairing approvals.
        </p>
      </div>

      <div class="grid gap-6 md:grid-cols-2">
        <div class="rounded-lg bg-white border border-gray-200 shadow-sm p-5">
          <h2 class="text-sm font-semibold text-gray-900">Inbound Policy</h2>

          <dl class="mt-3 space-y-2 text-sm text-gray-700">
            <div class="flex items-center justify-between">
              <dt class="text-gray-500">DM policy</dt>
              <dd class="font-mono"><%= @dm_policy %></dd>
            </div>
            <div class="flex items-center justify-between">
              <dt class="text-gray-500">Group policy</dt>
              <dd class="font-mono"><%= @group_policy %></dd>
            </div>
          </dl>

          <div class="mt-4 text-xs text-gray-500">
            Configure with env vars:
            <span class="font-mono">HAL_DM_POLICY</span>,
            <span class="font-mono">HAL_GROUP_POLICY</span>,
            <span class="font-mono">HAL_DM_ALLOWLIST</span>,
            <span class="font-mono">HAL_GROUP_ALLOWLIST</span>.
          </div>
        </div>

        <div class="rounded-lg bg-white border border-gray-200 shadow-sm p-5">
          <h2 class="text-sm font-semibold text-gray-900">Allowlists</h2>

          <div class="mt-3 space-y-3 text-sm">
            <div>
              <div class="text-gray-500">DM allowlist</div>
              <%= if MapSet.size(@dm_allowlist) == 0 do %>
                <div class="mt-1 text-gray-700">None</div>
              <% else %>
                <ul class="mt-1 font-mono text-xs text-gray-700 space-y-1">
                  <%= for {platform, external_id} <- Enum.sort(MapSet.to_list(@dm_allowlist)) do %>
                    <li><%= platform %>:<%= external_id %></li>
                  <% end %>
                </ul>
              <% end %>
            </div>

            <div>
              <div class="text-gray-500">Group allowlist</div>
              <%= if MapSet.size(@group_allowlist) == 0 do %>
                <div class="mt-1 text-gray-700">None</div>
              <% else %>
                <ul class="mt-1 font-mono text-xs text-gray-700 space-y-1">
                  <%= for {channel_type, channel_id} <- Enum.sort(MapSet.to_list(@group_allowlist)) do %>
                    <li><%= channel_type %>:<%= channel_id %></li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="mt-10">
        <h2 class="text-lg font-semibold text-gray-900">Pending Pairings</h2>
        <p class="mt-1 text-sm text-gray-600">
          Approve a pairing request to allow that user to start a DM session.
        </p>

        <%= if Enum.empty?(@pairings) do %>
          <div class="mt-4 text-center py-12 bg-white rounded-lg border border-gray-200">
            <.icon name="hero-lock-open" class="mx-auto h-12 w-12 text-green-500" />
            <h3 class="mt-2 text-sm font-semibold text-gray-900">No pending pairing requests</h3>
            <p class="mt-1 text-sm text-gray-500">
              You're all clear.
            </p>
          </div>
        <% else %>
          <div class="mt-4 overflow-hidden rounded-lg bg-white shadow-sm border border-gray-200">
            <div class="divide-y divide-gray-200">
              <%= for req <- @pairings do %>
                <div class="p-4 sm:p-6">
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <div class="flex items-center gap-2">
                        <span class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800">
                          Pending
                        </span>
                        <span class="text-sm font-mono text-gray-700"><%= req.code %></span>
                      </div>

                      <div class="mt-2 text-sm text-gray-900">
                        <span class="font-medium"><%= req.user.username || "Unknown user" %></span>
                        <span class="text-gray-500">•</span>
                        <span class="font-mono text-gray-700"><%= req.user.platform %>:<%= req.user.external_id %></span>
                      </div>

                      <div class="mt-2 text-xs text-gray-500">
                        Requested <%= format_relative(req.inserted_at) %>
                      </div>
                    </div>

                    <div class="flex shrink-0 items-center gap-2">
                      <button
                        phx-click="deny_pairing"
                        phx-value-code={req.code}
                        class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                      >
                        Deny
                      </button>
                      <button
                        phx-click="approve_pairing"
                        phx-value-code={req.code}
                        class="inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500"
                      >
                        Approve
                      </button>
                      <button
                        phx-click="approve_pairing_owner"
                        phx-value-code={req.code}
                        class="inline-flex items-center rounded-md bg-blue-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-500"
                        title="Approve and promote this user to owner (full tool access)"
                      >
                        Approve + Owner
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_relative(nil), do: "unknown"

  defp format_relative(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end
end
