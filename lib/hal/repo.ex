defmodule Hal.Repo do
  use Ecto.Repo,
    otp_app: :hal,
    adapter: Ecto.Adapters.Postgres
end
