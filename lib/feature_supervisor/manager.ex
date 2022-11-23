defmodule FeatureSupervisor.Manager do
  @moduledoc false
  use GenServer

  defmodule State do
    @moduledoc false
    defstruct children: [],
              supervisor: FeatureSupervisor,
              refresh_interval: 5000,
              timer: nil
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    fields = Keyword.take(opts, [:children, :supervisor, :refresh_interval])
    {:ok, State |> struct!(fields) |> set_timer()}
  end

  @impl true
  def handle_info(:refresh, %State{children: children, supervisor: supervisor} = state) do
    Process.cancel_timer(state.timer)
    FeatureSupervisor.refresh(supervisor, children)
    {:noreply, set_timer(state)}
  end

  def set_timer(state) do
    %{state | timer: Process.send_after(self(), :refresh, state.refresh_interval)}
  end
end
