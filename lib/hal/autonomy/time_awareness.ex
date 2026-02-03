defmodule HAL.Autonomy.TimeAwareness do
  @moduledoc """
  Time-aware decision making for autonomous work.

  Determines when it's appropriate for HAL to work or reach out to the user,
  respecting quiet hours, busy periods, and user preferences.

  ## Configuration

  Time settings can be configured in workspace/USER.md or via application config:

      config :hal, HAL.Autonomy.TimeAwareness,
        timezone: "Australia/Sydney",
        quiet_hours_start: 23,
        quiet_hours_end: 8,
        work_hours_start: 9,
        work_hours_end: 18

  ## Usage

      # Check if it's appropriate to work
      iex> TimeAwareness.appropriate_to_work?()
      {:yes, :clear_to_work}

      # Check if we should reach out (with urgency override)
      iex> TimeAwareness.appropriate_to_reach_out?(:urgent)
      true

      # Get current period context
      iex> TimeAwareness.get_current_period()
      %{period: :work_hours, hour: 14, can_work: true, can_reach_out: true}
  """

  require Logger

  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")

  # Default configuration (can be overridden)
  @default_config %{
    timezone: "UTC",
    quiet_hours_start: 23,
    quiet_hours_end: 8,
    work_hours_start: 9,
    work_hours_end: 18
  }

  @doc """
  Determine if it's appropriate to do autonomous work.

  Returns {:yes, reason} or {:no, reason}.

  ## Factors considered
    - Quiet hours (late night/early morning)
    - User marked as busy
    - Focus mode enabled
  """
  @spec appropriate_to_work?() :: {:yes, atom()} | {:no, atom()}
  def appropriate_to_work? do
    config = get_config()
    current = get_current_time(config.timezone)
    hour = current.hour

    cond do
      # Quiet hours check
      in_quiet_hours?(hour, config) ->
        {:no, :quiet_hours}

      # Check if user marked as busy
      user_is_busy?() ->
        {:no, :user_busy}

      # Check for focus mode
      focus_mode_enabled?() ->
        {:no, :focus_mode}

      # All clear
      true ->
        {:yes, :clear_to_work}
    end
  end

  @doc """
  Determine if it's appropriate to reach out to the user.

  More restrictive than work - considers if the notification is worth interrupting.

  ## Parameters
    - urgency: :normal, :important, or :urgent

  ## Returns
    - true if should reach out
    - false if should stay silent
  """
  @spec appropriate_to_reach_out?(atom()) :: boolean()
  def appropriate_to_reach_out?(urgency \\ :normal) do
    case {appropriate_to_work?(), urgency} do
      # Urgent overrides quiet hours (but not focus mode)
      {{:no, :quiet_hours}, :urgent} -> true
      {{:no, :focus_mode}, _} -> false
      {{:no, :user_busy}, :urgent} -> true
      {{:no, _}, _} -> false
      {{:yes, _}, _} -> true
    end
  end

  @doc """
  Get the current time period context.

  Returns a map with all relevant time information for decision making.
  """
  @spec get_current_period() :: map()
  def get_current_period do
    config = get_config()
    current = get_current_time(config.timezone)
    hour = current.hour

    period = determine_period(hour, config)
    {can_work, work_reason} = appropriate_to_work?()

    %{
      period: period,
      hour: hour,
      minute: current.minute,
      day_of_week: Date.day_of_week(current),
      is_weekend: Date.day_of_week(current) in [6, 7],
      can_work: can_work == :yes,
      work_reason: work_reason,
      can_reach_out: appropriate_to_reach_out?(:normal),
      timezone: config.timezone,
      local_time: current
    }
  end

  @doc """
  Check if we're in quiet hours.
  """
  @spec in_quiet_hours?() :: boolean()
  def in_quiet_hours? do
    config = get_config()
    current = get_current_time(config.timezone)
    in_quiet_hours?(current.hour, config)
  end

  @doc """
  Check if we're in work hours.
  """
  @spec in_work_hours?() :: boolean()
  def in_work_hours? do
    config = get_config()
    current = get_current_time(config.timezone)
    in_work_hours?(current.hour, config)
  end

  @doc """
  Get time until next work period starts.

  Useful for scheduling work to start at appropriate time.

  ## Returns
    - {:ok, minutes} if currently not in work hours
    - :now if already in work hours
  """
  @spec time_until_work_hours() :: {:ok, non_neg_integer()} | :now
  def time_until_work_hours do
    if in_work_hours?() do
      :now
    else
      config = get_config()
      current = get_current_time(config.timezone)

      # Calculate minutes until work_hours_start
      current_minutes = current.hour * 60 + current.minute
      work_start_minutes = config.work_hours_start * 60

      minutes_until =
        if current_minutes < work_start_minutes do
          work_start_minutes - current_minutes
        else
          # Tomorrow
          24 * 60 - current_minutes + work_start_minutes
        end

      {:ok, minutes_until}
    end
  end

  @doc """
  Set user as busy (temporary flag).

  ## Parameters
    - duration_minutes: How long to mark as busy (default: 60)
  """
  @spec set_user_busy(pos_integer()) :: :ok
  def set_user_busy(duration_minutes \\ 60) do
    busy_until = DateTime.add(DateTime.utc_now(), duration_minutes, :minute)
    :persistent_term.put({__MODULE__, :busy_until}, busy_until)
    :ok
  end

  @doc """
  Clear user busy status.
  """
  @spec clear_user_busy() :: :ok
  def clear_user_busy do
    :persistent_term.erase({__MODULE__, :busy_until})
    :ok
  end

  @doc """
  Enable focus mode (no interruptions).

  ## Parameters
    - duration_minutes: How long focus mode lasts (default: 120)
  """
  @spec enable_focus_mode(pos_integer()) :: :ok
  def enable_focus_mode(duration_minutes \\ 120) do
    focus_until = DateTime.add(DateTime.utc_now(), duration_minutes, :minute)
    :persistent_term.put({__MODULE__, :focus_until}, focus_until)
    Logger.info("Focus mode enabled for #{duration_minutes} minutes")
    :ok
  end

  @doc """
  Disable focus mode.
  """
  @spec disable_focus_mode() :: :ok
  def disable_focus_mode do
    :persistent_term.erase({__MODULE__, :focus_until})
    Logger.info("Focus mode disabled")
    :ok
  end

  # Private Functions

  defp get_config do
    # Try to load from workspace/USER.md or application config
    app_config = Application.get_env(:hal, __MODULE__, [])

    @default_config
    |> Map.merge(Map.new(app_config))
    |> maybe_load_user_preferences()
  end

  defp maybe_load_user_preferences(config) do
    user_file = Path.join(@workspace_dir, "USER.md")

    case File.read(user_file) do
      {:ok, content} ->
        parse_user_preferences(content, config)

      {:error, _} ->
        config
    end
  end

  defp parse_user_preferences(content, config) do
    # Look for time preferences in USER.md
    # Format: timezone: Australia/Sydney
    #         quiet_hours: 22:00-07:00
    #         work_hours: 09:00-18:00

    timezone =
      case Regex.run(~r/timezone:\s*(\S+)/i, content) do
        [_, tz] -> tz
        _ -> config.timezone
      end

    quiet_hours =
      case Regex.run(~r/quiet_hours:\s*(\d+):?\d*\s*-\s*(\d+)/i, content) do
        [_, start_h, end_h] ->
          {String.to_integer(start_h), String.to_integer(end_h)}

        _ ->
          {config.quiet_hours_start, config.quiet_hours_end}
      end

    work_hours =
      case Regex.run(~r/work_hours:\s*(\d+):?\d*\s*-\s*(\d+)/i, content) do
        [_, start_h, end_h] ->
          {String.to_integer(start_h), String.to_integer(end_h)}

        _ ->
          {config.work_hours_start, config.work_hours_end}
      end

    {quiet_start, quiet_end} = quiet_hours
    {work_start, work_end} = work_hours

    %{
      config
      | timezone: timezone,
        quiet_hours_start: quiet_start,
        quiet_hours_end: quiet_end,
        work_hours_start: work_start,
        work_hours_end: work_end
    }
  end

  defp get_current_time(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} ->
        dt

      {:error, _} ->
        # Fallback to UTC if timezone invalid
        DateTime.utc_now()
    end
  end

  defp in_quiet_hours?(hour, config) do
    start_h = config.quiet_hours_start
    end_h = config.quiet_hours_end

    if start_h > end_h do
      # Spans midnight (e.g., 23:00-08:00)
      hour >= start_h or hour < end_h
    else
      # Same day range
      hour >= start_h and hour < end_h
    end
  end

  defp in_work_hours?(hour, config) do
    hour >= config.work_hours_start and hour < config.work_hours_end
  end

  defp determine_period(hour, config) do
    cond do
      in_quiet_hours?(hour, config) -> :quiet_hours
      in_work_hours?(hour, config) -> :work_hours
      hour < config.work_hours_start -> :morning
      true -> :evening
    end
  end

  defp user_is_busy? do
    case :persistent_term.get({__MODULE__, :busy_until}, nil) do
      nil ->
        false

      busy_until ->
        case DateTime.compare(DateTime.utc_now(), busy_until) do
          :lt ->
            true

          _ ->
            # Expired, clear it
            clear_user_busy()
            false
        end
    end
  end

  defp focus_mode_enabled? do
    case :persistent_term.get({__MODULE__, :focus_until}, nil) do
      nil ->
        false

      focus_until ->
        case DateTime.compare(DateTime.utc_now(), focus_until) do
          :lt ->
            true

          _ ->
            # Expired, clear it
            disable_focus_mode()
            false
        end
    end
  end
end
