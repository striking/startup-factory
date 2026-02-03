defmodule HalWeb.HalComponents do
  @moduledoc """
  A2UI-inspired components for HAL's chat interface.

  These components provide rich visualization of HAL's actions:
  - Tool calls (what HAL is doing)
  - Cards (structured information)
  - Action buttons (user interactions)
  - Progress indicators (long-running operations)

  ## Philosophy

  Inspired by Google's A2UI spec - declarative, safe components that
  HAL can request to render. The component catalog ensures HAL can
  only render pre-approved UI elements.
  """

  use Phoenix.Component

  # ============================================
  # Tool Call Component
  # ============================================

  @doc """
  Renders a tool call visualization.

  Shows what tool HAL is calling, its parameters, and status.

  ## Examples

      <.tool_call
        name="search_calendar"
        status={:running}
        params={%{query: "meetings tomorrow"}}
      />

      <.tool_call
        name="read_file"
        status={:complete}
        duration_ms={1200}
        result="Found 3 events"
      />
  """
  attr :name, :string, required: true, doc: "Tool name"
  attr :status, :atom, default: :pending, values: [:pending, :running, :complete, :error]
  attr :params, :map, default: %{}, doc: "Tool parameters"
  attr :result, :string, default: nil, doc: "Result summary"
  attr :error, :string, default: nil, doc: "Error message if failed"
  attr :duration_ms, :integer, default: nil, doc: "Execution time in milliseconds"
  attr :collapsible, :boolean, default: true, doc: "Whether params are collapsible"
  attr :id, :string, default: nil

  def tool_call(assigns) do
    assigns = assign_new(assigns, :id, fn -> "tool-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div
      id={@id}
      class={[
        "my-2 rounded-lg border text-sm font-mono",
        status_border_class(@status),
        status_bg_class(@status)
      ]}
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-3 py-2">
        <div class="flex items-center gap-2">
          <span class={["text-lg", status_icon_class(@status)]}>
            {status_icon(@status)}
          </span>
          <span class="font-semibold text-gray-800">{format_tool_name(@name)}</span>
          <span :if={@duration_ms} class="text-xs text-gray-500">
            ({format_duration(@duration_ms)})
          </span>
        </div>
        <span class={["text-xs px-2 py-0.5 rounded-full", status_badge_class(@status)]}>
          {format_status(@status)}
        </span>
      </div>

      <%!-- Parameters (collapsible) --%>
      <div :if={@params != %{}} class="border-t border-gray-200">
        <details class="group" open={not @collapsible}>
          <summary class="px-3 py-1.5 text-xs text-gray-500 cursor-pointer hover:bg-gray-50 select-none">
            Parameters
            <span class="ml-1 group-open:rotate-90 inline-block transition-transform">▶</span>
          </summary>
          <div class="px-3 pb-2 text-xs">
            <div :for={{key, value} <- @params} class="flex gap-2 py-0.5">
              <span class="text-gray-500">{key}:</span>
              <span class="text-gray-700">{inspect(value)}</span>
            </div>
          </div>
        </details>
      </div>

      <%!-- Result or Error --%>
      <div :if={@result || @error} class="border-t border-gray-200 px-3 py-2">
        <div :if={@result} class="text-xs text-green-700">
          <span class="font-medium">Result:</span> {@result}
        </div>
        <div :if={@error} class="text-xs text-red-700">
          <span class="font-medium">Error:</span> {@error}
        </div>
      </div>
    </div>
    """
  end

  defp status_icon(:pending), do: "⏳"
  defp status_icon(:running), do: "⚙️"
  defp status_icon(:complete), do: "✓"
  defp status_icon(:error), do: "✗"

  defp status_icon_class(:error), do: "text-red-500"
  defp status_icon_class(:complete), do: "text-green-500"
  defp status_icon_class(_), do: "text-gray-500"

  defp status_border_class(:error), do: "border-red-200"
  defp status_border_class(:complete), do: "border-green-200"
  defp status_border_class(:running), do: "border-blue-200"
  defp status_border_class(_), do: "border-gray-200"

  defp status_bg_class(:error), do: "bg-red-50"
  defp status_bg_class(:complete), do: "bg-green-50"
  defp status_bg_class(:running), do: "bg-blue-50"
  defp status_bg_class(_), do: "bg-gray-50"

  defp status_badge_class(:error), do: "bg-red-100 text-red-700"
  defp status_badge_class(:complete), do: "bg-green-100 text-green-700"
  defp status_badge_class(:running), do: "bg-blue-100 text-blue-700 animate-pulse"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-700"

  defp format_status(:pending), do: "pending"
  defp format_status(:running), do: "running..."
  defp format_status(:complete), do: "done"
  defp format_status(:error), do: "failed"

  defp format_tool_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  # ============================================
  # Card Component
  # ============================================

  @doc """
  Renders a structured information card.

  ## Examples

      <.card title="Task Created" variant={:success}>
        <p>Your task has been added to the calendar.</p>
      </.card>

      <.card title="Meeting Found" metadata={%{date: "Tomorrow", time: "2pm"}}>
        <p>Team standup with 5 participants</p>
      </.card>
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :variant, :atom, default: :default, values: [:default, :success, :warning, :error, :info]
  attr :metadata, :map, default: %{}, doc: "Key-value metadata to display"
  attr :icon, :string, default: nil, doc: "Optional icon (emoji or heroicon name)"
  attr :collapsible, :boolean, default: false
  attr :id, :string, default: nil

  slot :inner_block
  slot :actions, doc: "Optional action buttons"

  def card(assigns) do
    assigns = assign_new(assigns, :id, fn -> "card-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div
      id={@id}
      class={[
        "my-2 rounded-lg border shadow-sm overflow-hidden",
        card_variant_class(@variant)
      ]}
    >
      <%!-- Header --%>
      <div class={["px-4 py-3 flex items-center gap-3", card_header_class(@variant)]}>
        <span :if={@icon} class="text-xl">{@icon}</span>
        <div class="flex-1">
          <h3 class="font-semibold text-gray-900">{@title}</h3>
          <p :if={@subtitle} class="text-sm text-gray-500">{@subtitle}</p>
        </div>
      </div>

      <%!-- Body --%>
      <div :if={@inner_block != []} class="px-4 py-3 text-sm text-gray-700">
        {render_slot(@inner_block)}
      </div>

      <%!-- Metadata --%>
      <div :if={@metadata != %{}} class="px-4 py-2 bg-gray-50 border-t border-gray-100">
        <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
          <div :for={{key, value} <- @metadata} class="contents">
            <dt class="text-gray-500">{format_metadata_key(key)}</dt>
            <dd class="text-gray-700 font-medium">{value}</dd>
          </div>
        </dl>
      </div>

      <%!-- Actions --%>
      <div :if={@actions != []} class="px-4 py-3 bg-gray-50 border-t border-gray-100 flex gap-2 justify-end">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  defp card_variant_class(:success), do: "border-green-200"
  defp card_variant_class(:warning), do: "border-yellow-200"
  defp card_variant_class(:error), do: "border-red-200"
  defp card_variant_class(:info), do: "border-blue-200"
  defp card_variant_class(_), do: "border-gray-200"

  defp card_header_class(:success), do: "bg-green-50"
  defp card_header_class(:warning), do: "bg-yellow-50"
  defp card_header_class(:error), do: "bg-red-50"
  defp card_header_class(:info), do: "bg-blue-50"
  defp card_header_class(_), do: "bg-white"

  defp format_metadata_key(key) when is_atom(key), do: key |> to_string() |> format_metadata_key()

  defp format_metadata_key(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  # ============================================
  # Action Button Component
  # ============================================

  @doc """
  Renders an action button that HAL can offer to users.

  ## Examples

      <.action_button label="Approve" action="approve_task" variant={:primary} />
      <.action_button label="Cancel" action="cancel" variant={:secondary} />
  """
  attr :label, :string, required: true
  attr :action, :string, required: true, doc: "The action identifier sent on click"
  attr :variant, :atom, default: :primary, values: [:primary, :secondary, :danger, :ghost]
  attr :icon, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :confirm, :string, default: nil, doc: "Confirmation message before action"
  attr :rest, :global

  def action_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="hal_action"
      phx-value-action={@action}
      data-confirm={@confirm}
      disabled={@disabled}
      class={[
        "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors",
        button_variant_class(@variant),
        @disabled && "opacity-50 cursor-not-allowed"
      ]}
      {@rest}
    >
      <span :if={@icon}>{@icon}</span>
      {@label}
    </button>
    """
  end

  defp button_variant_class(:primary), do: "bg-blue-600 text-white hover:bg-blue-700"
  defp button_variant_class(:secondary), do: "bg-gray-100 text-gray-700 hover:bg-gray-200"
  defp button_variant_class(:danger), do: "bg-red-600 text-white hover:bg-red-700"
  defp button_variant_class(:ghost), do: "text-gray-600 hover:bg-gray-100"

  # ============================================
  # Progress Component
  # ============================================

  @doc """
  Renders a progress indicator for long-running operations.

  ## Examples

      <.progress label="Processing files" percent={45} />
      <.progress label="Searching" indeterminate />
  """
  attr :label, :string, required: true
  attr :percent, :integer, default: nil, doc: "Progress percentage (0-100)"
  attr :indeterminate, :boolean, default: false, doc: "Show indeterminate progress"
  attr :status, :string, default: nil, doc: "Optional status text"

  def progress(assigns) do
    ~H"""
    <div class="my-2 p-3 rounded-lg bg-gray-50 border border-gray-200">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-gray-700">{@label}</span>
        <span :if={@percent} class="text-xs text-gray-500">{@percent}%</span>
      </div>

      <div class="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
        <div
          :if={@indeterminate}
          class="h-full bg-blue-500 rounded-full animate-indeterminate"
          style="width: 30%"
        />
        <div
          :if={@percent}
          class="h-full bg-blue-500 rounded-full transition-all duration-300"
          style={"width: #{@percent}%"}
        />
      </div>

      <p :if={@status} class="mt-1.5 text-xs text-gray-500">{@status}</p>
    </div>
    """
  end

  # ============================================
  # Thinking Indicator
  # ============================================

  @doc """
  Renders a "HAL is thinking" indicator.

  ## Examples

      <.thinking />
      <.thinking message="Searching calendar..." />
  """
  attr :message, :string, default: "Thinking..."

  def thinking(assigns) do
    ~H"""
    <div class="flex items-center gap-2 py-2 text-gray-500">
      <div class="flex gap-1">
        <span class="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style="animation-delay: 0ms" />
        <span class="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style="animation-delay: 150ms" />
        <span class="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style="animation-delay: 300ms" />
      </div>
      <span class="text-sm italic">{@message}</span>
    </div>
    """
  end

  # ============================================
  # HAL Message Wrapper
  # ============================================

  @doc """
  Renders a complete HAL message with optional components.

  Parses the response and renders appropriate components inline.
  """
  attr :content, :string, required: true
  attr :tool_calls, :list, default: [], doc: "List of tool call maps"
  attr :cards, :list, default: [], doc: "List of card maps"
  attr :actions, :list, default: [], doc: "List of action maps"

  def hal_message(assigns) do
    ~H"""
    <div class="hal-message space-y-2">
      <%!-- Tool calls first --%>
      <.tool_call :for={tc <- @tool_calls} {tc} />

      <%!-- Main content --%>
      <div :if={@content && @content != ""} class="prose prose-sm max-w-none">
        {Phoenix.HTML.raw(render_markdown(@content))}
      </div>

      <%!-- Cards --%>
      <.card :for={card <- @cards} {card} />

      <%!-- Action buttons --%>
      <div :if={@actions != []} class="flex gap-2 mt-3">
        <.action_button :for={action <- @actions} {action} />
      </div>
    </div>
    """
  end

  defp render_markdown(content) do
    case Earmark.as_html(content, code_class_prefix: "language-", smartypants: false) do
      {:ok, html, _} -> html
      {:error, _, _} -> content
    end
  end
end
