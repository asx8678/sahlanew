defmodule Sahla.Repo do
  use Ecto.Repo,
    otp_app: :sahla,
    adapter: Ecto.Adapters.Postgres
end
