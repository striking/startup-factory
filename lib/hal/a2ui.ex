defmodule HAL.A2UI do
  @moduledoc """
  A2UI (Agent-to-UI) Protocol for declarative agent-driven interfaces.

  A2UI v0.8 allows agents to generate rich, structured UI without directly
  manipulating DOM or LiveView. Agents declare what they want to show, and
  the renderer translates to actual components.

  ## Philosophy

  Instead of agents generating raw HTML (security risk, inconsistent UX),
  agents produce A2UI documents - declarative specifications of UI elements.
  The renderer validates and renders these to safe, consistent UI.

  ## Document Structure

  An A2UI document contains a list of "surfaces" - individual UI components:

      %{
        version: "0.8",
        surfaces: [
          %{id: "status", component: "Card", props: %{title: "Status", value: "Active"}},
          %{id: "chart", component: "BarChart", props: %{title: "Tasks", data: [...]}
        ]
      }

  ## Supported Components

  - **Card** - Metric/info display (title, value, icon)
  - **BarChart, LineChart, PieChart, AreaChart** - Data visualizations
  - **Table** - Tabular data (columns, rows)
  - **List** - Item lists (items with optional icons/links)
  - **Form** - User input collection (fields with validation)

  ## Usage

      # Build a dashboard
      doc = HAL.A2UI.new()
        |> HAL.A2UI.add_surface(HAL.A2UI.card("status", title: "Status", value: "Active"))
        |> HAL.A2UI.add_surface(HAL.A2UI.chart("tasks", :bar, data, title: "Tasks"))

      # Broadcast to LiveView
      HAL.A2UI.broadcast(doc, "session-123")

      # Or serialize for API response
      json = HAL.A2UI.to_json(doc)

  ## LiveView Integration

  In your LiveView, subscribe to A2UI updates:

      def mount(_params, _session, socket) do
        if connected?(socket), do: HAL.A2UI.subscribe("session-123")
        {:ok, assign(socket, a2ui_doc: nil)}
      end

      def handle_info({:a2ui_update, doc}, socket) do
        {:noreply, assign(socket, a2ui_doc: doc)}
      end

  Then render using the A2UIRenderer component.
  """

  @version "0.8"
  @pubsub Hal.PubSub
  @chart_components ~w(BarChart LineChart PieChart AreaChart)

  @type surface :: %{
          id: String.t(),
          component: String.t(),
          props: map()
        }

  @type document :: %{
          version: String.t(),
          surfaces: [surface()]
        }

  # ============================================
  # Document Management
  # ============================================

  @doc """
  Creates a new empty A2UI document.

  ## Examples

      doc = HAL.A2UI.new()
      #=> %{version: "0.8", surfaces: []}
  """
  @spec new() :: document()
  def new do
    %{
      version: @version,
      surfaces: []
    }
  end

  @doc """
  Creates a new A2UI document with initial surfaces.

  ## Examples

      doc = HAL.A2UI.new([
        HAL.A2UI.card("status", title: "Status", value: "OK"),
        HAL.A2UI.card("count", title: "Tasks", value: "5")
      ])
  """
  @spec new([surface()]) :: document()
  def new(surfaces) when is_list(surfaces) do
    %{
      version: @version,
      surfaces: surfaces
    }
  end

  @doc """
  Adds a surface to the document.

  ## Examples

      doc
      |> HAL.A2UI.add_surface(HAL.A2UI.card("status", title: "Status", value: "OK"))
  """
  @spec add_surface(document(), surface()) :: document()
  def add_surface(doc, surface) do
    %{doc | surfaces: doc.surfaces ++ [surface]}
  end

  @doc """
  Updates an existing surface by ID.

  Merges the updates into the existing surface's props.
  Returns the document unchanged if the surface ID is not found.

  ## Examples

      doc |> HAL.A2UI.update_surface("status", %{value: "Busy"})
  """
  @spec update_surface(document(), String.t(), map()) :: document()
  def update_surface(doc, surface_id, updates) do
    surfaces =
      Enum.map(doc.surfaces, fn surface ->
        if surface.id == surface_id do
          %{surface | props: Map.merge(surface.props, updates)}
        else
          surface
        end
      end)

    %{doc | surfaces: surfaces}
  end

  @doc """
  Removes a surface by ID.

  ## Examples

      doc |> HAL.A2UI.remove_surface("old-card")
  """
  @spec remove_surface(document(), String.t()) :: document()
  def remove_surface(doc, surface_id) do
    surfaces = Enum.reject(doc.surfaces, &(&1.id == surface_id))
    %{doc | surfaces: surfaces}
  end

  @doc """
  Gets a surface by ID.

  ## Examples

      HAL.A2UI.get_surface(doc, "status")
      #=> %{id: "status", component: "Card", props: %{...}}
  """
  @spec get_surface(document(), String.t()) :: surface() | nil
  def get_surface(doc, surface_id) do
    Enum.find(doc.surfaces, &(&1.id == surface_id))
  end

  # ============================================
  # Surface Builders
  # ============================================

  @doc """
  Creates a Card surface for displaying metrics or key information.

  ## Options

  - `:title` - Card title (required)
  - `:value` - Main value to display
  - `:subtitle` - Secondary text
  - `:icon` - Icon emoji or name
  - `:variant` - Visual variant (:default, :success, :warning, :error, :info)
  - `:metadata` - Map of key-value pairs to show

  ## Examples

      HAL.A2UI.card("status", title: "Status", value: "Active", icon: "✓")
      HAL.A2UI.card("error", title: "Error", value: "Connection failed", variant: :error)
  """
  @spec card(String.t(), keyword()) :: surface()
  def card(id, opts) do
    props = %{
      title: Keyword.fetch!(opts, :title),
      value: Keyword.get(opts, :value),
      subtitle: Keyword.get(opts, :subtitle),
      icon: Keyword.get(opts, :icon),
      variant: Keyword.get(opts, :variant, :default),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %{id: id, component: "Card", props: props}
  end

  @doc """
  Creates a Chart surface for data visualization.

  ## Chart Types

  - `:bar` - Vertical bar chart
  - `:line` - Line chart with points
  - `:pie` - Pie/donut chart
  - `:area` - Filled area chart

  ## Data Format

  Data should be a list of maps with `:label` and `:value` keys:

      [
        %{label: "Jan", value: 100},
        %{label: "Feb", value: 150}
      ]

  ## Options

  - `:title` - Chart title
  - `:height` - Chart height in pixels (default: 200)
  - `:color` - Primary color (default: "blue")
  - `:show_legend` - Show legend (default: true for pie)

  ## Examples

      data = [%{label: "Done", value: 5}, %{label: "Pending", value: 3}]
      HAL.A2UI.chart("tasks", :bar, data, title: "Task Status")
      HAL.A2UI.chart("progress", :pie, data, title: "Completion")
  """
  @spec chart(String.t(), atom(), list(), keyword()) :: surface()
  def chart(id, type, data, opts \\ []) when type in [:bar, :line, :pie, :area] do
    component =
      case type do
        :bar -> "BarChart"
        :line -> "LineChart"
        :pie -> "PieChart"
        :area -> "AreaChart"
      end

    props = %{
      type: type,
      data: data,
      title: Keyword.get(opts, :title),
      height: Keyword.get(opts, :height, 200),
      color: Keyword.get(opts, :color, "blue"),
      show_legend: Keyword.get(opts, :show_legend, type == :pie)
    }

    %{id: id, component: component, props: props}
  end

  @doc """
  Creates a Table surface for tabular data.

  ## Options

  - `:columns` - List of column definitions (required)
  - `:rows` - List of row data (required)
  - `:title` - Optional table title
  - `:sortable` - Enable column sorting (default: false)
  - `:paginate` - Rows per page, nil for no pagination

  ## Column Format

      [
        %{key: "name", label: "Name"},
        %{key: "status", label: "Status", align: :center}
      ]

  ## Examples

      columns = [
        %{key: "name", label: "Name"},
        %{key: "status", label: "Status"}
      ]
      rows = [
        %{name: "Task 1", status: "Done"},
        %{name: "Task 2", status: "Pending"}
      ]
      HAL.A2UI.table("tasks", columns, rows, title: "Tasks")
  """
  @spec table(String.t(), list(), list(), keyword()) :: surface()
  def table(id, columns, rows, opts \\ []) do
    props = %{
      columns: columns,
      rows: rows,
      title: Keyword.get(opts, :title),
      sortable: Keyword.get(opts, :sortable, false),
      paginate: Keyword.get(opts, :paginate)
    }

    %{id: id, component: "Table", props: props}
  end

  @doc """
  Creates a List surface for displaying items.

  ## Item Format

  Items can be strings or maps with additional properties:

      # Simple strings
      ["Item 1", "Item 2"]

      # Rich items
      [
        %{text: "Task 1", icon: "✓", subtitle: "Completed"},
        %{text: "Task 2", icon: "○", link: "/tasks/2"}
      ]

  ## Options

  - `:title` - List title
  - `:ordered` - Use numbered list (default: false)
  - `:icon` - Default icon for all items

  ## Examples

      HAL.A2UI.list("files", ["README.md", "mix.exs"], title: "Files")

      items = [%{text: "Buy milk", icon: "○"}, %{text: "Call mom", icon: "✓"}]
      HAL.A2UI.list("todos", items, title: "Today's Tasks")
  """
  @spec list(String.t(), list(), keyword()) :: surface()
  def list(id, items, opts \\ []) do
    # Normalize items to maps
    normalized_items =
      Enum.map(items, fn
        item when is_binary(item) -> %{text: item}
        item when is_map(item) -> item
      end)

    props = %{
      items: normalized_items,
      title: Keyword.get(opts, :title),
      ordered: Keyword.get(opts, :ordered, false),
      icon: Keyword.get(opts, :icon)
    }

    %{id: id, component: "List", props: props}
  end

  @doc """
  Creates a Form surface for user input.

  ## Field Format

      [
        %{name: "email", type: "email", label: "Email", required: true},
        %{name: "message", type: "textarea", label: "Message", rows: 4},
        %{name: "priority", type: "select", label: "Priority",
          options: [%{value: "low", label: "Low"}, %{value: "high", label: "High"}]}
      ]

  ## Supported Field Types

  - `text`, `email`, `password`, `number`, `date`, `time`
  - `textarea` - Multiline text
  - `select` - Dropdown (requires `:options`)
  - `checkbox` - Boolean toggle
  - `radio` - Radio group (requires `:options`)

  ## Options

  - `:title` - Form title
  - `:submit_label` - Submit button text (default: "Submit")
  - `:action` - Action identifier sent on submit

  ## Examples

      fields = [
        %{name: "task", type: "text", label: "Task", required: true},
        %{name: "due", type: "date", label: "Due Date"}
      ]
      HAL.A2UI.form("new-task", fields, title: "Add Task", action: "create_task")
  """
  @spec form(String.t(), list(), keyword()) :: surface()
  def form(id, fields, opts \\ []) do
    props = %{
      fields: fields,
      title: Keyword.get(opts, :title),
      submit_label: Keyword.get(opts, :submit_label, "Submit"),
      action: Keyword.get(opts, :action, "form_submit")
    }

    %{id: id, component: "Form", props: props}
  end

  @doc """
  Creates a custom surface with any component type.

  Use this for extending A2UI with custom components. The renderer must
  know how to handle the component type.

  ## Examples

      HAL.A2UI.custom("map", "MapView", %{center: [151.2, -33.8], zoom: 12})
  """
  @spec custom(String.t(), String.t(), map()) :: surface()
  def custom(id, component, props) do
    %{id: id, component: component, props: props}
  end

  # ============================================
  # Serialization
  # ============================================

  @doc """
  Converts an A2UI document to JSON.

  ## Examples

      json = HAL.A2UI.to_json(doc)
  """
  @spec to_json(document()) :: String.t()
  def to_json(doc) do
    Jason.encode!(doc)
  end

  @doc """
  Parses an A2UI document from JSON.

  Returns `{:ok, document}` or `{:error, reason}`.

  ## Examples

      {:ok, doc} = HAL.A2UI.from_json(json_string)
  """
  @spec from_json(String.t()) :: {:ok, document()} | {:error, term()}
  def from_json(json) do
    case Jason.decode(json, keys: :atoms) do
      {:ok, data} ->
        doc = %{
          version: Map.get(data, :version, @version),
          surfaces: Map.get(data, :surfaces, [])
        }

        {:ok, doc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates an A2UI document structure.

  Returns `:ok` or `{:error, errors}` with a list of validation errors.

  ## Examples

      :ok = HAL.A2UI.validate(doc)
      {:error, ["Surface 'foo' missing required prop: title"]} = HAL.A2UI.validate(bad_doc)
  """
  @spec validate(document()) :: :ok | {:error, [String.t()]}
  def validate(doc) do
    errors =
      doc.surfaces
      |> Enum.flat_map(&validate_surface/1)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  defp validate_surface(%{id: id, component: component, props: props}) do
    required_props = get_required_props(component)
    validate_required(id, props, required_props)
  end

  defp validate_surface(_), do: ["Invalid surface structure"]

  defp get_required_props("Card"), do: [:title]
  defp get_required_props(chart) when chart in @chart_components, do: [:data]
  defp get_required_props("Table"), do: [:columns, :rows]
  defp get_required_props("List"), do: [:items]
  defp get_required_props("Form"), do: [:fields]
  defp get_required_props(_), do: []

  defp validate_required(surface_id, props, required_keys) do
    Enum.flat_map(required_keys, fn key ->
      if Map.get(props, key) == nil do
        ["Surface '#{surface_id}' missing required prop: #{key}"]
      else
        []
      end
    end)
  end

  # ============================================
  # Broadcasting
  # ============================================

  @doc """
  Broadcasts an A2UI document update to subscribers.

  Subscribers will receive `{:a2ui_update, document}`.

  ## Examples

      HAL.A2UI.broadcast(doc, "session-123")
  """
  @spec broadcast(document(), String.t()) :: :ok | {:error, term()}
  def broadcast(doc, session_id) do
    Phoenix.PubSub.broadcast(@pubsub, a2ui_topic(session_id), {:a2ui_update, doc})
  end

  @doc """
  Subscribes to A2UI updates for a session.

  ## Examples

      HAL.A2UI.subscribe("session-123")
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, a2ui_topic(session_id))
  end

  @doc """
  Unsubscribes from A2UI updates for a session.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(session_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, a2ui_topic(session_id))
  end

  defp a2ui_topic(session_id), do: "a2ui:#{session_id}"
end
