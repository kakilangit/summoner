defmodule Summoner.Ports.Persistence.KnowledgeBases.Adapter do
  @moduledoc "Behaviour for knowledge base persistence operations."

  @callback create_knowledge_base(String.t(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_knowledge_base!(String.t(), String.t()) :: struct()
  @callback get_knowledge_base(String.t(), String.t()) :: struct() | nil
  @callback list_knowledge_bases(String.t()) :: [struct()]
  @callback list_knowledge_bases_paginated(String.t(), keyword()) :: struct()
  @callback update_knowledge_base(struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_status(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_knowledge_base(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback link_agent(String.t(), String.t()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback unlink_agent(String.t(), String.t()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_linked_agents(String.t()) :: [struct()]
  @callback list_knowledge_bases_for_agent(String.t()) :: [struct()]
end
