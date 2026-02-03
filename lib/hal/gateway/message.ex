defmodule Hal.Gateway.Message do
  @moduledoc """
  Schema representing a single message within a session.

  Messages store the conversation history including user prompts, assistant responses,
  and system messages. Attachments (images, files, voice) are stored as JSONB arrays.

  ## Fields

    * `session_id` - Reference to the parent Session
    * `role` - Message role: user, assistant, system
    * `content` - The message text content
    * `attachments` - Array of attachment metadata (file_id, type, url, etc.)
    * `metadata` - Additional message metadata (tokens used, model, tool calls, etc.)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Hal.Gateway.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_roles ~w(user assistant system)

  schema "messages" do
    field :role, :string
    field :content, :string
    field :attachments, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    belongs_to :session, Session

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset for creating a new message.

  ## Required Fields
    * `session_id` - Reference to the parent session
    * `role` - One of: user, assistant, system
    * `content` - Message text content

  ## Optional Fields
    * `attachments` - Array of attachment metadata
    * `metadata` - Additional metadata (tokens, model info, etc.)
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:session_id, :role, :content, :attachments, :metadata])
    |> validate_required([:session_id, :role, :content])
    |> validate_inclusion(:role, @valid_roles,
      message: "must be one of: #{Enum.join(@valid_roles, ", ")}"
    )
    |> validate_length(:content, min: 1)
    |> validate_attachments()
    |> foreign_key_constraint(:session_id)
  end

  # Validate attachments structure
  defp validate_attachments(changeset) do
    case get_change(changeset, :attachments) do
      nil ->
        changeset

      attachments when is_list(attachments) ->
        validate_attachment_structure(changeset, attachments)

      _ ->
        add_error(changeset, :attachments, "must be a list")
    end
  end

  defp validate_attachment_structure(changeset, attachments) do
    valid? =
      Enum.all?(attachments, fn
        %{} = _attachment -> true
        _ -> false
      end)

    if valid? do
      changeset
    else
      add_error(changeset, :attachments, "each attachment must be a map")
    end
  end

  @doc """
  Returns the list of valid roles.
  """
  def valid_roles, do: @valid_roles
end
