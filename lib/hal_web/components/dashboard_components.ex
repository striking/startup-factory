defmodule HalWeb.DashboardComponents do
  @moduledoc """
  Components specific to the HAL dashboard.

  Provides reusable components for:
  - Session cards
  - Chat messages
  - Statistics panels
  - Channel icons
  """

  use Phoenix.Component

  import HalWeb.CoreComponents, only: [icon: 1]

  # ============================================================================
  # Stats Panel
  # ============================================================================

  @doc """
  Renders a statistics panel with key metrics.

  ## Examples

      <.stats_panel stats={@stats} />
  """
  attr :stats, :map, required: true

  def stats_panel(assigns) do
    ~H"""
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
      <!-- Active Sessions -->
      <div class="overflow-hidden rounded-lg bg-white px-4 py-5 shadow-sm border border-gray-200 sm:p-6">
        <dt class="truncate text-sm font-medium text-gray-500">Active Sessions</dt>
        <dd class="mt-1 flex items-baseline justify-between md:block lg:flex">
          <div class="flex items-baseline text-2xl font-semibold text-red-600">
            <%= @stats.active_sessions %>
          </div>
          <div class="inline-flex items-baseline rounded-full bg-green-100 px-2.5 py-0.5 text-sm font-medium text-green-800 md:mt-2 lg:mt-0">
            <.icon name="hero-signal" class="h-4 w-4 mr-1" />
            Live
          </div>
        </dd>
      </div>

      <!-- Messages Today -->
      <div class="overflow-hidden rounded-lg bg-white px-4 py-5 shadow-sm border border-gray-200 sm:p-6">
        <dt class="truncate text-sm font-medium text-gray-500">Messages Today</dt>
        <dd class="mt-1 flex items-baseline justify-between md:block lg:flex">
          <div class="flex items-baseline text-2xl font-semibold text-red-600">
            <%= @stats.messages_today %>
          </div>
          <div class="inline-flex items-baseline rounded-full bg-blue-100 px-2.5 py-0.5 text-sm font-medium text-blue-800 md:mt-2 lg:mt-0">
            <.icon name="hero-chat-bubble-left-right" class="h-4 w-4 mr-1" />
            24h
          </div>
        </dd>
      </div>

      <!-- Channels Connected -->
      <div class="overflow-hidden rounded-lg bg-white px-4 py-5 shadow-sm border border-gray-200 sm:p-6">
        <dt class="truncate text-sm font-medium text-gray-500">Channels Connected</dt>
        <dd class="mt-1">
          <div class="flex items-center space-x-3">
            <%= for {channel, count} <- @stats.channels_connected do %>
              <div class="flex items-center space-x-1" title={"#{count} #{channel} sessions"}>
                <.channel_icon channel={channel} class="h-5 w-5" />
                <span class="text-sm font-medium text-gray-700"><%= count %></span>
              </div>
            <% end %>
            <%= if @stats.channels_connected == %{} do %>
              <span class="text-sm text-gray-400">No channels active</span>
            <% end %>
          </div>
        </dd>
      </div>

      <!-- Uptime -->
      <div class="overflow-hidden rounded-lg bg-white px-4 py-5 shadow-sm border border-gray-200 sm:p-6">
        <dt class="truncate text-sm font-medium text-gray-500">System Uptime</dt>
        <dd class="mt-1 flex items-baseline justify-between md:block lg:flex">
          <div class="flex items-baseline text-2xl font-semibold text-red-600">
            <%= @stats.uptime %>
          </div>
          <div class="inline-flex items-baseline rounded-full bg-green-100 px-2.5 py-0.5 text-sm font-medium text-green-800 md:mt-2 lg:mt-0">
            <.icon name="hero-clock" class="h-4 w-4 mr-1" />
            Up
          </div>
        </dd>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Session Card
  # ============================================================================

  @doc """
  Renders a session card with summary information.

  ## Examples

      <.session_card session={@session} on_click={JS.push("view_session", value: %{id: @session.id})} />
  """
  attr :session, :map, required: true
  attr :on_click, :any, default: nil

  def session_card(assigns) do
    ~H"""
    <div
      class="relative bg-white rounded-lg shadow-sm border border-gray-200 p-4 hover:shadow-md hover:border-gray-300 transition-all cursor-pointer"
      phx-click={@on_click}
      role="button"
      tabindex="0"
      aria-label={"View session for #{username(@session)}"}
    >
      <!-- Header -->
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center space-x-3">
          <.channel_icon channel={@session.channel_type} class="h-8 w-8" />
          <div>
            <h3 class="text-sm font-semibold text-gray-900 truncate max-w-[150px]">
              <%= username(@session) %>
            </h3>
            <p class="text-xs text-gray-500">
              <%= String.capitalize(@session.channel_type) %>
            </p>
          </div>
        </div>
        <span class={"inline-flex items-center rounded-full px-2 py-1 text-xs font-medium #{status_color(@session.status)}"}>
          <%= String.capitalize(@session.status) %>
        </span>
      </div>

      <!-- Details -->
      <div class="space-y-2">
        <div class="flex items-center text-xs text-gray-500">
          <.icon name="hero-chat-bubble-left-right" class="h-3.5 w-3.5 mr-1.5" />
          <span class="truncate" title={@session.channel_id}>
            <%= truncate(@session.channel_id, 25) %>
          </span>
        </div>
        <div class="flex items-center text-xs text-gray-500">
          <.icon name="hero-clock" class="h-3.5 w-3.5 mr-1.5" />
          <span><%= format_relative(@session.last_activity) %></span>
        </div>
      </div>

      <!-- Hover Indicator -->
      <div class="absolute inset-0 rounded-lg ring-2 ring-transparent hover:ring-red-500/20 transition-all pointer-events-none"></div>
    </div>
    """
  end

  defp username(session) do
    cond do
      session.user && session.user.username -> session.user.username
      session.user -> "User #{String.slice(session.user.id, 0..7)}"
      true -> "Unknown"
    end
  end

  defp status_color("active"), do: "bg-green-100 text-green-700"
  defp status_color("paused"), do: "bg-yellow-100 text-yellow-700"
  defp status_color("archived"), do: "bg-gray-100 text-gray-600"
  defp status_color(_), do: "bg-gray-100 text-gray-600"

  defp truncate(nil, _), do: ""
  defp truncate(string, length) when byte_size(string) <= length, do: string
  defp truncate(string, length), do: String.slice(string, 0, length) <> "..."

  defp format_relative(nil), do: "Never"

  defp format_relative(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  # ============================================================================
  # Chat Message
  # ============================================================================

  @doc """
  Renders a chat message bubble.

  ## Examples

      <.chat_message message={@message} />
  """
  attr :message, :map, required: true

  def chat_message(assigns) do
    ~H"""
    <div class={"flex #{if @message.role == "user", do: "justify-end", else: "justify-start"}"}>
      <div class={"max-w-[80%] rounded-lg px-4 py-2 #{message_style(@message.role)}"}>
        <!-- Role Label -->
        <div class="flex items-center space-x-2 mb-1">
          <span class={"text-xs font-medium #{role_label_color(@message.role)}"}>
            <%= role_label(@message.role) %>
          </span>
          <span class="text-xs text-gray-400">
            <%= format_time(@message.inserted_at) %>
          </span>
        </div>

        <!-- Content -->
        <div class={"text-sm #{content_color(@message.role)} whitespace-pre-wrap break-words"}>
          <%= @message.content %>
        </div>

        <!-- Attachments -->
        <%= if @message.attachments && length(@message.attachments) > 0 do %>
          <div class="mt-2 pt-2 border-t border-gray-200/50">
            <div class="flex flex-wrap gap-2">
              <%= for attachment <- @message.attachments do %>
                <.attachment_badge attachment={attachment} />
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Metadata (for assistant messages) -->
        <%= if @message.role == "assistant" && @message.metadata && map_size(@message.metadata) > 0 do %>
          <div class="mt-2 pt-2 border-t border-gray-200/30">
            <div class="flex flex-wrap gap-2 text-xs text-gray-400">
              <%= if @message.metadata["model"] do %>
                <span class="inline-flex items-center">
                  Model: <%= @message.metadata["model"] %>
                </span>
              <% end %>
              <%= if @message.metadata["tokens"] do %>
                <span class="inline-flex items-center">
                  <%= @message.metadata["tokens"] %> tokens
                </span>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp message_style("user"), do: "bg-red-600 text-white"
  defp message_style("assistant"), do: "bg-gray-100 text-gray-900"
  defp message_style("system"), do: "bg-blue-50 text-blue-900 border border-blue-200"
  defp message_style(_), do: "bg-gray-100 text-gray-900"

  defp role_label("user"), do: "You"
  defp role_label("assistant"), do: "HAL"
  defp role_label("system"), do: "System"
  defp role_label(role), do: String.capitalize(role)

  defp role_label_color("user"), do: "text-red-200"
  defp role_label_color("assistant"), do: "text-gray-500"
  defp role_label_color("system"), do: "text-blue-600"
  defp role_label_color(_), do: "text-gray-500"

  defp content_color("user"), do: "text-white"
  defp content_color(_), do: "text-gray-900"

  defp format_time(nil), do: ""

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  # ============================================================================
  # Attachment Badge
  # ============================================================================

  attr :attachment, :map, required: true

  defp attachment_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10">
      <%= attachment_icon(@attachment["type"] || "file") %>
      <%= @attachment["name"] || "attachment" %>
    </span>
    """
  end

  defp attachment_icon("image"), do: "photo"
  defp attachment_icon("audio"), do: "audio"
  defp attachment_icon("voice"), do: "audio"
  defp attachment_icon("video"), do: "video"
  defp attachment_icon("document"), do: "file"
  defp attachment_icon(_), do: "file"

  # ============================================================================
  # Channel Icon
  # ============================================================================

  @doc """
  Renders a channel-specific icon.

  ## Examples

      <.channel_icon channel="telegram" class="h-6 w-6" />
  """
  attr :channel, :string, required: true
  attr :class, :string, default: "h-6 w-6"

  def channel_icon(%{channel: "telegram"} = assigns) do
    ~H"""
    <div class={"#{@class} flex items-center justify-center rounded-full bg-blue-500 text-white"}>
      <svg class="h-3/5 w-3/5" viewBox="0 0 24 24" fill="currentColor">
        <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/>
      </svg>
    </div>
    """
  end

  def channel_icon(%{channel: "slack"} = assigns) do
    ~H"""
    <div class={"#{@class} flex items-center justify-center rounded-full bg-purple-600 text-white"}>
      <svg class="h-3/5 w-3/5" viewBox="0 0 24 24" fill="currentColor">
        <path d="M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zM6.313 15.165a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zM8.834 6.313a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zM18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zM17.688 8.834a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312zM15.165 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zM15.165 17.688a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z"/>
      </svg>
    </div>
    """
  end

  def channel_icon(%{channel: "discord"} = assigns) do
    ~H"""
    <div class={"#{@class} flex items-center justify-center rounded-full bg-indigo-600 text-white"}>
      <svg class="h-3/5 w-3/5" viewBox="0 0 24 24" fill="currentColor">
        <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z"/>
      </svg>
    </div>
    """
  end

  def channel_icon(assigns) do
    ~H"""
    <div class={"#{@class} flex items-center justify-center rounded-full bg-gray-500 text-white"}>
      <.icon name="hero-chat-bubble-left-right" class="h-3/5 w-3/5" />
    </div>
    """
  end

  # ============================================================================
  # Personality Panel
  # ============================================================================

  @doc """
  Renders a personality traits panel.

  ## Examples

      <.personality_panel personality={@personality} />
  """
  attr :personality, :map, default: nil

  def personality_panel(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <h3 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
        <.icon name="hero-user-circle" class="h-5 w-5 mr-2 text-red-500" />
        Personality Traits
      </h3>
      <%= if @personality do %>
        <div class="space-y-3">
          <.trait_bar label="Assertiveness" value={@personality.assertiveness} />
          <.trait_bar label="Warmth" value={@personality.warmth} />
          <.trait_bar label="Verbosity" value={@personality.verbosity} />
          <.trait_bar label="Proactivity" value={@personality.proactivity} />
          <.trait_bar label="Risk Tolerance" value={@personality.risk_tolerance} />
          <.trait_bar label="Humor" value={@personality.humor} />
          <.trait_bar label="Formality" value={@personality.formality} />
        </div>
        <div class="mt-4 pt-4 border-t border-gray-100">
          <p class="text-xs text-gray-500">
            Modifications remaining today:
            <span class="font-medium text-gray-700">
              <%= @personality.remaining_modifications || 3 %>
            </span>
          </p>
        </div>
      <% else %>
        <p class="text-sm text-gray-500">No personality configured</p>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :float, required: true

  defp trait_bar(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between text-sm mb-1">
        <span class="text-gray-600"><%= @label %></span>
        <span class="font-medium text-gray-900"><%= round(@value * 100) %>%</span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2">
        <div
          class="bg-red-500 h-2 rounded-full transition-all duration-300"
          style={"width: #{@value * 100}%"}
        ></div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Goals Panel
  # ============================================================================

  @doc """
  Renders active goals with progress bars.

  ## Examples

      <.goals_panel goals={@goals} />
  """
  attr :goals, :list, default: []

  def goals_panel(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <h3 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
        <.icon name="hero-flag" class="h-5 w-5 mr-2 text-red-500" />
        Active Goals
      </h3>
      <%= if Enum.empty?(@goals) do %>
        <p class="text-sm text-gray-500">No active goals</p>
      <% else %>
        <div class="space-y-4">
          <%= for goal <- @goals do %>
            <.goal_card goal={goal} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :goal, :map, required: true

  defp goal_card(assigns) do
    ~H"""
    <div class="border border-gray-100 rounded-lg p-3">
      <div class="flex items-start justify-between">
        <div class="flex-1 min-w-0">
          <h4 class="text-sm font-medium text-gray-900 truncate">
            <%= @goal.title %>
          </h4>
          <p class="text-xs text-gray-500 mt-0.5">
            <%= goal_type_label(@goal.type) %>
          </p>
        </div>
        <span class={"text-xs px-2 py-0.5 rounded-full #{goal_status_color(@goal.status)}"}>
          <%= String.capitalize(to_string(@goal.status)) %>
        </span>
      </div>
      <div class="mt-2">
        <div class="flex justify-between text-xs text-gray-500 mb-1">
          <span>Progress</span>
          <span><%= round(@goal.progress * 100) %>%</span>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-1.5">
          <div
            class={"h-1.5 rounded-full #{progress_color(@goal.progress)}"}
            style={"width: #{@goal.progress * 100}%"}
          ></div>
        </div>
      </div>
    </div>
    """
  end

  defp goal_type_label(:long_term), do: "Long-term"
  defp goal_type_label(:medium_term), do: "Medium-term"
  defp goal_type_label(:short_term), do: "Short-term"
  defp goal_type_label(_), do: "Goal"

  defp goal_status_color(:active), do: "bg-green-100 text-green-700"
  defp goal_status_color(:paused), do: "bg-yellow-100 text-yellow-700"
  defp goal_status_color(:completed), do: "bg-blue-100 text-blue-700"
  defp goal_status_color(_), do: "bg-gray-100 text-gray-600"

  defp progress_color(p) when p >= 0.75, do: "bg-green-500"
  defp progress_color(p) when p >= 0.5, do: "bg-yellow-500"
  defp progress_color(p) when p >= 0.25, do: "bg-orange-500"
  defp progress_color(_), do: "bg-red-500"

  # ============================================================================
  # Cost Panel
  # ============================================================================

  @doc """
  Renders cost tracking panel.

  ## Examples

      <.costs_panel budget={@budget} />
  """
  attr :budget, :map, default: nil

  def costs_panel(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <h3 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
        <.icon name="hero-currency-dollar" class="h-5 w-5 mr-2 text-red-500" />
        AI Spending
      </h3>
      <%= if @budget do %>
        <div class="space-y-4">
          <!-- Daily Budget -->
          <div>
            <div class="flex justify-between text-sm mb-1">
              <span class="text-gray-600">Daily Budget</span>
              <span class="font-medium text-gray-900">
                <%= format_cents(@budget.daily_remaining_cents) %> remaining
              </span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-2">
              <div
                class={"h-2 rounded-full #{budget_color(@budget.daily_used_percent)}"}
                style={"width: #{min(@budget.daily_used_percent, 100)}%"}
              ></div>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              <%= round(@budget.daily_used_percent) %>% used today
            </p>
          </div>

          <!-- Monthly Budget -->
          <div>
            <div class="flex justify-between text-sm mb-1">
              <span class="text-gray-600">Monthly Budget</span>
              <span class="font-medium text-gray-900">
                <%= format_cents(@budget.monthly_remaining_cents) %> remaining
              </span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-2">
              <div
                class={"h-2 rounded-full #{budget_color(@budget.monthly_used_percent)}"}
                style={"width: #{min(@budget.monthly_used_percent, 100)}%"}
              ></div>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              <%= round(@budget.monthly_used_percent) %>% used this month
            </p>
          </div>
        </div>
      <% else %>
        <p class="text-sm text-gray-500">No budget configured</p>
      <% end %>
    </div>
    """
  end

  defp format_cents(cents) when is_number(cents) do
    "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end

  defp format_cents(_), do: "$0.00"

  defp budget_color(pct) when pct >= 90, do: "bg-red-500"
  defp budget_color(pct) when pct >= 75, do: "bg-orange-500"
  defp budget_color(pct) when pct >= 50, do: "bg-yellow-500"
  defp budget_color(_), do: "bg-green-500"
end
