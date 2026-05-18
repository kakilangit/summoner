defmodule SummonerWeb.DevLive.Docs do
  @moduledoc """
  Developer documentation page. Only available in dev environment.
  """
  use SummonerWeb, :live_view

  @sections [
    {"themes", "Themes", "hero-swatch-micro"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Developer Docs", section: "themes")}
  end

  @impl true
  def handle_event("section", %{"id" => section}, socket) do
    {:noreply, assign(socket, section: section)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, sections: @sections)

    ~H"""
    <div class="flex flex-col lg:flex-row gap-6">
      <%!-- Sidebar --%>
      <aside class="lg:w-56 flex-shrink-0">
        <div class="lg:sticky lg:top-6">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/40 mb-3 px-3">
            Documentation
          </h2>
          <ul class="menu menu-sm bg-base-200 rounded-box w-full p-2">
            <li :for={{id, label, icon} <- @sections}>
              <button
                phx-click="section"
                phx-value-id={id}
                class={if(id == @section, do: "active", else: "")}
              >
                <span class={"#{icon} size-4"} /> {label}
              </button>
            </li>
          </ul>
        </div>
      </aside>

      <%!-- Content --%>
      <div class="flex-1 min-w-0">
        <.section_content section={@section} />
      </div>
    </div>
    """
  end

  attr :section, :string, required: true

  defp section_content(%{section: "themes"} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold">Theme System</h1>
        <p class="text-base-content/60 mt-1">
          DaisyUI-compatible color and layout token sets stored in the database.
        </p>
      </div>

      <div class="alert alert-info alert-soft">
        <span class="hero-information-circle size-5" />
        <span>
          Users switch themes from <strong>Settings &rarr; Themes</strong>.
          Custom themes are installed by uploading a
          <code class="badge badge-ghost badge-xs">.zip</code>
          file.
        </span>
      </div>

      <%!-- Example JSON --%>
      <.info_card title="theme.json Format">
        <div class="mockup-code text-xs">
          <pre :for={
            {line, idx} <-
              Enum.with_index(String.split(Jason.encode!(theme_example(), pretty: true), "\n"), 1)
          }><code><span class="text-base-content/30 select-none">{String.pad_leading("#{idx}", 2)}</span>  {line}</code></pre>
        </div>
      </.info_card>

      <%!-- Color Tokens --%>
      <.info_card title="Color Tokens (20)">
        <p class="text-sm text-base-content/60 mb-3">
          All color values must use <code class="badge badge-ghost badge-xs">oklch(L C H)</code>
          format.
        </p>
        <div class="overflow-x-auto">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>Token</th>
                <th>Description</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{token, desc} <- color_token_docs()}>
                <td><code class="text-primary text-xs">{token}</code></td>
                <td class="text-sm">{desc}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.info_card>

      <%!-- Layout Tokens --%>
      <.info_card title="Layout Tokens (8)">
        <div class="overflow-x-auto">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>Token</th>
                <th>Format</th>
                <th>Description</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{token, fmt, desc} <- layout_token_docs()}>
                <td><code class="text-primary text-xs">{token}</code></td>
                <td><span class="badge badge-ghost badge-xs">{fmt}</span></td>
                <td class="text-sm">{desc}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.info_card>

      <%!-- Constraints & Security --%>
      <div class="grid gap-4 sm:grid-cols-2">
        <.info_card title="Constraints">
          <ul class="space-y-1.5 text-sm">
            <li><strong>Name:</strong> lowercase kebab-case, 2-64 chars, unique</li>
            <li><strong>Display name:</strong> max 100 chars, no HTML</li>
            <li><strong>Color scheme:</strong> <code>"dark"</code> or <code>"light"</code></li>
            <li><strong>Tokens:</strong> exactly 28 (20 color + 8 layout)</li>
            <li><strong>Zip size:</strong> max 1 MB, max 5 entries</li>
            <li><strong>Max themes:</strong> 50 per installation</li>
            <li><strong>Built-in themes</strong> cannot be deleted</li>
          </ul>
        </.info_card>

        <.info_card title="Security">
          <p class="text-sm">
            All token values are validated against allowlisted patterns.
            Color values must match <code>oklch()</code> format exactly.
            Layout values must be simple CSS lengths or integers.
            Display names and author fields reject HTML characters.
            This prevents CSS injection attacks.
          </p>
        </.info_card>
      </div>
    </div>
    """
  end

  defp section_content(assigns) do
    ~H"""
    <div class="alert alert-warning">
      <span class="hero-exclamation-triangle size-5" />
      <span>Section not found.</span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Components
  # -------------------------------------------------------------------

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp info_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4">
        <h2 class="card-title text-sm font-semibold mb-2">{@title}</h2>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Data helpers
  # -------------------------------------------------------------------

  defp theme_example do
    %{
      "name" => "midnight-purple",
      "display_name" => "Midnight Purple",
      "color_scheme" => "dark",
      "author" => "Your Name",
      "version" => "1.0.0",
      "tokens" => %{
        "color-base-100" => "oklch(25% 0.02 280)",
        "color-base-200" => "oklch(20% 0.018 280)",
        "color-base-300" => "oklch(15% 0.015 280)",
        "color-base-content" => "oklch(95% 0.01 280)",
        "color-primary" => "oklch(65% 0.25 300)",
        "color-primary-content" => "oklch(98% 0.01 300)",
        "color-secondary" => "oklch(55% 0.2 260)",
        "color-secondary-content" => "oklch(98% 0.01 260)",
        "color-accent" => "oklch(70% 0.2 330)",
        "color-accent-content" => "oklch(98% 0.01 330)",
        "color-neutral" => "oklch(35% 0.03 280)",
        "color-neutral-content" => "oklch(95% 0.005 280)",
        "color-info" => "oklch(60% 0.15 240)",
        "color-info-content" => "oklch(98% 0.01 240)",
        "color-success" => "oklch(65% 0.15 150)",
        "color-success-content" => "oklch(98% 0.01 150)",
        "color-warning" => "oklch(70% 0.18 60)",
        "color-warning-content" => "oklch(98% 0.02 60)",
        "color-error" => "oklch(60% 0.25 20)",
        "color-error-content" => "oklch(98% 0.01 20)",
        "radius-selector" => "0.25rem",
        "radius-field" => "0.25rem",
        "radius-box" => "0.75rem",
        "size-selector" => "0.25rem",
        "size-field" => "0.25rem",
        "border" => "1px",
        "depth" => "1",
        "noise" => "0"
      }
    }
  end

  defp color_token_docs do
    [
      {"color-base-100", "Main background color"},
      {"color-base-200", "Slightly darker background (cards, sidebars)"},
      {"color-base-300", "Darkest background tier (borders, dividers)"},
      {"color-base-content", "Default text color on base backgrounds"},
      {"color-primary", "Primary brand / action color"},
      {"color-primary-content", "Text on primary backgrounds"},
      {"color-secondary", "Secondary action color"},
      {"color-secondary-content", "Text on secondary backgrounds"},
      {"color-accent", "Accent / highlight color"},
      {"color-accent-content", "Text on accent backgrounds"},
      {"color-neutral", "Neutral / muted color (badges, subtle UI)"},
      {"color-neutral-content", "Text on neutral backgrounds"},
      {"color-info", "Informational state color"},
      {"color-info-content", "Text on info backgrounds"},
      {"color-success", "Success state color"},
      {"color-success-content", "Text on success backgrounds"},
      {"color-warning", "Warning state color"},
      {"color-warning-content", "Text on warning backgrounds"},
      {"color-error", "Error / danger state color"},
      {"color-error-content", "Text on error backgrounds"}
    ]
  end

  defp layout_token_docs do
    [
      {"radius-selector", "CSS length", "Border radius for checkboxes, radios, toggles"},
      {"radius-field", "CSS length", "Border radius for inputs, selects, textareas"},
      {"radius-box", "CSS length", "Border radius for cards, modals, alerts"},
      {"size-selector", "CSS length", "Size scale for selectors"},
      {"size-field", "CSS length", "Size scale for fields"},
      {"border", "CSS length", "Default border width"},
      {"depth", "0-5", "Shadow depth level"},
      {"noise", "0-1", "Background noise texture (0=off, 1=on)"}
    ]
  end
end
