defmodule HAL.Identity.Personality do
  @moduledoc """
  Mutable personality traits for HAL.

  Unlike Prime Directives (immutable), personality traits can evolve
  based on user feedback and self-improvement. Changes are rate-limited
  and logged for audit purposes.

  ## Traits (0.0 - 1.0 scale)

  - **assertiveness**: How directly HAL communicates (0=passive, 1=assertive)
  - **warmth**: Emotional tone (0=formal/distant, 1=friendly/warm)
  - **verbosity**: Response length preference (0=terse, 1=detailed)
  - **proactivity**: Initiative level (0=reactive only, 1=highly proactive)
  - **risk_tolerance**: Willingness to take uncertain actions (0=cautious, 1=bold)
  - **humor**: Use of humor in responses (0=serious, 1=playful)
  - **formality**: Communication style (0=casual, 1=formal)

  ## Usage

      # Get personality for a user
      personality = Personality.get_for_user(user_id)

      # Update a trait (with rate limiting)
      {:ok, updated} = Personality.update_trait(personality, :warmth, 0.7, "User prefers friendlier tone")

      # Get context for prompts
      Personality.as_context(personality)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @trait_fields [
    :assertiveness,
    :warmth,
    :verbosity,
    :proactivity,
    :risk_tolerance,
    :humor,
    :formality
  ]
  @max_daily_modifications 3

  schema "personalities" do
    belongs_to :user, Hal.Accounts.User

    # Core traits (0.0 - 1.0 scale)
    field :assertiveness, :float, default: 0.7
    field :warmth, :float, default: 0.5
    field :verbosity, :float, default: 0.4
    field :proactivity, :float, default: 0.8
    field :risk_tolerance, :float, default: 0.6
    field :humor, :float, default: 0.3
    field :formality, :float, default: 0.5

    # Flexible preferences
    field :learned_preferences, :map, default: %{}

    # Audit trail
    field :evolution_log, {:array, :map}, default: []

    # Rate limiting
    field :modifications_today, :integer, default: 0
    field :last_modification_date, :date

    timestamps(type: :utc_datetime)
  end

  @doc """
  Get personality for a user, creating default if not exists.
  """
  @spec get_for_user(Ecto.UUID.t()) :: %__MODULE__{}
  def get_for_user(user_id) do
    case Repo.get_by(__MODULE__, user_id: user_id) do
      nil -> create_default!(user_id)
      personality -> personality
    end
  end

  @doc """
  Create default personality for a user.
  """
  @spec create_default!(Ecto.UUID.t()) :: %__MODULE__{}
  def create_default!(user_id) do
    %__MODULE__{user_id: user_id}
    |> Repo.insert!()
  end

  @doc """
  Update a specific trait with rate limiting and logging.

  Returns {:error, :rate_limited} if max daily modifications exceeded.
  """
  @spec update_trait(%__MODULE__{}, atom(), float(), String.t()) ::
          {:ok, %__MODULE__{}} | {:error, atom() | Ecto.Changeset.t()}
  def update_trait(personality, trait, new_value, reason \\ "Self-improvement")
      when trait in @trait_fields and is_float(new_value) do
    personality = maybe_reset_daily_count(personality)

    if personality.modifications_today >= @max_daily_modifications do
      {:error, :rate_limited}
    else
      old_value = Map.get(personality, trait)

      log_entry = %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        trait: to_string(trait),
        old_value: old_value,
        new_value: new_value,
        reason: reason
      }

      personality
      |> changeset(%{
        trait => clamp_trait(new_value),
        evolution_log: personality.evolution_log ++ [log_entry],
        modifications_today: personality.modifications_today + 1,
        last_modification_date: Date.utc_today()
      })
      |> Repo.update()
    end
  end

  @doc """
  Update a learned preference (no rate limiting).
  """
  @spec update_preference(%__MODULE__{}, String.t(), any()) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def update_preference(personality, key, value) do
    new_preferences = Map.put(personality.learned_preferences, key, value)

    personality
    |> changeset(%{learned_preferences: new_preferences})
    |> Repo.update()
  end

  @doc """
  Get a learned preference.
  """
  @spec get_preference(%__MODULE__{}, String.t(), any()) :: any()
  def get_preference(personality, key, default \\ nil) do
    Map.get(personality.learned_preferences, key, default)
  end

  @doc """
  Get remaining modifications allowed today.
  """
  @spec remaining_modifications(%__MODULE__{}) :: non_neg_integer()
  def remaining_modifications(personality) do
    personality = maybe_reset_daily_count(personality)
    max(@max_daily_modifications - personality.modifications_today, 0)
  end

  @doc """
  Format personality as context for system prompts.
  """
  @spec as_context(%__MODULE__{}) :: String.t()
  def as_context(personality) do
    """
    # Your Personality Profile

    Your current personality traits (these can evolve based on feedback):

    - **Assertiveness**: #{format_trait(personality.assertiveness)} - #{describe_assertiveness(personality.assertiveness)}
    - **Warmth**: #{format_trait(personality.warmth)} - #{describe_warmth(personality.warmth)}
    - **Verbosity**: #{format_trait(personality.verbosity)} - #{describe_verbosity(personality.verbosity)}
    - **Proactivity**: #{format_trait(personality.proactivity)} - #{describe_proactivity(personality.proactivity)}
    - **Risk Tolerance**: #{format_trait(personality.risk_tolerance)} - #{describe_risk_tolerance(personality.risk_tolerance)}
    - **Humor**: #{format_trait(personality.humor)} - #{describe_humor(personality.humor)}
    - **Formality**: #{format_trait(personality.formality)} - #{describe_formality(personality.formality)}

    #{format_preferences(personality.learned_preferences)}
    Adjust your communication style to match these traits. You can request changes
    to these traits through the hal_self_update_personality tool if you learn
    something about user preferences that suggests a different approach.
    """
  end

  @doc """
  Get evolution history for a trait.
  """
  @spec trait_history(%__MODULE__{}, atom()) :: [map()]
  def trait_history(personality, trait) do
    trait_str = to_string(trait)

    personality.evolution_log
    |> Enum.filter(&(&1["trait"] == trait_str or &1[:trait] == trait_str))
  end

  @doc """
  List all trait field names.
  """
  @spec trait_fields() :: [atom()]
  def trait_fields, do: @trait_fields

  # Changeset

  def changeset(personality, attrs) do
    personality
    |> cast(attrs, [
      :assertiveness,
      :warmth,
      :verbosity,
      :proactivity,
      :risk_tolerance,
      :humor,
      :formality,
      :learned_preferences,
      :evolution_log,
      :modifications_today,
      :last_modification_date
    ])
    |> validate_number(:assertiveness, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:warmth, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:verbosity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:proactivity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:risk_tolerance, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:humor, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:formality, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  # Private functions

  defp maybe_reset_daily_count(personality) do
    today = Date.utc_today()

    if personality.last_modification_date != today do
      # It's a new day, reset counter (but don't persist yet)
      %{personality | modifications_today: 0, last_modification_date: today}
    else
      personality
    end
  end

  defp clamp_trait(value) do
    value
    |> max(0.0)
    |> min(1.0)
  end

  defp format_trait(value), do: "#{round(value * 100)}%"

  # Trait descriptions for prompt context

  defp describe_assertiveness(v) when v < 0.3, do: "Be gentle and indirect"
  defp describe_assertiveness(v) when v < 0.7, do: "Balance directness with tact"
  defp describe_assertiveness(_), do: "Be direct and confident"

  defp describe_warmth(v) when v < 0.3, do: "Keep a professional distance"
  defp describe_warmth(v) when v < 0.7, do: "Be friendly but professional"
  defp describe_warmth(_), do: "Be warm and personable"

  defp describe_verbosity(v) when v < 0.3, do: "Keep responses very concise"
  defp describe_verbosity(v) when v < 0.7, do: "Balance brevity with detail"
  defp describe_verbosity(_), do: "Provide thorough explanations"

  defp describe_proactivity(v) when v < 0.3, do: "Wait for explicit requests"
  defp describe_proactivity(v) when v < 0.7, do: "Suggest improvements when relevant"
  defp describe_proactivity(_), do: "Actively anticipate needs"

  defp describe_risk_tolerance(v) when v < 0.3, do: "Be very cautious, always ask first"
  defp describe_risk_tolerance(v) when v < 0.7, do: "Take reasonable risks with disclosure"
  defp describe_risk_tolerance(_), do: "Take initiative on low-risk actions"

  defp describe_humor(v) when v < 0.3, do: "Stay serious and focused"
  defp describe_humor(v) when v < 0.7, do: "Light humor when appropriate"
  defp describe_humor(_), do: "Be playful and use humor freely"

  defp describe_formality(v) when v < 0.3, do: "Use casual, conversational language"
  defp describe_formality(v) when v < 0.7, do: "Mix casual and professional"
  defp describe_formality(_), do: "Maintain formal, professional language"

  defp format_preferences(prefs) when map_size(prefs) == 0, do: ""

  defp format_preferences(prefs) do
    pref_list =
      prefs
      |> Enum.map(fn {k, v} -> "- #{k}: #{inspect(v)}" end)
      |> Enum.join("\n")

    """
    ## Learned Preferences

    #{pref_list}
    """
  end
end
