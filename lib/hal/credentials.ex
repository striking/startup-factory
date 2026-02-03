defmodule HAL.Credentials do
  @moduledoc """
  Simple local credential loader for HAL integrations.

  Follows the OpenClaw pattern: credentials are stored locally at ~/.hal/credentials/
  and loaded at runtime. No complex OAuth flows - tokens are acquired manually
  and stored in JSON files.

  ## Structure

      ~/.hal/credentials/
      ├── google.json      # Gmail + Calendar tokens
      ├── linear.json      # Linear API key
      └── ...

  ## Usage

      # Load Google credentials
      {:ok, creds} = HAL.Credentials.load(:google)
      access_token = creds["access_token"]

      # Load Linear API key
      {:ok, creds} = HAL.Credentials.load(:linear)
      api_key = creds["api_key"]

      # Check if credentials exist
      HAL.Credentials.exists?(:google)

  ## Token Refresh

  For Google OAuth, if access_token is expired, use the refresh_token
  to get a new one via `HAL.Credentials.refresh_google_token/0`.
  """

  require Logger

  @credentials_dir Path.expand("~/.hal/credentials")

  @doc """
  Load credentials for a service.

  Returns `{:ok, map}` with the parsed JSON, or `{:error, reason}`.
  """
  @spec load(atom()) :: {:ok, map()} | {:error, term()}
  def load(service) when is_atom(service) do
    path = credential_path(service)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, creds} -> {:ok, creds}
          {:error, _} -> {:error, :invalid_json}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if credentials exist for a service.
  """
  @spec exists?(atom()) :: boolean()
  def exists?(service) when is_atom(service) do
    path = credential_path(service)
    File.exists?(path)
  end

  @doc """
  Save credentials for a service.
  """
  @spec save(atom(), map()) :: :ok | {:error, term()}
  def save(service, credentials) when is_atom(service) and is_map(credentials) do
    path = credential_path(service)

    # Ensure directory exists
    File.mkdir_p!(@credentials_dir)

    case Jason.encode(credentials, pretty: true) do
      {:ok, json} ->
        File.write(path, json)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a valid Google access token, refreshing if expired.
  """
  @spec get_google_token() :: {:ok, String.t()} | {:error, term()}
  def get_google_token do
    case load(:google) do
      {:ok, creds} ->
        if token_expired?(creds) do
          refresh_google_token(creds)
        else
          {:ok, creds["access_token"]}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refresh Google OAuth token using refresh_token.
  """
  @spec refresh_google_token(map()) :: {:ok, String.t()} | {:error, term()}
  def refresh_google_token(creds \\ nil) do
    creds = creds || elem(load(:google), 1)

    case creds["refresh_token"] do
      nil ->
        {:error, :no_refresh_token}

      refresh_token ->
        body =
          URI.encode_query(%{
            "client_id" => creds["client_id"],
            "client_secret" => creds["client_secret"],
            "refresh_token" => refresh_token,
            "grant_type" => "refresh_token"
          })

        headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

        case HTTPoison.post("https://oauth2.googleapis.com/token", body, headers) do
          {:ok, %{status_code: 200, body: response_body}} ->
            new_tokens = Jason.decode!(response_body)

            # Update stored credentials
            updated_creds =
              creds
              |> Map.put("access_token", new_tokens["access_token"])
              |> Map.put("token_expiry", calculate_expiry(new_tokens["expires_in"]))

            :ok = save(:google, updated_creds)
            Logger.info("Refreshed Google access token")
            {:ok, new_tokens["access_token"]}

          {:ok, %{status_code: status, body: response_body}} ->
            Logger.error("Google token refresh failed: #{status} - #{response_body}")
            {:error, {:refresh_failed, status}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  List all available credentials.
  """
  @spec list() :: [atom()]
  def list do
    case File.ls(@credentials_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.reject(&String.ends_with?(&1, ".example"))
        |> Enum.map(fn file ->
          file
          |> String.replace(".json", "")
          |> String.to_atom()
        end)

      {:error, _} ->
        []
    end
  end

  # Private functions

  defp credential_path(service) do
    Path.join(@credentials_dir, "#{service}.json")
  end

  defp token_expired?(creds) do
    case creds["token_expiry"] do
      nil ->
        false

      expiry_str ->
        case DateTime.from_iso8601(expiry_str) do
          {:ok, expiry, _} ->
            # Consider expired 5 minutes before actual expiry
            buffer = DateTime.add(DateTime.utc_now(), 5, :minute)
            DateTime.compare(expiry, buffer) == :lt

          _ ->
            false
        end
    end
  end

  defp calculate_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.to_iso8601()
  end

  defp calculate_expiry(_), do: nil
end
