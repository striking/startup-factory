defmodule Hal.Accounts.DefaultUser do
  @moduledoc """
  Resolves the primary/local user for autonomous operations.

  Local-first behavior:
  1) Look up by `HAL_DEFAULT_USER_EXTERNAL_ID` + `HAL_DEFAULT_USER_PLATFORM`
  2) Fall back to `external_id = "web-chat-user"` on platform "terminal"
  3) Fall back to the first user in the DB
  """

  import Ecto.Query, only: [from: 2]

  alias Hal.Accounts.User
  alias Hal.Repo

  @default_external_id "web-chat-user"
  @default_platform "terminal"

  @spec get() :: User.t() | nil
  def get do
    external_id = System.get_env("HAL_DEFAULT_USER_EXTERNAL_ID") || @default_external_id
    platform = System.get_env("HAL_DEFAULT_USER_PLATFORM") || @default_platform

    Repo.get_by(User, external_id: external_id, platform: platform) ||
      Repo.get_by(User, external_id: external_id) ||
      Repo.one(from(u in User, limit: 1))
  end
end
