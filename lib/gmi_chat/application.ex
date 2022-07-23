defmodule Gmichat.App do
  use Application

  def start(_type, _args) do
    children = [
      Gmichat.Repo,
    ]
    opts = [strategy: :one_for_one, name: Friends.Supervisor]
    Supervisor.start_link(children, opts)
    Gmichat.start()
    Supervisor.start_link [], strategy: :one_for_one
  end
end
