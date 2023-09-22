defmodule Pidge.MixProject do
  use Mix.Project

  def project do
    [
      app: :pidge,
      version: "0.2.0",
      elixir: "~> 1.14",
      escript: escript_config(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Pidge - Your description of the project here",
      package: package_config()
    ]
  end

  defp package_config do
    [
      maintainers: ["Dave Buchanan"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/unlox775/project-roe"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]

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
      {:solid, "~> 0.7.0"},
      {:jason, "~> 1.4.1"},
      {:websockex, "~> 0.4.3"},
      {:poolboy, "~> 1.5.1"},
      {:mix_test_watch, "~> 1.0", only: :dev},
      {:mock, "~> 0.3.4", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  def escript_config do
    [
      main_module: Pidge,
      emu_args: "+Bd"
    ]
  end
end
