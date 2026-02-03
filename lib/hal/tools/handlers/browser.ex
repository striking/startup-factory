defmodule Hal.Tools.Handlers.Browser do
  @moduledoc """
  Handler for HAL browser automation tools.

  Leverages two complementary browser control methods:

  ## Chrome DevTools MCP
  - Accessed via `mcp__chrome-devtools__*` tools
  - Best for: automation, headless operation, A11y tree snapshots
  - Requires Chrome with `--remote-debugging-port`

  ## Claude Extension
  - Accessed via native messaging through Claude Code
  - Best for: interactive testing with existing browser session (logged in sites)
  - Requires Claude Chrome extension v1.0.36+

  ## Usage Strategy

  - Use `mode: "devtools"` for automated workflows, CI, headless
  - Use `mode: "extension"` when you need existing cookies/sessions
  - Default to devtools for reliability
  """

  require Logger
  alias Hal.Tools.Executor

  @doc """
  Navigate to a URL in the browser.
  """
  @spec navigate(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def navigate(args, _opts) do
    url = Map.get(args, "url")
    mode = Map.get(args, "mode", "devtools")

    if is_nil(url) or url == "" do
      Executor.return_error("Missing required argument: url")
    else
      case mode do
        "devtools" ->
          # Use Chrome DevTools MCP
          navigate_via_devtools(url, args)

        "extension" ->
          # Claude Extension - handled by Claude Code directly
          Executor.return_success(
            "Navigation requested via Claude Extension",
            %{
              url: url,
              instruction: "Use Claude Chrome Extension to navigate to #{url}",
              mode: "extension"
            }
          )

        _ ->
          Executor.return_error("Invalid mode: #{mode}. Use 'devtools' or 'extension'")
      end
    end
  end

  @doc """
  Take an accessibility tree snapshot of the current page.
  """
  @spec snapshot(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def snapshot(args, _opts) do
    verbose = Map.get(args, "verbose", false)

    # This delegates to Chrome DevTools MCP
    Executor.return_success(
      "Snapshot requested",
      %{
        mcp_tool: "mcp__chrome-devtools__take_snapshot",
        args: %{verbose: verbose},
        instruction: "Call mcp__chrome-devtools__take_snapshot to get the A11y tree"
      }
    )
  end

  @doc """
  Click on an element.
  """
  @spec click(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def click(args, _opts) do
    uid = Map.get(args, "uid")
    selector = Map.get(args, "selector")
    double_click = Map.get(args, "double_click", false)

    cond do
      uid ->
        Executor.return_success(
          "Click requested",
          %{
            mcp_tool: "mcp__chrome-devtools__click",
            args: %{uid: uid, dblClick: double_click},
            instruction: "Call mcp__chrome-devtools__click with uid: #{uid}"
          }
        )

      selector ->
        # Need to first snapshot to get uid, then click
        Executor.return_success(
          "Click by selector requested",
          %{
            instruction:
              "First call mcp__chrome-devtools__take_snapshot, find element matching '#{selector}', then call mcp__chrome-devtools__click with its uid"
          }
        )

      true ->
        Executor.return_error("Must provide either 'uid' or 'selector'")
    end
  end

  @doc """
  Fill a form field with text.
  """
  @spec fill(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def fill(args, _opts) do
    uid = Map.get(args, "uid")
    selector = Map.get(args, "selector")
    value = Map.get(args, "value")

    if is_nil(value) do
      Executor.return_error("Missing required argument: value")
    else
      cond do
        uid ->
          Executor.return_success(
            "Fill requested",
            %{
              mcp_tool: "mcp__chrome-devtools__fill",
              args: %{uid: uid, value: value},
              instruction: "Call mcp__chrome-devtools__fill with uid: #{uid}, value: #{value}"
            }
          )

        selector ->
          Executor.return_success(
            "Fill by selector requested",
            %{
              instruction:
                "First call mcp__chrome-devtools__take_snapshot, find element matching '#{selector}', then call mcp__chrome-devtools__fill with its uid and value: #{value}"
            }
          )

        true ->
          Executor.return_error("Must provide either 'uid' or 'selector'")
      end
    end
  end

  @doc """
  Take a screenshot of the current page.
  """
  @spec screenshot(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def screenshot(args, _opts) do
    full_page = Map.get(args, "full_page", false)
    selector = Map.get(args, "selector")

    Executor.return_success(
      "Screenshot requested",
      %{
        mcp_tool: "mcp__chrome-devtools__take_screenshot",
        args: %{fullPage: full_page, element: selector},
        instruction: "Call mcp__chrome-devtools__take_screenshot"
      }
    )
  end

  @doc """
  Execute JavaScript in the browser.
  """
  @spec evaluate(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def evaluate(args, _opts) do
    script = Map.get(args, "script")

    if is_nil(script) or script == "" do
      Executor.return_error("Missing required argument: script")
    else
      Executor.return_success(
        "JavaScript evaluation requested",
        %{
          mcp_tool: "mcp__chrome-devtools__evaluate_script",
          args: %{function: script},
          instruction: "Call mcp__chrome-devtools__evaluate_script with the function"
        }
      )
    end
  end

  @doc """
  Get browser console messages.
  """
  @spec console(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def console(args, _opts) do
    level = Map.get(args, "level", "all")
    limit = Map.get(args, "limit", 50)

    Executor.return_success(
      "Console messages requested",
      %{
        mcp_tool: "mcp__chrome-devtools__list_console_messages",
        args: %{level: level, limit: limit},
        instruction: "Call mcp__chrome-devtools__list_console_messages"
      }
    )
  end

  @doc """
  Get network requests from the page.
  """
  @spec network(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def network(args, _opts) do
    filter = Map.get(args, "filter")
    type = Map.get(args, "type", "all")
    limit = Map.get(args, "limit", 50)

    Executor.return_success(
      "Network requests requested",
      %{
        mcp_tool: "mcp__chrome-devtools__list_network_requests",
        args: %{filter: filter, type: type, limit: limit},
        instruction: "Call mcp__chrome-devtools__list_network_requests"
      }
    )
  end

  # Private helpers

  defp navigate_via_devtools(url, args) do
    wait_for = Map.get(args, "wait_for", "load")

    Executor.return_success(
      "Navigation requested via DevTools",
      %{
        mcp_tool: "mcp__chrome-devtools__navigate_page",
        args: %{url: url, type: "url"},
        wait_for: wait_for,
        instruction: "Call mcp__chrome-devtools__navigate_page with url: #{url}"
      }
    )
  end
end
