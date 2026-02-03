defmodule HAL.Integrations.Tasks do
  @moduledoc """
  Linear API integration for task management.

  Provides functions to interact with Linear tasks (issues) including:
  - Listing tasks with filters
  - Creating new tasks
  - Updating existing tasks
  - Marking tasks as complete

  ## Configuration

  The Linear API key must be configured in runtime.exs:

      config :hal, HAL.Integrations.Tasks,
        api_key: System.get_env("LINEAR_API_KEY")

  ## API Reference

  Linear uses GraphQL for all API operations.
  API Documentation: https://developers.linear.app/docs/graphql/working-with-the-graphql-api
  """

  require Logger

  @api_url "https://api.linear.app/graphql"
  @default_timeout 15_000
  # Reserved for future resilience integration:
  # - Rate limiter: :tasks_rate_limiter
  # - Circuit breaker: :tasks_circuit_breaker

  # TODO: Configure Linear API key in runtime.exs
  # config :hal, HAL.Integrations.Tasks, api_key: System.get_env("LINEAR_API_KEY")

  @type task_id :: String.t()
  @type team_id :: String.t()

  @type task :: %{
          id: String.t(),
          title: String.t(),
          description: String.t() | nil,
          state: %{
            id: String.t(),
            name: String.t()
          },
          priority: integer(),
          assignee:
            %{
              id: String.t(),
              name: String.t()
            }
            | nil,
          created_at: String.t(),
          updated_at: String.t(),
          url: String.t()
        }

  @type filter_opts :: [
          team_id: team_id(),
          assignee_id: String.t(),
          state: String.t(),
          priority: integer(),
          limit: integer()
        ]

  @type create_opts :: [
          team_id: team_id(),
          title: String.t(),
          description: String.t(),
          assignee_id: String.t(),
          priority: integer(),
          state_id: String.t()
        ]

  @type update_opts :: [
          title: String.t(),
          description: String.t(),
          assignee_id: String.t(),
          priority: integer(),
          state_id: String.t()
        ]

  # Public API

  @doc """
  Lists tasks (issues) from Linear with optional filters.

  ## Options

    * `:team_id` - Filter by team ID (required for most queries)
    * `:assignee_id` - Filter by assignee user ID
    * `:state` - Filter by state name (e.g., "In Progress", "Todo")
    * `:priority` - Filter by priority (0-4, where 0 is no priority)
    * `:limit` - Maximum number of results (default: 50)

  ## Examples

      # List all tasks for a team
      {:ok, tasks} = Tasks.list_tasks(team_id: "team_123")

      # List tasks assigned to a specific user
      {:ok, tasks} = Tasks.list_tasks(team_id: "team_123", assignee_id: "user_456")

      # List high priority tasks in progress
      {:ok, tasks} = Tasks.list_tasks(
        team_id: "team_123",
        state: "In Progress",
        priority: 1
      )

  ## Returns

    * `{:ok, [task()]}` - List of tasks matching the filters
    * `{:error, reason}` - Error description
  """
  @spec list_tasks(filter_opts()) :: {:ok, [task()]} | {:error, String.t()}
  def list_tasks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    filter = build_filter(opts)

    query = """
    query($filter: IssueFilter, $first: Int) {
      issues(filter: $filter, first: $first) {
        nodes {
          id
          title
          description
          priority
          url
          createdAt
          updatedAt
          state {
            id
            name
          }
          assignee {
            id
            name
          }
        }
      }
    }
    """

    variables = %{
      filter: filter,
      first: limit
    }

    case graphql_request(query, variables) do
      {:ok, %{"data" => %{"issues" => %{"nodes" => tasks}}}} ->
        formatted_tasks = Enum.map(tasks, &format_task/1)
        {:ok, formatted_tasks}

      {:ok, %{"errors" => errors}} ->
        {:error, format_graphql_errors(errors)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new task (issue) in Linear.

  ## Required Options

    * `:team_id` - The team ID where the task will be created
    * `:title` - Task title

  ## Optional Options

    * `:description` - Task description (Markdown supported)
    * `:assignee_id` - User ID to assign the task to
    * `:priority` - Priority level (0-4, where 0 is no priority, 1 is urgent)
    * `:state_id` - State ID (e.g., "Todo", "In Progress")

  ## Examples

      # Create a simple task
      {:ok, task} = Tasks.create_task(
        team_id: "team_123",
        title: "Implement new feature"
      )

      # Create a task with all options
      {:ok, task} = Tasks.create_task(
        team_id: "team_123",
        title: "Fix critical bug",
        description: "Bug causing crashes in production",
        assignee_id: "user_456",
        priority: 1,
        state_id: "state_in_progress"
      )

  ## Returns

    * `{:ok, task()}` - The created task
    * `{:error, reason}` - Error description
  """
  @spec create_task(create_opts()) :: {:ok, task()} | {:error, String.t()}
  def create_task(opts) do
    with :ok <- validate_required(opts, [:team_id, :title]) do
      input = build_create_input(opts)

      query = """
      mutation($input: IssueCreateInput!) {
        issueCreate(input: $input) {
          success
          issue {
            id
            title
            description
            priority
            url
            createdAt
            updatedAt
            state {
              id
              name
            }
            assignee {
              id
              name
            }
          }
        }
      }
      """

      variables = %{input: input}

      case graphql_request(query, variables) do
        {:ok, %{"data" => %{"issueCreate" => %{"success" => true, "issue" => task}}}} ->
          {:ok, format_task(task)}

        {:ok, %{"data" => %{"issueCreate" => %{"success" => false}}}} ->
          {:error, "Failed to create task"}

        {:ok, %{"errors" => errors}} ->
          {:error, format_graphql_errors(errors)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Updates an existing task in Linear.

  ## Arguments

    * `task_id` - The ID of the task to update

  ## Options

    * `:title` - New task title
    * `:description` - New task description
    * `:assignee_id` - New assignee user ID
    * `:priority` - New priority level (0-4)
    * `:state_id` - New state ID

  ## Examples

      # Update task title
      {:ok, task} = Tasks.update_task("issue_123", title: "Updated title")

      # Update multiple fields
      {:ok, task} = Tasks.update_task("issue_123",
        title: "Updated title",
        description: "New description",
        priority: 2
      )

  ## Returns

    * `{:ok, task()}` - The updated task
    * `{:error, reason}` - Error description
  """
  @spec update_task(task_id(), update_opts()) :: {:ok, task()} | {:error, String.t()}
  def update_task(task_id, opts) when is_binary(task_id) and is_list(opts) do
    if opts == [] do
      {:error, "No update fields provided"}
    else
      input = build_update_input(task_id, opts)

      query = """
      mutation($input: IssueUpdateInput!, $id: String!) {
        issueUpdate(input: $input, id: $id) {
          success
          issue {
            id
            title
            description
            priority
            url
            createdAt
            updatedAt
            state {
              id
              name
            }
            assignee {
              id
              name
            }
          }
        }
      }
      """

      variables = %{
        input: input,
        id: task_id
      }

      case graphql_request(query, variables) do
        {:ok, %{"data" => %{"issueUpdate" => %{"success" => true, "issue" => task}}}} ->
          {:ok, format_task(task)}

        {:ok, %{"data" => %{"issueUpdate" => %{"success" => false}}}} ->
          {:error, "Failed to update task"}

        {:ok, %{"errors" => errors}} ->
          {:error, format_graphql_errors(errors)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Marks a task as complete in Linear.

  This is a convenience function that updates the task's state to "Done".
  Note: The actual state ID for "Done" may vary by team configuration.

  ## Arguments

    * `task_id` - The ID of the task to complete

  ## Examples

      {:ok, task} = Tasks.complete_task("issue_123")

  ## Returns

    * `{:ok, task()}` - The completed task
    * `{:error, reason}` - Error description

  ## Note

  If your team uses a different state name for completed tasks,
  you can use `update_task/2` with the appropriate `state_id`.
  """
  @spec complete_task(task_id()) :: {:ok, task()} | {:error, String.t()}
  def complete_task(task_id) when is_binary(task_id) do
    # First, get the task to find its team
    # Then get the team's workflow states to find the "Done" state
    # For now, we'll use a common approach: find the completed state

    query = """
    query($id: String!) {
      issue(id: $id) {
        id
        team {
          states {
            nodes {
              id
              name
              type
            }
          }
        }
      }
    }
    """

    variables = %{id: task_id}

    with {:ok, %{"data" => %{"issue" => issue_data}}} <- graphql_request(query, variables),
         {:ok, done_state_id} <- find_completed_state(issue_data) do
      update_task(task_id, state_id: done_state_id)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Failed to find completed state for task"}
    end
  end

  # Private Functions

  defp get_api_key do
    Application.get_env(:hal, __MODULE__, [])
    |> Keyword.get(:api_key)
  end

  defp http_client do
    Application.get_env(:hal, :httpoison_module, HTTPoison)
  end

  defp graphql_request(query, variables) do
    api_key = get_api_key()

    if is_binary(api_key) and api_key != "" do
      headers = [
        {"Authorization", api_key},
        {"Content-Type", "application/json"}
      ]

      body =
        Jason.encode!(%{
          query: query,
          variables: variables
        })

      # Note: Resilience features (circuit breaker, retry, rate limiting) can be added
      # via HAL.Resilience.call wrapper when needed in production
      case http_client().post(@api_url, body, headers, timeout: @default_timeout) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          Jason.decode(response_body)

        {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
          Logger.error("Linear API error: #{status_code} - #{error_body}")
          {:error, "API request failed with status #{status_code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Linear API request failed: #{inspect(reason)}")
          {:error, "Network error: #{inspect(reason)}"}
      end
    else
      {:error, "LINEAR_API_KEY not configured"}
    end
  end

  defp build_filter(opts) do
    filter = %{}

    filter =
      if team_id = Keyword.get(opts, :team_id) do
        Map.put(filter, :team, %{id: %{eq: team_id}})
      else
        filter
      end

    filter =
      if assignee_id = Keyword.get(opts, :assignee_id) do
        Map.put(filter, :assignee, %{id: %{eq: assignee_id}})
      else
        filter
      end

    filter =
      if state = Keyword.get(opts, :state) do
        Map.put(filter, :state, %{name: %{eq: state}})
      else
        filter
      end

    filter =
      if priority = Keyword.get(opts, :priority) do
        Map.put(filter, :priority, %{eq: priority})
      else
        filter
      end

    filter
  end

  defp build_create_input(opts) do
    input = %{
      teamId: Keyword.fetch!(opts, :team_id),
      title: Keyword.fetch!(opts, :title)
    }

    input =
      if description = Keyword.get(opts, :description) do
        Map.put(input, :description, description)
      else
        input
      end

    input =
      if assignee_id = Keyword.get(opts, :assignee_id) do
        Map.put(input, :assigneeId, assignee_id)
      else
        input
      end

    input =
      if priority = Keyword.get(opts, :priority) do
        Map.put(input, :priority, priority)
      else
        input
      end

    input =
      if state_id = Keyword.get(opts, :state_id) do
        Map.put(input, :stateId, state_id)
      else
        input
      end

    input
  end

  defp build_update_input(task_id, opts) do
    input = %{id: task_id}

    input =
      if title = Keyword.get(opts, :title) do
        Map.put(input, :title, title)
      else
        input
      end

    input =
      if description = Keyword.get(opts, :description) do
        Map.put(input, :description, description)
      else
        input
      end

    input =
      if assignee_id = Keyword.get(opts, :assignee_id) do
        Map.put(input, :assigneeId, assignee_id)
      else
        input
      end

    input =
      if priority = Keyword.get(opts, :priority) do
        Map.put(input, :priority, priority)
      else
        input
      end

    input =
      if state_id = Keyword.get(opts, :state_id) do
        Map.put(input, :stateId, state_id)
      else
        input
      end

    input
  end

  defp format_task(task) do
    %{
      id: task["id"],
      title: task["title"],
      description: task["description"],
      priority: task["priority"],
      url: task["url"],
      created_at: task["createdAt"],
      updated_at: task["updatedAt"],
      state: %{
        id: get_in(task, ["state", "id"]),
        name: get_in(task, ["state", "name"])
      },
      assignee:
        if assignee = task["assignee"] do
          %{
            id: assignee["id"],
            name: assignee["name"]
          }
        else
          nil
        end
    }
  end

  defp find_completed_state(%{"team" => %{"states" => %{"nodes" => states}}}) do
    # Look for a state with type "completed" or name containing "Done"
    done_state =
      Enum.find(states, fn state ->
        state["type"] == "completed" or
          String.contains?(String.downcase(state["name"]), "done")
      end)

    case done_state do
      %{"id" => id} -> {:ok, id}
      nil -> {:error, "No completed state found"}
    end
  end

  defp find_completed_state(_), do: {:error, "Invalid issue data"}

  defp format_graphql_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(& &1["message"])
    |> Enum.join(", ")
  end

  defp format_graphql_errors(_), do: "Unknown GraphQL error"

  defp validate_required(opts, required_keys) do
    missing =
      Enum.filter(required_keys, fn key ->
        !Keyword.has_key?(opts, key)
      end)

    case missing do
      [] -> :ok
      keys -> {:error, "Missing required fields: #{inspect(keys)}"}
    end
  end
end
