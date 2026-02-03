defmodule HalWeb.ChatLive do
  use HalWeb, :live_view
  require Logger

  alias Hal.Gateway.SessionManager
  alias Hal.Gateway.SessionServer
  alias Hal.Commands
  alias Hal.Knowledge
  alias HAL.Autonomy.Approvals
  alias HAL.Memory
  alias HalWeb.Helpers.Markdown
  alias HalWeb.Components.Catalog
  import HalWeb.HalComponents

  @refresh_ms 2_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_ms, self(), :refresh)
    end

    # Create a web chat session
    user_id = get_or_create_web_user()
    session_id = "web-chat-#{user_id}"

    # Get or create session
    {:ok, session_pid} = get_or_create_session(user_id, session_id)

    # Load message history
    messages = load_message_history(session_pid)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:session_id, session_id)
      |> assign(:session_pid, session_pid)
      |> assign(:messages, messages)
      |> assign(:message_input, "")
      |> assign(:loading, false)
      |> assign(:thinking_message, nil)
      |> assign(:show_memory_panel, false)
      |> assign(:last_memory_context, [])
      |> assign(:pending_approvals_count, count_pending_approvals())

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    Logger.info("=== CHAT: Received send_message event with: #{inspect(message)}")

    if String.trim(message) != "" do
      # Add user message to UI immediately
      user_message = %{
        role: "user",
        content: message,
        timestamp: DateTime.utc_now()
      }

      socket = assign(socket, :messages, socket.assigns.messages ++ [user_message])
      socket = assign(socket, :message_input, "")
      socket = assign(socket, :loading, true)

      # Send to HAL in background
      send(self(), {:process_message, message})

      {:noreply, socket}
    else
      Logger.info("=== CHAT: Empty message, ignoring")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    Logger.debug("=== CHAT: Input updated to: #{inspect(message)}")
    {:noreply, assign(socket, :message_input, message)}
  end

  @impl true
  def handle_event("hal_action", %{"action" => action}, socket) do
    Logger.info("HAL action triggered: #{action}")
    # Handle action button clicks - send as a new message to HAL
    send(self(), {:process_message, "[User clicked: #{action}]"})
    {:noreply, assign(socket, :loading, true)}
  end

  @impl true
  def handle_event("toggle_memory_panel", _params, socket) do
    {:noreply, assign(socket, :show_memory_panel, !socket.assigns.show_memory_panel)}
  end

  @impl true
  def handle_info({:process_message, message}, socket) do
    user_id = socket.assigns.user_id

    # First, check if this is a command (habit, task, knowledge action)
    case Commands.maybe_execute(user_id, message) do
      {:executed, response} ->
        # Command was handled - show the response directly
        assistant_message = %{
          role: "assistant",
          content: response,
          components: [],
          memory_context: [],
          timestamp: DateTime.utc_now()
        }

        socket = assign(socket, :messages, socket.assigns.messages ++ [assistant_message])
        socket = assign(socket, :loading, false)
        socket = assign(socket, :thinking_message, nil)

        {:noreply, socket}

      {:not_command, _message} ->
        # Not a command - route to AI as usual
        process_ai_message(message, socket)
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :pending_approvals_count, count_pending_approvals())}
  end

  # Process message through AI when it's not a direct command
  defp process_ai_message(message, socket) do
    user_id = socket.assigns.user_id

    # Recall relevant memories for this message
    memory_context = recall_memories(message)

    # Get knowledge base context (user's documents)
    knowledge_context = get_knowledge_context(user_id, message)

    # Build enhanced message with knowledge context
    enhanced_message = build_enhanced_message(message, knowledge_context)

    # Send message to HAL's AI provider (uses Claude OAuth token)
    case SessionServer.handle_message(socket.assigns.session_pid, enhanced_message, []) do
      {:ok, response} ->
        # Parse response for embedded components (A2UI-style)
        {clean_content, components} = Catalog.parse_response(response)

        # Add HAL's response to messages with parsed components and memory context
        assistant_message = %{
          role: "assistant",
          content: clean_content,
          components: components,
          memory_context: memory_context,
          timestamp: DateTime.utc_now()
        }

        socket = assign(socket, :messages, socket.assigns.messages ++ [assistant_message])
        socket = assign(socket, :loading, false)
        socket = assign(socket, :thinking_message, nil)
        socket = assign(socket, :last_memory_context, memory_context)

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("AI request failed: #{inspect(reason)}")

        error_message = %{
          role: "assistant",
          content: """
          Sorry, I encountered an error: #{inspect(reason)}

          To fix this, make sure you're authenticated with Claude Code:

          1. Run: claude auth login
          2. Follow the authentication flow
          3. Restart HAL server

          HAL uses your Claude Code subscription (no API key needed!).
          """,
          components: [],
          timestamp: DateTime.utc_now()
        }

        socket = assign(socket, :messages, socket.assigns.messages ++ [error_message])
        socket = assign(socket, :loading, false)
        socket = assign(socket, :thinking_message, nil)

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-4">
            <.link navigate={~p"/"} class="text-gray-600 hover:text-gray-900">
              ← Back
            </.link>
            <h1 class="text-2xl font-bold text-gray-900">Chat with HAL</h1>
          </div>
          <div class="flex items-center space-x-4">
            <button
              phx-click="toggle_memory_panel"
              class={[
                "flex items-center space-x-2 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors",
                if(@show_memory_panel,
                  do: "bg-purple-100 text-purple-700",
                  else: "bg-gray-100 text-gray-600 hover:bg-gray-200"
                )
              ]}
            >
              <span>🧠</span>
              <span>Memory</span>
              <%= if length(@last_memory_context) > 0 do %>
                <span class="bg-purple-500 text-white text-xs px-1.5 py-0.5 rounded-full">
                  <%= length(@last_memory_context) %>
                </span>
              <% end %>
            </button>

            <.link
              navigate={~p"/approvals"}
              class="flex items-center space-x-2 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors bg-gray-100 text-gray-600 hover:bg-gray-200"
            >
              <span>✅</span>
              <span>Approvals</span>
              <%= if @pending_approvals_count > 0 do %>
                <span class="bg-red-600 text-white text-xs px-1.5 py-0.5 rounded-full">
                  <%= @pending_approvals_count %>
                </span>
              <% end %>
            </.link>
            <div class="flex items-center space-x-2">
              <div class="h-2 w-2 rounded-full bg-green-500"></div>
              <span class="text-sm text-gray-600">Connected</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Memory Context Panel (collapsible) -->
      <%= if @show_memory_panel do %>
        <div class="bg-purple-50 border-b border-purple-200 px-6 py-4">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-semibold text-purple-900 flex items-center space-x-2">
              <span>🧠</span>
              <span>Memory Context</span>
            </h3>
            <span class="text-xs text-purple-600">
              Showing memories recalled for last message
            </span>
          </div>
          <%= if Enum.empty?(@last_memory_context) do %>
            <p class="text-sm text-purple-600 italic">No relevant memories found</p>
          <% else %>
            <div class="space-y-2 max-h-48 overflow-y-auto">
              <%= for memory <- @last_memory_context do %>
                <div class="bg-white rounded-lg p-3 border border-purple-200 shadow-sm">
                  <div class="flex items-start justify-between">
                    <p class="text-sm text-gray-800 flex-1"><%= memory.content %></p>
                    <span class={[
                      "ml-2 text-xs font-mono px-2 py-0.5 rounded",
                      similarity_color(memory.similarity)
                    ]}>
                      <%= memory.similarity %>
                    </span>
                  </div>
                  <div class="flex items-center space-x-3 mt-2 text-xs text-gray-500">
                    <span class="flex items-center space-x-1">
                      <span><%= source_icon(memory.source) %></span>
                      <span><%= memory.source %></span>
                    </span>
                    <%= if memory.inserted_at do %>
                      <span><%= format_memory_date(memory.inserted_at) %></span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Messages Area -->
      <div
        id="messages-container"
        class="flex-1 overflow-y-auto px-6 py-4 space-y-4"
      >
        <%= if Enum.empty?(@messages) do %>
          <div class="flex items-center justify-center h-full">
            <div class="text-center">
              <div class="text-6xl mb-4">🤖</div>
              <h2 class="text-xl font-semibold text-gray-900 mb-2">Start a conversation</h2>
              <p class="text-gray-600">Ask HAL anything!</p>
            </div>
          </div>
        <% else %>
          <%= for message <- @messages do %>
            <div class={[
              "flex",
              if(message.role == "user", do: "justify-end", else: "justify-start")
            ]}>
              <div class={[
                "max-w-3xl rounded-lg px-4 py-3",
                if(message.role == "user",
                  do: "bg-blue-600 text-white",
                  else: "bg-white border border-gray-200 text-gray-900"
                )
              ]}>
                <div class="flex items-start space-x-2">
                  <div class="flex-shrink-0 text-2xl">
                    <%= if message.role == "user", do: "👤", else: "🤖" %>
                  </div>
                  <div class="flex-1">
                    <p class="text-sm font-medium mb-1">
                      <%= if message.role == "user", do: "You", else: "HAL" %>
                    </p>
                    <div class={[
                      "prose prose-sm max-w-none",
                      if(message.role == "user",
                        do: "prose-invert prose-p:text-white prose-headings:text-white prose-strong:text-white prose-code:text-blue-200 prose-li:text-white",
                        else: "prose-gray"
                      )
                    ]}>
                      <%!-- Render tool calls first (for HAL messages) --%>
                      <%= if message.role == "assistant" do %>
                        <%= for comp <- Map.get(message, :components, []) do %>
                          <%= render_component(comp) %>
                        <% end %>
                      <% end %>
                      <%!-- Main content --%>
                      <%= Markdown.render(message.content) %>
                    </div>
                    <div class="flex items-center justify-between mt-2">
                      <p class={[
                        "text-xs",
                        if(message.role == "user", do: "text-blue-200", else: "text-gray-500")
                      ]}>
                        <%= format_time(message.timestamp) %>
                      </p>
                      <%= if message.role == "assistant" and length(Map.get(message, :memory_context, [])) > 0 do %>
                        <span class="text-xs bg-purple-100 text-purple-700 px-2 py-0.5 rounded-full flex items-center space-x-1">
                          <span>🧠</span>
                          <span><%= length(message.memory_context) %> memories</span>
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @loading do %>
            <div class="flex justify-start">
              <div class="max-w-3xl rounded-lg px-4 py-3 bg-white border border-gray-200">
                <div class="flex items-center space-x-2">
                  <div class="text-2xl">🤖</div>
                  <.thinking message={@thinking_message || "Thinking..."} />
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- Input Area -->
      <div class="bg-white border-t border-gray-200 px-6 py-4">
        <form phx-submit="send_message" phx-change="update_input" class="flex space-x-4">
          <input
            type="text"
            name="message"
            value={@message_input}
            placeholder="Type a message..."
            class="flex-1 rounded-lg border border-gray-300 px-4 py-3 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={@loading}
            autocomplete="off"
          />
          <button
            type="submit"
            disabled={@loading}
            class="px-6 py-3 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            <%= if @loading do %>
              <div class="flex items-center space-x-2">
                <div class="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin">
                </div>
                <span>Sending...</span>
              </div>
            <% else %>
              Send
            <% end %>
          </button>
        </form>
        <p class="text-xs text-gray-500 mt-2">
          Press Enter to send • HAL can make mistakes. Consider checking important information.
        </p>
      </div>
    </div>
    """
  end

  # Private Functions

  defp get_or_create_web_user do
    # For now, use a single web user UUID
    # Use "terminal" platform for web chat (valid platform value)
    # In production, would use actual authentication
    case Hal.Repo.get_by(Hal.Accounts.User, external_id: "web-chat-user", platform: "terminal") do
      nil ->
        # Create web user
        {:ok, user} =
          %Hal.Accounts.User{}
          |> Hal.Accounts.User.changeset(%{
            external_id: "web-chat-user",
            platform: "terminal",
            username: "Web User",
            role: "owner"
          })
          |> Hal.Repo.insert()

        user.id

      user ->
        user.id
    end
  end

  defp get_or_create_session(user_id, session_id) do
    case SessionManager.get_or_create_session(
           Hal.Gateway.SessionManager,
           "terminal",
           session_id,
           user_id
         ) do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end

  defp load_message_history(session_pid) do
    # Load message history from the SessionServer
    Logger.info("Loading message history from session: #{inspect(session_pid)}")

    try do
      case SessionServer.get_state(session_pid) do
        %{messages: messages} = state when is_list(messages) ->
          Logger.info("Loaded #{length(messages)} messages from session #{state.session_id}")

          # Convert to the format expected by the UI
          Enum.map(messages, fn msg ->
            %{
              role: msg.role,
              content: msg.content,
              timestamp: msg[:inserted_at] || DateTime.utc_now()
            }
          end)

        other ->
          Logger.warning("Unexpected state format: #{inspect(other)}")
          []
      end
    rescue
      e ->
        Logger.error("Failed to load message history: #{inspect(e)}")
        []
    end
  end

  defp format_time(timestamp) do
    Calendar.strftime(timestamp, "%I:%M %p")
  end

  defp recall_memories(query) do
    case Memory.recall(query, limit: 5, threshold: 0.5) do
      {:ok, results} ->
        Enum.map(results, fn %{memory: memory, similarity: similarity} ->
          %{
            content: memory.content,
            source: memory.source,
            similarity: Float.round(similarity, 2),
            inserted_at: memory.inserted_at
          }
        end)

      {:error, reason} ->
        Logger.warning("Memory recall failed: #{inspect(reason)}")
        []
    end
  end

  defp similarity_color(similarity) when similarity >= 0.8, do: "bg-green-100 text-green-800"
  defp similarity_color(similarity) when similarity >= 0.6, do: "bg-yellow-100 text-yellow-800"
  defp similarity_color(_), do: "bg-gray-100 text-gray-600"

  defp source_icon("user_input"), do: "👤"
  defp source_icon("agent_output"), do: "🤖"
  defp source_icon("observation"), do: "👁"
  defp source_icon("system"), do: "⚙️"
  defp source_icon("document"), do: "📄"
  defp source_icon(_), do: "💾"

  defp format_memory_date(datetime) do
    now = DateTime.utc_now()
    diff_days = Date.diff(DateTime.to_date(now), DateTime.to_date(datetime))

    cond do
      diff_days == 0 -> "today"
      diff_days == 1 -> "yesterday"
      diff_days < 7 -> "#{diff_days} days ago"
      diff_days < 30 -> "#{div(diff_days, 7)} weeks ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  # Render a component from the catalog
  defp render_component(%{type: :tool_call, props: props}) do
    assigns = Map.put(props, :__changed__, nil)
    ~H"<.tool_call {assigns} />"
  end

  defp render_component(%{type: :card, props: props}) do
    assigns = Map.put(props, :__changed__, nil)
    ~H"<.card title={@title} variant={@variant}><%= @body %></.card>"
  end

  defp render_component(%{type: :action_button, props: props}) do
    assigns = Map.put(props, :__changed__, nil)
    ~H"<.action_button {assigns} />"
  end

  defp render_component(%{type: :progress, props: props}) do
    assigns = Map.put(props, :__changed__, nil)
    ~H"<.progress {assigns} />"
  end

  defp render_component(_), do: nil

  # Knowledge Base Integration

  defp get_knowledge_context(user_id, query) do
    case Knowledge.search(user_id, query, limit: 3, threshold: 0.6) do
      {:ok, [_ | _] = results} ->
        results

      _ ->
        []
    end
  end

  defp build_enhanced_message(message, []) do
    # No knowledge context, return original message
    message
  end

  defp build_enhanced_message(message, knowledge_results) do
    # Format knowledge results with citations
    formatted_context =
      knowledge_results
      |> Enum.with_index(1)
      |> Enum.map(fn {result, idx} ->
        source = result.source.title
        snippet = String.slice(result.content, 0, 500)
        "[#{idx}] From \"#{source}\":\n#{snippet}"
      end)
      |> Enum.join("\n\n")

    """
    [Relevant documents from your knowledge base - cite sources when using this information]
    #{formatted_context}

    [User's message]
    #{message}
    """
  end

  defp count_pending_approvals do
    Approvals.list_pending(limit: 50) |> length()
  end
end
