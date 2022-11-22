defmodule FeatureSupervisorTest do
  use ExUnit.Case

  describe "init/2" do
    test "equal to Supervisor.init/2 when used with static only children" do
      children = [
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child1),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child2),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child3)
      ]

      assert {:ok, {flags, children}} = FeatureSupervisor.init(children, strategy: :one_for_one)
      assert %{strategy: :one_for_one, intensity: 3, period: 5} = flags

      assert [
               %{id: :child1},
               %{id: :child2},
               %{id: :child3}
             ] = children
    end

    test "excludes disabled children" do
      children = [
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child1),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
      ]

      assert {:ok, {_flags, children}} = FeatureSupervisor.init(children, strategy: :one_for_one)

      assert [
               %{id: :child1},
               %{id: :child2}
             ] = children
    end

    test "includes the manager child when the :refresh_interval option is present" do
      children = [
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child1),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
      ]

      assert {:ok, {_flags, children}} =
               FeatureSupervisor.init(children,
                 strategy: :one_for_one,
                 refresh_interval: 1000
               )

      assert [
               %{id: :child1},
               %{id: :child2},
               %{id: FeatureSupervisor.Manager, start: {_, _, [monitor_options]}}
             ] = children

      assert [
               %{id: :child2},
               %{id: :child3}
             ] = monitor_options[:children]
    end
  end

  describe "refresh/2" do
    setup do
      children = [
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child1),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
      ]

      {:ok, pid} = FeatureSupervisor.start_link(children, strategy: :one_for_one)
      {:ok, children: children, supervisor: pid}
    end

    test "starts the child if a feature was enabled", ctx do
      assert [
               {:child2, pid2, _, _},
               {:child1, pid1, _, _}
             ] = Supervisor.which_children(ctx.supervisor)

      assert is_pid(pid2)
      assert is_pid(pid1)

      children = [
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: true)
      ]

      assert :ok = FeatureSupervisor.refresh(ctx.supervisor, children)

      assert [
               {:child3, pid3, _, _},
               {:child2, ^pid2, _, _},
               {:child1, ^pid1, _, _}
             ] = Supervisor.which_children(ctx.supervisor)

      assert is_pid(pid3)
    end

    test "terminates the child if a feature was disabled", ctx do
      assert [
               {:child2, _pid, _, _},
               {:child1, pid1, _, _}
             ] = Supervisor.which_children(ctx.supervisor)

      children = [
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: false),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
      ]

      assert :ok = FeatureSupervisor.refresh(ctx.supervisor, children)

      assert [
               {:child2, :undefined, _, _},
               {:child1, ^pid1, _, _}
             ] = Supervisor.which_children(ctx.supervisor)

      assert is_pid(pid1)
    end

    test "restarts the child if a feature was re-enabled", ctx do
      assert :ok = Supervisor.terminate_child(ctx.supervisor, :child2)

      children = [
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
      ]

      assert :ok = FeatureSupervisor.refresh(ctx.supervisor, children)

      assert [
               {:child2, pid2, _, _},
               {:child1, pid1, _, _}
             ] = Supervisor.which_children(ctx.supervisor)

      assert is_pid(pid2)
      assert is_pid(pid1)
    end
  end

  describe "automatic refresh" do
    test "works" do
      init_store = fn ->
        %{
          feature1: true,
          feature2: false
        }
      end

      enabled? = fn %{feat_id: feat_id} ->
        try do
          Agent.get(:store, &Map.fetch!(&1, feat_id))
        catch
          :exit, {:noproc, _} -> false
        end
      end

      children = [
        %{
          id: :child1,
          start: {:erlang, :apply, [Agent, :start_link, [init_store, [name: :store]]]}
        },
        FeatureSupervisor.child_spec({Agent, fn -> :ok end},
          id: :child2,
          feat_id: :feature1,
          enabled?: enabled?
        ),
        FeatureSupervisor.child_spec({Agent, fn -> :ok end},
          id: :child3,
          feat_id: :feature2,
          enabled?: enabled?
        )
      ]

      refresh_interval = 10

      assert {:ok, sup_pid} =
               FeatureSupervisor.start_link(children,
                 refresh_interval: refresh_interval,
                 strategy: :one_for_one,
                 name: __MODULE__
               )

      assert [
               {FeatureSupervisor.Manager, pid, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup_pid)

      Process.sleep(refresh_interval)
      # wait for the monitor to finish refreshing
      :sys.get_state(pid)

      assert [
               {:child2, _, _, _},
               {FeatureSupervisor.Manager, _, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup_pid)
    end
  end
end
