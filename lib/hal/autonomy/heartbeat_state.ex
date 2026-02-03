defmodule HAL.Autonomy.HeartbeatState do
  @moduledoc """
  Track heartbeat check state to prevent redundant work.

  Stores when each check type was last performed in workspace/heartbeat-state.json.
  Enables rotation through checks and prevents redundant API calls.

  ## Usage

      # Check if email should be checked (2 hour interval)
      iex> HeartbeatState.should_check?(:email, 2)
      true

      # Record that email was checked
      iex> HeartbeatState.record_check(:email)
      :ok

      # Get next due check from rotation
      iex> HeartbeatState.get_next_due_check()
      {:email, 2}
  """

  require Logger

  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")
  @state_file "heartbeat-state.json"

  # Default check intervals (hours)
  @check_intervals %{
    # User-created autonomous goals (highest priority)
    goals: 1,
    email: 2,
    calendar: 4,
    projects: 6,
    memory_maintenance: 24,
    weather: 8,
    notifications: 1
  }

  @doc """
  Check if a specific check type is due based on interval.

  ## Parameters
    - check_type: Atom like :email, :calendar, :projects
    - min_interval_hours: Minimum hours between checks (default from @check_intervals)

  ## Returns
    - true if check is due
    - false if recently checked
  """
  @spec should_check?(atom(), pos_integer() | nil) :: boolean()
  def should_check?(check_type, min_interval_hours \\ nil) do
    interval = min_interval_hours || Map.get(@check_intervals, check_type, 2)
    state = load_state()
    last_check = get_in(state, ["lastChecks", to_string(check_type)])

    cond do
      is_nil(last_check) ->
        true

      hours_since(last_check) >= interval ->
        true

      true ->
        false
    end
  end

  @doc """
  Record that a check was performed.

  ## Parameters
    - check_type: Atom like :email, :calendar
    - metadata: Optional map of additional info to store

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  @spec record_check(atom(), map()) :: :ok | {:error, term()}
  def record_check(check_type, metadata \\ %{}) do
    state = load_state()

    updated =
      state
      |> put_in(["lastChecks", to_string(check_type)], now_unix())
      |> put_in(["lastCheckMetadata", to_string(check_type)], metadata)

    save_state(updated)
  end

  @doc """
  Get all checks that are currently due.

  ## Returns
    - List of {check_type, hours_since_last} tuples
  """
  @spec get_due_checks() :: [{atom(), number()}]
  def get_due_checks do
    @check_intervals
    |> Enum.filter(fn {check_type, _interval} ->
      should_check?(check_type)
    end)
    |> Enum.map(fn {check_type, interval} ->
      state = load_state()
      last = get_in(state, ["lastChecks", to_string(check_type)])
      hours = if last, do: hours_since(last), else: :never
      {check_type, hours, interval}
    end)
    |> Enum.sort_by(fn {_type, hours, _interval} ->
      # Prioritize things never checked, then oldest
      case hours do
        :never -> 999_999
        h -> -h
      end
    end)
    |> Enum.map(fn {type, hours, _interval} -> {type, hours} end)
  end

  @doc """
  Get the next check that should be performed (rotation).

  Returns the check that's been waiting longest relative to its interval.

  ## Returns
    - {check_type, hours_overdue} if a check is due
    - nil if nothing is due
  """
  @spec get_next_due_check() :: {atom(), number()} | nil
  def get_next_due_check do
    case get_due_checks() do
      [] -> nil
      [first | _] -> first
    end
  end

  @doc """
  Get the full state including all timestamps.
  """
  @spec get_state() :: map()
  def get_state do
    load_state()
  end

  @doc """
  Reset state for a specific check type (for testing).
  """
  @spec reset_check(atom()) :: :ok
  def reset_check(check_type) do
    state = load_state()

    updated =
      state
      |> update_in(["lastChecks"], &Map.delete(&1 || %{}, to_string(check_type)))
      |> update_in(["lastCheckMetadata"], &Map.delete(&1 || %{}, to_string(check_type)))

    save_state(updated)
  end

  @doc """
  Get the configured check intervals.
  """
  @spec get_check_intervals() :: map()
  def get_check_intervals, do: @check_intervals

  # Private Functions

  defp load_state do
    path = state_file_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, state} ->
            ensure_structure(state)

          {:error, _} ->
            Logger.warning("Invalid heartbeat-state.json, resetting")
            initial_state()
        end

      {:error, :enoent} ->
        initial_state()

      {:error, reason} ->
        Logger.warning("Failed to read heartbeat-state.json: #{inspect(reason)}")
        initial_state()
    end
  end

  defp save_state(state) do
    path = state_file_path()

    # Ensure workspace directory exists
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, Jason.encode!(state, pretty: true)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to write heartbeat-state.json: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp state_file_path do
    Path.join(@workspace_dir, @state_file)
  end

  defp initial_state do
    %{
      "lastChecks" => %{},
      "lastCheckMetadata" => %{},
      "createdAt" => now_unix()
    }
  end

  defp ensure_structure(state) do
    state
    |> Map.put_new("lastChecks", %{})
    |> Map.put_new("lastCheckMetadata", %{})
  end

  defp now_unix do
    DateTime.utc_now() |> DateTime.to_unix()
  end

  defp hours_since(unix_timestamp) when is_integer(unix_timestamp) do
    now = now_unix()
    (now - unix_timestamp) / 3600
  end

  defp hours_since(_), do: 999_999
end
