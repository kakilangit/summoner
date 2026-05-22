defmodule Summoner.Domain.Policies.ContractValidatorTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.ContractValidator

  describe "validate_tools/2" do
    test "passes when all expected tools present" do
      tools = [%{"name" => "foo"}, %{"name" => "bar"}]
      assert :ok = ContractValidator.validate_tools(tools, ["foo", "bar"])
    end

    test "fails when expected tools missing" do
      tools = [%{"name" => "foo"}]
      assert {:error, msg} = ContractValidator.validate_tools(tools, ["foo", "bar"])
      assert msg =~ "bar"
    end

    test "passes with empty expected list" do
      assert :ok = ContractValidator.validate_tools([%{"name" => "x"}], [])
    end
  end

  describe "validate_webhook_response/1" do
    test "passes with actions array" do
      assert :ok = ContractValidator.validate_webhook_response(%{"actions" => []})
    end

    test "fails without actions" do
      assert {:error, _} = ContractValidator.validate_webhook_response(%{})
    end
  end

  describe "validate_hook_response/1" do
    test "accepts proceed" do
      assert :ok = ContractValidator.validate_hook_response(%{"action" => "proceed"})
    end

    test "accepts modify" do
      assert :ok = ContractValidator.validate_hook_response(%{"action" => "modify"})
    end

    test "accepts halt" do
      assert :ok = ContractValidator.validate_hook_response(%{"action" => "halt"})
    end

    test "rejects unknown action" do
      assert {:error, _} = ContractValidator.validate_hook_response(%{"action" => "nope"})
    end

    test "rejects missing action" do
      assert {:error, _} = ContractValidator.validate_hook_response(%{})
    end
  end

  describe "validate_models_response/1" do
    test "passes with valid model list" do
      models = [%{"id" => "m1", "name" => "Model 1"}]
      assert :ok = ContractValidator.validate_models_response(models)
    end

    test "fails with missing fields" do
      models = [%{"id" => "m1"}]
      assert {:error, _} = ContractValidator.validate_models_response(models)
    end

    test "fails with non-list" do
      assert {:error, _} = ContractValidator.validate_models_response("not a list")
    end
  end
end
