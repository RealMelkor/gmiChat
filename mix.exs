defmodule Gmichat.App do
  use Application

  def start(_type, _args) do
    GeminiServer.listen()
    Supervisor.start_link [], strategy: :one_for_one
  end
end

defmodule Gmichat.MixProject do
  use Mix.Project

  def project do
    [
      app: :gmichat,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Gmichat.App, []},
      extra_applications: [:logger, :ssl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
