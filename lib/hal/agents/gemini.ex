defmodule HAL.Agents.Gemini do
  @moduledoc """
  Delegation module for Google Gemini.

  Allows Claude (the brain) to delegate specific tasks to Gemini.
  Gemini excels at fast, cost-effective tasks like summarization,
  document completion, and general analysis.

  ## Architecture

  Claude decides to delegate → calls HAL.Agents.Gemini → Gemini API executes

  ## Usage

      # Delegate summarization
      {:ok, task} = Gemini.summarize("Long document text here...", max_length: 500)

      # Delegate completion
      {:ok, task} = Gemini.complete("Draft email:", tone: "professional")

      # Check status
      {:ok, status} = Gemini.check_status(task.id)

      # Get result
      {:ok, result} = Gemini.get_result(task.id)
  """

  use GenServer
  require Logger

  @type task_id :: String.t()
  @type task :: %{
          id: task_id(),
          type: :summarize | :complete | :delegate,
          status: :pending | :running | :completed | :failed,
          input: String.t(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          result: String.t() | nil,
          error: String.t() | nil
        }

  # Client API

  @doc """
  Start the Gemini agent GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Delegate a general task to Gemini.

  ## Options

    * `:system_prompt` - Optional system instructions
    * `:temperature` - Sampling temperature (default: 0.7)
    * `:max_tokens` - Max output tokens (default: 2048)

  ## Returns

    * `{:ok, task}` - Task started successfully
    * `{:error, reason}` - Failed to start task
  """
  @spec delegate(String.t(), keyword()) :: {:ok, task()} | {:error, term()}
  def delegate(prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:delegate, :delegate, prompt, opts}, :infinity)
  end

  @doc """
  Delegate text completion to Gemini.

  ## Options

    * `:tone` - Desired tone (professional, casual, technical)
    * `:max_tokens` - Max output tokens (default: 1024)

  ## Returns

    * `{:ok, task}` - Task started successfully
    * `{:error, reason}` - Failed to start task
  """
  @spec complete(String.t(), keyword()) :: {:ok, task()} | {:error, term()}
  def complete(partial_text, opts \\ []) do
    system_prompt = build_completion_prompt(opts)
    opts = Keyword.put(opts, :system_prompt, system_prompt)
    GenServer.call(__MODULE__, {:delegate, :complete, partial_text, opts}, :infinity)
  end

  @doc """
  Delegate summarization to Gemini.

  ## Options

    * `:max_length` - Target summary length in words (default: 200)
    * `:style` - Summary style: bullets, paragraph, key_points (default: paragraph)

  ## Returns

    * `{:ok, task}` - Task started successfully
    * `{:error, reason}` - Failed to start task
  """
  @spec summarize(String.t(), keyword()) :: {:ok, task()} | {:error, term()}
  def summarize(text, opts \\ []) do
    system_prompt = build_summarization_prompt(opts)
    opts = Keyword.put(opts, :system_prompt, system_prompt)
    GenServer.call(__MODULE__, {:delegate, :summarize, text, opts}, :infinity)
  end

  @doc """
  Check the status of a Gemini task.
  """
  @spec check_status(task_id()) :: {:ok, task()} | {:error, :not_found}
  def check_status(task_id) do
    GenServer.call(__MODULE__, {:check_status, task_id})
  end

  @doc """
  Get the result of a completed Gemini task.
  """
  @spec get_result(task_id()) :: {:ok, String.t()} | {:error, :not_found | :not_completed}
  def get_result(task_id) do
    GenServer.call(__MODULE__, {:get_result, task_id})
  end

  @doc """
  List all tasks.
  """
  @spec list_tasks() :: [task()]
  def list_tasks do
    GenServer.call(__MODULE__, :list_tasks)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      tasks: %{},
      gemini_available: check_gemini_availability()
    }

    Logger.info("HAL.Agents.Gemini initialized, API available: #{state.gemini_available}")
    {:ok, state}
  end

  @impl true
  def handle_call({:delegate, type, input, opts}, _from, state) do
    task_id = generate_task_id()

    task = %{
      id: task_id,
      type: type,
      status: :pending,
      input: truncate_for_logging(input),
      opts: opts,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      result: nil,
      error: nil
    }

    # Execute Gemini call (synchronous for now, fast enough)
    case execute_gemini_task(input, opts) do
      {:ok, result, _session} ->
        task = %{
          task
          | status: :completed,
            completed_at: DateTime.utc_now(),
            result: result
        }

        new_state = put_in(state.tasks[task_id], task)
        Logger.info("Completed Gemini #{type} task #{task_id}")
        {:reply, {:ok, task}, new_state}

      {:error, reason} ->
        task = %{
          task
          | status: :failed,
            completed_at: DateTime.utc_now(),
            error: inspect(reason)
        }

        new_state = put_in(state.tasks[task_id], task)
        Logger.error("Failed Gemini #{type} task #{task_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:check_status, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil -> {:reply, {:error, :not_found}, state}
      task -> {:reply, {:ok, task}, state}
    end
  end

  @impl true
  def handle_call({:get_result, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil -> {:reply, {:error, :not_found}, state}
      %{status: :completed, result: result} -> {:reply, {:ok, result}, state}
      _ -> {:reply, {:error, :not_completed}, state}
    end
  end

  @impl true
  def handle_call(:list_tasks, _from, state) do
    tasks = Map.values(state.tasks)
    {:reply, tasks, state}
  end

  # Private Functions

  defp generate_task_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp check_gemini_availability do
    # Check for API key (either naming convention) or Gemini CLI
    api_key = System.get_env("GOOGLE_AI_API_KEY") || System.get_env("GEMINI_API_KEY")
    has_api_key = not is_nil(api_key) and api_key != ""

    # Also check if Gemini CLI is available (authenticated via gcloud)
    has_cli = System.find_executable("gemini") != nil

    has_api_key or has_cli
  end

  defp execute_gemini_task(input, opts) do
    # Prefer CLI if available (uses gcloud auth), fall back to API
    case System.find_executable("gemini") do
      nil ->
        # Use the API provider
        Hal.AI.Gemini.prompt(nil, input, opts)

      gemini_path ->
        execute_via_cli(gemini_path, input, opts)
    end
  end

  defp execute_via_cli(gemini_path, input, opts) do
    system_prompt = Keyword.get(opts, :system_prompt)

    # Build CLI args
    args = ["-p", input]
    args = if system_prompt, do: args ++ ["-s", system_prompt], else: args

    case System.cmd(gemini_path, args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output), nil}

      {error, _code} ->
        Logger.warning("Gemini CLI failed, falling back to API: #{String.slice(error, 0, 100)}")
        # Fall back to API
        Hal.AI.Gemini.prompt(nil, input, opts)
    end
  end

  defp build_completion_prompt(opts) do
    tone = Keyword.get(opts, :tone, "natural")

    """
    You are a writing assistant. Complete the given text naturally.
    Tone: #{tone}
    Continue the text seamlessly without repeating what was already written.
    """
  end

  defp build_summarization_prompt(opts) do
    max_length = Keyword.get(opts, :max_length, 200)
    style = Keyword.get(opts, :style, :paragraph)

    style_instruction =
      case style do
        :bullets -> "Use bullet points."
        :key_points -> "List the key points."
        :paragraph -> "Write in paragraph form."
        _ -> "Write in paragraph form."
      end

    """
    Summarize the following text in approximately #{max_length} words.
    #{style_instruction}
    Be concise and capture the main ideas.
    """
  end

  defp truncate_for_logging(text) when byte_size(text) > 100 do
    String.slice(text, 0, 100) <> "..."
  end

  defp truncate_for_logging(text), do: text
end
