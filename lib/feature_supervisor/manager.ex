defmodule FeatureSupervisor.Manager do
  @moduledoc false
  use GenServer, restart: :transient

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [:children, :supervisor, :sync_interval, :timer]
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.put_new(opts, :supervisor, self())
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %State{
      children: Keyword.fetch!(opts, :children),
      supervisor: Keyword.fetch!(opts, :supervisor),
      sync_interval: Keyword.get(opts, :sync_interval)
    }

    {:ok, state, {:continue, :sync}}
  end

  @impl true
  def handle_continue(:sync, %State{} = state) do
    children = sync(state.children, state.supervisor)

    if Enum.empty?(children) or is_nil(state.sync_interval) do
      {:stop, :normal, %{state | children: children}}
    else
      timer = Process.send_after(self(), :timer_end, state.sync_interval)
      {:noreply, %{state | children: children, timer: timer}}
    end
  end

  @impl true
  def handle_info(:timer_end, state) do
    {:noreply, state, {:continue, :sync}}
  end

  @spec sync([Supervisor.child_spec()], Supervisor.supervisor()) :: [Supervisor.child_spec()]
  def sync(children, supervisor) do
    {present_ids, started_ids} =
      supervisor
      |> Supervisor.which_children()
      |> group_supervisor_children()

    Enum.reject(children, fn %{id: id} = spec ->
      enabled? = enabled?(spec)
      present? = id in present_ids
      started? = id in started_ids

      cond do
        enabled? and present? and not started? ->
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

      _reject? = enabled? and temporary?(spec)
    end)
  end

  defp enabled?(%{enabled?: fun} = spec) when is_function(fun, 1), do: fun.(spec)

  defp temporary?(spec), do: Map.get(spec, :restart, :permanent) != :permanent

  defp group_supervisor_children(children) do
    Enum.reduce(children, {[], []}, fn {id, pid, _type, _modules}, {present_ids, started_ids} ->
      {[id | present_ids], if(is_pid(pid), do: [id | started_ids], else: started_ids)}
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
