defmodule HalWeb.Components.Catalog do
  @moduledoc """
  A2UI-inspired component catalog for HAL.

  This module provides a registry of pre-approved UI components that HAL
  can request to render. Following A2UI principles, HAL can only render
  components from this catalog, ensuring safety and predictability.

  ## Philosophy

  Like A2UI, the catalog separates UI specification from rendering:
  1. HAL outputs structured data (component type + props)
  2. Catalog resolves the component
  3. LiveView renders the actual HTML

  ## Usage

      # In HAL's response parsing
      components = HalWeb.Components.Catalog.parse_response(hal_response)

      # In LiveView template
      <.dynamic_component :for={comp <- @components} {comp} />

  ## Component Types

  HAL can request these component types:
  - `tool_call` - Visualize a tool being called
  - `card` - Display structured information
  - `action_button` - Offer user actions
  - `progress` - Show long-running operations
  - `thinking` - Indicate HAL is processing
  """

  alias HalWeb.HalComponents

  @type component_type :: :tool_call | :card | :action_button | :progress | :thinking
  @type component_spec :: %{type: component_type, props: map()}

  @doc """
  List of all registered component types.
  """
  @spec registered_types() :: [component_type()]
  def registered_types do
    [:tool_call, :card, :action_button, :progress, :thinking]
  end

  @doc """
  Check if a component type is registered in the catalog.
  """
  @spec registered?(atom()) :: boolean()
  def registered?(type), do: type in registered_types()

  @doc """
  Get the component function for a given type.

  Returns `nil` if the type is not registered.
  """
  @spec get_component(atom()) :: function() | nil
  def get_component(:tool_call), do: &HalComponents.tool_call/1
  def get_component(:card), do: &HalComponents.card/1
  def get_component(:action_button), do: &HalComponents.action_button/1
  def get_component(:progress), do: &HalComponents.progress/1
  def get_component(:thinking), do: &HalComponents.thinking/1
  def get_component(_), do: nil

  @doc """
  Parse a HAL response for component markers.

  HAL can embed component requests in its response using special markers:

      [[tool_call:search_calendar:running:query=meetings tomorrow]]
      [[card:success:Task Created:Your task has been added]]
      [[action:approve:Approve This:primary]]

  Returns a list of component specs that can be rendered.
  """
  @spec parse_response(String.t()) :: {String.t(), [component_spec()]}
  def parse_response(response) when is_binary(response) do
    # Pattern for tool calls: [[tool:name:status:params]]
    tool_pattern = ~r/\[\[tool:([^:]+):([^:]+)(?::([^\]]+))?\]\]/

    # Pattern for cards: [[card:variant:title:body]]
    card_pattern = ~r/\[\[card:([^:]+):([^:]+)(?::([^\]]+))?\]\]/

    # Pattern for actions: [[action:id:label:variant]]
    action_pattern = ~r/\[\[action:([^:]+):([^:]+)(?::([^\]]+))?\]\]/

    # Extract tool calls
    tool_calls =
      Regex.scan(tool_pattern, response)
      |> Enum.map(fn
        [_, name, status] ->
          %{type: :tool_call, props: %{name: name, status: parse_status(status)}}

        [_, name, status, params] ->
          %{
            type: :tool_call,
            props: %{name: name, status: parse_status(status), params: parse_params(params)}
          }
      end)

    # Extract cards
    cards =
      Regex.scan(card_pattern, response)
      |> Enum.map(fn
        [_, variant, title] ->
          %{type: :card, props: %{variant: String.to_atom(variant), title: title}}

        [_, variant, title, body] ->
          %{type: :card, props: %{variant: String.to_atom(variant), title: title, body: body}}
      end)

    # Extract actions
    actions =
      Regex.scan(action_pattern, response)
      |> Enum.map(fn
        [_, id, label] ->
          %{type: :action_button, props: %{action: id, label: label}}

        [_, id, label, variant] ->
          %{
            type: :action_button,
            props: %{action: id, label: label, variant: String.to_atom(variant)}
          }
      end)

    # Remove markers from response
    clean_response =
      response
      |> String.replace(tool_pattern, "")
      |> String.replace(card_pattern, "")
      |> String.replace(action_pattern, "")
      |> String.trim()

    components = tool_calls ++ cards ++ actions

    {clean_response, components}
  end

  @doc """
  Build a component spec for HAL to use.

  HAL can use this to create properly formatted component requests.
  """
  @spec build_tool_call(String.t(), atom(), map()) :: String.t()
  def build_tool_call(name, status, params \\ %{}) do
    params_str = if params == %{}, do: "", else: ":" <> encode_params(params)
    "[[tool:#{name}:#{status}#{params_str}]]"
  end

  @spec build_card(atom(), String.t(), String.t() | nil) :: String.t()
  def build_card(variant, title, body \\ nil) do
    body_str = if body, do: ":#{body}", else: ""
    "[[card:#{variant}:#{title}#{body_str}]]"
  end

  @spec build_action(String.t(), String.t(), atom()) :: String.t()
  def build_action(id, label, variant \\ :primary) do
    "[[action:#{id}:#{label}:#{variant}]]"
  end

  @doc """
  Validate a component spec against the catalog.

  Returns `{:ok, spec}` if valid, `{:error, reason}` if not.
  """
  @spec validate(component_spec()) :: {:ok, component_spec()} | {:error, String.t()}
  def validate(%{type: type} = spec) do
    if registered?(type) do
      {:ok, spec}
    else
      {:error, "Unknown component type: #{type}"}
    end
  end

  def validate(_), do: {:error, "Invalid component spec format"}

  # Private helpers

  defp parse_status("pending"), do: :pending
  defp parse_status("running"), do: :running
  defp parse_status("complete"), do: :complete
  defp parse_status("error"), do: :error
  defp parse_status(other), do: String.to_atom(other)

  defp parse_params(params_str) do
    params_str
    |> String.split(",")
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> {String.trim(key), String.trim(value)}
        [key] -> {String.trim(key), true}
      end
    end)
    |> Map.new()
  end

  defp encode_params(params) do
    params
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(",")
  end
end
