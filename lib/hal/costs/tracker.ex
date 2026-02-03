defmodule HAL.Costs.Tracker do
  @moduledoc """
  Token and cost tracking for all AI providers.

  Tracks usage across:
  - Claude (Anthropic)
  - Gemini (Google)
  - Codex (OpenAI)
  - Jules (Google)

  All costs are stored in cents to avoid floating-point precision issues.

  ## Usage

      # Track a message
      Tracker.track_message("claude", %{
        model: "claude-opus-4-5-20251101",
        input_tokens: 1500,
        output_tokens: 500,
        task_type: "chat"
      }, user_id: user_id)

      # Get session summary
      Tracker.get_session_summary(session_id)

      # Get daily costs
      Tracker.get_daily_costs(user_id, Date.utc_today())
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Cost per million tokens (in cents) - as of 2025
  @pricing %{
    # Claude models
    # $15/$75 per MTok
    "claude-opus-4-5-20251101" => %{input: 1500, output: 7500},
    # $3/$15 per MTok
    "claude-sonnet-4-20250514" => %{input: 300, output: 1500},
    # assume Sonnet tier
    "claude-sonnet-4-5-20250929" => %{input: 300, output: 1500},
    # $1/$5 per MTok
    "claude-haiku-3-5-20241022" => %{input: 100, output: 500},

    # Gemini models (approximate)
    "gemini-1.5-pro" => %{input: 125, output: 500},
    "gemini-1.5-flash" => %{input: 8, output: 30},
    "gemini-2.0-flash" => %{input: 10, output: 40},
    "gemini-2.5-flash" => %{input: 10, output: 40},

    # Default fallback
    "default" => %{input: 300, output: 1500}
  }

  schema "cost_records" do
    belongs_to :user, Hal.Accounts.User

    field :provider, :string
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cache_read_tokens, :integer, default: 0
    field :cache_write_tokens, :integer, default: 0
    field :cost_cents, :integer, default: 0
    field :task_type, :string
    field :session_id, :binary_id
    field :goal_id, :binary_id
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Track a message/API call.
  """
  @spec track_message(String.t(), map(), keyword()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def track_message(provider, usage, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    session_id = Keyword.get(opts, :session_id)
    goal_id = Keyword.get(opts, :goal_id)

    model = usage[:model] || usage["model"] || "default"
    input_tokens = usage[:input_tokens] || usage["input_tokens"] || 0
    output_tokens = usage[:output_tokens] || usage["output_tokens"] || 0
    cache_read = usage[:cache_read_tokens] || usage["cache_read_tokens"] || 0
    cache_write = usage[:cache_write_tokens] || usage["cache_write_tokens"] || 0
    task_type = usage[:task_type] || usage["task_type"] || "unknown"

    cost_cents = calculate_cost(model, input_tokens, output_tokens, cache_read)

    %__MODULE__{}
    |> changeset(%{
      user_id: user_id,
      provider: provider,
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_read_tokens: cache_read,
      cache_write_tokens: cache_write,
      cost_cents: cost_cents,
      task_type: task_type,
      session_id: session_id,
      goal_id: goal_id,
      metadata: usage[:metadata] || %{}
    })
    |> Repo.insert()
    |> case do
      {:ok, record} ->
        # Update budget tracking
        if user_id, do: HAL.Costs.Budget.add_cost(user_id, cost_cents)
        {:ok, record}

      error ->
        error
    end
  end

  @doc """
  Get total costs for a session.
  """
  @spec get_session_summary(Ecto.UUID.t()) :: map()
  def get_session_summary(session_id) do
    query =
      from r in __MODULE__,
        where: r.session_id == ^session_id,
        select: %{
          total_cost_cents: sum(r.cost_cents),
          total_input_tokens: sum(r.input_tokens),
          total_output_tokens: sum(r.output_tokens),
          message_count: count(r.id)
        }

    result = Repo.one(query) || %{}

    %{
      cost_cents: result[:total_cost_cents] || 0,
      cost_dollars: format_dollars(result[:total_cost_cents] || 0),
      input_tokens: result[:total_input_tokens] || 0,
      output_tokens: result[:total_output_tokens] || 0,
      message_count: result[:message_count] || 0
    }
  end

  @doc """
  Get costs aggregated by date for a user.
  """
  @spec get_daily_costs(Ecto.UUID.t(), Date.t()) :: map()
  def get_daily_costs(user_id, date) do
    start_of_day = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_of_day = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    query =
      from r in __MODULE__,
        where:
          r.user_id == ^user_id and
            r.inserted_at >= ^start_of_day and
            r.inserted_at < ^end_of_day,
        group_by: r.provider,
        select:
          {r.provider,
           %{
             cost_cents: sum(r.cost_cents),
             input_tokens: sum(r.input_tokens),
             output_tokens: sum(r.output_tokens),
             message_count: count(r.id)
           }}

    by_provider = Repo.all(query) |> Enum.into(%{})

    total_cents = by_provider |> Map.values() |> Enum.map(& &1.cost_cents) |> Enum.sum()

    %{
      date: date,
      total_cost_cents: total_cents,
      total_cost_dollars: format_dollars(total_cents),
      by_provider: by_provider
    }
  end

  @doc """
  Get costs for a date range.
  """
  @spec get_costs_in_range(Ecto.UUID.t(), Date.t(), Date.t()) :: [map()]
  def get_costs_in_range(user_id, start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(Date.add(end_date, 1), ~T[00:00:00], "Etc/UTC")

    query =
      from r in __MODULE__,
        where:
          r.user_id == ^user_id and
            r.inserted_at >= ^start_dt and
            r.inserted_at < ^end_dt,
        group_by: fragment("DATE(?)", r.inserted_at),
        order_by: fragment("DATE(?)", r.inserted_at),
        select: %{
          date: fragment("DATE(?)", r.inserted_at),
          cost_cents: sum(r.cost_cents),
          input_tokens: sum(r.input_tokens),
          output_tokens: sum(r.output_tokens)
        }

    Repo.all(query)
  end

  @doc """
  Get costs by task type for analysis.
  """
  @spec get_costs_by_task_type(Ecto.UUID.t(), keyword()) :: [map()]
  def get_costs_by_task_type(user_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    since = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

    query =
      from r in __MODULE__,
        where: r.user_id == ^user_id and r.inserted_at >= ^since,
        group_by: [r.task_type, r.provider],
        order_by: [desc: sum(r.cost_cents)],
        select: %{
          task_type: r.task_type,
          provider: r.provider,
          cost_cents: sum(r.cost_cents),
          message_count: count(r.id)
        }

    Repo.all(query)
  end

  @doc """
  Get dashboard stats for display.
  """
  @spec get_dashboard_stats(Ecto.UUID.t()) :: map()
  def get_dashboard_stats(user_id) do
    today = Date.utc_today()
    week_ago = Date.add(today, -7)
    month_ago = Date.add(today, -30)

    today_costs = get_daily_costs(user_id, today)
    week_costs = get_costs_in_range(user_id, week_ago, today)
    month_costs = get_costs_in_range(user_id, month_ago, today)

    week_total = Enum.sum(Enum.map(week_costs, & &1.cost_cents))
    month_total = Enum.sum(Enum.map(month_costs, & &1.cost_cents))

    %{
      today: today_costs,
      week_total_cents: week_total,
      week_total_dollars: format_dollars(week_total),
      month_total_cents: month_total,
      month_total_dollars: format_dollars(month_total),
      daily_history: week_costs
    }
  end

  # Changeset

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :user_id,
      :provider,
      :model,
      :input_tokens,
      :output_tokens,
      :cache_read_tokens,
      :cache_write_tokens,
      :cost_cents,
      :task_type,
      :session_id,
      :goal_id,
      :metadata
    ])
    |> validate_required([:provider, :input_tokens, :output_tokens, :cost_cents])
  end

  # Private functions

  defp calculate_cost(model, input_tokens, output_tokens, cache_read_tokens) do
    pricing = Map.get(@pricing, model, @pricing["default"])

    # Cache reads are typically 90% cheaper
    cache_discount = 0.1

    input_cost = div(input_tokens * pricing.input, 1_000_000)
    output_cost = div(output_tokens * pricing.output, 1_000_000)
    cache_cost = div(round(cache_read_tokens * pricing.input * cache_discount), 1_000_000)

    input_cost + output_cost + cache_cost
  end

  defp format_dollars(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_dollars(_), do: "$0.00"
end
