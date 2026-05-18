defmodule Summoner.Presets do
  @moduledoc """
  Compile-time loader for presets (MCP servers, providers, etc.).

  Reads `priv/presets.json` at compile time and exposes typed
  accessors. Adding a new preset only requires editing the JSON file.
  """

  @presets_path Path.join(:code.priv_dir(:summoner), "presets.json")
  @external_resource @presets_path

  @raw Jason.decode!(File.read!(@presets_path))

  @mcp_servers @raw["mcp_servers"]
               |> Enum.map(fn {k, v} ->
                 {k, Map.new(v, fn {vk, vv} -> {String.to_atom(vk), vv} end)}
               end)
               |> Map.new()

  @providers @raw["providers"]
             |> Enum.map(fn {k, v} ->
               {k, Map.new(v, fn {vk, vv} -> {String.to_atom(vk), vv} end)}
             end)
             |> Map.new()

  @agents @raw["agents"]
          |> Enum.map(fn {k, v} ->
            {k, Map.new(v, fn {vk, vv} -> {String.to_atom(vk), vv} end)}
          end)
          |> Map.new()

  @skills @raw["skills"]
          |> Enum.map(fn {k, v} ->
            {k, Map.new(v, fn {vk, vv} -> {String.to_atom(vk), vv} end)}
          end)
          |> Map.new()

  @harness @raw["harness"]
           |> Enum.map(fn {k, v} -> {k, v} end)
           |> Map.new()

  # -------------------------------------------------------------------
  # MCP server presets
  # -------------------------------------------------------------------

  @doc "Returns the full MCP server presets map (string key → preset map)."
  def mcp_servers, do: @mcp_servers

  @doc "Returns a single MCP server preset by key, or nil."
  def mcp_server(key) when is_binary(key), do: Map.get(@mcp_servers, key)

  @doc """
  Returns MCP server presets as `{label, key}` options for a select input,
  sorted alphabetically by label, with a blank prompt prepended.
  """
  def mcp_server_options do
    [
      {"— Select a preset —", ""}
      | @mcp_servers
        |> Enum.map(fn {k, v} -> {v.label, k} end)
        |> Enum.sort_by(&elem(&1, 0))
    ]
  end

  # -------------------------------------------------------------------
  # Provider presets
  # -------------------------------------------------------------------

  @doc "Returns the full provider presets map (string key → preset map)."
  def providers, do: @providers

  @doc "Returns a single provider preset by key, or nil."
  def provider(key) when is_binary(key), do: Map.get(@providers, key)

  @doc "Returns a map of provider kind → default base_url."
  def provider_default_urls do
    @providers
    |> Enum.reject(fn {_k, v} -> v.base_url == "" end)
    |> Map.new(fn {k, v} -> {k, v.base_url} end)
  end

  @doc "Returns all default base_url values (for detecting user-changed URLs)."
  def provider_default_url_values do
    provider_default_urls() |> Map.values()
  end

  @doc """
  Returns provider presets as `{label, key}` options for a select input,
  sorted alphabetically by label.
  """
  def provider_kind_options do
    @providers
    |> Enum.map(fn {k, v} -> {v.label, k} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  # -------------------------------------------------------------------
  # Agent presets
  # -------------------------------------------------------------------

  @doc "Returns the full agent presets map (string key → preset map)."
  def agents, do: @agents

  @doc "Returns a single agent preset by key, or nil."
  def agent(key) when is_binary(key), do: Map.get(@agents, key)

  @doc """
  Returns agent presets as `{label, key}` options for a select input,
  sorted alphabetically by label, with a blank prompt prepended.
  """
  def agent_options do
    [
      {"— No template —", ""}
      | @agents
        |> Enum.map(fn {k, v} -> {v.label, k} end)
        |> Enum.sort_by(&elem(&1, 0))
    ]
  end

  # -------------------------------------------------------------------
  # Skill presets
  # -------------------------------------------------------------------

  @doc "Returns the full skill presets map (string key → preset map)."
  def skills, do: @skills

  @doc "Returns a single skill preset by key, or nil."
  def skill(key) when is_binary(key), do: Map.get(@skills, key)

  @doc """
  Returns skill presets as `{label, key}` options for a select input,
  sorted alphabetically by label, with a blank prompt prepended.
  """
  def skill_options do
    [
      {"— No template —", ""}
      | @skills
        |> Enum.map(fn {k, v} -> {v.label, k} end)
        |> Enum.sort_by(&elem(&1, 0))
    ]
  end

  # -------------------------------------------------------------------
  # Harness presets
  # -------------------------------------------------------------------

  @doc "Returns the default harness content."
  def default_harness, do: Map.get(@harness, "default", "")
end
