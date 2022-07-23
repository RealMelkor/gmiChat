import Config

config :gmichat, Gmichat.Repo,
  database: "gmichat_repo",
  username: "user",
  password: "pass",
  hostname: "localhost"

config :gmichat, Gmichat.Repo,
  database: "gmichat_repo",
  username: "user",
  password: "pass",
  hostname: "localhost"

config :gmichat,
  ecto_repos: [Gmichat.Repo]

config :logger, :console,
 format: "[$level]$metadata $message\n"
