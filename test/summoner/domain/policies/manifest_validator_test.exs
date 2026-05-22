defmodule Summoner.Domain.Policies.ManifestValidatorTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.ManifestValidator

  defp base_manifest do
    %{
      "name" => "grimoire-test",
      "version" => "1.0.0",
      "image" => "ghcr.io/test:1.0.0",
      "capabilities" => ["tools"]
    }
  end

  describe "validate/1" do
    test "accepts minimal valid manifest" do
      assert {:ok, _} = ManifestValidator.validate(base_manifest())
    end

    test "rejects non-map" do
      assert {:error, ["manifest must be a map"]} = ManifestValidator.validate("string")
    end

    test "rejects missing required fields" do
      assert {:error, errors} = ManifestValidator.validate(%{})
      assert Enum.any?(errors, &String.contains?(&1, "name"))
      assert Enum.any?(errors, &String.contains?(&1, "image"))
      assert Enum.any?(errors, &String.contains?(&1, "capabilities"))
    end

    test "rejects invalid capabilities" do
      manifest = %{base_manifest() | "capabilities" => ["bogus"]}
      assert {:error, errors} = ManifestValidator.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "bogus"))
    end

    test "rejects empty capabilities" do
      manifest = %{base_manifest() | "capabilities" => []}
      assert {:error, errors} = ManifestValidator.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "empty"))
    end

    test "webhooks capability requires routes" do
      manifest = %{base_manifest() | "capabilities" => ["webhooks"]}
      assert {:error, errors} = ManifestValidator.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "webhooks.routes"))
    end

    test "webhooks with valid routes passes" do
      manifest =
        base_manifest()
        |> Map.put("capabilities", ["webhooks"])
        |> Map.put("webhooks", %{"routes" => ["events"]})

      assert {:ok, _} = ManifestValidator.validate(manifest)
    end

    test "events capability requires subscribes" do
      manifest = %{base_manifest() | "capabilities" => ["events"]}
      assert {:error, errors} = ManifestValidator.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "events.subscribes"))
    end

    test "events with valid subscribes passes" do
      manifest =
        base_manifest()
        |> Map.put("capabilities", ["events"])
        |> Map.put("events", %{"subscribes" => ["invocation.completed"]})

      assert {:ok, _} = ManifestValidator.validate(manifest)
    end

    test "hooks capability requires valid points" do
      manifest = %{base_manifest() | "capabilities" => ["hooks"]}
      assert {:error, errors} = ManifestValidator.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "hooks.points"))
    end

    test "hooks with invalid points rejected" do
      manifest =
        base_manifest()
        |> Map.put("capabilities", ["hooks"])
        |> Map.put("hooks", %{"points" => ["invalid_point"]})

      assert {:error, errors} = ManifestValidator.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "invalid_point"))
    end

    test "hooks with valid points passes" do
      manifest =
        base_manifest()
        |> Map.put("capabilities", ["hooks"])
        |> Map.put("hooks", %{"points" => ["before_invocation", "on_error"]})

      assert {:ok, _} = ManifestValidator.validate(manifest)
    end

    test "provider capability requires name" do
      manifest = %{base_manifest() | "capabilities" => ["provider"]}
      assert {:error, errors} = ManifestValidator.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "provider.name"))
    end

    test "provider with valid name passes" do
      manifest =
        base_manifest()
        |> Map.put("capabilities", ["provider"])
        |> Map.put("provider", %{"name" => "Custom LLM"})

      assert {:ok, _} = ManifestValidator.validate(manifest)
    end

    test "multiple capabilities validated together" do
      manifest =
        base_manifest()
        |> Map.put("capabilities", ["tools", "webhooks", "events"])
        |> Map.put("webhooks", %{"routes" => ["events"]})
        |> Map.put("events", %{"subscribes" => ["invocation.completed"]})

      assert {:ok, _} = ManifestValidator.validate(manifest)
    end

    test "tools and theme require no extra config" do
      manifest = %{base_manifest() | "capabilities" => ["tools", "theme"]}
      assert {:ok, _} = ManifestValidator.validate(manifest)
    end
  end
end
