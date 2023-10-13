defmodule FeatureSupervisor do
  @moduledoc """
  A small wrapper for `Supervisor` that dynamically starts/terminates children based on feature flags.

  ## Example

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
  """

  alias FeatureSupervisor.Manager

  @type child ::
          Supervisor.child_spec()
          | {module(), term()}
          | module()
          | (old_erlang_child_spec :: :supervisor.child_spec())

  @type option :: {:sync_interval, non_neg_integer()}

  @doc """
  Wraps the `Supervisor.start_link/2` function.

  Children will be split into two groups:

  * "static" - those without the `:enabled?` field or with `enabled?: true`
  * "dynamic" - those with the `:enabled?` field set to a function

  Children with `enabled?: false` will be excluded.

  "static" children will be started as normal.

  "dynamic" children (if any) will be started separately via `Supervisor.start_child/2`.

  If a "dynamic" child is expected to be started/terminated later via a feature flag
  you should provide the `sync_interval` option. The child's `:restart` option must be set to `:permanent`.
  """
  @spec start_link([child()], [Supervisor.option() | Supervisor.init_option() | option()]) ::
          {:ok, pid} | {:error, {:already_started, pid} | {:shutdown, term} | term}
  def start_link(children, options) when is_list(children) do
    children
    |> group_children()
    |> maybe_add_manager_spec(options)
    |> Supervisor.start_link(options)
  end

  @doc """
  Same as `Supervisor.child_spec/2` but allows any key in the overrides.
  """
  @spec child_spec(child(), Keyword.t()) :: map()
  def child_spec(child, overrides) do
    child
    |> Supervisor.child_spec([])
    |> Map.merge(Map.new(overrides))
  end

  @doc false
  @spec group_children([child()]) :: {static :: [map()], dynamic :: [map()]}
  def group_children(children) do
    children
    |> Enum.reverse()
    |> Enum.reduce({[], []}, fn spec, {static, dynamic} = acc ->
      case child_spec(spec, []) do
        %{enabled?: fun} = spec when is_function(fun, 1) -> {static, [spec | dynamic]}
        %{enabled?: false} -> acc
        spec -> {[spec | static], dynamic}
      end
    end)
  end

  defp maybe_add_manager_spec({static, []}, _), do: static

  defp maybe_add_manager_spec({static, dynamic}, options) do
    static ++
      [
        Manager.child_spec(
          children: dynamic,
          sync_interval: Keyword.get(options, :sync_interval)
        )
      ]
  end
end
