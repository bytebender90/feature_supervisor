defmodule FeatureSupervisorTest do
  use ExUnit.Case

  import FeatureSupervisor, only: [child_spec: 2]

  alias FeatureSupervisor.Manager

  defmodule Child do
    use Agent

    def start_link(opts) do
      Agent.start_link(
        fn ->
          case opts[:send] do
            {pid, msg} -> send(pid, {self(), msg})
            nil -> :ok
          end

          opts[:state]
        end,
        opts
      )
    end
  end

  @moduletag :capture_log

  describe "group_children/2" do
    test "splits children into 'static' and 'features' groups" do
      children = [
        Child,
        child_spec(Child, id: :child2, enabled?: true),
        child_spec(Child, id: :child3, enabled?: false),
        child_spec(Child, id: :child4, enabled?: fn _ -> true end)
      ]

      assert {
               static,
               dynamic
             } = FeatureSupervisor.group_children(children)

      assert [
               %{id: Child},
               %{id: :child2}
             ] = static

      assert [
               %{id: :child4}
             ] = dynamic
    end
  end

  describe "start_link/2" do
    test "works with static only children" do
      children = [
        child_spec(Child, id: :child1),
        child_spec(Child, id: :child2, enabled?: false),
        child_spec(Child, id: :child3, enabled?: true)
      ]

      {:ok, sup} = FeatureSupervisor.start_link(children, strategy: :one_for_one)

      assert [
               {:child3, _, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup)
    end

    test "works with dynamic children" do
      children = [
        child_spec(Child, id: :child1),
        child_spec({Child, send: {self(), :up2}}, id: :child2, enabled?: fn _ -> false end),
        child_spec({Child, send: {self(), :up3}}, id: :child3, enabled?: fn _ -> true end)
      ]

      {:ok, sup} = FeatureSupervisor.start_link(children, strategy: :one_for_one)

      assert_receive {pid3, :up3}

      assert [
               {:child3, ^pid3, _, _},
               {Manager, _, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup)
    end

    test "manages dynamic children in the sync mode" do
      me = self()
      enabled? = fn %{id: id} -> Agent.get(:store, &Map.fetch!(&1, id)) end

      children = [
        child_spec({Child, state: %{child2: false, child3: true}, name: :store}, id: :child1),
        child_spec({Child, send: {me, :up2}}, id: :child2, enabled?: enabled?),
        child_spec({Child, send: {me, :up3}}, id: :child3, enabled?: enabled?)
      ]

      {:ok, sup} =
        FeatureSupervisor.start_link(children,
          strategy: :one_for_one,
          sync_interval: 10
        )

      assert_receive {pid3, :up3}
      Process.monitor(pid3)

      assert [
               {:child3, _, _, _},
               {Manager, _, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup)

      Agent.update(:store, fn _ -> %{child2: true, child3: false} end)

      assert_receive {pid2, :up2}
      assert_receive {:DOWN, _ref, :process, ^pid3, :shutdown}

      assert [
               {:child2, ^pid2, _, _},
               {:child3, :undefined, _, _},
               {Manager, _, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup)
    end

    test "does not restart temporary children in the sync mode" do
      me = self()

      children = [
        child_spec({Task, fn -> send(me, {:task1, self()}) end},
          id: :task1,
          restart: :temporary,
          enabled?: fn _ -> true end
        ),
        child_spec({Task, fn -> send(me, {:task2, self()}) end},
          id: :task2,
          restart: :transient,
          enabled?: fn _ -> true end
        )
      ]

      {:ok, _sup} =
        FeatureSupervisor.start_link(children,
          strategy: :one_for_one,
          sync_interval: 10
        )

      assert_receive {:task1, pid1}
      assert_receive {:task2, pid2}

      Process.monitor(pid1)
      Process.monitor(pid2)

      assert_receive {:DOWN, _ref, :process, ^pid1, _reason}
      assert_receive {:DOWN, _ref, :process, ^pid2, _reason}

      refute_receive {:task1, _}, 20
      refute_receive {:task2, _}, 20
    end
  end
end
