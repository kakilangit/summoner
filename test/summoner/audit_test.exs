defmodule Summoner.AuditTest do
  use Summoner.DataCase

  alias Summoner.Audit

  import Summoner.AccountsFixtures
  import Summoner.AgentsFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    %{scope: scope, workspace: workspace, agent: agent}
  end

  # -------------------------------------------------------------------
  # log/1
  # -------------------------------------------------------------------

  describe "log/1" do
    setup :create_context

    test "creates an audit log with all fields", %{scope: scope, workspace: ws, agent: fam} do
      {:ok, log} =
        Audit.log(%{
          workspace_id: ws.id,
          user_id: scope.user.id,
          agent_id: fam.id,
          action: "quota_exceeded",
          detail: %{"usage" => 52_000, "quota" => 50_000}
        })

      assert log.action == "quota_exceeded"
      assert log.detail == %{"usage" => 52_000, "quota" => 50_000}
      assert log.workspace_id == ws.id
      assert log.user_id == scope.user.id
      assert log.agent_id == fam.id
    end

    test "creates with only required fields", %{workspace: ws} do
      {:ok, log} = Audit.log(%{workspace_id: ws.id, action: "provider_added"})

      assert log.action == "provider_added"
      assert log.user_id == nil
      assert log.agent_id == nil
      assert log.detail == nil
    end

    test "fails without workspace_id" do
      assert {:error, %Ecto.Changeset{}} = Audit.log(%{action: "test"})
    end

    test "fails without action", %{workspace: ws} do
      assert {:error, %Ecto.Changeset{}} = Audit.log(%{workspace_id: ws.id})
    end

    test "fails with empty action", %{workspace: ws} do
      {:error, changeset} = Audit.log(%{workspace_id: ws.id, action: ""})
      assert errors_on(changeset).action
    end
  end

  # -------------------------------------------------------------------
  # list_logs/2
  # -------------------------------------------------------------------

  describe "list_logs/2" do
    setup :create_context

    test "returns logs ordered by most recent", %{workspace: ws} do
      {:ok, l1} = Audit.log(%{workspace_id: ws.id, action: "first"})
      {:ok, l2} = Audit.log(%{workspace_id: ws.id, action: "second"})

      result = Audit.list_logs(ws.id)
      assert [%{id: id2}, %{id: id1}] = result
      assert id1 == l1.id
      assert id2 == l2.id
    end

    test "filters by action", %{workspace: ws} do
      {:ok, _} = Audit.log(%{workspace_id: ws.id, action: "quota_exceeded"})
      {:ok, _} = Audit.log(%{workspace_id: ws.id, action: "provider_added"})

      result = Audit.list_logs(ws.id, action: "quota_exceeded")
      assert length(result) == 1
      assert hd(result).action == "quota_exceeded"
    end

    test "filters by user_id", %{scope: scope, workspace: ws} do
      {:ok, _} = Audit.log(%{workspace_id: ws.id, action: "a", user_id: scope.user.id})
      {:ok, _} = Audit.log(%{workspace_id: ws.id, action: "b"})

      result = Audit.list_logs(ws.id, user_id: scope.user.id)
      assert length(result) == 1
    end

    test "filters by agent_id", %{workspace: ws, agent: fam} do
      {:ok, _} = Audit.log(%{workspace_id: ws.id, action: "a", agent_id: fam.id})
      {:ok, _} = Audit.log(%{workspace_id: ws.id, action: "b"})

      result = Audit.list_logs(ws.id, agent_id: fam.id)
      assert length(result) == 1
    end

    test "respects limit", %{workspace: ws} do
      for i <- 1..5, do: Audit.log(%{workspace_id: ws.id, action: "action_#{i}"})

      result = Audit.list_logs(ws.id, limit: 3)
      assert length(result) == 3
    end

    test "supports pagination via offset", %{workspace: ws} do
      for i <- 1..5, do: Audit.log(%{workspace_id: ws.id, action: "action_#{i}"})

      page1 = Audit.list_logs(ws.id, limit: 2, offset: 0)
      page2 = Audit.list_logs(ws.id, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 2

      page1_ids = Enum.map(page1, & &1.id)
      page2_ids = Enum.map(page2, & &1.id)
      assert Enum.all?(page2_ids, &(&1 not in page1_ids))
    end

    test "does not return logs from other workspaces", %{scope: scope, workspace: ws} do
      {:ok, _} = Audit.log(%{workspace_id: ws.id, action: "mine"})

      other_ws = workspace_fixture(scope, name: "other-ws")
      {:ok, _} = Audit.log(%{workspace_id: other_ws.id, action: "theirs"})

      result = Audit.list_logs(ws.id)
      assert length(result) == 1
      assert hd(result).action == "mine"
    end
  end
end
