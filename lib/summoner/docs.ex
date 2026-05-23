defmodule Summoner.Docs do
  @moduledoc """
  Generates a standalone HTML site from docs/*.md files.

  Output: priv/static/docs/index.html
  Auto-generated on dev server start.
  """

  @docs_dir Path.expand("../../docs", __DIR__)
  @output_dir Application.app_dir(:summoner, "priv/static/docs")

  @pages [
    {"01-overview.md", "Overview"},
    {"02-installation.md", "Installation"},
    {"03-setup.md", "Setup"},
    {"04-scroll.md", "Scroll"},
    {"05-archon.md", "Archon"},
    {"06-themes.md", "Themes"},
    {"07-a2a.md", "A2A"},
    {"08-api.md", "API & Webhooks"},
    {"09-failover.md", "Failover"},
    {"10-artifacts.md", "Artifacts"},
    {"11-approvals.md", "Approvals"},
    {"12-event-rules.md", "Event Rules"},
    {"13-grimoires.md", "Grimoires"}
  ]

  def generate do
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
      Enum.map_join(sections, "\n", fn {id, label, _} ->
        ~s(<li><a href="##{id}" class="nav-link" data-section="#{id}">#{label}</a></li>)
      end)

    body =
      Enum.map_join(sections, "\n", fn {id, _label, html} ->
        ~s(<section id="#{id}" class="doc-section">#{html}</section>)
      end)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Summoner Documentation</title>
    <style>
    *{margin:0;padding:0;box-sizing:border-box}
    :root{--bg:oklch(30.33% 0.016 252.42);--bg2:oklch(25.26% 0.014 253.1);--bg3:oklch(20.15% 0.012 254.09);--fg:oklch(97.807% 0.029 256.847);--fg2:oklch(65% 0.025 256);--primary:oklch(58% 0.233 277.117);--accent:oklch(60% 0.25 292.717);--neutral:oklch(37% 0.044 257.287);--border:oklch(20.15% 0.012 254.09);--code-bg:oklch(18% 0.012 254);--link:oklch(58% 0.233 277.117);--info:oklch(58% 0.158 241.966);--success:oklch(60% 0.118 184.704);--warning:oklch(66% 0.179 58.318);--error:oklch(58% 0.253 17.585);--radius:0.5rem}
    body{font-family:ui-sans-serif,system-ui,sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol","Noto Color Emoji";background:var(--bg);color:var(--fg);line-height:1.6;display:flex;min-height:100dvh}
    nav.sidebar{position:sticky;top:0;height:100dvh;width:220px;flex-shrink:0;background:var(--bg2);border-right:1.5px solid var(--border);overflow-y:auto;padding:1.5rem 0}
    nav.sidebar h2{font-size:.7rem;text-transform:uppercase;letter-spacing:.1em;color:var(--fg2);padding:0 1.25rem;margin-bottom:.75rem}
    nav.sidebar ul{list-style:none}
    nav.sidebar li a{display:block;padding:.4rem 1.25rem;color:var(--fg2);text-decoration:none;font-size:.875rem;border-left:3px solid transparent;transition:all .15s}
    nav.sidebar li a:hover,nav.sidebar li a.active{color:var(--fg);background:oklch(58% 0.233 277.117/.08);border-left-color:var(--primary)}
    main{flex:1;min-width:0;max-width:52rem;margin:0 auto;padding:2rem 2.5rem}
    .doc-section{display:none;animation:fadeIn .2s}
    .doc-section.active{display:block}
    @keyframes fadeIn{from{opacity:0}to{opacity:1}}
    h1{font-size:1.75rem;font-weight:700;margin-bottom:.5rem;color:var(--fg)}
    h2{font-size:1.35rem;font-weight:600;margin:2rem 0 .75rem;padding-bottom:.4rem;border-bottom:1.5px solid var(--border);color:var(--fg)}
    h3{font-size:1.1rem;font-weight:600;margin:1.5rem 0 .5rem;color:var(--fg)}
    h4{font-size:1rem;font-weight:600;margin:1.25rem 0 .4rem;color:var(--fg2)}
    p{margin:.75rem 0;color:var(--fg)}
    a{color:var(--link);text-decoration:none}
    a:hover{text-decoration:underline;color:var(--accent)}
    ul,ol{margin:.75rem 0 .75rem 1.5rem}
    li{margin:.25rem 0}
    strong{font-weight:600}
    code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;font-size:.85em;background:var(--code-bg);padding:.15em .35em;border-radius:0.25rem;color:var(--accent)}
    pre{margin:1rem 0;padding:1rem;background:var(--code-bg);border:1.5px solid var(--border);border-radius:var(--radius);overflow-x:auto;line-height:1.5}
    pre code{background:none;padding:0;color:var(--fg);font-size:.8rem}
    table{width:100%;border-collapse:collapse;margin:1rem 0;font-size:.875rem}
    th{text-align:left;padding:.5rem .75rem;background:var(--bg2);border:1.5px solid var(--border);font-weight:600;color:var(--fg2)}
    td{padding:.5rem .75rem;border:1.5px solid var(--border)}
    tr:nth-child(even) td{background:oklch(25.26% 0.014 253.1/.5)}
    hr{border:none;border-top:1.5px solid var(--border);margin:2rem 0}
    @media(max-width:768px){
      nav.sidebar{position:fixed;z-index:10;width:100%;height:auto;border-right:none;border-bottom:1.5px solid var(--border);padding:.75rem 0}
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
