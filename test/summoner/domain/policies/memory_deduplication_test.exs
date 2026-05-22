defmodule Summoner.Domain.Policies.MemoryDeduplicationTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.MemoryDeduplication

  describe "duplicate?/3" do
    test "identical strings are duplicates" do
      assert MemoryDeduplication.duplicate?("hello world", "hello world")
    end

    test "case-insensitive match" do
      assert MemoryDeduplication.duplicate?("Hello World", "hello world")
    end

    test "whitespace-trimmed match" do
      assert MemoryDeduplication.duplicate?("  hello world  ", "hello world")
    end

    test "very similar strings are duplicates" do
      assert MemoryDeduplication.duplicate?(
               "The user prefers dark mode",
               "The user prefers dark modes"
             )
    end

    test "different strings are not duplicates" do
      refute MemoryDeduplication.duplicate?(
               "The user prefers dark mode",
               "Always respond in French"
             )
    end

    test "custom threshold" do
      # With a very high threshold, even similar strings aren't duplicates
      refute MemoryDeduplication.duplicate?(
               "hello world",
               "hello worlds",
               threshold: 0.99
             )
    end

    test "empty strings are duplicates" do
      assert MemoryDeduplication.duplicate?("", "")
    end
  end
end
