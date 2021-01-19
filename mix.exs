defmodule Sqelect.MixProject do
  use Mix.Project

  def project do
    [
      app: :sqelect,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),
      test_paths: test_paths(),
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
    # deps
    [
      {:ecto, "~>3.4.5"
#                , path: "deps/ecto", override: true
                                     },
      {:ecto_sql, "~>3.4.5"
#  , path: "deps/ecto_sql", override: true
                        },
    ] ++
    # dev deps
    [
      {:credo, "~>1.4.0"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_paths, do: ["integration/sqelect", "test"]
end
