defmodule Summoner.Domain.Schemas.PluginInstallationTest do
  use Summoner.DataCase

  alias Summoner.Domain.Schemas.PluginInstallation

  defp valid_attrs do
    %{
      name: "grimoire-test",
      ref: "a1b2c3d4e5f6",
      version: "1.0.0",
      capabilities: ["tools"],
      manifest: %{"name" => "grimoire-test", "version" => "1.0.0"},
      workspace_id: Nulid.Ecto.autogenerate()
    }
  end

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = PluginInstallation.changeset(%PluginInstallation{}, valid_attrs())
      assert changeset.valid?
    end

    test "requires name, ref, version, manifest, workspace_id" do
      changeset = PluginInstallation.changeset(%PluginInstallation{}, %{})
      errors = errors_on(changeset)

      assert errors[:name]
      assert errors[:ref]
      assert errors[:version]
      assert errors[:manifest]
      assert errors[:workspace_id]
    end

    test "rejects invalid capabilities" do
      changeset =
        PluginInstallation.changeset(
          %PluginInstallation{},
          %{valid_attrs() | capabilities: ["invalid_cap"]}
        )

      assert %{capabilities: [_]} = errors_on(changeset)
    end

    test "accepts all valid capabilities" do
      all_caps = PluginInstallation.valid_capabilities()

      changeset =
        PluginInstallation.changeset(
          %PluginInstallation{},
          %{valid_attrs() | capabilities: all_caps}
        )

      assert changeset.valid?
    end

    test "defaults status to installed" do
      changeset = PluginInstallation.changeset(%PluginInstallation{}, valid_attrs())
      assert Ecto.Changeset.get_field(changeset, :status) == :installed
    end

    test "defaults config to empty map" do
      changeset = PluginInstallation.changeset(%PluginInstallation{}, valid_attrs())
      assert Ecto.Changeset.get_field(changeset, :config) == %{}
    end
  end

  describe "status_changeset/3" do
    test "updates status" do
      plugin = %PluginInstallation{status: :installed}
      changeset = PluginInstallation.status_changeset(plugin, :enabled)
      assert Ecto.Changeset.get_change(changeset, :status) == :enabled
    end

    test "sets error message" do
      plugin = %PluginInstallation{status: :enabled}
      changeset = PluginInstallation.status_changeset(plugin, :error, "container crashed")
      assert Ecto.Changeset.get_change(changeset, :error_message) == "container crashed"
    end
  end
end
