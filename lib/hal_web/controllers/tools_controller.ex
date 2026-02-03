defmodule HalWeb.ToolsController do
  @moduledoc """
  Minimal control-plane endpoint for invoking HAL tools via HTTP.

  Disabled by default unless `HAL_CONTROL_PLANE_TOKEN` is set.
  """

  use HalWeb, :controller

  alias Hal.Accounts.DefaultUser
  alias Hal.Tools.Executor

  @doc """
  POST /tools/invoke

  Body:
  {
    "tool": "hal_memory_search",
    "args": {...},
    "context": {...},
    "user_id": "..."
  }
  """
  def invoke(conn, params) do
    with :ok <- authorize(conn),
         {:ok, tool_name} <- fetch_tool_name(params),
         {:ok, {args, opts}} <- build_exec_params(params) do
      case Executor.execute(tool_name, args, opts) do
        {:ok, result} ->
          json(conn, result)

        {:error, %{type: :needs_approval} = error} ->
          conn
          |> put_status(:accepted)
          |> json(error)

        {:error, %{type: :policy_denied} = error} ->
          conn
          |> put_status(:forbidden)
          |> json(error)

        {:error, error} ->
          conn
          |> put_status(:bad_request)
          |> json(error)
      end
    else
      {:error, :not_enabled} ->
        send_resp(conn, 404, "Not found")

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Unauthorized"})

      {:error, :bad_request, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: message})
    end
  end

  defp authorize(conn) do
    expected = System.get_env("HAL_CONTROL_PLANE_TOKEN")

    cond do
      is_nil(expected) or expected == "" ->
        {:error, :not_enabled}

      expected == bearer_token(conn) ->
        :ok

      true ->
        {:error, :unauthorized}
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp fetch_tool_name(%{"tool" => tool}) when is_binary(tool) and tool != "", do: {:ok, tool}

  defp fetch_tool_name(%{"tool_name" => tool}) when is_binary(tool) and tool != "",
    do: {:ok, tool}

  defp fetch_tool_name(_), do: {:error, :bad_request, "Missing required field: tool"}

  defp build_exec_params(params) do
    args = Map.get(params, "args") || %{}
    context = Map.get(params, "context") || %{}

    if not is_map(args) or not is_map(context) do
      {:error, :bad_request, "args and context must be JSON objects"}
    else
      user_id =
        Map.get(params, "user_id") ||
          Map.get(context, "user_id") ||
          case DefaultUser.get() do
            %{id: id} -> id
            _ -> nil
          end

      opts =
        []
        |> maybe_put(:user_id, user_id)
        |> maybe_put(:session_id, Map.get(context, "session_id"))
        |> maybe_put(:channel_type, Map.get(context, "channel_type"))
        |> maybe_put(:channel_id, Map.get(context, "channel_id"))

      {:ok, {args, opts}}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
