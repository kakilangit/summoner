#!/usr/bin/env elixir

# Generates a standalone HTML site from docs/*.md files.
# Usage: mix run docs/generate.exs
# Output: docs/_site/index.html

defmodule Docs.Generator do
  @docs_dir Path.expand("../", __ENV__.file)
  @output_dir Path.join(@docs_dir, "_site")

  @pages [
    {"01-overview.md", "Overview"},
    {"02-installation.md", "Installation"},
    {"03-setup.md", "Setup"},
    {"04-scroll.md", "Scroll"},
    {"05-archon.md", "Archon"},
    {"06-themes.md", "Themes"}
  ]

  def run do
    File.mkdir_p!(@output_dir)

    sections =
      Enum.map(@pages, fn {file, label} ->
        path = Path.join(@docs_dir, file)
        md = File.read!(path)
        {:ok, html, _} = Earmark.as_html(md)
        id = file |> String.replace_trailing(".md", "") |> String.replace(~r/^\d+-/, "")
        {id, label, html}
      end)

    html = render(sections)
    out = Path.join(@output_dir, "index.html")
    File.write!(out, html)
    IO.puts("Generated #{out}")
  end

  defp render(sections) do
    nav =
      sections
      |> Enum.map(fn {id, label, _} ->
        ~s(<li><a href="##{id}" class="nav-link" data-section="#{id}">#{label}</a></li>)
      end)
      |> Enum.join("\n")

    body =
      sections
      |> Enum.map(fn {id, _label, html} ->
        ~s(<section id="#{id}" class="doc-section">#{html}</section>)
      end)
      |> Enum.join("\n")

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Summoner Documentation</title>
    <style>
    *{margin:0;padding:0;box-sizing:border-box}
    :root{--bg:#1a1a2e;--bg2:#16213e;--bg3:#0f3460;--fg:#e8e8e8;--fg2:#a0a0b0;--accent:#e94560;--accent2:#533483;--border:#2a2a4a;--code-bg:#0d1117;--link:#6ea8fe;--radius:6px}
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--fg);line-height:1.6;display:flex;min-height:100dvh}
    nav.sidebar{position:sticky;top:0;height:100dvh;width:220px;flex-shrink:0;background:var(--bg2);border-right:1px solid var(--border);overflow-y:auto;padding:1.5rem 0}
    nav.sidebar h2{font-size:.7rem;text-transform:uppercase;letter-spacing:.1em;color:var(--fg2);padding:0 1.25rem;margin-bottom:.75rem}
    nav.sidebar ul{list-style:none}
    nav.sidebar li a{display:block;padding:.4rem 1.25rem;color:var(--fg2);text-decoration:none;font-size:.875rem;border-left:3px solid transparent;transition:all .15s}
    nav.sidebar li a:hover,nav.sidebar li a.active{color:var(--fg);background:rgba(233,69,96,.08);border-left-color:var(--accent)}
    main{flex:1;min-width:0;max-width:52rem;margin:0 auto;padding:2rem 2.5rem}
    .doc-section{display:none;animation:fadeIn .2s}
    .doc-section.active{display:block}
    @keyframes fadeIn{from{opacity:0}to{opacity:1}}
    h1{font-size:1.75rem;font-weight:700;margin-bottom:.5rem;color:var(--fg)}
    h2{font-size:1.35rem;font-weight:600;margin:2rem 0 .75rem;padding-bottom:.4rem;border-bottom:1px solid var(--border);color:var(--fg)}
    h3{font-size:1.1rem;font-weight:600;margin:1.5rem 0 .5rem;color:var(--fg)}
    h4{font-size:1rem;font-weight:600;margin:1.25rem 0 .4rem;color:var(--fg2)}
    p{margin:.75rem 0;color:var(--fg)}
    a{color:var(--link);text-decoration:none}
    a:hover{text-decoration:underline}
    ul,ol{margin:.75rem 0 .75rem 1.5rem}
    li{margin:.25rem 0}
    strong{font-weight:600}
    code{font-family:"SF Mono",Consolas,"Liberation Mono",Menlo,monospace;font-size:.85em;background:var(--code-bg);padding:.15em .35em;border-radius:3px;color:#e06c75}
    pre{margin:1rem 0;padding:1rem;background:var(--code-bg);border:1px solid var(--border);border-radius:var(--radius);overflow-x:auto;line-height:1.5}
    pre code{background:none;padding:0;color:var(--fg);font-size:.8rem}
    table{width:100%;border-collapse:collapse;margin:1rem 0;font-size:.875rem}
    th{text-align:left;padding:.5rem .75rem;background:var(--bg2);border:1px solid var(--border);font-weight:600;color:var(--fg2)}
    td{padding:.5rem .75rem;border:1px solid var(--border)}
    tr:nth-child(even) td{background:rgba(255,255,255,.02)}
    hr{border:none;border-top:1px solid var(--border);margin:2rem 0}
    @media(max-width:768px){
      nav.sidebar{position:fixed;z-index:10;width:100%;height:auto;border-right:none;border-bottom:1px solid var(--border);padding:.75rem 0}
      nav.sidebar ul{display:flex;flex-wrap:wrap;gap:.25rem;padding:0 .75rem}
      nav.sidebar li a{padding:.3rem .6rem;border-left:none;border-radius:var(--radius);font-size:.8rem}
      nav.sidebar h2{display:none}
      main{padding:5rem 1rem 2rem}
    }
    </style>
    </head>
    <body>
    <nav class="sidebar">
    <h2>Documentation</h2>
    <ul>
    #{nav}
    </ul>
    </nav>
    <main>
    #{body}
    </main>
    <script>
    (function(){
      const links=document.querySelectorAll('.nav-link');
      const sections=document.querySelectorAll('.doc-section');
      function show(id){
        sections.forEach(s=>s.classList.toggle('active',s.id===id));
        links.forEach(a=>a.classList.toggle('active',a.dataset.section===id));
        history.replaceState(null,'','#'+id);
      }
      links.forEach(a=>a.addEventListener('click',e=>{e.preventDefault();show(a.dataset.section)}));
      const hash=location.hash.slice(1);
      show(hash&&document.getElementById(hash)?hash:'overview');
    })();
    </script>
    </body>
    </html>
    """
  end
end

Docs.Generator.run()
