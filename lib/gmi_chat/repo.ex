defmodule Gmichat.Repo do
  use Ecto.Repo,
    otp_app: :gmichat,
    adapter: Ecto.Adapters.SQLite3
end
