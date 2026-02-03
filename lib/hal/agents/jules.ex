defmodule HAL.Agents.Jules do
  @moduledoc """
  Delegation module for Google Jules async coding agent.

  Jules is Google's AI coding agent that can work on GitHub repositories
  in the background, creating PRs with code changes.

  ## Configuration

  Set the following in your environment:

      export JULES_API_KEY="your-api-key"

  Get your API key from the Jules web app Settings page (max 3 keys per account).

  ## Architecture

  Claude decides to delegate → calls HAL.Agents.Jules → Jules API executes in background

  ## Usage

      # Start a background task
      {:ok, task} = Jules.start_task("Refactor the authentication module", repo: "owner/repo")

      # Check status
      {:ok, status} = Jules.check_status(task.id)

      # List activities
      {:ok, activities} = Jules.list_activities(task.id)

  ## API Reference

  See https://jules.google/docs/api/reference/ for full API documentation.
  """

  use GenServer
  require Logger

  @base_url "https://jules.google/v1alpha"
  @default_timeout 30_000

  @type task_id :: String.t()
  @type jules_session_id :: String.t()
  @type task :: %{
          id: task_id(),
          jules_session_id: jules_session_id() | nil,
          status: :pending | :running | :plan_ready | :completed | :failed,
          description: String.t(),
          repo: String.t() | nil,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          result: map() | nil,
          error: String.t() | nil
        }

  # Client API

  @doc """
  Start the Jules agent GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a new async background task with Jules.

  ## Options

    * `:repo` - GitHub repository (owner/repo format) - REQUIRED
    * `:branch` - Target branch (default: main)
    * `:auto_pr` - Automatically create PR when done (default: true)
    * `:require_plan_approval` - Require plan approval before execution (default: false)

  ## Returns

    * `{:ok, task}` - Task started successfully
    * `{:error, reason}` - Failed to start task
  """
  @spec start_task(String.t(), keyword()) :: {:ok, task()} | {:error, term()}
  def start_task(description, opts \\ []) do
    repo = Keyword.get(opts, :repo)

    if is_nil(repo) or repo == "" do
      {:error, :repo_required}
    else
      GenServer.call(__MODULE__, {:start_task, description, opts}, :infinity)
    end
  end

  @doc """
  Approve a plan for a task that's waiting for approval.
  Only needed if `require_plan_approval: true` was set.
  """
  @spec approve_plan(task_id()) :: {:ok, task()} | {:error, term()}
  def approve_plan(task_id) do
    GenServer.call(__MODULE__, {:approve_plan, task_id}, :infinity)
  end

  @doc """
  Send a message to an active Jules session.
  """
  @spec send_message(task_id(), String.t()) :: {:ok, task()} | {:error, term()}
  def send_message(task_id, message) do
    GenServer.call(__MODULE__, {:send_message, task_id, message}, :infinity)
  end

  @doc """
  List activities (progress updates) for a task.
  """
  @spec list_activities(task_id()) :: {:ok, [map()]} | {:error, term()}
  def list_activities(task_id) do
    GenServer.call(__MODULE__, {:list_activities, task_id})
  end

  @doc """
  Check the status of a Jules task.
  """
  @spec check_status(task_id()) :: {:ok, task()} | {:error, :not_found}
  def check_status(task_id) do
    GenServer.call(__MODULE__, {:check_status, task_id})
  end

  @doc """
  Cancel a running Jules task.
  """
  @spec cancel_task(task_id()) :: :ok | {:error, :not_found | :cannot_cancel}
  def cancel_task(task_id) do
    GenServer.call(__MODULE__, {:cancel_task, task_id})
  end

  @doc """
  Get the result of a completed Jules task.
  """
  @spec get_result(task_id()) :: {:ok, map()} | {:error, :not_found | :not_completed}
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
    # Schedule periodic status checks for running tasks
    :timer.send_interval(30_000, :check_running_tasks)

    api_key = get_api_key()

    state = %{
      tasks: %{},
      api_key: api_key,
      api_available: not is_nil(api_key) and api_key != ""
    }

    if state.api_available do
      Logger.info("HAL.Agents.Jules initialized with API key")
    else
      Logger.warning("HAL.Agents.Jules initialized WITHOUT API key - set JULES_API_KEY")
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:start_task, description, opts}, _from, state) do
    if not state.api_available do
      {:reply, {:error, :api_key_not_configured}, state}
    else
      task_id = generate_task_id()
      repo = Keyword.get(opts, :repo)

      task = %{
        id: task_id,
        jules_session_id: nil,
        status: :pending,
        description: description,
        repo: repo,
        opts: opts,
        started_at: DateTime.utc_now(),
        completed_at: nil,
        result: nil,
        error: nil
      }

      # Call Jules API to create session
      case create_jules_session(state.api_key, description, opts) do
        {:ok, jules_response} ->
          jules_session_id = jules_response["name"]

          task = %{
            task
            | status: :running,
              jules_session_id: jules_session_id
          }

          new_state = put_in(state.tasks[task_id], task)
          Logger.info("Started Jules session #{jules_session_id} for task #{task_id}")
          {:reply, {:ok, task}, new_state}

        {:error, reason} ->
          task = %{task | status: :failed, error: inspect(reason)}
          new_state = put_in(state.tasks[task_id], task)
          {:reply, {:error, reason}, new_state}
      end
    end
  end

  @impl true
  def handle_call({:approve_plan, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{jules_session_id: nil} ->
        {:reply, {:error, :no_session}, state}

      %{jules_session_id: session_id} = task ->
        case approve_jules_plan(state.api_key, session_id) do
          :ok ->
            task = %{task | status: :running}
            new_state = put_in(state.tasks[task_id], task)
            {:reply, {:ok, task}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:send_message, task_id, message}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{jules_session_id: nil} ->
        {:reply, {:error, :no_session}, state}

      %{jules_session_id: session_id} = task ->
        case send_jules_message(state.api_key, session_id, message) do
          :ok -> {:reply, {:ok, task}, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:list_activities, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{jules_session_id: nil} ->
        {:reply, {:error, :no_session}, state}

      %{jules_session_id: session_id} ->
        case get_jules_activities(state.api_key, session_id) do
          {:ok, activities} -> {:reply, {:ok, activities}, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
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
  def handle_call({:cancel_task, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: status} when status in [:completed, :failed] ->
        {:reply, {:error, :cannot_cancel}, state}

      task ->
        # Jules API doesn't have an explicit cancel endpoint
        # We just mark it as cancelled locally
        task = %{task | status: :failed, error: "Cancelled by user"}
        new_state = put_in(state.tasks[task_id], task)
        Logger.info("Cancelled Jules task #{task_id}")
        {:reply, :ok, new_state}
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

  @impl true
  def handle_info(:check_running_tasks, state) do
    if not state.api_available do
      {:noreply, state}
    else
      # Check status of all running tasks
      running_tasks =
        state.tasks
        |> Enum.filter(fn {_id, task} ->
          task.status in [:running, :plan_ready] and not is_nil(task.jules_session_id)
        end)

      new_state =
        Enum.reduce(running_tasks, state, fn {task_id, task}, acc ->
          case check_jules_session_status(acc.api_key, task.jules_session_id) do
            {:ok, %{"status" => "completed", "activities" => activities}} ->
              result = extract_result_from_activities(activities)

              task = %{
                task
                | status: :completed,
                  completed_at: DateTime.utc_now(),
                  result: result
              }

              Logger.info("Jules task #{task_id} completed")
              put_in(acc.tasks[task_id], task)

            {:ok, %{"status" => "failed", "activities" => activities}} ->
              error = extract_error_from_activities(activities)

              task = %{
                task
                | status: :failed,
                  completed_at: DateTime.utc_now(),
                  error: error
              }

              Logger.warning("Jules task #{task_id} failed: #{error}")
              put_in(acc.tasks[task_id], task)

            {:ok, %{"status" => "plan_ready"}} ->
              task = %{task | status: :plan_ready}
              put_in(acc.tasks[task_id], task)

            {:error, reason} ->
              Logger.error("Failed to check Jules task #{task_id}: #{inspect(reason)}")
              acc

            _ ->
              acc
          end
        end)

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp generate_task_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp get_api_key do
    System.get_env("JULES_API_KEY")
  end

  defp extract_result_from_activities(activities) do
    # Look for completed activity with PR info or summary
    Enum.find_value(activities, %{}, fn activity ->
      case activity do
        %{"type" => "COMPLETED", "data" => data} -> data
        %{"type" => "PR_CREATED", "data" => data} -> data
        _ -> nil
      end
    end)
  end

  defp extract_error_from_activities(activities) do
    # Look for failed activity with error message
    Enum.find_value(activities, "Unknown error", fn activity ->
      case activity do
        %{"type" => "FAILED", "data" => %{"message" => message}} -> message
        %{"type" => "FAILED", "data" => %{"error" => error}} -> error
        _ -> nil
      end
    end)
  end

  defp create_jules_session(api_key, description, opts) do
    repo = Keyword.get(opts, :repo)
    branch = Keyword.get(opts, :branch, "main")
    auto_pr = Keyword.get(opts, :auto_pr, true)
    require_approval = Keyword.get(opts, :require_plan_approval, false)

    body =
      Jason.encode!(%{
        "prompt" => description,
        "sourceContext" => %{
          "source" => "sources/github/#{repo}",
          "githubRepoContext" => %{
            "startingBranch" => branch
          }
        },
        "automationMode" => if(auto_pr, do: "AUTO_CREATE_PR", else: "MANUAL"),
        "requirePlanApproval" => require_approval,
        "title" => String.slice(description, 0, 100)
      })

    case http_post("#{@base_url}/sessions", body, api_key) do
      {:ok, %{status_code: status, body: response_body}} when status in 200..299 ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: status, body: response_body}} ->
        {:error, parse_api_error(status, response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_jules_session_status(api_key, session_id) do
    # Get activities to determine current state
    case http_get("#{@base_url}/#{session_id}/activities?pageSize=1", api_key) do
      {:ok, %{status_code: status, body: response_body}} when status in 200..299 ->
        response = Jason.decode!(response_body)
        activities = Map.get(response, "activities", [])

        status =
          case activities do
            [%{"type" => "COMPLETED"} | _] -> "completed"
            [%{"type" => "FAILED"} | _] -> "failed"
            [%{"type" => "PLAN_READY"} | _] -> "plan_ready"
            _ -> "running"
          end

        {:ok, %{"status" => status, "activities" => activities}}

      {:ok, %{status_code: status, body: response_body}} ->
        {:error, parse_api_error(status, response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp approve_jules_plan(api_key, session_id) do
    case http_post("#{@base_url}/#{session_id}:approvePlan", "{}", api_key) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: status, body: response_body}} ->
        {:error, parse_api_error(status, response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_jules_message(api_key, session_id, message) do
    body = Jason.encode!(%{"message" => message})

    case http_post("#{@base_url}/#{session_id}:sendMessage", body, api_key) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: status, body: response_body}} ->
        {:error, parse_api_error(status, response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_jules_activities(api_key, session_id) do
    case http_get("#{@base_url}/#{session_id}/activities?pageSize=30", api_key) do
      {:ok, %{status_code: status, body: response_body}} when status in 200..299 ->
        response = Jason.decode!(response_body)
        {:ok, Map.get(response, "activities", [])}

      {:ok, %{status_code: status, body: response_body}} ->
        {:error, parse_api_error(status, response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_get(url, api_key) do
    headers = [
      {"X-Goog-Api-Key", api_key},
      {"Content-Type", "application/json"}
    ]

    HTTPoison.get(url, headers, timeout: @default_timeout, recv_timeout: @default_timeout)
  end

  defp http_post(url, body, api_key) do
    headers = [
      {"X-Goog-Api-Key", api_key},
      {"Content-Type", "application/json"}
    ]

    HTTPoison.post(url, body, headers, timeout: @default_timeout, recv_timeout: @default_timeout)
  end

  defp parse_api_error(status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        "Jules API error (#{status}): #{message}"

      {:ok, data} ->
        "Jules API error (#{status}): #{inspect(data)}"

      _ ->
        "Jules API error (#{status}): #{body}"
    end
  end

  defp parse_api_error(status, _), do: "Jules API error (#{status})"
end
