defmodule HalWeb.SessionDetailLive do
  @moduledoc """
  LiveView for displaying a single session's conversation history.

  Features:
  - Real-time message updates via PubSub
  - Chat-style message display
  - Session metadata and statistics
  """

  use HalWeb, :live_view

  alias Hal.Dashboard
  alias HalWeb.DashboardComponents

  @impl true
  def mount(%{"id" => session_id}, _session, socket) do
    session = Dashboard.get_session_with_user(session_id)

    if session do
      if connected?(socket) do
        # Subscribe to messages for this session
        Dashboard.subscribe_to_session(session_id)
      end

      messages = Dashboard.list_messages_for_session(session_id)
      message_count = Dashboard.count_messages_for_session(session_id)

      {:ok,
       socket
       |> assign(:page_title, session_title(session))
       |> assign(:active_tab, :sessions)
       |> assign(:session, session)
       |> assign(:messages, messages)
       |> assign(:message_count, message_count)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Session not found")
       |> push_navigate(to: ~p"/sessions")}
    end
  end

  defp session_title(session) do
    username = if session.user, do: session.user.username, else: "Unknown"
    "#{String.capitalize(session.channel_type)} - #{username}"
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    messages = socket.assigns.messages ++ [message]
    message_count = socket.assigns.message_count + 1

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:message_count, message_count)}
  end

  @impl true
  def handle_info({:session_updated, session}, socket) do
    {:noreply, assign(socket, :session, session)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:session] do
      Dashboard.unsubscribe_from_session(socket.assigns.session.id)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-0">
      <!-- Back Link -->
      <div class="mb-4">
        <.styled_link navigate={~p"/sessions"} class="inline-flex items-center text-sm font-medium text-gray-500 hover:text-gray-700">
          <.icon name="hero-arrow-left" class="mr-2 h-4 w-4" />
          Back to sessions
        </.styled_link>
      </div>

      <!-- Session Header -->
      <div class="mb-6 bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <div class="flex items-start justify-between">
          <div class="flex items-center space-x-4">
            <DashboardComponents.channel_icon channel={@session.channel_type} class="h-12 w-12" />
            <div>
              <h1 class="text-xl font-bold text-gray-900">
                <%= if @session.user do %>
                  <%= @session.user.username || "User" %>
                <% else %>
                  Unknown User
                <% end %>
              </h1>
              <p class="text-sm text-gray-500">
                <%= String.capitalize(@session.channel_type) %> &middot; <%= @session.channel_id %>
              </p>
            </div>
          </div>
          <div class="flex items-center space-x-2">
            <span class={"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{status_color(@session.status)}"}>
              <%= String.capitalize(@session.status) %>
            </span>
          </div>
        </div>

        <!-- Session Stats -->
        <div class="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div class="text-center">
            <p class="text-2xl font-bold text-gray-900"><%= @message_count %></p>
            <p class="text-sm text-gray-500">Messages</p>
          </div>
          <div class="text-center">
            <p class="text-2xl font-bold text-gray-900"><%= format_date(@session.inserted_at) %></p>
            <p class="text-sm text-gray-500">Created</p>
          </div>
          <div class="text-center">
            <p class="text-2xl font-bold text-gray-900"><%= format_relative(@session.last_activity) %></p>
            <p class="text-sm text-gray-500">Last Activity</p>
          </div>
          <div class="text-center">
            <p class="text-2xl font-bold text-gray-900 truncate" title={@session.claude_session_id || "N/A"}>
              <%= truncate(@session.claude_session_id || "N/A", 12) %>
            </p>
            <p class="text-sm text-gray-500">Claude Session</p>
          </div>
        </div>
      </div>

      <!-- Conversation -->
      <div class="bg-white rounded-lg shadow-sm border border-gray-200">
        <div class="border-b border-gray-200 px-6 py-4">
          <h2 class="text-lg font-semibold text-gray-900">Conversation</h2>
        </div>

        <%= if Enum.empty?(@messages) do %>
          <div class="p-12 text-center">
            <.icon name="hero-chat-bubble-left-right" class="mx-auto h-12 w-12 text-gray-400" />
            <h3 class="mt-4 text-sm font-semibold text-gray-900">No messages yet</h3>
            <p class="mt-2 text-sm text-gray-500">
              Messages will appear here as the conversation progresses.
            </p>
          </div>
        <% else %>
          <div class="p-4 space-y-4 max-h-[600px] overflow-y-auto" id="messages-container" phx-hook="ScrollToBottom">
            <%= for message <- @messages do %>
              <DashboardComponents.chat_message message={message} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_color("active"), do: "bg-green-100 text-green-800"
  defp status_color("paused"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("archived"), do: "bg-gray-100 text-gray-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_date(nil), do: "N/A"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_relative(nil), do: "Never"

  defp format_relative(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp truncate(nil, _), do: "N/A"
  defp truncate(string, length) when byte_size(string) <= length, do: string
  defp truncate(string, length), do: String.slice(string, 0, length) <> "..."
end
