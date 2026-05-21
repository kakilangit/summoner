defmodule SummonerWeb.API.PaginationJSON do
  @moduledoc """
  Shared JSON rendering helpers for paginated responses.
  """

  @doc """
  Renders pagination metadata from a `%Pagination{}` struct.
  """
  def page_meta(page) do
    %{
      page: page.page,
      per_page: page.per_page,
      total_entries: page.total_entries,
      total_pages: page.total_pages
    }
  end
end
