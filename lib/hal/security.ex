defmodule Hal.Security do
  @moduledoc """
  Inbound trust gating and pairing approvals.

  This provides OpenClaw-style "DM pairing" so HAL can run 24/7 without
  exposing tools to arbitrary inbound messages.

  Policies (configurable):
  - DMs: `:pairing | :allowlist | :open | :disabled`
  - Groups: `:allowlist | :open | :disabled`
  """

  import Ecto.Query, only: [from: 2]

  alias Hal.Accounts.User
  alias Hal.Repo
  alias Hal.Security.PairingRequest

  @type dm_policy :: :pairing | :allowlist | :open | :disabled
  @type group_policy :: :allowlist | :open | :disabled

  @dm_policies ~w(pairing allowlist open disabled)a
  @group_policies ~w(allowlist open disabled)a

  @doc """
  Returns the configured DM policy.
  """
  @spec dm_policy() :: dm_policy()
  def dm_policy do
    normalize_policy(get_config(:dm_policy, :pairing), @dm_policies, :pairing)
  end

  @doc """
  Returns the configured group policy.
  """
  @spec group_policy() :: group_policy()
  def group_policy do
    normalize_policy(get_config(:group_policy, :allowlist), @group_policies, :allowlist)
  end

  @doc """
  Returns the configured DM allowlist as a MapSet of `{platform, external_id}` pairs.
  """
  @spec dm_allowlist() :: MapSet.t({String.t(), String.t()})
  def dm_allowlist do
    get_config(:dm_allowlist, [])
    |> parse_pairs()
  end

  @doc """
  Returns the configured group allowlist as a MapSet of `{channel_type, channel_id}` pairs.
  """
  @spec group_allowlist() :: MapSet.t({String.t(), String.t()})
  def group_allowlist do
    get_config(:group_allowlist, [])
    |> parse_pairs()
  end

  @doc """
  Authorizes an inbound message based on DM/group policy.

  Returns:
  - `:allow` to continue routing to a session
  - `:ignored` to drop the message (silent)
  - `{:respond, text}` to return a message without creating a session
  - `{:error, reason}` for unexpected failures
  """
  @spec authorize_inbound(map()) :: :allow | :ignored | {:respond, String.t()} | {:error, term()}
  def authorize_inbound(message) when is_map(message) do
    is_dm = get_bool(message, :is_dm)
    channel_type = get_channel_type(message)
    channel_id = get_string(message, :channel_id)
    user_id = get_string(message, :user_id)

    cond do
      is_nil(channel_type) or is_nil(channel_id) ->
        {:error, :invalid_message}

      is_dm ->
        if is_nil(user_id) do
          {:error, :missing_user_id}
        else
          authorize_dm(channel_type, user_id)
        end

      true ->
        authorize_group(channel_type, channel_id)
    end
  end

  defp authorize_group(channel_type, channel_id) do
    case group_policy() do
      :open ->
        :allow

      :disabled ->
        :ignored

      :allowlist ->
        if MapSet.member?(group_allowlist(), {channel_type, channel_id}) do
          :allow
        else
          :ignored
        end
    end
  end

  defp authorize_dm(channel_type, user_id) do
    with %User{} = user <- Repo.get(User, user_id) do
      cond do
        user.paired_at != nil ->
          :allow

        MapSet.member?(dm_allowlist(), {user.platform, user.external_id}) ->
          :allow

        true ->
          authorize_unpaired_dm(user, channel_type)
      end
    else
      nil -> {:error, :unknown_user}
    end
  end

  defp authorize_unpaired_dm(%User{} = user, _channel_type) do
    case dm_policy() do
      :open ->
        :allow

      :disabled ->
        {:respond, "Direct messages are disabled for this bot."}

      :allowlist ->
        {:respond,
         "This bot is not open to new users. Ask the operator to allowlist your account."}

      :pairing ->
        case get_or_create_pairing_request(user) do
          {:ok, request} ->
            {:respond, pairing_instructions(request)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns pending pairing requests (most recent first).
  """
  @spec list_pending_pairings(keyword()) :: [PairingRequest.t()]
  def list_pending_pairings(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(r in PairingRequest,
      where: r.status == "pending",
      order_by: [desc: r.inserted_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Approves a pairing request by code and marks the user as paired.
  """
  @spec approve_pairing(String.t(), keyword()) :: {:ok, PairingRequest.t()} | {:error, term()}
  def approve_pairing(code, opts \\ []) when is_binary(code) do
    role = Keyword.get(opts, :role)

    Repo.transaction(fn ->
      case Repo.get_by(PairingRequest, code: code) do
        nil ->
          Repo.rollback(:not_found)

        %PairingRequest{status: status} when status != "pending" ->
          Repo.rollback(:not_pending)

        %PairingRequest{} = req ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          {:ok, req} =
            req
            |> PairingRequest.changeset(%{status: "approved", approved_at: now})
            |> Repo.update()

          user_attrs =
            %{paired_at: now}
            |> maybe_put(:role, role)

          _ =
            Repo.get(User, req.user_id)
            |> User.changeset(user_attrs)
            |> Repo.update()

          req
      end
    end)
    |> normalize_tx_result()
  end

  @doc """
  Denies a pairing request by code.
  """
  @spec deny_pairing(String.t(), String.t()) :: {:ok, PairingRequest.t()} | {:error, term()}
  def deny_pairing(code, reason) when is_binary(code) and is_binary(reason) do
    Repo.transaction(fn ->
      case Repo.get_by(PairingRequest, code: code) do
        nil ->
          Repo.rollback(:not_found)

        %PairingRequest{status: status} when status != "pending" ->
          Repo.rollback(:not_pending)

        %PairingRequest{} = req ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          {:ok, req} =
            req
            |> PairingRequest.changeset(%{
              status: "denied",
              denied_at: now,
              deny_reason: reason
            })
            |> Repo.update()

          req
      end
    end)
    |> normalize_tx_result()
  end

  defp normalize_tx_result({:ok, %PairingRequest{} = req}), do: {:ok, Repo.preload(req, :user)}
  defp normalize_tx_result({:error, reason}), do: {:error, reason}

  defp get_or_create_pairing_request(%User{} = user) do
    case Repo.one(
           from(r in PairingRequest,
             where: r.user_id == ^user.id and r.status == "pending",
             order_by: [desc: r.inserted_at],
             limit: 1
           )
         ) do
      %PairingRequest{} = existing ->
        {:ok, existing |> Repo.preload(:user)}

      nil ->
        insert_pairing_request(user, 5)
    end
  end

  defp insert_pairing_request(_user, 0), do: {:error, :could_not_generate_code}

  defp insert_pairing_request(%User{} = user, attempts_left) do
    code = generate_pairing_code()

    changeset =
      %PairingRequest{}
      |> PairingRequest.changeset(%{
        user_id: user.id,
        code: code,
        status: "pending"
      })

    case Repo.insert(changeset) do
      {:ok, req} ->
        {:ok, req |> Repo.preload(:user)}

      {:error, %Ecto.Changeset{} = cs} ->
        if Keyword.has_key?(cs.errors, :code) do
          insert_pairing_request(user, attempts_left - 1)
        else
          {:error, cs}
        end
    end
  end

  defp generate_pairing_code do
    raw = :crypto.strong_rand_bytes(5) |> Base.encode32(padding: false)
    String.slice(raw, 0, 4) <> "-" <> String.slice(raw, 4, 4)
  end

  defp pairing_instructions(%PairingRequest{} = req) do
    code = req.code

    """
    🔒 Pairing required.

    Your pairing code is: #{code}

    Ask the operator to approve it in the HAL UI at /security.
    After approval, resend your message.
    """
    |> String.trim()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_config(key, default) do
    :hal
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end

  defp normalize_policy(value, allowed, default) when is_atom(value) do
    if value in allowed, do: value, else: default
  end

  defp normalize_policy(value, allowed, default) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
    |> normalize_policy(allowed, default)
  rescue
    _ -> default
  end

  defp parse_pairs(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> parse_pairs()
  end

  defp parse_pairs(value) when is_list(value) do
    value
    |> Enum.map(fn
      item when is_binary(item) -> String.trim(item)
      other -> to_string(other)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(MapSet.new(), fn entry, acc ->
      case String.split(entry, ":", parts: 2) do
        [a, b] when a != "" and b != "" -> MapSet.put(acc, {a, b})
        _ -> acc
      end
    end)
  end

  defp parse_pairs(_), do: MapSet.new()

  defp get_string(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_bool(map, key) do
    case get_string(map, key) do
      true -> true
      "true" -> true
      1 -> true
      "1" -> true
      _ -> false
    end
  end

  defp get_channel_type(message) do
    case Map.get(message, :channel_type) || Map.get(message, "channel_type") do
      nil -> nil
      type when is_atom(type) -> Atom.to_string(type)
      type when is_binary(type) -> type
      other -> to_string(other)
    end
  end
end
