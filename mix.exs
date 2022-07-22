defmodule Gmichat.App do
  use Application

  def start(_type, _args) do
    Gmi.init()
    Gmi.add_route("/", fn _ ->
      Gmi.content("# Index\n\n> Hello world\n=>/input Text input\n=>/generic/test Generic 1\n=>/generic/test/abcd Generic 2")
    end)
    Gmi.add_route("/generic/:name", fn args ->
      Gmi.content("# 1 generic\n\n> 123456\n" <> args[:name] <> "\n")
    end)
    Gmi.add_route("/generic/:name/:second", fn args ->
      Gmi.content("# 2 generic\n\n> First parameter : " <> args[:name] <> "\n> Second parameter : " <> args[:second] <> "\n")
    end)
    Gmi.add_route("/input", fn args ->
      if args[:query] == "" do
        Gmi.input("test input")
      else
        Gmi.content("You wrote " <> args[:query])
      end
    end)
    Gmi.listen()
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
