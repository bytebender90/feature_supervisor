defmodule FeatureSupervisor do
  @moduledoc """
  A wrapper for built-in `Supervisor` that allows starting a certain child only if the feature
  that it corresponds to is enabled.
  """

  require Logger

  @type child ::
          Supervisor.child_spec()
          | {module(), term()}
          | module()
          | (old_erlang_child_spec :: :supervisor.child_spec())

  @type init_option ::
          Supervisor.init_option()
          | {:refresh_interval, non_neg_integer()}
          | {:name, Supervisor.name()}

  @doc """
  Same as `Supervisor.start_link/2`, but with additional logic to handle "feature" children.
  """
  @spec start_link([child()], [Supervisor.option() | init_option()]) ::
          {:ok, pid} | {:error, {:already_started, pid} | {:shutdown, term} | term}
  def start_link(children, options) when is_list(children) do
    {:ok, {_flags, children}} = init(children, options)
    Supervisor.start_link(children, options)
  end

  @doc """
  Same as `Supervisor.child_spec/2` but allows any key in the overrides.
  """
  @spec child_spec(Supervisor.child_spec(), Keyword.t()) :: map()
  def child_spec(spec, overrides) do
    spec
    |> Supervisor.child_spec([])
    |> Map.merge(Map.new(overrides))
  end

  @doc """
  Same as `Supervisor.init/2` but with additional logic to handle "feature" children.

  A "feature" children is simply a child spec that contains the `:enabled?` key.

  The `:enabled?` value can be either a boolean or a function that accepts the spec and returns
  a boolean.

  Disabled specs (those with `enabled?: false`) will be excluded from the children list,
  and therefore will not be started by the supervisor automatically.

  Provide the `:refresh_interval` option if you want to be able to toggle "feature" children.
  """
  @spec init([child()], [init_option()]) ::
          {:ok,
           {Supervisor.sup_flags(),
            [Supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
  def init(children, options) do
    {:ok, {sup_flags, children}} = Supervisor.init(children, options)
    {feature_children, children} = Enum.split_with(children, &feature_children?/1)
    children = children ++ Enum.filter(feature_children, &enabled?/1)

    children =
      if (int = Keyword.get(options, :refresh_interval)) && length(feature_children) > 0 do
        children ++
          [
            FeatureSupervisor.Manager.child_spec(
              children: feature_children,
              refresh_interval: int,
              supervisor: Keyword.get(options, :name, __MODULE__)
            )
          ]
      else
        children
      end

    {:ok, {sup_flags, children}}
  end

  @doc false
  @spec refresh(Supervisor.supervisor(), [Supervisor.child_spec()]) :: :ok
  def refresh(supervisor \\ __MODULE__, children) do
    {present_children, started_children} = group_children(supervisor)

    for %{id: id} = spec <- children, feature_children?(spec) do
      enabled? = enabled?(spec)
      present? = id in present_children
      started? = id in started_children
      permanent? = Map.get(spec, :restart, :permanent) == :permanent

      cond do
        enabled? and present? and permanent? and not started? ->
          case Supervisor.restart_child(supervisor, id) do
            {:ok, pid} -> log_started(spec, pid)
            {:ok, pid, _info} -> log_started(spec, pid)
            {:error, error} -> log_error(spec, error)
          end

        enabled? and not present? ->
          # make dialyzer happy
          spec = Map.delete(spec, :enabled?)

          case Supervisor.start_child(supervisor, spec) do
            {:ok, pid} -> log_started(spec, pid)
            {:ok, pid, _info} -> log_started(spec, pid)
            {:error, error} -> log_error(spec, error)
          end

        not enabled? and started? ->
          Supervisor.terminate_child(supervisor, id)
          Logger.info("[FeatureSupervisor] terminated child #{inspect(id)}")

        true ->
          :ok
      end
    end

    :ok
  end

  defp feature_children?(spec), do: Map.has_key?(spec, :enabled?)

  defp enabled?(%{enabled?: val}) when is_boolean(val), do: val
  defp enabled?(%{enabled?: fun} = spec) when is_function(fun, 1), do: fun.(spec)

  defp group_children(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.reduce({[], []}, fn {id, pid, _type, _modules}, {present, started} ->
      {[id | present], if(is_pid(pid), do: [id | started], else: started)}
    end)
  end

  defp log_started(spec, pid) do
    Logger.info("[FeatureSupervisor] started child #{inspect(spec.id)} #{inspect(pid)}")
  end

  defp log_error(spec, error) do
    Logger.error(
      "[FeatureSupervisor] failed to start child #{inspect(spec.id)} with error #{inspect(error)}"
    )
  end
end
