defmodule SummonerWeb.API.PaginationParams do
  @moduledoc """
  Extracts pagination parameters from request query params.

  Converts string params `"page"` and `"per_page"` to keyword opts
  compatible with `Summoner.Adapters.Persistence.Pagination.paginate/2`.
  """

  @doc """
  Extracts pagination opts from conn params.

  Returns a keyword list with `:page` and `:per_page` keys.
  Defaults to page 1 and per_page 20 if not provided.

  ## Examples

      iex> pagination_opts(%{"page" => "2", "per_page" => "50"})
      [page: 2, per_page: 50]

      iex> pagination_opts(%{})
      []
  """
  @spec pagination_opts(map()) :: keyword()
  def pagination_opts(params) do
    opts = []

    opts =
      case params["page"] do
        nil -> opts
        val -> Keyword.put(opts, :page, to_integer(val, 1))
      end

    case params["per_page"] do
      nil -> opts
      val -> Keyword.put(opts, :per_page, to_integer(val, 20))
    end
  end

  defp to_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _other -> default
    end
  end

  defp to_integer(val, _default) when is_integer(val), do: val
  defp to_integer(_val, default), do: default
end
