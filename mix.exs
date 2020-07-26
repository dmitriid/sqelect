defmodule Sqelect.MixProject do
  use Mix.Project

  def project do
    [
      app: :sqelect,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
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
    # deps
    [
      {:ecto, "~>3.4.5"},
      {:ecto_sql, "~>3.4.5"},
      {:db_connection, "~>2.2.2"},
      {:sqlitex, "~>1.7.1"}
    ] ++
    # dev deps
    [
      {:credo, "~>1.4.0"}
    ]
  end
end
