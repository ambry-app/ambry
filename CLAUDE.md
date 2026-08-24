# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ambry is a self-hosted audiobook library server built with Elixir/Phoenix. Audiobooks arrive through the inbox, are placed into a library root, and are served as the files they already are ("direct play") to the browser and the mobile app. The mobile app code is in a separate repository.

## Development Commands

```bash
# Setup (first time)
mix deps.get && mix npm_deps.get
mix ecto.setup              # Creates and migrates database
mix seed                    # Populate with example data

# Run development server
iex -S mix phx.server       # Runs at http://localhost:4000

# Testing
mix test                    # Run all tests
mix test path/to/test.exs   # Run single test file
mix test path/to/test.exs:42  # Run specific test at line

# Code quality
mix format                  # Format code (uses Styler, TailwindFormatter, Phoenix.LiveView.HTMLFormatter)
mix check                   # Runs format check, compile warnings, credo, dialyzer
mix credo                   # Linter
mix dialyzer                # Static analysis

# Database migrations
mix ecto.gen.migration migration_name  # Generate a new migration file
mix ecto.migrate                       # Run pending migrations
mix ecto.rollback                      # Rollback last migration
```

## Important Conventions

### Comments and documentation

**When in doubt, delete it.** The code says what it does. Prose is for what
the code cannot say, and nothing else.

- **No comment that narrates the line under it.** If the comment restates the
  code, the code was already clear enough.
- **Moduledocs and `@doc`s are brief.** A sentence or two saying what the
  thing is for. Not an essay, not a design rationale, not a tour of the
  alternatives.
- **Keep only:** a non-obvious invariant, a gotcha that will bite the next
  person, or the reason the obvious implementation is wrong. One or two
  sentences each.
- **No history.** Never "this used to be X", "previously", "no longer", "the
  old behaviour", version numbers, PR numbers, dates, or a record of what was
  tried and rejected. State the rule and the consequence that makes it right.
  Git has the history.
- **No references to a particular deployment.** No "in production", no "the
  operator's library", no counts or measurements taken from one instance, no
  links to working notes outside the repo. Ambry is self-hosted open source:
  whoever runs it is not whoever wrote it. Where a measurement is worth
  keeping, state the finding generically ("roughly 96% of releases carry a
  title in tags"), never its provenance.
- **Nothing rendered may encode one operator's taste.** No placeholder or
  example drawn from what somebody happened to be doing; a placeholder either
  teaches the _format_ of a field or is absent. No feature that grades one
  valid arrangement as better than another.

The admin's own visual rules live in `docs/admin-design-language.md`, which
follows the same standard: read it before touching an admin surface.

### Creating Migrations

Always use `mix ecto.gen.migration` to create new migration files - never manually create migration files or generate timestamps. The mix task handles timestamp generation and proper file placement automatically.

## Architecture

### Boundary-Based Module Structure

The codebase uses the [Boundary](https://github.com/sasa1977/boundary) library to enforce module dependencies. Each top-level module under `lib/` defines its allowed dependencies and exports:

- **Ambry** - Core business logic contexts (accounts, books, media, people, search)
- **AmbryApp** - OTP application supervision tree
- **AmbryWeb** - Phoenix web layer (controllers, LiveViews, components)
- **AmbrySchema** - GraphQL API (Absinthe schema, resolvers)
- **AmbryScraping** - API clients for external metadata services (Audible catalog, Audnexus), wrapped by the `Ambry.Metadata` provider layer

### Core Contexts (lib/ambry/)

Each context manages a domain with Ecto schemas, queries, and business logic:

- `Accounts` - User authentication, sessions, admin management
- `Books` - Books, Series, SeriesBook associations
- `People` - Person (authors/narrators), Author, Narrator entities
- `Media` - Audiobook media files, tracks, player state, bookmarks
- `Search` - Full-text search with PostgreSQL trigrams
- `PubSub` - Event broadcasting via Phoenix.PubSub + Oban for async

### Audio: direct play, and the transcoded recordings beside it

Ambry does not transcode. `Ambry.Media.Scanner` probes a file with ffprobe
and the importer writes `media_tracks`; clients are served those files
directly.

Some recordings are instead served from packaged artifacts — `mp4_path` /
`mpd_path` / `hls_path` — which the server serves and deletes but cannot
produce. A recording is one of these exactly when it has no tracks, and its
`source_path` / `source_files` state what its transcode consumed. An
imported recording has neither.

### Flat Views Pattern

Several contexts use "Flat" view schemas (e.g., `BookFlat`, `PersonFlat`, `MediaFlat`) - these are PostgreSQL views that denormalize data for efficient listing/filtering queries.

### Web Layer (lib/ambry_web/)

- Uses Phoenix LiveView extensively
- Admin interface under `live/admin/`
- Components in `components/` including `core_components.ex`
- GraphQL endpoint at `/gql` using Absinthe

### GraphQL API (lib/ambry_schema/)

Relay-compatible GraphQL schema for mobile app. Uses Dataloader for batching.

## Key Dependencies

- Phoenix 1.8 with LiveView
- Ecto with PostgreSQL
- Absinthe (GraphQL)
- Oban (background jobs)
- Boundary (module dependency enforcement)
- Image/Vix (image processing via libvips)

## External Requirements

- PostgreSQL database
- FFmpeg (ffprobe, for reading durations, tags and chapters)

## Tidewave MCP Server

When the dev server is running (`iex -S mix phx.server`), the Tidewave MCP
server provides direct access to the running application.

**If the `mcp__tidewave__*` tools are missing, the config is almost certainly
fine.** The MCP client connects once, at editor startup, so a server that
wasn't running at that moment leaves the tools absent for the whole session —
starting it later does not make them appear. Start the dev server first, or
reconnect the `tidewave` server afterwards.

Without restarting anything, it is also a plain HTTP MCP server and can be
driven directly:

```bash
curl -s -X POST http://localhost:4000/tidewave/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"project_eval","arguments":{"code":"1 + 1"}}}'
```

Available tools:

| Tool                                 | Description                                       |
| ------------------------------------ | ------------------------------------------------- |
| `mcp__tidewave__get_ecto_schemas`    | List all Ecto schemas in the project              |
| `mcp__tidewave__get_logs`            | Retrieve live server logs with optional filtering |
| `mcp__tidewave__get_source_location` | Find source file location for a module/function   |
| `mcp__tidewave__get_docs`            | Get documentation for modules and functions       |
| `mcp__tidewave__project_eval`        | Execute Elixir code in the running server context |
| `mcp__tidewave__execute_sql_query`   | Run SQL queries against the database              |
| `mcp__tidewave__search_package_docs` | Search Hex documentation for dependencies         |

### Hot Reloading Code Changes

After editing Elixir files, recompile without restarting the server:

```elixir
# Via mcp__tidewave__project_eval
IEx.Helpers.recompile()
```

This hot-reloads code changes into the running server. Avoid using `mix compile` in a separate shell as it can interfere with the running IEx session.

### Test User Account

A test user exists for development/testing:

- **Email:** `agent@test.local`
- **Password:** `AgentTestPassword123!`

### GraphQL Testing

The best way to test GraphQL queries is directly through Absinthe using `mcp__tidewave__project_eval`, bypassing HTTP entirely:

```elixir
# Run authenticated GraphQL query directly (via mcp__tidewave__project_eval)
user = Ambry.Accounts.get_user_by_email("agent@test.local")

query = """
  query {
    me { email admin insertedAt }
  }
"""

Absinthe.run(query, AmbrySchema, context: %{current_user: user})
```

This avoids shell escaping issues and is faster than HTTP requests.
