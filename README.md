# FeatureSupervisor

[![CI](https://github.com/nmbrone/feature_supervisor/actions/workflows/ci.yml/badge.svg)](https://github.com/nmbrone/feature_supervisor/actions/workflows/ci.yml)

A small wrapper for `Supervisor` that dynamically starts/terminates children based on feature flags.

## Installation

The package can be installed by adding `feature_supervisor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:feature_supervisor, "~> 0.1.0"} # {x-release-please-version}
  ]
end
```

## How to use

`FeatureSupervisor` should be used the same way you would use `Supervisor`.

```elixir
defmodule MyApp.Application do
  use Application

  @mix_env Mix.env()

  def start(_type, _args) do
    children = [
      # a regular child
      Child1,
      # supposed to be disabled in tests
      FeatureSupervisor.child_spec(Child2, enabled?: @mix_env != :test),
      # supposed to run only when the feature is enabled
      FeatureSupervisor.child_spec({Child3, name: Child3},
        enabled?: &feature_enabled?/1,
        feature_id: "my-feature"
      )
    ]

    FeatureSupervisor.start_link(children, strategy: :one_for_one, sync_interval: 1000)
  end

  defp feature_enabled?(spec) do
    MyApp.Features.enabled?(spec.feature_id)
  end
end
```
