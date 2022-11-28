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

    {:ok, state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, %State{sync_interval: nil} = state) do
    sync(state.children, state.supervisor)
    {:stop, :normal, state}
  end

  def handle_continue(:start, %State{} = state) do
    sync(state.children, state.supervisor)
    children = Enum.reject(state.children, &temporary?/1)
    timer = Process.send_after(self(), :sync, state.sync_interval)
    {:noreply, %{state | children: children, timer: timer}}
  end

  @impl true
  def handle_info(:sync, %State{} = state) do
    sync(state.children, state.supervisor)
    timer = Process.send_after(self(), :sync, state.sync_interval)
    {:noreply, %{state | timer: timer}}
  end

  defp sync(children, supervisor) do
    {present_ids, started_ids} =
      supervisor
      |> Supervisor.which_children()
      |> group_supervisor_children()

    for %{id: id} = spec <- children do
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
    end

    :ok
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
