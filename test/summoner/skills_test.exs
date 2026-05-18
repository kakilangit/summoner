defmodule Summoner.SkillsTest do
  use Summoner.DataCase

  alias Summoner.Skills

  import Summoner.AccountsFixtures
  import Summoner.WorkspacesFixtures
  import Summoner.ProvidersFixtures
  import Summoner.AgentsFixtures
  import Summoner.SkillsFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    %{scope: scope, workspace: workspace, provider: provider, agent: agent}
  end

  # -------------------------------------------------------------------
  # Skill CRUD
  # -------------------------------------------------------------------

  describe "create_skill/2" do
    setup :create_context

    test "creates a skill", %{scope: scope, workspace: ws} do
      {:ok, skill} =
        Skills.create_skill(scope, %{
          name: "elixir-basics",
          content: "Elixir is a functional language.",
          workspace_id: ws.id
        })

      assert skill.name == "elixir-basics"
      assert skill.content == "Elixir is a functional language."
      assert skill.workspace_id == ws.id
      assert is_nil(skill.embedding)
    end

    test "rejects duplicate names in same workspace", %{scope: scope, workspace: ws} do
      skill_fixture(scope, ws.id, %{name: "duplicate"})

      {:error, changeset} =
        Skills.create_skill(scope, %{
          name: "duplicate",
          content: "some content",
          workspace_id: ws.id
        })

      assert errors_on(changeset).workspace_id || errors_on(changeset).name
    end

    test "requires name and content", %{scope: scope, workspace: ws} do
      {:error, changeset} = Skills.create_skill(scope, %{workspace_id: ws.id})
      assert errors_on(changeset).name
      assert errors_on(changeset).content
    end
  end

  describe "list_skills/2" do
    setup :create_context

    test "returns skills ordered by name", %{scope: scope, workspace: ws} do
      skill_fixture(scope, ws.id, %{name: "zeta"})
      skill_fixture(scope, ws.id, %{name: "alpha"})

      skills = Skills.list_skills(scope, ws.id, ws.tenant_id)
      assert [%{name: "alpha"}, %{name: "zeta"}] = skills
    end

    test "scopes to workspace", %{scope: scope, workspace: ws} do
      skill_fixture(scope, ws.id)

      other_ws = workspace_fixture(scope, %{name: "other-ws"})
      skill_fixture(scope, other_ws.id, %{name: "other-skill"})

      skills = Skills.list_skills(scope, ws.id, ws.tenant_id)
      assert length(skills) == 1
    end
  end

  describe "get_skill!/3" do
    setup :create_context

    test "returns skill by id", %{scope: scope, workspace: ws} do
      skill = skill_fixture(scope, ws.id)
      found = Skills.get_skill!(scope, ws.id, ws.tenant_id, skill.id)
      assert found.id == skill.id
    end
  end

  describe "update_skill/3" do
    setup :create_context

    test "updates skill content", %{scope: scope, workspace: ws} do
      skill = skill_fixture(scope, ws.id)
      {:ok, updated} = Skills.update_skill(scope, skill, %{content: "new content"})
      assert updated.content == "new content"
    end
  end

  describe "delete_skill/2" do
    setup :create_context

    test "deletes a skill", %{scope: scope, workspace: ws} do
      skill = skill_fixture(scope, ws.id)
      {:ok, _} = Skills.delete_skill(scope, skill)

      assert_raise Ecto.NoResultsError, fn ->
        Skills.get_skill!(scope, ws.id, ws.tenant_id, skill.id)
      end
    end

    test "rejects deletion when equipped to an agent", %{
      scope: scope,
      workspace: ws,
      agent: agent
    } do
      skill = skill_fixture(scope, ws.id)
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: skill.id})

      {:error, changeset} = Skills.delete_skill(scope, skill)
      assert errors_on(changeset).agent_skills
    end
  end

  # -------------------------------------------------------------------
  # Equip / Unequip
  # -------------------------------------------------------------------

  describe "equip_skill/2" do
    setup :create_context

    test "equips a skill to an agent", %{scope: scope, workspace: ws, agent: agent} do
      skill = skill_fixture(scope, ws.id)
      {:ok, link} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: skill.id})
      assert link.agent_id == agent.id
      assert link.skill_id == skill.id
    end

    test "rejects duplicate equip", %{scope: scope, workspace: ws, agent: agent} do
      skill = skill_fixture(scope, ws.id)
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: skill.id})
      {:error, changeset} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: skill.id})
      assert errors_on(changeset).agent_id
    end
  end

  describe "unequip_skill/3" do
    setup :create_context

    test "unequips a skill", %{scope: scope, workspace: ws, agent: agent} do
      skill = skill_fixture(scope, ws.id)
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: skill.id})
      {:ok, _} = Skills.unequip_skill(scope, agent.id, skill.id)

      assert Skills.list_equipped_skills(scope, agent.id) == []
    end

    test "returns error for non-existent link", %{scope: scope, agent: agent} do
      {:ok, id} = Nulid.generate()
      assert {:error, :not_found} = Skills.unequip_skill(scope, agent.id, id)
    end
  end

  describe "list_equipped_skills/2" do
    setup :create_context

    test "returns equipped skills", %{scope: scope, workspace: ws, agent: agent} do
      s1 = skill_fixture(scope, ws.id, %{name: "alpha"})
      s2 = skill_fixture(scope, ws.id, %{name: "beta"})
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s1.id})
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s2.id})

      skills = Skills.list_equipped_skills(scope, agent.id)
      assert length(skills) == 2
    end
  end

  describe "list_available_skills/3" do
    setup :create_context

    test "excludes already equipped skills", %{scope: scope, workspace: ws, agent: agent} do
      s1 = skill_fixture(scope, ws.id, %{name: "equipped"})
      _s2 = skill_fixture(scope, ws.id, %{name: "available"})
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s1.id})

      available = Skills.list_available_skills(scope, ws.id, ws.tenant_id, agent.id)
      assert length(available) == 1
      assert hd(available).name == "available"
    end
  end

  # -------------------------------------------------------------------
  # Embedding
  # -------------------------------------------------------------------

  describe "update_embedding/2" do
    setup :create_context

    test "stores an embedding vector", %{scope: scope, workspace: ws} do
      skill = skill_fixture(scope, ws.id)
      embedding = List.duplicate(0.1, 1536)
      {:ok, updated} = Skills.update_embedding(skill, embedding)
      assert updated.embedding != nil
      assert length(updated.embedding) == 1536
    end
  end

  describe "find_relevant_skills/3" do
    setup :create_context

    test "returns skills ordered by cosine similarity", %{
      scope: scope,
      workspace: ws,
      agent: agent
    } do
      s1 = skill_fixture(scope, ws.id, %{name: "close"})
      s2 = skill_fixture(scope, ws.id, %{name: "far"})

      # Create two distinct embeddings
      close_embedding = [1.0] ++ List.duplicate(0.0, 1535)
      far_embedding = List.duplicate(0.0, 1535) ++ [1.0]

      {:ok, _} = Skills.update_embedding(s1, close_embedding)
      {:ok, _} = Skills.update_embedding(s2, far_embedding)

      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s1.id})
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s2.id})

      # Query with embedding similar to s1
      query = [0.9] ++ List.duplicate(0.0, 1535)
      results = Skills.find_relevant_skills(agent.id, query, limit: 2, max_distance: 1.0)

      assert length(results) == 2
      assert hd(results).name == "close"
    end

    test "only returns equipped skills", %{scope: scope, workspace: ws, agent: agent} do
      s1 = skill_fixture(scope, ws.id, %{name: "equipped"})
      s2 = skill_fixture(scope, ws.id, %{name: "not-equipped"})

      embedding = List.duplicate(0.5, 1536)
      {:ok, _} = Skills.update_embedding(s1, embedding)
      {:ok, _} = Skills.update_embedding(s2, embedding)

      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s1.id})

      results = Skills.find_relevant_skills(agent.id, embedding, max_distance: 1.0)
      assert length(results) == 1
      assert hd(results).name == "equipped"
    end

    test "respects max_distance threshold", %{scope: scope, workspace: ws, agent: agent} do
      s1 = skill_fixture(scope, ws.id)
      far_embedding = List.duplicate(0.0, 1535) ++ [1.0]
      {:ok, _} = Skills.update_embedding(s1, far_embedding)
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s1.id})

      # Query in opposite direction — distance should exceed threshold
      query = [1.0] ++ List.duplicate(0.0, 1535)
      results = Skills.find_relevant_skills(agent.id, query, max_distance: 0.1)
      assert results == []
    end

    test "skips skills without embeddings", %{scope: scope, workspace: ws, agent: agent} do
      s1 = skill_fixture(scope, ws.id)
      {:ok, _} = Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: s1.id})

      query = List.duplicate(0.5, 1536)
      results = Skills.find_relevant_skills(agent.id, query, max_distance: 1.0)
      assert results == []
    end
  end
end
