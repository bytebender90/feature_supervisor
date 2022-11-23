defmodule FeatureSupervisorTest do
  use ExUnit.Case

  import FeatureSupervisor, only: [child_spec: 2]

  @moduletag :capture_log

  describe "init/2" do
    test "equal to Supervisor.init/2 when used with static only children" do
      children = [
        child_spec({Agent, fn -> :ok end}, id: :child1),
        child_spec({Agent, fn -> :ok end}, id: :child2),
        child_spec({Agent, fn -> :ok end}, id: :child3)
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
        child_spec({Agent, fn -> :ok end}, id: :child1),
        child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
      ]

      assert {:ok, {_flags, children}} = FeatureSupervisor.init(children, strategy: :one_for_one)

      assert [
               %{id: :child1},
               %{id: :child2}
             ] = children
    end

    test "appends the manager child when the :refresh_interval option is present and there are feature children" do
      children = [
        child_spec({Agent, fn -> :ok end}, id: :child1),
        child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
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
    test "starts a child when its feature enabled" do
      children = [
        child_spec({Agent, fn -> :ok end}, id: :child1),
        child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: false)
      ]

      {:ok, sup} = FeatureSupervisor.start_link(children, strategy: :one_for_one)

      assert [
               {:child2, _, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup)

      children =
        children
        |> List.update_at(2, &child_spec(&1, enabled?: true))

      assert :ok = FeatureSupervisor.refresh(sup, children)

      assert [
               {:child3, _, _, _},
               {:child2, _, _, _},
               {:child1, _, _, _}
             ] = Supervisor.which_children(sup)
    end

    test "terminates a child when its feature disabled" do
      children = [
        child_spec({Agent, fn -> :ok end}, id: :child1),
        child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: true)
      ]

      {:ok, sup} = FeatureSupervisor.start_link(children, strategy: :one_for_one)

      assert [
               {:child3, pid3, _, _},
               {:child2, pid2, _, _},
               {:child1, pid1, _, _}
             ] = Supervisor.which_children(sup)

      children =
        children
        |> List.update_at(1, &child_spec(&1, enabled?: false))
        |> List.update_at(2, &child_spec(&1, enabled?: false))

      assert :ok = FeatureSupervisor.refresh(sup, children)

      assert [
               {:child3, :undefined, _, _},
               {:child2, :undefined, _, _},
               {:child1, ^pid1, _, _}
             ] = Supervisor.which_children(sup)

      assert Process.alive?(pid1)
      refute Process.alive?(pid2)
      refute Process.alive?(pid3)
    end

    test "restarts a non-permanent child when its feature re-enabled" do
      children = [
        child_spec({Agent, fn -> :ok end}, id: :child1),
        child_spec({Agent, fn -> :ok end}, id: :child2, enabled?: true),
        child_spec({Agent, fn -> :ok end}, id: :child3, enabled?: true, restart: :transient)
      ]

      {:ok, sup} = FeatureSupervisor.start_link(children, strategy: :one_for_one)
      # simulate feature disabling
      assert :ok = Supervisor.terminate_child(sup, :child2)
      assert :ok = Supervisor.terminate_child(sup, :child3)

      assert :ok = FeatureSupervisor.refresh(sup, children)

      assert [
               {:child3, :undefined, _, _},
               {:child2, pid2, _, _},
               {:child1, pid1, _, _}
             ] = Supervisor.which_children(sup)

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
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
        child_spec({Agent, fn -> :ok end}, id: :child2, feat_id: :feature1, enabled?: enabled?),
        child_spec({Agent, fn -> :ok end}, id: :child3, feat_id: :feature2, enabled?: enabled?)
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
