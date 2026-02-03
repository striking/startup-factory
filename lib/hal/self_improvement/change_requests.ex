defmodule HAL.SelfImprovement.ChangeRequests do
  @moduledoc """
  Self-improvement codops pipeline.

  Creates and tracks ChangeRequests that are generated in a sandboxed worktree
  and applied only after explicit human approval.
  """

  import Ecto.Query, only: [from: 2]

  alias HAL.SelfImprovement.ChangeRequest
  alias HAL.SelfImprovement.ChangeRequestWorker
  alias Hal.Repo

  @type id :: Ecto.UUID.t()

  @spec get(id()) :: ChangeRequest.t() | nil
  def get(id) when is_binary(id), do: Repo.get(ChangeRequest, id)

  @spec get!(id()) :: ChangeRequest.t()
  def get!(id) when is_binary(id), do: Repo.get!(ChangeRequest, id)

  @spec list_recent(keyword()) :: [ChangeRequest.t()]
  def list_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(c in ChangeRequest,
      order_by: [desc: c.inserted_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  @spec create(Ecto.UUID.t(), map()) :: {:ok, ChangeRequest.t()} | {:error, Ecto.Changeset.t()}
  def create(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    %ChangeRequest{}
    |> ChangeRequest.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @spec update(ChangeRequest.t(), map()) ::
          {:ok, ChangeRequest.t()} | {:error, Ecto.Changeset.t()}
  def update(%ChangeRequest{} = change_request, attrs) when is_map(attrs) do
    change_request
    |> ChangeRequest.changeset(attrs)
    |> Repo.update()
  end

  @spec enqueue_generation(ChangeRequest.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_generation(%ChangeRequest{id: id}) when is_binary(id) do
    job =
      ChangeRequestWorker.new(%{"change_request_id" => id},
        unique: [
          fields: [:args, :queue, :worker],
          keys: [:change_request_id],
          period: 60 * 60 * 24
        ]
      )

    Oban.insert(job)
  end
end
