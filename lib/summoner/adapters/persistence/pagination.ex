defmodule Summoner.Adapters.Persistence.Pagination do
  @moduledoc """
  Offset-based pagination with sorting and filtering.

  Provides `paginate/2` to apply limit/offset/order/filter to an Ecto query
  and return a `%Pagination{}` struct with entries, metadata, and navigation info.
  """

  @behaviour Summoner.Ports.Persistence.Pagination.Adapter

  import Ecto.Query, warn: false

  alias Summoner.Repo

  defstruct [:entries, :page, :per_page, :total_entries, :total_pages]

  @type t :: %__MODULE__{
          entries: [any()],
          page: pos_integer(),
          per_page: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer()
        }

  @default_per_page 20
  @max_per_page 100

  @doc """
  Paginates an Ecto query with optional sorting and filtering.

  ## Options

    * `:page` — current page number (default `1`)
    * `:per_page` — entries per page (default `#{@default_per_page}`, max `#{@max_per_page}`)
    * `:sort_by` — atom field name to sort by (default: no additional ordering)
    * `:sort_dir` — `:asc` or `:desc` (default `:asc`)
    * `:filter` — search string to filter on `:filter_fields`
    * `:filter_fields` — list of atom field names to apply ilike filter on

  Returns a `%Summoner.Adapters.Persistence.Pagination{}` struct.
  """
  @spec paginate(Ecto.Queryable.t(), keyword()) :: t()
  def paginate(query, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> max(1) |> min(@max_per_page)

    query =
      query
      |> apply_filter(opts)
      |> apply_sort(opts)

    total_entries = Repo.aggregate(query, :count)
    total_pages = max(ceil(total_entries / per_page), 1)

    page = min(page, total_pages)
    offset = (page - 1) * per_page

    entries =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %__MODULE__{
      entries: entries,
      page: page,
      per_page: per_page,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  defp apply_filter(query, opts) do
    filter = opts |> Keyword.get(:filter, "") |> to_string() |> String.trim()
    fields = Keyword.get(opts, :filter_fields, [])

    if filter == "" or fields == [] do
      query
    else
      pattern = "%#{escape_like(filter)}%"
      build_filter_query(query, fields, pattern)
    end
  end

  defp build_filter_query(query, [field], pattern) do
    where(query, [q], ilike(field(q, ^field), ^pattern))
  end

  defp build_filter_query(query, fields, pattern) do
    conditions =
      Enum.reduce(fields, dynamic(false), fn field, acc ->
        dynamic([q], ^acc or ilike(field(q, ^field), ^pattern))
      end)

    where(query, ^conditions)
  end

  defp apply_sort(query, opts) do
    case Keyword.get(opts, :sort_by) do
      nil -> query
      field -> order_by(query, [q], [{^sort_dir(opts), field(q, ^field)}])
    end
  end

  defp sort_dir(opts) do
    case Keyword.get(opts, :sort_dir, :asc) do
      :desc -> :desc
      _ -> :asc
    end
  end

  defp escape_like(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
