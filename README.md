# FeatureSupervisor

A wrapper for built-in `Supervisor` that allows starting children only if the features that they correspond to are enabled.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `feature_supervisor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:feature_supervisor, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/feature_supervisor>.

## Usage

Since `FeatureSupervisor` is a simple wrapper for built-in `Supervisor` it can be used exactly the same way.

```elixir
defmodule MyApp.Application do
  use Application

  @mix_env Mix.env()

  def start(_type, _args) do
    children = [
      # a regular child
      Child1,
      # supposed to be disabled in tests
      FeatureSupervisor.child_spec(Child2, enabled?: @mix_env != :test)
      # supposed to run only when the feature is enabled
      FeatureSupervisor.child_spec({Child3, name: Child3}, enabled?: &feature_enabled?/1, feature_id: "my-feature")
    ]

    # modifies (if necessary) the children list and passes it to `Supervisor.start_link/2`
    FeatureSupervisor.start_link(children, strategy: :one_for_one, sync_interval: 1000)
  end

  defp feature_enabled?(spec) do
    MyApp.Features.enabled?(spec.feature_id)
  end
end
```
