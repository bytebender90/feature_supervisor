defmodule FeatureSupervisor.MixProject do
  use Mix.Project

  @source_url "https://github.com/nmbrone/feature_supervisor"

  def project do
    [
      app: :feature_supervisor,
      version: "0.0.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "FeatureSupervisor",
      description: "Supervisor for features",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29.1", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Serhii Snozyk"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "Readme",
      # x-release-please-start-version
      source_ref: "v0.0.1",
      # x-release-please-end
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
