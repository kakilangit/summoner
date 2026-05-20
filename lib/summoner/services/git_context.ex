defmodule Summoner.Services.GitContext do
  @moduledoc """
  Builds a git repository context summary for injection into agent system prompts.

  When a workspace directory is a git repository, this module extracts:
  - Current branch name
  - Working tree status (clean/dirty, staged/unstaged counts)
  - Recent commit history (last 5 commits)

  Returns nil if the directory is not a git repo or git is unavailable.
  """

  @max_commits 5

  @doc """
  Builds a git context markdown block for the given directory.

  Returns a string like:

      ## Git Context
      - Branch: main
      - Status: 2 modified, 1 untracked
      - Recent commits:
        - abc1234 Fix bug in parser (2 hours ago)
        - def5678 Add new feature (1 day ago)

  Returns nil if the directory is not a git repo.
  """
  def build(workspace_dir) when is_binary(workspace_dir) do
    with {:ok, branch} <- git_branch(workspace_dir),
         {:ok, status} <- git_status(workspace_dir),
         {:ok, log} <- git_log(workspace_dir) do
      format_context(branch, status, log)
    else
      _ -> nil
    end
  end

  def build(_), do: nil

  # -------------------------------------------------------------------
  # Git commands
  # -------------------------------------------------------------------

  defp git_branch(dir), do: git_cmd(["branch", "--show-current"], dir)

  defp git_status(dir) do
    case git_cmd(["status", "--porcelain"], dir) do
      {:ok, output} -> {:ok, parse_status(output)}
      :error -> :error
    end
  end

  defp git_log(dir) do
    args = [
      "log",
      "--oneline",
      "--no-decorate",
      "-n",
      to_string(@max_commits),
      "--format=%h %s (%ar)"
    ]

    case git_cmd(args, dir) do
      {:ok, output} -> {:ok, output}
      :error -> {:ok, ""}
    end
  end

  defp git_cmd(args, dir) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      _ -> :error
    end
  rescue
    ErlangError -> :error
  end

  # -------------------------------------------------------------------
  # Parsing & formatting
  # -------------------------------------------------------------------

  defp parse_status(""), do: "clean"

  defp parse_status(output) do
    lines = String.split(output, "\n", trim: true)
    total = length(lines)

    staged =
      Enum.count(lines, fn line ->
        String.length(line) >= 2 and String.at(line, 0) not in [" ", "?"]
      end)

    modified =
      Enum.count(lines, fn line ->
        String.length(line) >= 2 and String.at(line, 1) == "M"
      end)

    untracked = Enum.count(lines, fn line -> String.starts_with?(line, "??") end)

    parts =
      [
        if(staged > 0, do: "#{staged} staged"),
        if(modified > 0, do: "#{modified} modified"),
        if(untracked > 0, do: "#{untracked} untracked")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "#{total} changed"
      _ -> Enum.join(parts, ", ")
    end
  end

  defp format_context(branch, status, log) do
    commits =
      case log do
        "" ->
          ""

        _ ->
          entries =
            log
            |> String.split("\n", trim: true)
            |> Enum.map_join("\n", fn line -> "  - #{line}" end)

          "\n- Recent commits:\n#{entries}"
      end

    """
    ## Git Context
    - Branch: #{branch}
    - Status: #{status}#{commits}\
    """
  end
end
