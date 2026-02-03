defmodule Hal.Dashboard do
  @moduledoc """
  Context module for dashboard-related queries and operations.

  Provides functions to query sessions, messages, and statistics
  for the LiveView dashboard.
  """

  import Ecto.Query
  alias Hal.Gateway.{Session, Message}
  alias Hal.Accounts.User
  alias Hal.Repo

  # PubSub topics
  @sessions_topic "sessions"

  @doc """
  Returns the PubSub topic for session events.
  """
  def sessions_topic, do: @sessions_topic

  @doc """
  Returns the PubSub topic for a specific session's events.
  """
  def session_topic(session_id), do: "sessions:#{session_id}"

  @doc """
  Subscribe to session events.
  """
  def subscribe_to_sessions do
    Phoenix.PubSub.subscribe(Hal.PubSub, @sessions_topic)
  end

  @doc """
  Subscribe to a specific session's events.
  """
  def subscribe_to_session(session_id) do
    Phoenix.PubSub.subscribe(Hal.PubSub, session_topic(session_id))
  end

  @doc """
  Unsubscribe from a specific session's events.
  """
  def unsubscribe_from_session(session_id) do
    Phoenix.PubSub.unsubscribe(Hal.PubSub, session_topic(session_id))
  end

  @doc """
  Broadcast a session event.
  """
  def broadcast_session_event(event, payload) do
    Phoenix.PubSub.broadcast(Hal.PubSub, @sessions_topic, {event, payload})
  end

  @doc """
  Broadcast a message event for a specific session.
  """
  def broadcast_message_event(session_id, event, payload) do
    Phoenix.PubSub.broadcast(Hal.PubSub, session_topic(session_id), {event, payload})
  end

  # ============================================================================
  # Session Queries
  # ============================================================================

  @doc """
  Lists all active sessions with preloaded user information.

  ## Options

    * `:channel_type` - Filter by channel type (telegram, slack, discord)
    * `:search` - Search by channel_id or user username
    * `:limit` - Maximum number of sessions to return (default: 50)
    * `:offset` - Number of sessions to skip (default: 0)

  ## Examples

      iex> list_active_sessions()
      [%Session{}, ...]

      iex> list_active_sessions(channel_type: "telegram", limit: 10)
      [%Session{}, ...]
  """
  def list_active_sessions(opts \\ []) do
    channel_type = Keyword.get(opts, :channel_type)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from s in Session,
        where: s.status == "active",
        order_by: [desc: s.last_activity],
        limit: ^limit,
        offset: ^offset,
        preload: [:user]

    query =
      if channel_type && channel_type != "" && channel_type != "all" do
        from s in query, where: s.channel_type == ^channel_type
      else
        query
      end

    query =
      if search && search != "" do
        search_term = "%#{search}%"

        from s in query,
          left_join: u in assoc(s, :user),
          where:
            ilike(s.channel_id, ^search_term) or
              ilike(u.username, ^search_term)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Counts active sessions.

  ## Options

    * `:channel_type` - Filter by channel type
  """
  def count_active_sessions(opts \\ []) do
    channel_type = Keyword.get(opts, :channel_type)

    query =
      from s in Session,
        where: s.status == "active",
        select: count(s.id)

    query =
      if channel_type && channel_type != "" && channel_type != "all" do
        from s in query, where: s.channel_type == ^channel_type
      else
        query
      end

    Repo.one(query) || 0
  end

  @doc """
  Counts active sessions grouped by channel type.
  """
  def count_sessions_by_channel do
    query =
      from s in Session,
        where: s.status == "active",
        group_by: s.channel_type,
        select: {s.channel_type, count(s.id)}

    Repo.all(query) |> Map.new()
  end

  @doc """
  Gets a single session by ID with preloaded associations.
  """
  def get_session(id) do
    Session
    |> Repo.get(id)
    |> Repo.preload([:user, :messages])
  end

  @doc """
  Gets a session with only user preloaded (no messages).
  """
  def get_session_with_user(id) do
    Session
    |> Repo.get(id)
    |> Repo.preload(:user)
  end

  # ============================================================================
  # Message Queries
  # ============================================================================

  @doc """
  Lists messages for a session, ordered by creation time.

  ## Options

    * `:limit` - Maximum number of messages to return (default: 100)
    * `:before` - Only return messages before this timestamp
    * `:after` - Only return messages after this timestamp
  """
  def list_messages_for_session(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    before_time = Keyword.get(opts, :before)
    after_time = Keyword.get(opts, :after)

    query =
      from m in Message,
        where: m.session_id == ^session_id,
        order_by: [asc: m.inserted_at],
        limit: ^limit

    query =
      if before_time do
        from m in query, where: m.inserted_at < ^before_time
      else
        query
      end

    query =
      if after_time do
        from m in query, where: m.inserted_at > ^after_time
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Counts messages for today (since midnight UTC).
  """
  def count_messages_today do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    query =
      from m in Message,
        where: m.inserted_at >= ^today_start,
        select: count(m.id)

    Repo.one(query) || 0
  end

  @doc """
  Counts total messages.
  """
  def count_total_messages do
    query = from m in Message, select: count(m.id)
    Repo.one(query) || 0
  end

  @doc """
  Counts messages for a specific session.
  """
  def count_messages_for_session(session_id) do
    query =
      from m in Message,
        where: m.session_id == ^session_id,
        select: count(m.id)

    Repo.one(query) || 0
  end

  @doc """
  Gets the last message for a session.
  """
  def get_last_message_for_session(session_id) do
    query =
      from m in Message,
        where: m.session_id == ^session_id,
        order_by: [desc: m.inserted_at],
        limit: 1

    Repo.one(query)
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Returns dashboard statistics.

  Returns a map with:
    * `:active_sessions` - Number of active sessions
    * `:messages_today` - Number of messages sent today
    * `:channels_connected` - Map of channel type to count
    * `:total_messages` - Total number of messages ever
    * `:uptime` - Application uptime (if available)
  """
  def get_stats do
    %{
      active_sessions: count_active_sessions(),
      messages_today: count_messages_today(),
      channels_connected: count_sessions_by_channel(),
      total_messages: count_total_messages(),
      uptime: get_uptime()
    }
  end

  @doc """
  Gets application uptime.
  """
  def get_uptime do
    case :erlang.statistics(:wall_clock) do
      {uptime_ms, _} ->
        format_uptime(uptime_ms)

      _ ->
        "N/A"
    end
  end

  defp format_uptime(ms) when ms < 60_000 do
    "#{div(ms, 1000)}s"
  end

  defp format_uptime(ms) when ms < 3_600_000 do
    minutes = div(ms, 60_000)
    "#{minutes}m"
  end

  defp format_uptime(ms) when ms < 86_400_000 do
    hours = div(ms, 3_600_000)
    minutes = div(rem(ms, 3_600_000), 60_000)
    "#{hours}h #{minutes}m"
  end

  defp format_uptime(ms) do
    days = div(ms, 86_400_000)
    hours = div(rem(ms, 86_400_000), 3_600_000)
    "#{days}d #{hours}h"
  end

  # ============================================================================
  # User Queries
  # ============================================================================

  @doc """
  Counts total users.
  """
  def count_users do
    query = from u in User, select: count(u.id)
    Repo.one(query) || 0
  end

  @doc """
  Counts users by platform.
  """
  def count_users_by_platform do
    query =
      from u in User,
        group_by: u.platform,
        select: {u.platform, count(u.id)}

    Repo.all(query) |> Map.new()
  end
end
