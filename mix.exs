defmodule Pidge.MixProject do
  use Mix.Project

  def project do
    [
      app: :pidge,
      version: "0.1.0",
      elixir: "~> 1.15",
      escript: escript_config(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.8.0"},
      {:poison, "~> 5.0"},
      {:solid, "~> 0.7.0"}
    ]
  end

  def escript_config do
    [
      main_module: Pidge,
      emu_args: "+Bd -noinput"
    ]
  end
end
