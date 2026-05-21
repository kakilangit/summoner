defmodule Summoner.Services.Orchestration.BuiltinTools do
  @moduledoc """
  Standard built-in tools for agent execution.

  Provides core filesystem, shell, and web tools that models are commonly
  trained on: `bash`, `read`, `write`, `edit`, `grep`, `glob`, `webfetch`.

  These are always available to agents regardless of MCP server
  configuration, giving models summon tool names that produce
  reliable native tool calls.

  ## Security

  All filesystem operations are **sandboxed** to the workspace directory
  (`~/.summoner/workspaces/<workspace_id>`). Any path that resolves
  outside this sandbox is rejected. Shell commands execute with the
  workspace directory as their working directory.

  All operations are bounded:
  - Shell commands have a configurable timeout (default 120s, max 300s)
  - Shell working directory is confined to the workspace sandbox
  - File reads are capped at 2000 lines / 51_200 bytes
  - Grep results are capped at 100 matches
  - Glob results are capped at 100 files
  - Web fetches are capped at 5 MB response, 120s max timeout
  """

  require Logger

  @max_read_lines 2_000
  @max_read_bytes 51_200
  @max_grep_matches 100
  @max_glob_files 100
  @default_shell_timeout 120_000
  @max_shell_timeout 300_000
  @max_fetch_bytes 5_242_880
  @default_fetch_timeout 30
  @max_fetch_timeout 120

  # -------------------------------------------------------------------
  # Tool definitions (OpenAI function-calling format)
  # -------------------------------------------------------------------

  @tool_defs [
    %{
      type: "function",
      function: %{
        name: "bash",
        description:
          "Execute a shell command. Use for system operations, git, builds, tests, etc. " <>
            "Returns stdout and stderr. Commands time out after the specified duration.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "command" => %{
              "type" => "string",
              "description" => "The shell command to execute"
            },
            "timeout" => %{
              "type" => "integer",
              "description" => "Timeout in milliseconds (default 120000, max 300000)"
            },
            "workdir" => %{
              "type" => "string",
              "description" =>
                "Working directory relative to workspace. Defaults to workspace root."
            }
          },
          "required" => ["command"],
          "additionalProperties" => false
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "read",
        description:
          "Read a file or directory listing. Returns file contents with line numbers, " <>
            "or directory entries. Supports offset and limit for large files.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "file_path" => %{
              "type" => "string",
              "description" => "Path to file or directory relative to the workspace directory"
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Line number to start from, 1-indexed (default 1)"
            },
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum lines to read (default #{@max_read_lines})"
            }
          },
          "required" => ["file_path"],
          "additionalProperties" => false
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "write",
        description:
          "Write content to a file, creating it if it doesn't exist or overwriting if it does.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "file_path" => %{
              "type" => "string",
              "description" => "Path to file relative to the workspace directory"
            },
            "content" => %{
              "type" => "string",
              "description" => "Content to write to the file"
            }
          },
          "required" => ["file_path", "content"],
          "additionalProperties" => false
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "edit",
        description:
          "Edit a file by replacing an exact string match. Use for targeted modifications " <>
            "without rewriting the entire file.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "file_path" => %{
              "type" => "string",
              "description" => "Path to the file to edit relative to the workspace directory"
            },
            "old_string" => %{
              "type" => "string",
              "description" => "The exact text to find and replace"
            },
            "new_string" => %{
              "type" => "string",
              "description" => "The replacement text"
            },
            "replace_all" => %{
              "type" => "boolean",
              "description" => "Replace all occurrences (default false)"
            }
          },
          "required" => ["file_path", "old_string", "new_string"],
          "additionalProperties" => false
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "grep",
        description:
          "Search file contents using a regular expression pattern. " <>
            "Returns matching file paths, line numbers, and content.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "pattern" => %{
              "type" => "string",
              "description" => "Regex pattern to search for"
            },
            "path" => %{
              "type" => "string",
              "description" =>
                "Directory to search in relative to workspace (default: workspace root)"
            },
            "include" => %{
              "type" => "string",
              "description" => "File glob pattern filter, e.g. \"*.ex\", \"*.{ex,exs}\""
            }
          },
          "required" => ["pattern"],
          "additionalProperties" => false
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "glob",
        description:
          "Find files matching a glob pattern. " <>
            "Returns matching file paths sorted by modification time.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "pattern" => %{
              "type" => "string",
              "description" => "Glob pattern, e.g. \"**/*.ex\", \"lib/**/*.ex\""
            },
            "path" => %{
              "type" => "string",
              "description" => "Base directory relative to workspace (default: workspace root)"
            }
          },
          "required" => ["pattern"],
          "additionalProperties" => false
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "webfetch",
        description:
          "Fetch content from a URL. Returns the page content in the requested format. " <>
            "Use for retrieving documentation, API responses, or web page content.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "url" => %{
              "type" => "string",
              "description" => "The URL to fetch content from (must be http:// or https://)"
            },
            "format" => %{
              "type" => "string",
              "enum" => ["text", "markdown", "html"],
              "description" => "Response format: text (plain text), markdown (default), or html"
            },
            "timeout" => %{
              "type" => "integer",
              "description" => "Timeout in seconds (default 30, max 120)"
            }
          },
          "required" => ["url"],
          "additionalProperties" => false
        }
      }
    }
  ]

  @builtin_names MapSet.new([
                   "bash",
                   "read",
                   "write",
                   "edit",
                   "grep",
                   "glob",
                   "webfetch",
                   "__generate_image__",
                   "__generate_video__",
                   "__create_artifact__",
                   "__update_artifact__",
                   "__read_artifact__"
                 ])

  @generate_image_def %{
    type: "function",
    function: %{
      name: "__generate_image__",
      description:
        "Generate an image from a text prompt. The image will appear in the conversation when ready. " <>
          "Use detailed, descriptive prompts for best results.",
      parameters: %{
        type: "object",
        properties: %{
          prompt: %{
            type: "string",
            description: "Detailed description of the image to generate"
          },
          size: %{
            type: "string",
            enum: ["1024x1024", "1792x1024", "1024x1792"],
            default: "1024x1024",
            description: "Image dimensions"
          },
          quality: %{
            type: "string",
            enum: ["standard", "hd", "auto"],
            default: "auto",
            description: "Image quality level"
          },
          n: %{
            type: "integer",
            minimum: 1,
            maximum: 4,
            default: 1,
            description: "Number of images to generate"
          }
        },
        required: ["prompt"]
      }
    }
  }

  @generate_video_def %{
    type: "function",
    function: %{
      name: "__generate_video__",
      description:
        "Generate a video from a text prompt. The video will appear in the conversation when ready " <>
          "(may take several minutes). Use detailed, descriptive prompts for best results.",
      parameters: %{
        type: "object",
        properties: %{
          prompt: %{
            type: "string",
            description: "Detailed description of the video to generate"
          },
          duration_s: %{
            type: "integer",
            minimum: 1,
            maximum: 60,
            default: 5,
            description: "Video duration in seconds"
          },
          size: %{
            type: "string",
            enum: ["1080p", "720p", "480p"],
            default: "720p",
            description: "Video resolution"
          }
        },
        required: ["prompt"]
      }
    }
  }

  @doc "Returns the list of built-in tool definitions in OpenAI format."
  @spec tool_definitions() :: [map()]
  def tool_definitions, do: @tool_defs

  @doc "Returns the generate image tool definition (injected conditionally)."
  def generate_image_tool_definition, do: [@generate_image_def]

  @doc "Returns the generate video tool definition (injected conditionally)."
  def generate_video_tool_definition, do: [@generate_video_def]

  @doc "Returns the artifact tool definitions (always injected)."
  def artifact_tool_definitions do
    [
      %{
        type: "function",
        function: %{
          name: "__create_artifact__",
          description:
            "Create a persistent artifact (document, code, report) that outlives this conversation. " <>
              "Use this when the user asks you to produce a document, write code to a file, or generate a report.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "name" => %{
                "type" => "string",
                "description" => "Artifact name (e.g. 'meeting-notes', 'api-spec')"
              },
              "type" => %{
                "type" => "string",
                "enum" => ["document", "code", "dataset", "image", "report"],
                "description" => "Artifact type"
              },
              "content" => %{"type" => "string", "description" => "Full content of the artifact"},
              "content_type" => %{
                "type" => "string",
                "description" => "MIME type (default text/markdown)",
                "default" => "text/markdown"
              }
            },
            "required" => ["name", "type", "content"],
            "additionalProperties" => false
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "__update_artifact__",
          description:
            "Update an existing artifact by creating a new version. The old version is preserved. " <>
              "Use this when the user asks to revise or update a previously created artifact.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string", "description" => "Name of the artifact to update"},
              "content" => %{"type" => "string", "description" => "New content for the artifact"}
            },
            "required" => ["name", "content"],
            "additionalProperties" => false
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "__read_artifact__",
          description:
            "Read an existing artifact by name. Returns the latest version's content. " <>
              "Use this when you need to reference a previously created artifact.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string", "description" => "Name of the artifact to read"}
            },
            "required" => ["name"],
            "additionalProperties" => false
          }
        }
      }
    ]
  end

  @doc "Returns the set of built-in tool names."
  @spec builtin_names() :: MapSet.t()
  def builtin_names, do: @builtin_names

  @doc "Returns true if the given tool name is a built-in tool."
  @spec builtin?(String.t()) :: boolean()
  def builtin?(name), do: MapSet.member?(@builtin_names, name)

  @doc """
  Execute a built-in tool call.

  The `workspace_root` is the base directory for relative paths.
  All filesystem paths are sandboxed to this directory.
  """
  @spec execute(String.t(), map(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def execute(name, args, workspace_root) do
    case name do
      "bash" -> exec_bash(args, workspace_root)
      "read" -> exec_read(args, workspace_root)
      "write" -> exec_write(args, workspace_root)
      "edit" -> exec_edit(args, workspace_root)
      "grep" -> exec_grep(args, workspace_root)
      "glob" -> exec_glob(args, workspace_root)
      "webfetch" -> exec_webfetch(args)
      _ -> {:error, "unknown built-in tool: #{name}"}
    end
  rescue
    e ->
      Logger.error("Built-in tool #{name} crashed: #{Exception.message(e)}")
      {:error, "tool error: #{Exception.message(e)}"}
  end

  # -------------------------------------------------------------------
  # bash — shell command execution
  # -------------------------------------------------------------------

  defp exec_bash(%{"command" => ""}, _root), do: {:error, "command is required"}
  defp exec_bash(%{"command" => cmd} = args, root), do: run_shell(cmd, args, root)
  defp exec_bash(_args, _root), do: {:error, "command is required"}

  defp run_shell(command, args, workspace_root) do
    timeout = clamp_timeout(Map.get(args, "timeout", @default_shell_timeout))

    with {:ok, workdir} <- sandbox_path(Map.get(args, "workdir"), workspace_root) do
      run_shell_cmd(command, workdir, timeout)
    end
  rescue
    e in ErlangError -> format_shell_error(e.original)
  end

  defp run_shell_cmd(command, workdir, timeout) do
    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", command],
          cd: workdir,
          stderr_to_stdout: true,
          env: []
        )
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} -> {:ok, truncate_output(output)}
      {:ok, {output, code}} -> {:ok, "Exit code: #{code}\n#{truncate_output(output)}"}
      nil -> {:error, "command timed out after #{timeout}ms"}
    end
  end

  defp clamp_timeout(t), do: t |> min(@max_shell_timeout) |> max(1_000)

  defp format_shell_error(:enoent),
    do: {:error, "command not found or working directory does not exist"}

  defp format_shell_error(reason), do: {:error, "shell error: #{inspect(reason)}"}

  # -------------------------------------------------------------------
  # read — file/directory reading
  # -------------------------------------------------------------------

  defp exec_read(args, workspace_root) do
    with {:ok, path} <- sandbox_path(Map.get(args, "file_path"), workspace_root) do
      read_path(path, args)
    end
  end

  defp read_path(path, args) do
    cond do
      File.dir?(path) -> read_directory(path)
      File.regular?(path) -> read_file_with_lines(path, args)
      true -> {:error, "path does not exist: #{path}"}
    end
  end

  defp read_directory(path) do
    entries =
      path
      |> File.ls!()
      |> Enum.sort()
      |> Enum.map_join("\n", fn entry ->
        if File.dir?(Path.join(path, entry)), do: "#{entry}/", else: entry
      end)

    {:ok, entries}
  end

  defp read_file_with_lines(path, args) do
    offset = max(Map.get(args, "offset", 1), 1)
    limit = min(Map.get(args, "limit", @max_read_lines), @max_read_lines)

    result =
      path
      |> File.stream!([], :line)
      |> Stream.with_index(1)
      |> Stream.drop(offset - 1)
      |> Stream.take(limit)
      |> Enum.reduce_while({"", 0}, &accumulate_line/2)
      |> elem(0)

    {:ok, result}
  end

  defp accumulate_line({line, idx}, {acc, bytes}) do
    line_str = "#{idx}: #{line}"
    new_bytes = bytes + byte_size(line_str)

    if new_bytes > @max_read_bytes do
      {:halt, {acc <> "[truncated at #{@max_read_bytes} bytes]\n", new_bytes}}
    else
      {:cont, {acc <> line_str, new_bytes}}
    end
  end

  # -------------------------------------------------------------------
  # write — file creation/overwrite
  # -------------------------------------------------------------------

  defp exec_write(args, workspace_root) do
    with {:ok, path} <- sandbox_path(Map.get(args, "file_path"), workspace_root) do
      content = Map.get(args, "content", "")
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, content)
      {:ok, "Written #{byte_size(content)} bytes to #{path}"}
    end
  end

  # -------------------------------------------------------------------
  # edit — search-and-replace in file
  # -------------------------------------------------------------------

  defp exec_edit(args, workspace_root) do
    with {:ok, path} <- sandbox_path(Map.get(args, "file_path"), workspace_root),
         {:ok, old_string} <- require_param(args, "old_string"),
         {:ok, content} <- read_for_edit(path) do
      new_string = Map.get(args, "new_string", "")
      replace_all = Map.get(args, "replace_all", false)
      apply_edit(path, content, old_string, new_string, replace_all)
    end
  end

  defp require_param(args, key) do
    case Map.get(args, key, "") do
      "" -> {:error, "#{key} is required"}
      value -> {:ok, value}
    end
  end

  defp read_for_edit(path) do
    case File.read(path) do
      {:ok, _content} = ok -> ok
      {:error, :enoent} -> {:error, "file not found: #{path}"}
      {:error, reason} -> {:error, "cannot read #{path}: #{reason}"}
    end
  end

  defp apply_edit(path, content, old_string, new_string, replace_all) do
    if String.contains?(content, old_string) do
      updated = do_replace(content, old_string, new_string, replace_all)
      File.write!(path, updated)
      {:ok, "Edited #{path}"}
    else
      {:error, "old_string not found in #{path}"}
    end
  end

  defp do_replace(content, old, new, true), do: String.replace(content, old, new)

  defp do_replace(content, old, new, false) do
    case String.split(content, old, parts: 2) do
      [before, after_part] -> before <> new <> after_part
      _ -> content
    end
  end

  # -------------------------------------------------------------------
  # grep — regex content search via ripgrep
  # -------------------------------------------------------------------

  defp exec_grep(%{"pattern" => ""}, _root), do: {:error, "pattern is required"}

  defp exec_grep(%{"pattern" => pattern} = args, workspace_root) do
    with {:ok, path} <- sandbox_path(Map.get(args, "path"), workspace_root) do
      run_ripgrep(pattern, path, Map.get(args, "include"))
    end
  rescue
    e in ErlangError -> format_rg_error(e.original)
  end

  defp exec_grep(_args, _root), do: {:error, "pattern is required"}

  defp run_ripgrep(pattern, path, include) do
    rg_args =
      ["--line-number", "--no-heading", "--color", "never", "-e", pattern] ++
        if(include, do: ["-g", include], else: []) ++
        [path]

    case System.cmd("rg", rg_args, stderr_to_stdout: true, env: [], into: "") do
      {output, 0} -> format_grep_output(output)
      {_, 1} -> {:ok, "No matches found"}
      {output, _} -> {:error, "grep error: #{truncate_output(output)}"}
    end
  end

  defp format_grep_output(output) do
    lines = String.split(output, "\n", trim: true)
    truncated = Enum.take(lines, @max_grep_matches)
    result = Enum.join(truncated, "\n")
    remaining = length(lines) - @max_grep_matches

    if remaining > 0 do
      {:ok, result <> "\n[#{remaining} more matches truncated]"}
    else
      {:ok, result}
    end
  end

  defp format_rg_error(:enoent), do: {:error, "ripgrep (rg) not found. Install it to use grep."}
  defp format_rg_error(reason), do: {:error, "grep error: #{inspect(reason)}"}

  # -------------------------------------------------------------------
  # glob — file pattern matching
  # -------------------------------------------------------------------

  defp exec_glob(%{"pattern" => ""}, _root), do: {:error, "pattern is required"}

  defp exec_glob(%{"pattern" => pattern} = args, workspace_root) do
    with {:ok, path} <- sandbox_path(Map.get(args, "path"), workspace_root) do
      find_glob_matches(pattern, path, workspace_root)
    end
  end

  defp exec_glob(_args, _root), do: {:error, "pattern is required"}

  defp find_glob_matches(pattern, path, workspace_root) do
    matches =
      path
      |> Path.join(pattern)
      |> Path.wildcard()
      |> Enum.take(@max_glob_files)
      |> Enum.map(&Path.relative_to(&1, workspace_root))

    if matches == [] do
      {:ok, "No files matched pattern: #{pattern}"}
    else
      {:ok, Enum.join(matches, "\n")}
    end
  end

  # -------------------------------------------------------------------
  # webfetch — HTTP URL fetching
  # -------------------------------------------------------------------

  @fetch_headers [
    {"user-agent",
     "Mozilla/5.0 (compatible; Summoner/1.0; +https://github.com/kakilangit/summoner)"},
    {"accept-language", "en-US,en;q=0.9"}
  ]

  defp exec_webfetch(%{"url" => url} = args) when is_binary(url) and url != "" do
    with :ok <- validate_url(url) do
      format = Map.get(args, "format", "markdown")
      timeout = clamp_fetch_timeout(Map.get(args, "timeout", @default_fetch_timeout))
      fetch_url(url, format, timeout)
    end
  end

  defp exec_webfetch(_args), do: {:error, "url is required"}

  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> :ok
      _ -> {:error, "invalid URL: must start with http:// or https://"}
    end
  end

  defp clamp_fetch_timeout(t) when is_integer(t), do: t |> min(@max_fetch_timeout) |> max(1)
  defp clamp_fetch_timeout(_), do: @default_fetch_timeout

  defp fetch_url(url, format, timeout_seconds) do
    accept = fetch_accept_header(format)
    headers = [{"accept", accept} | @fetch_headers]

    case Req.get(url,
           headers: headers,
           receive_timeout: timeout_seconds * 1_000,
           max_retries: 0,
           redirect_log_level: false,
           max_redirects: 5
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        process_fetch_response(body, format)

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status} fetching #{url}"}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, "connection error: #{reason}"}

      {:error, reason} ->
        {:error, "fetch error: #{inspect(reason)}"}
    end
  end

  defp fetch_accept_header("html"), do: "text/html,application/xhtml+xml,*/*"
  defp fetch_accept_header("text"), do: "text/plain,text/html,*/*"
  defp fetch_accept_header(_markdown), do: "text/html,application/xhtml+xml,*/*"

  defp process_fetch_response(body, _format) when byte_size(body) > @max_fetch_bytes do
    {:ok,
     binary_part(body, 0, @max_fetch_bytes) <>
       "\n[truncated at #{@max_fetch_bytes} bytes]"}
  end

  defp process_fetch_response(body, "html"), do: {:ok, body}

  defp process_fetch_response(body, "text") do
    {:ok, strip_html_tags(body)}
  end

  defp process_fetch_response(body, _markdown) do
    {:ok, html_to_markdown(body)}
  end

  defp strip_html_tags(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp html_to_markdown(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> String.replace(~r/<h1[^>]*>(.*?)<\/h1>/is, "\n# \\1\n")
    |> String.replace(~r/<h2[^>]*>(.*?)<\/h2>/is, "\n## \\1\n")
    |> String.replace(~r/<h3[^>]*>(.*?)<\/h3>/is, "\n### \\1\n")
    |> String.replace(~r/<h4[^>]*>(.*?)<\/h4>/is, "\n#### \\1\n")
    |> String.replace(~r/<h5[^>]*>(.*?)<\/h5>/is, "\n##### \\1\n")
    |> String.replace(~r/<h6[^>]*>(.*?)<\/h6>/is, "\n###### \\1\n")
    |> String.replace(~r/<strong[^>]*>(.*?)<\/strong>/is, "**\\1**")
    |> String.replace(~r/<b[^>]*>(.*?)<\/b>/is, "**\\1**")
    |> String.replace(~r/<em[^>]*>(.*?)<\/em>/is, "*\\1*")
    |> String.replace(~r/<i[^>]*>(.*?)<\/i>/is, "*\\1*")
    |> String.replace(~r/<code[^>]*>(.*?)<\/code>/is, "`\\1`")
    |> String.replace(~r/<pre[^>]*>(.*?)<\/pre>/is, "\n```\n\\1\n```\n")
    |> String.replace(~r/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/is, "[\\2](\\1)")
    |> String.replace(~r/<li[^>]*>(.*?)<\/li>/is, "- \\1\n")
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<p[^>]*>(.*?)<\/p>/is, "\n\\1\n")
    |> String.replace(~r/<blockquote[^>]*>(.*?)<\/blockquote>/is, "\n> \\1\n")
    |> String.replace(~r/<hr\s*\/?>/, "\n---\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # -------------------------------------------------------------------
  # Path sandboxing
  # -------------------------------------------------------------------

  # Resolves a path relative to workspace_root and ensures it stays
  # within the sandbox. Absolute paths are rejected unless they fall
  # inside the workspace root.
  @spec sandbox_path(String.t() | nil, String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp sandbox_path(nil, workspace_root), do: {:ok, workspace_root}
  defp sandbox_path("", workspace_root), do: {:ok, workspace_root}

  defp sandbox_path(path, workspace_root) do
    resolved = resolve_and_expand(path, workspace_root)
    canonical_root = Path.expand(workspace_root)
    validate_in_sandbox(resolved, canonical_root, path)
  end

  defp resolve_and_expand(path, workspace_root) do
    if Path.type(path) == :absolute do
      Path.expand(path)
    else
      Path.expand(Path.join(workspace_root, path))
    end
  end

  defp validate_in_sandbox(resolved, root, original_path) do
    if resolved == root or String.starts_with?(resolved, root <> "/") do
      {:ok, resolved}
    else
      {:error, "access denied: path #{original_path} is outside the workspace directory"}
    end
  end

  defp truncate_output(output) when byte_size(output) > @max_read_bytes do
    binary_part(output, 0, @max_read_bytes) <> "\n[truncated at #{@max_read_bytes} bytes]"
  end

  defp truncate_output(output), do: output
end
