defmodule SummonerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SummonerWeb, :html

  @dev_routes Application.compile_env(:summoner, :dev_routes, false)

  def dev_routes?, do: @dev_routes

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :breadcrumbs, :list, default: nil, doc: "list of {label, path} tuples; last has path nil"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.breadcrumb_bar breadcrumbs={@breadcrumbs} />
    <main class="flex-1 min-h-0 overflow-auto py-6">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 space-y-4">
        <%= if assigns[:inner_content] do %>
          {@inner_content}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders a full-bleed layout with no padding or scroll wrapper.

  Used by pages that need full control over the content area (e.g. chat).
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :breadcrumbs, :list, default: nil, doc: "list of {label, path} tuples; last has path nil"

  slot :inner_block, required: true

  def chat(assigns) do
    ~H"""
    <.breadcrumb_bar breadcrumbs={@breadcrumbs} />
    <main class="flex-1 min-h-0 flex flex-col overflow-hidden">
      <%= if assigns[:inner_content] do %>
        {@inner_content}
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :breadcrumbs, :list, default: nil

  defp breadcrumb_bar(assigns) do
    ~H"""
    <div :if={@breadcrumbs} class="flex-shrink-0 bg-base-200/40">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="text-sm breadcrumbs py-1.5">
          <ul>
            <li :for={{label, path} <- @breadcrumbs}>
              <.link :if={path} navigate={path}>{label}</.link>
              <span :if={!path}>{label}</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
