defmodule HAL.Agents.Supervisor do
  @moduledoc """
  Supervisor for external agent delegation modules.

  Supervises the GenServers that allow Claude (the brain) to delegate
  tasks to external AI agents:
  - HAL.Agents.Codex - OpenAI Codex for complex coding tasks
  - HAL.Agents.Jules - OpenAI Jules for async background tasks
  - HAL.Agents.Gemini - Google Gemini for fast summarization/completion

  ## Architecture

  Claude (via Agent SDK) makes ALL decisions. When it decides to delegate:
  1. Claude calls the appropriate agent module
  2. The agent module manages the external session/task
  3. Results flow back to Claude for final decision-making

  ## Supervision Strategy

  Uses `:one_for_one` - if one agent crashes, others continue.
  Each agent is independent and stateless enough to restart safely.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      HAL.Agents.Codex,
      HAL.Agents.Jules,
      HAL.Agents.Gemini
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
