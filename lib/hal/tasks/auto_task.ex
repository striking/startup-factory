defmodule Hal.Tasks.AutoTask do
  @moduledoc """
  Schema for multi-step autonomous tasks.

  Enables HAL to execute complex tasks that span multiple steps and time.
  Tasks persist through restarts and can be paused/resumed.

  ## Example Flow

      # User says: "Research the best Elixir frameworks and email me a summary"
      # This becomes a 3-step task:

      AutoTask.create(user_id, %{
        title: "Research Elixir Frameworks",
        original_request: "Research the best Elixir frameworks and email me a summary",
        steps: [
          %{name: "research", prompt: "Research the top Elixir frameworks..."},
          %{name: "summarize", prompt: "Summarize the research findings..."},
          %{name: "email", prompt: "Email the summary to the user..."}
        ]
      })

  ## Step Structure

  Each step in the `steps` array is a map:
  ```
  %{
    name: "research",           # Step identifier
    prompt: "Research...",      # What to ask Claude
    status: "pending",          # pending, running, completed, failed
    result: nil,                # Claude's response
    error: nil,                 # Error message if failed
    started_at: nil,            # When step started
    completed_at: nil           # When step finished
  }
  ```
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Accounts.User
  alias HAL.Autonomy.Brain
  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending running paused completed failed)
  @priorities ~w(low normal high urgent)

  schema "autonomous_tasks" do
    belongs_to :user, User

    # Task definition
    field :title, :string
    field :description, :string
    field :original_request, :string

    # Steps and progress
    field :steps, {:array, :map}, default: []
    field :current_step, :integer, default: 0

    # Status
    field :status, :string, default: "pending"
    field :priority, :string, default: "normal"

    # Results
    field :final_result, :string
    field :error_message, :string

    # Timing
    field :scheduled_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :retry_count, :integer, default: 0
    field :max_retries, :integer, default: 3

    # Additional context
    field :context, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an autonomous task.
  """
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :user_id,
      :title,
      :description,
      :original_request,
      :steps,
      :current_step,
      :status,
      :priority,
      :final_result,
      :error_message,
      :scheduled_at,
      :started_at,
      :completed_at,
      :retry_count,
      :max_retries,
      :context
    ])
    |> validate_required([:user_id, :title, :original_request])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> validate_length(:steps, min: 1, message: "must have at least one step")
  end

  @doc """
  Creates a new autonomous task.
  """
  @spec create(binary(), map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(user_id, attrs) do
    # Initialize steps with pending status
    steps = Map.get(attrs, :steps, []) |> initialize_steps()

    %__MODULE__{}
    |> changeset(Map.merge(attrs, %{user_id: user_id, steps: steps}))
    |> Repo.insert()
  end

  @doc """
  Creates a task from a natural language request using Claude to decompose it.

  This is the main entry point - takes the user's request and breaks it into steps.
  """
  @spec create_from_request(binary(), String.t(), keyword()) ::
          {:ok, %__MODULE__{}} | {:error, term()}
  def create_from_request(user_id, request, opts \\ []) do
    priority = Keyword.get(opts, :priority, "normal")
    scheduled_at = Keyword.get(opts, :scheduled_at)
    context = Keyword.get(opts, :context, %{})

    # Use Claude to decompose the request into steps
    case decompose_request(user_id, request) do
      {:ok, %{title: title, steps: steps}} ->
        create(user_id, %{
          title: title,
          original_request: request,
          steps: steps,
          priority: priority,
          scheduled_at: scheduled_at,
          context: context
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a task by ID.
  """
  @spec get(binary()) :: %__MODULE__{} | nil
  def get(task_id) do
    Repo.get(__MODULE__, task_id)
  end

  @doc """
  Gets a task by ID with user preloaded.
  """
  @spec get_with_user(binary()) :: %__MODULE__{} | nil
  def get_with_user(task_id) do
    Repo.get(__MODULE__, task_id) |> Repo.preload(:user)
  end

  @doc """
  Lists tasks for a user.
  """
  @spec list_for_user(binary(), keyword()) :: [%__MODULE__{}]
  def list_for_user(user_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(t in __MODULE__,
        where: t.user_id == ^user_id,
        order_by: [desc: t.inserted_at],
        limit: ^limit
      )

    query = if status, do: where(query, [t], t.status == ^status), else: query

    Repo.all(query)
  end

  @doc """
  Gets pending tasks that are ready to run.
  """
  @spec get_pending() :: [%__MODULE__{}]
  def get_pending do
    now = DateTime.utc_now()

    from(t in __MODULE__,
      where: t.status == "pending",
      where: is_nil(t.scheduled_at) or t.scheduled_at <= ^now,
      order_by: [
        asc:
          fragment(
            "CASE WHEN ? = 'urgent' THEN 0 WHEN ? = 'high' THEN 1 WHEN ? = 'normal' THEN 2 ELSE 3 END",
            t.priority,
            t.priority,
            t.priority
          )
      ],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Starts execution of a task.
  """
  @spec start(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def start(task_id) do
    case get(task_id) do
      nil ->
        {:error, :not_found}

      task ->
        task
        |> changeset(%{status: "running", started_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc """
  Advances to the next step after completing the current one.
  """
  @spec complete_step(binary(), String.t()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def complete_step(task_id, result) do
    case get(task_id) do
      nil ->
        {:error, :not_found}

      task ->
        steps =
          update_step_status(task.steps, task.current_step, %{
            status: "completed",
            result: result,
            completed_at: DateTime.utc_now()
          })

        next_step = task.current_step + 1

        if next_step >= length(steps) do
          # All steps completed
          task
          |> changeset(%{
            steps: steps,
            current_step: next_step,
            status: "completed",
            final_result: result,
            completed_at: DateTime.utc_now()
          })
          |> Repo.update()
        else
          # More steps to go
          task
          |> changeset(%{steps: steps, current_step: next_step})
          |> Repo.update()
        end
    end
  end

  @doc """
  Marks the current step as failed.
  """
  @spec fail_step(binary(), String.t()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def fail_step(task_id, error) do
    case get(task_id) do
      nil ->
        {:error, :not_found}

      task ->
        steps =
          update_step_status(task.steps, task.current_step, %{
            status: "failed",
            error: error,
            completed_at: DateTime.utc_now()
          })

        if task.retry_count < task.max_retries do
          # Can retry
          task
          |> changeset(%{steps: steps, retry_count: task.retry_count + 1})
          |> Repo.update()
        else
          # Max retries exceeded
          task
          |> changeset(%{
            steps: steps,
            status: "failed",
            error_message: "Max retries exceeded. Last error: #{error}",
            completed_at: DateTime.utc_now()
          })
          |> Repo.update()
        end
    end
  end

  @doc """
  Pauses a running task.
  """
  @spec pause(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def pause(task_id) do
    case get(task_id) do
      nil ->
        {:error, :not_found}

      %{status: "running"} = task ->
        task |> changeset(%{status: "paused"}) |> Repo.update()

      _ ->
        {:error, :not_running}
    end
  end

  @doc """
  Resumes a paused task.
  """
  @spec resume(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def resume(task_id) do
    case get(task_id) do
      nil ->
        {:error, :not_found}

      %{status: "paused"} = task ->
        task |> changeset(%{status: "running"}) |> Repo.update()

      _ ->
        {:error, :not_paused}
    end
  end

  @doc """
  Gets the current step information for a task.
  """
  @spec get_current_step(%__MODULE__{}) :: map() | nil
  def get_current_step(%{steps: steps, current_step: idx}) when idx < length(steps) do
    Enum.at(steps, idx)
  end

  def get_current_step(_), do: nil

  @doc """
  Gets task progress as a percentage.
  """
  @spec progress(%__MODULE__{}) :: integer()
  def progress(%{steps: steps, current_step: current}) do
    total = length(steps)
    if total > 0, do: round(current / total * 100), else: 0
  end

  # Private Helpers

  defp initialize_steps(steps) do
    Enum.map(steps, fn step ->
      Map.merge(
        %{
          "status" => "pending",
          "result" => nil,
          "error" => nil,
          "started_at" => nil,
          "completed_at" => nil
        },
        stringify_keys(step)
      )
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp update_step_status(steps, index, updates) do
    List.update_at(steps, index, fn step ->
      Map.merge(step, stringify_keys(updates))
    end)
  end

  defp decompose_request(user_id, request) do
    # Use Claude to break down the request into steps
    prompt = """
    Analyze this user request and break it into discrete steps that can be executed autonomously.

    User Request: #{request}

    Respond with JSON in this exact format:
    {
      "title": "Short title for the task (max 50 chars)",
      "steps": [
        {"name": "step_identifier", "prompt": "Detailed prompt for this step..."},
        {"name": "step_identifier", "prompt": "Detailed prompt for this step..."}
      ]
    }

    Rules:
    - Each step should be self-contained
    - Steps should be executable in order
    - Include any dependencies between steps in the prompts
    - Use descriptive step names (research, analyze, summarize, email, etc.)
    - Maximum 5 steps
    """

    turn_id = "task-decompose:#{Ecto.UUID.generate()}"

    case Brain.prompt(prompt,
           user_id: user_id,
           hal_session_id: turn_id,
           channel_type: "terminal",
           channel_id: "task_decompose",
           timeout: 120_000
         ) do
      {:ok, response} ->
        parse_decomposition(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_decomposition(response) do
    # Extract JSON from response
    with {:ok, json} <- extract_json(response),
         {:ok, decoded} <- Jason.decode(json) do
      {:ok,
       %{
         title: decoded["title"],
         steps: decoded["steps"]
       }}
    else
      _ -> {:error, :parse_failed}
    end
  end

  defp extract_json(text) do
    # Find JSON block in response
    case Regex.run(~r/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/s, text) do
      [json | _] -> {:ok, json}
      nil -> {:error, :no_json}
    end
  end
end
