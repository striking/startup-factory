defmodule HAL.AI.Supervisor do
  @moduledoc """
  Supervisor for HAL AI components.

  Supervises:
  - HAL.AI.AgentSDK - Claude Agent SDK client via Node.js Port

  ## Supervision Strategy

  Uses `:one_for_one` - if the AgentSDK crashes, only it restarts.
  This is appropriate because:
  - AgentSDK is stateless (Port handles state)
  - Crashed requests get error responses
  - New queries will restart the port

  ## Configuration

  Configure in `config/config.exs`:

      config :hal, HAL.AI.AgentSDK,
        model: "claude-sonnet-4-5-20250929",
        start_immediately: false
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {HAL.AI.AgentSDK, get_agent_sdk_opts()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp get_agent_sdk_opts do
    Application.get_env(:hal, HAL.AI.AgentSDK, [])
    |> Keyword.put(:working_dir, File.cwd!())
  end
end
