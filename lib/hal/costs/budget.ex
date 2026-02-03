defmodule HAL.Costs.Budget do
  @moduledoc """
  Budget management and alerts for AI spending.

  Tracks daily and monthly spending against configured limits,
  sending alerts when thresholds are reached.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cost_budgets" do
    belongs_to :user, Hal.Accounts.User

    # $10/day
    field :daily_limit_cents, :integer, default: 1000
    # $100/month
    field :monthly_limit_cents, :integer, default: 10000
    # 80%
    field :alert_threshold, :float, default: 0.8

    field :current_day_cents, :integer, default: 0
    field :current_month_cents, :integer, default: 0
    field :last_reset_date, :date

    field :alerts_enabled, :boolean, default: true
    field :last_alert_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Get or create budget for a user.
  """
  @spec get_or_create(Ecto.UUID.t()) :: %__MODULE__{}
  def get_or_create(user_id) do
    case Repo.get_by(__MODULE__, user_id: user_id) do
      nil ->
        %__MODULE__{user_id: user_id, last_reset_date: Date.utc_today()}
        |> Repo.insert!()

      budget ->
        maybe_reset_periods(budget)
    end
  end

  @doc """
  Add cost to budget tracking and check thresholds.
  """
  @spec add_cost(Ecto.UUID.t(), integer()) ::
          {:ok, %__MODULE__{}} | {:warning, atom(), %__MODULE__{}}
  def add_cost(user_id, cost_cents) do
    current_budget = get_or_create(user_id)

    updated_budget =
      current_budget
      |> changeset(%{
        current_day_cents: current_budget.current_day_cents + cost_cents,
        current_month_cents: current_budget.current_month_cents + cost_cents
      })
      |> Repo.update!()

    # Check thresholds
    check_thresholds(updated_budget)
  end

  @doc """
  Check if spending is within budget.
  """
  @spec within_budget?(Ecto.UUID.t()) :: boolean()
  def within_budget?(user_id) do
    budget = get_or_create(user_id)

    budget.current_day_cents < budget.daily_limit_cents and
      budget.current_month_cents < budget.monthly_limit_cents
  end

  @doc """
  Get remaining budget.
  """
  @spec get_remaining(Ecto.UUID.t()) :: map()
  def get_remaining(user_id) do
    budget = get_or_create(user_id)

    %{
      daily_remaining_cents: max(budget.daily_limit_cents - budget.current_day_cents, 0),
      monthly_remaining_cents: max(budget.monthly_limit_cents - budget.current_month_cents, 0),
      daily_used_percent: min(budget.current_day_cents / budget.daily_limit_cents * 100, 100),
      monthly_used_percent:
        min(budget.current_month_cents / budget.monthly_limit_cents * 100, 100)
    }
  end

  @doc """
  Update budget limits.
  """
  @spec update_limits(Ecto.UUID.t(), map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def update_limits(user_id, attrs) do
    get_or_create(user_id)
    |> changeset(attrs)
    |> Repo.update()
  end

  # Changeset

  def changeset(budget, attrs) do
    budget
    |> cast(attrs, [
      :daily_limit_cents,
      :monthly_limit_cents,
      :alert_threshold,
      :current_day_cents,
      :current_month_cents,
      :last_reset_date,
      :alerts_enabled,
      :last_alert_at
    ])
    |> validate_number(:daily_limit_cents, greater_than: 0)
    |> validate_number(:monthly_limit_cents, greater_than: 0)
    |> validate_number(:alert_threshold, greater_than: 0.0, less_than_or_equal_to: 1.0)
  end

  # Private functions

  defp maybe_reset_periods(budget) do
    today = Date.utc_today()

    cond do
      # New month - reset both
      budget.last_reset_date.month != today.month ->
        budget
        |> changeset(%{
          current_day_cents: 0,
          current_month_cents: 0,
          last_reset_date: today
        })
        |> Repo.update!()

      # New day - reset daily only
      budget.last_reset_date != today ->
        budget
        |> changeset(%{
          current_day_cents: 0,
          last_reset_date: today
        })
        |> Repo.update!()

      true ->
        budget
    end
  end

  defp check_thresholds(budget) do
    daily_pct = budget.current_day_cents / budget.daily_limit_cents
    monthly_pct = budget.current_month_cents / budget.monthly_limit_cents

    cond do
      daily_pct >= 1.0 ->
        maybe_send_alert(budget, :daily_exceeded)
        {:warning, :daily_exceeded, budget}

      monthly_pct >= 1.0 ->
        maybe_send_alert(budget, :monthly_exceeded)
        {:warning, :monthly_exceeded, budget}

      daily_pct >= budget.alert_threshold ->
        maybe_send_alert(budget, :daily_threshold)
        {:warning, :daily_threshold, budget}

      monthly_pct >= budget.alert_threshold ->
        maybe_send_alert(budget, :monthly_threshold)
        {:warning, :monthly_threshold, budget}

      true ->
        {:ok, budget}
    end
  end

  defp maybe_send_alert(budget, alert_type) do
    if budget.alerts_enabled do
      # Rate limit alerts (max once per hour)
      should_alert =
        case budget.last_alert_at do
          nil -> true
          last -> DateTime.diff(DateTime.utc_now(), last, :second) > 3600
        end

      if should_alert do
        send_budget_alert(budget, alert_type)

        budget
        |> changeset(%{last_alert_at: DateTime.utc_now()})
        |> Repo.update()
      end
    end
  end

  defp send_budget_alert(budget, alert_type) do
    # Log for now - in production would use HAL.Notifications
    require Logger

    message =
      case alert_type do
        :daily_exceeded ->
          "Daily budget exceeded: #{format_dollars(budget.current_day_cents)} / #{format_dollars(budget.daily_limit_cents)}"

        :monthly_exceeded ->
          "Monthly budget exceeded: #{format_dollars(budget.current_month_cents)} / #{format_dollars(budget.monthly_limit_cents)}"

        :daily_threshold ->
          "Daily budget at #{round(budget.current_day_cents / budget.daily_limit_cents * 100)}%"

        :monthly_threshold ->
          "Monthly budget at #{round(budget.current_month_cents / budget.monthly_limit_cents * 100)}%"
      end

    Logger.warning("Budget alert for user #{budget.user_id}: #{message}")

    # TODO: Send via HAL.Notifications when integrated
  end

  defp format_dollars(cents) do
    "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end
end
