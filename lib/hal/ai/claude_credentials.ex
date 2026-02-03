defmodule Hal.AI.ClaudeCredentials do
  @moduledoc """
  Reads Claude OAuth credentials from ~/.claude/.credentials.json

  Supports using Claude subscription (Pro/Team/Max) instead of API keys.
  """

  require Logger

  @credentials_path Path.expand("~/.claude/.credentials.json")

  @doc """
  Get Claude OAuth access token from credentials file.

  Returns {:ok, token} or {:error, reason}
  """
  def get_oauth_token do
    with {:ok, content} <- File.read(@credentials_path),
         {:ok, json} <- Jason.decode(content),
         {:ok, token} <- extract_access_token(json) do
      {:ok, token}
    else
      {:error, :enoent} ->
        {:error, :credentials_file_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get Claude credentials as environment variables for Claude Agent SDK.

  Returns map with either:
  - %{"ANTHROPIC_API_KEY" => key} if using API key
  - %{"CLAUDE_CODE_OAUTH_TOKEN" => token} if using OAuth
  """
  def get_env_vars do
    cond do
      # Check for explicit ANTHROPIC_API_KEY
      api_key = System.get_env("ANTHROPIC_API_KEY") ->
        %{"ANTHROPIC_API_KEY" => api_key}

      # Check for explicit CLAUDE_CODE_OAUTH_TOKEN
      oauth_token = System.get_env("CLAUDE_CODE_OAUTH_TOKEN") ->
        %{"CLAUDE_CODE_OAUTH_TOKEN" => oauth_token}

      # Try to load from credentials file
      true ->
        case get_oauth_token() do
          {:ok, token} ->
            Logger.info("Using Claude OAuth token from ~/.claude/.credentials.json")
            %{"CLAUDE_CODE_OAUTH_TOKEN" => token}

          {:error, reason} ->
            Logger.warning("""
            Could not load Claude credentials: #{inspect(reason)}

            Please either:
            1. Set ANTHROPIC_API_KEY environment variable
            2. Set CLAUDE_CODE_OAUTH_TOKEN environment variable
            3. Run 'claude setup-token' to authenticate with Claude subscription
            """)

            %{}
        end
    end
  end

  @doc """
  Get subscription information from credentials file.

  Returns {:ok, info} with subscription type and rate limit tier.
  """
  def get_subscription_info do
    with {:ok, content} <- File.read(@credentials_path),
         {:ok, json} <- Jason.decode(content) do
      oauth = get_in(json, ["claudeAiOauth"])

      info = %{
        subscription_type: oauth["subscriptionType"],
        rate_limit_tier: oauth["rateLimitTier"],
        scopes: oauth["scopes"],
        expires_at: oauth["expiresAt"]
      }

      {:ok, info}
    else
      error ->
        error
    end
  end

  @doc """
  Check if OAuth token is expired.
  """
  def token_expired? do
    case get_subscription_info() do
      {:ok, %{expires_at: expires_at}} when is_integer(expires_at) ->
        # expires_at is Unix timestamp in milliseconds
        current_time = System.system_time(:millisecond)
        current_time >= expires_at

      _ ->
        # If we can't determine, assume expired
        true
    end
  end

  ## Private Functions

  defp extract_access_token(json) do
    case get_in(json, ["claudeAiOauth", "accessToken"]) do
      nil ->
        {:error, :access_token_not_found}

      token when is_binary(token) ->
        {:ok, token}

      _ ->
        {:error, :invalid_access_token}
    end
  end
end
