defmodule HalWeb.Components.A2UIRenderer do
  @moduledoc """
  LiveView component that renders A2UI documents.

  Transforms A2UI document specifications into Phoenix LiveView components.
  Each A2UI surface type (Card, Chart, Table, etc.) maps to a corresponding
  Phoenix component.

  ## Usage in LiveView

      # In your LiveView module
      def mount(_params, _session, socket) do
        if connected?(socket), do: HAL.A2UI.subscribe("session-123")
        {:ok, assign(socket, a2ui_doc: nil)}
      end

      def handle_info({:a2ui_update, doc}, socket) do
        {:noreply, assign(socket, a2ui_doc: doc)}
      end

      # In your template
      <.live_component module={HalWeb.Components.A2UIRenderer} id="a2ui" doc={@a2ui_doc} />

  ## Or as a function component

      <HalWeb.Components.A2UIRenderer.render_doc doc={@a2ui_doc} />

  ## Supported Components

  - Card - Displays metric/info cards
  - BarChart, LineChart, PieChart, AreaChart - Data visualizations
  - Table - Tabular data display
  - List - Item lists
  - Form - User input forms
  """

  use Phoenix.Component

  # ============================================
  # Main Renderer
  # ============================================

  @doc """
  Renders a complete A2UI document.

  ## Attributes

  - `doc` - The A2UI document to render (can be nil)
  - `class` - Additional CSS classes for the container

  ## Examples

      <.render_doc doc={@a2ui_doc} />
      <.render_doc doc={@a2ui_doc} class="space-y-4" />
  """
  attr :doc, :map, default: nil
  attr :class, :string, default: "space-y-4"

  def render_doc(assigns) do
    ~H"""
    <div :if={@doc} class={@class}>
      <.render_surface :for={surface <- @doc.surfaces} surface={surface} />
    </div>
    <div :if={is_nil(@doc)} class="text-gray-400 text-sm italic">
      No content to display
    </div>
    """
  end

  @doc """
  Renders a single A2UI surface.

  Dispatches to the appropriate renderer based on component type.
  """
  attr :surface, :map, required: true

  def render_surface(assigns) do
    ~H"""
    <%= case @surface.component do %>
      <% "Card" -> %>
        <.a2ui_card surface={@surface} />
      <% "BarChart" -> %>
        <.a2ui_bar_chart surface={@surface} />
      <% "LineChart" -> %>
        <.a2ui_line_chart surface={@surface} />
      <% "PieChart" -> %>
        <.a2ui_pie_chart surface={@surface} />
      <% "AreaChart" -> %>
        <.a2ui_area_chart surface={@surface} />
      <% "Table" -> %>
        <.a2ui_table surface={@surface} />
      <% "List" -> %>
        <.a2ui_list surface={@surface} />
      <% "Form" -> %>
        <.a2ui_form surface={@surface} />
      <% _ -> %>
        <.a2ui_unknown surface={@surface} />
    <% end %>
    """
  end

  # ============================================
  # Card Component
  # ============================================

  attr :surface, :map, required: true

  defp a2ui_card(assigns) do
    props = assigns.surface.props

    assigns =
      assign(assigns, %{
        id: assigns.surface.id,
        title: props[:title],
        value: props[:value],
        subtitle: props[:subtitle],
        icon: props[:icon],
        variant: props[:variant] || :default,
        metadata: props[:metadata] || %{}
      })

    ~H"""
    <div
      id={@id}
      class={[
        "rounded-lg border shadow-sm overflow-hidden",
        card_border_class(@variant)
      ]}
    >
      <div class={["px-4 py-3 flex items-center gap-3", card_header_class(@variant)]}>
        <span :if={@icon} class="text-2xl">{@icon}</span>
        <div class="flex-1">
          <h3 class="font-semibold text-gray-900">{@title}</h3>
          <p :if={@subtitle} class="text-sm text-gray-500">{@subtitle}</p>
        </div>
        <div :if={@value} class="text-2xl font-bold text-gray-900">
          {@value}
        </div>
      </div>

      <div :if={@metadata != %{}} class="px-4 py-2 bg-gray-50 border-t border-gray-100">
        <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
          <div :for={{key, val} <- @metadata} class="contents">
            <dt class="text-gray-500">{format_key(key)}</dt>
            <dd class="text-gray-700 font-medium">{val}</dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  defp card_border_class(:success), do: "border-green-200"
  defp card_border_class(:warning), do: "border-yellow-200"
  defp card_border_class(:error), do: "border-red-200"
  defp card_border_class(:info), do: "border-blue-200"
  defp card_border_class(_), do: "border-gray-200"

  defp card_header_class(:success), do: "bg-green-50"
  defp card_header_class(:warning), do: "bg-yellow-50"
  defp card_header_class(:error), do: "bg-red-50"
  defp card_header_class(:info), do: "bg-blue-50"
  defp card_header_class(_), do: "bg-white"

  # ============================================
  # Chart Components
  # ============================================

  # Note: These render placeholder charts. For production, integrate with
  # a charting library like Chart.js via hooks or use SVG-based rendering.

  attr :surface, :map, required: true

  defp a2ui_bar_chart(assigns) do
    props = assigns.surface.props
    data = props[:data] || []
    max_value = data |> Enum.map(& &1[:value]) |> Enum.max(fn -> 1 end)

    assigns =
      assign(assigns, %{
        id: assigns.surface.id,
        title: props[:title],
        data: data,
        max_value: max_value,
        height: props[:height] || 200,
        color: props[:color] || "blue"
      })

    ~H"""
    <div id={@id} class="rounded-lg border border-gray-200 p-4">
      <h4 :if={@title} class="font-medium text-gray-900 mb-3">{@title}</h4>
      <div class="flex items-end gap-2" style={"height: #{@height}px"}>
        <div :for={item <- @data} class="flex-1 flex flex-col items-center gap-1">
          <div
            class={["w-full rounded-t transition-all", bar_color_class(@color)]}
            style={"height: #{bar_height(item[:value], @max_value, @height - 30)}px"}
          />
          <span class="text-xs text-gray-500 truncate max-w-full" title={item[:label]}>
            {item[:label]}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp bar_height(value, max, available_height) when max > 0 do
    round(value / max * available_height)
  end

  defp bar_height(_, _, _), do: 0

  defp bar_color_class("blue"), do: "bg-blue-500"
  defp bar_color_class("green"), do: "bg-green-500"
  defp bar_color_class("red"), do: "bg-red-500"
  defp bar_color_class("yellow"), do: "bg-yellow-500"
  defp bar_color_class("purple"), do: "bg-purple-500"
  defp bar_color_class(_), do: "bg-blue-500"

  attr :surface, :map, required: true

  defp a2ui_line_chart(assigns) do
    props = assigns.surface.props

    assigns
    |> assign(%{
      id: assigns.surface.id,
      title: props[:title],
      data: props[:data] || [],
      height: props[:height] || 200,
      icon: "📈",
      label: "Line Chart"
    })
    |> a2ui_chart_placeholder()
  end

  attr :surface, :map, required: true

  defp a2ui_pie_chart(assigns) do
    props = assigns.surface.props
    data = props[:data] || []
    total = data |> Enum.map(& &1[:value]) |> Enum.sum()

    assigns =
      assign(assigns, %{
        id: assigns.surface.id,
        title: props[:title],
        data: data,
        total: total,
        height: props[:height] || 200,
        show_legend: props[:show_legend] != false
      })

    ~H"""
    <div id={@id} class="rounded-lg border border-gray-200 p-4">
      <h4 :if={@title} class="font-medium text-gray-900 mb-3">{@title}</h4>
      <div class="flex gap-4" style={"min-height: #{@height}px"}>
        <div class="flex-shrink-0 w-32 h-32 rounded-full bg-gray-100 flex items-center justify-center">
          <span class="text-2xl font-bold text-gray-600">{@total}</span>
        </div>
        <div :if={@show_legend} class="flex flex-col gap-1">
          <div :for={{item, idx} <- Enum.with_index(@data)} class="flex items-center gap-2 text-sm">
            <div class={["w-3 h-3 rounded-sm", pie_color_class(idx)]} />
            <span class="text-gray-600">{item[:label]}</span>
            <span class="text-gray-400">({item[:value]})</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp pie_color_class(0), do: "bg-blue-500"
  defp pie_color_class(1), do: "bg-green-500"
  defp pie_color_class(2), do: "bg-yellow-500"
  defp pie_color_class(3), do: "bg-red-500"
  defp pie_color_class(4), do: "bg-purple-500"
  defp pie_color_class(_), do: "bg-gray-500"

  attr :surface, :map, required: true

  defp a2ui_area_chart(assigns) do
    props = assigns.surface.props

    assigns
    |> assign(%{
      id: assigns.surface.id,
      title: props[:title],
      data: props[:data] || [],
      height: props[:height] || 200,
      icon: "📊",
      label: "Area Chart"
    })
    |> a2ui_chart_placeholder()
  end

  # Shared placeholder component for charts without full rendering
  defp a2ui_chart_placeholder(assigns) do
    ~H"""
    <div id={@id} class="rounded-lg border border-gray-200 p-4">
      <h4 :if={@title} class="font-medium text-gray-900 mb-3">{@title}</h4>
      <div class="flex items-center justify-center text-gray-400" style={"height: #{@height}px"}>
        <div class="text-center">
          <div class="text-4xl mb-2">{@icon}</div>
          <div class="text-sm">{@label}</div>
          <div class="text-xs">{length(@data)} data points</div>
        </div>
      </div>
    </div>
    """
  end

  # ============================================
  # Table Component
  # ============================================

  attr :surface, :map, required: true

  defp a2ui_table(assigns) do
    props = assigns.surface.props

    assigns =
      assign(assigns, %{
        id: assigns.surface.id,
        title: props[:title],
        columns: props[:columns] || [],
        rows: props[:rows] || []
      })

    ~H"""
    <div id={@id} class="rounded-lg border border-gray-200 overflow-hidden">
      <div :if={@title} class="px-4 py-3 bg-gray-50 border-b border-gray-200">
        <h4 class="font-medium text-gray-900">{@title}</h4>
      </div>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th
                :for={col <- @columns}
                class={[
                  "px-4 py-2 text-xs font-medium text-gray-500 uppercase tracking-wider",
                  column_align_class(col[:align])
                ]}
              >
                {col[:label] || col[:key]}
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={row <- @rows} class="hover:bg-gray-50">
              <td
                :for={col <- @columns}
                class={[
                  "px-4 py-2 text-sm text-gray-700",
                  column_align_class(col[:align])
                ]}
              >
                {get_cell_value(row, col[:key])}
              </td>
            </tr>
            <tr :if={@rows == []}>
              <td colspan={length(@columns)} class="px-4 py-8 text-center text-gray-400 text-sm">
                No data
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp column_align_class(:center), do: "text-center"
  defp column_align_class(:right), do: "text-right"
  defp column_align_class(_), do: "text-left"

  defp get_cell_value(row, key) when is_atom(key),
    do: Map.get(row, key) || Map.get(row, to_string(key))

  defp get_cell_value(row, key), do: Map.get(row, key) || Map.get(row, String.to_atom(key))

  # ============================================
  # List Component
  # ============================================

  attr :surface, :map, required: true

  defp a2ui_list(assigns) do
    props = assigns.surface.props

    assigns =
      assign(assigns, %{
        id: assigns.surface.id,
        title: props[:title],
        items: props[:items] || [],
        ordered: props[:ordered] || false,
        default_icon: props[:icon]
      })

    ~H"""
    <div id={@id} class="rounded-lg border border-gray-200">
      <div :if={@title} class="px-4 py-3 bg-gray-50 border-b border-gray-200">
        <h4 class="font-medium text-gray-900">{@title}</h4>
      </div>
      <ul class={["divide-y divide-gray-100", @ordered && "list-decimal list-inside"]}>
        <li :for={{item, idx} <- Enum.with_index(@items)} class="px-4 py-2 flex items-center gap-2">
          <span :if={!@ordered} class="text-gray-400">
            {item[:icon] || @default_icon || "•"}
          </span>
          <span :if={@ordered} class="text-gray-400 w-6">{idx + 1}.</span>
          <span class="flex-1 text-sm text-gray-700">{item[:text]}</span>
          <span :if={item[:subtitle]} class="text-xs text-gray-400">{item[:subtitle]}</span>
        </li>
        <li :if={@items == []} class="px-4 py-4 text-center text-gray-400 text-sm">
          No items
        </li>
      </ul>
    </div>
    """
  end

  # ============================================
  # Form Component
  # ============================================

  attr :surface, :map, required: true

  defp a2ui_form(assigns) do
    props = assigns.surface.props

    assigns =
      assign(assigns, %{
        id: assigns.surface.id,
        title: props[:title],
        fields: props[:fields] || [],
        submit_label: props[:submit_label] || "Submit",
        action: props[:action] || "form_submit"
      })

    ~H"""
    <div id={@id} class="rounded-lg border border-gray-200">
      <div :if={@title} class="px-4 py-3 bg-gray-50 border-b border-gray-200">
        <h4 class="font-medium text-gray-900">{@title}</h4>
      </div>
      <form phx-submit={@action} class="p-4 space-y-4">
        <input type="hidden" name="surface_id" value={@id} />
        <.form_field :for={field <- @fields} field={field} />
        <button
          type="submit"
          class="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors font-medium"
        >
          {@submit_label}
        </button>
      </form>
    </div>
    """
  end

  attr :field, :map, required: true

  defp form_field(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">
        {@field[:label] || @field[:name]}
        <span :if={@field[:required]} class="text-red-500">*</span>
      </label>
      <%= case @field[:type] do %>
        <% "textarea" -> %>
          <textarea
            name={@field[:name]}
            required={@field[:required]}
            rows={@field[:rows] || 3}
            placeholder={@field[:placeholder]}
            class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          />
        <% "select" -> %>
          <select
            name={@field[:name]}
            required={@field[:required]}
            class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="">Select...</option>
            <option :for={opt <- @field[:options] || []} value={opt[:value]}>{opt[:label]}</option>
          </select>
        <% "checkbox" -> %>
          <input
            type="checkbox"
            name={@field[:name]}
            class="h-4 w-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
          />
        <% _ -> %>
          <input
            type={@field[:type] || "text"}
            name={@field[:name]}
            required={@field[:required]}
            placeholder={@field[:placeholder]}
            class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          />
      <% end %>
    </div>
    """
  end

  # ============================================
  # Unknown Component (Fallback)
  # ============================================

  attr :surface, :map, required: true

  defp a2ui_unknown(assigns) do
    ~H"""
    <div
      id={@surface.id}
      class="rounded-lg border border-yellow-200 bg-yellow-50 p-4"
    >
      <div class="flex items-center gap-2 text-yellow-700">
        <span class="text-lg">⚠️</span>
        <span class="font-medium">Unknown component: {@surface.component}</span>
      </div>
      <pre class="mt-2 text-xs text-yellow-600 overflow-auto">
        {inspect(@surface.props, pretty: true)}
      </pre>
    </div>
    """
  end

  # ============================================
  # Helpers
  # ============================================

  defp format_key(key) when is_atom(key), do: key |> to_string() |> format_key()

  defp format_key(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
