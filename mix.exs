defmodule FeatureSupervisor.MixProject do
  use Mix.Project

  def project do
    [
      app: :feature_supervisor,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "FeatureSupervisor",
      description: "Supervisor for features",
      source_url: "https://github.com/nmbrone/feature_supervisor",
      homepage_url: "https://github.com/nmbrone/feature_supervisor",
      package: [
        maintainers: ["Serhii Snozyk"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/nmbrone/feature_supervisor"}
      ],
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
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
end
