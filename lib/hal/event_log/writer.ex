defmodule HAL.EventLog.Writer do
  @moduledoc """
  Async buffered writer for EventLog.

  Decouples callers from disk I/O by:
  - Buffering writes in memory
  - Flushing periodically or when buffer is full
  - Using async file operations

  This prevents disk I/O spikes from blocking GenServers.
  """
  use GenServer

  require Logger

  @flush_interval_ms 1_000
  @max_buffer_size 100

  # Public API

  @doc """
  Starts the writer process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    log_file = Keyword.get(opts, :log_file)
    GenServer.start_link(__MODULE__, %{log_file: log_file}, name: name)
  end

  @doc """
  Queues an event for writing. Non-blocking.
  """
  @spec write(String.t()) :: :ok
  def write(json_line) do
    GenServer.cast(__MODULE__, {:write, json_line})
  end

  @doc """
  Forces an immediate flush. Blocks until complete.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush, 10_000)
  end

  @doc """
  Returns buffer stats for monitoring.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # GenServer Callbacks

  @impl true
  def init(%{log_file: log_file}) do
    # Schedule periodic flush
    schedule_flush()

    state = %{
      log_file: log_file,
      buffer: [],
      buffer_size: 0,
      total_writes: 0,
      total_flushes: 0,
      last_flush: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:write, json_line}, state) do
    new_buffer = [json_line | state.buffer]
    new_size = state.buffer_size + 1

    state = %{state | buffer: new_buffer, buffer_size: new_size}

    # Flush if buffer is full
    if new_size >= @max_buffer_size do
      {:noreply, do_flush(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = do_flush(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      buffer_size: state.buffer_size,
      total_writes: state.total_writes,
      total_flushes: state.total_flushes,
      last_flush: state.last_flush
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:scheduled_flush, state) do
    schedule_flush()

    if state.buffer_size > 0 do
      {:noreply, do_flush(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp schedule_flush do
    Process.send_after(self(), :scheduled_flush, @flush_interval_ms)
  end

  defp do_flush(%{buffer: []} = state), do: state

  defp do_flush(state) do
    # Reverse buffer to write in correct order
    lines = state.buffer |> Enum.reverse() |> Enum.join("\n")
    content = lines <> "\n"

    # Write synchronously - GenServer already decouples callers via cast/buffering,
    # so we don't need async I/O here. Synchronous writes prevent race conditions.
    write_to_file(state.log_file, content)

    %{
      state
      | buffer: [],
        buffer_size: 0,
        total_writes: state.total_writes + length(state.buffer),
        total_flushes: state.total_flushes + 1,
        last_flush: DateTime.utc_now()
    }
  end

  defp write_to_file(log_file, content) do
    case File.write(log_file, content, [:append]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("EventLog.Writer: Failed to write - #{inspect(reason)}")
        {:error, reason}
    end
  end
end
