# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ambry is a self-hosted audiobook library server built with Elixir/Phoenix. Users upload audiobooks, which are processed and transcoded for streaming via browser or mobile app. The mobile app code is in a separate repository.

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

### Creating Migrations

Always use `mix ecto.gen.migration` to create new migration files - never manually create migration files or generate timestamps. The mix task handles timestamp generation and proper file placement automatically.

## Architecture

### Boundary-Based Module Structure

The codebase uses the [Boundary](https://github.com/sasa1977/boundary) library to enforce module dependencies. Each top-level module under `lib/` defines its allowed dependencies and exports:

- **Ambry** - Core business logic contexts (accounts, books, media, people, search)
- **AmbryApp** - OTP application supervision tree
- **AmbryWeb** - Phoenix web layer (controllers, LiveViews, components)
- **AmbrySchema** - GraphQL API (Absinthe schema, resolvers)
- **AmbryScraping** - Web scraping for metadata from GoodReads, Audible, Audnexus

### Core Contexts (lib/ambry/)

Each context manages a domain with Ecto schemas, queries, and business logic:

- `Accounts` - User authentication, sessions, admin management
- `Books` - Books, Series, SeriesBook associations
- `People` - Person (authors/narrators), Author, Narrator entities
- `Media` - Audiobook media files, player state, bookmarks, processing
- `Search` - Full-text search with PostgreSQL trigrams
- `PubSub` - Event broadcasting via Phoenix.PubSub + Oban for async

### Media Processing Pipeline

Audio processing uses FFmpeg and shaka-packager. Processors in `lib/ambry/media/processor/`:
- MP3, MP4 (single file and concatenation)
- Opus concatenation
- HLS packaging for streaming

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
- FFmpeg and shaka-packager for audio transcoding
- Optional: Headless Firefox with Marionette for GoodReads scraping

## Tidewave MCP Server

When the dev server is running (`iex -S mix phx.server`), the Tidewave MCP server provides direct access to the running application. Available tools:

| Tool | Description |
|------|-------------|
| `mcp__tidewave__get_ecto_schemas` | List all Ecto schemas in the project |
| `mcp__tidewave__get_logs` | Retrieve live server logs with optional filtering |
| `mcp__tidewave__get_source_location` | Find source file location for a module/function |
| `mcp__tidewave__get_docs` | Get documentation for modules and functions |
| `mcp__tidewave__project_eval` | Execute Elixir code in the running server context |
| `mcp__tidewave__execute_sql_query` | Run SQL queries against the database |
| `mcp__tidewave__search_package_docs` | Search Hex documentation for dependencies |

### Hot Reloading Code Changes

After editing Elixir files, recompile without restarting the server:

```elixir
# Via mcp__tidewave__project_eval
IEx.Helpers.recompile()
```

This hot-reloads code changes into the running server. Avoid using `mix compile` in a separate shell as it can interfere with the running IEx session.

### Test User Account

A test user exists for development/testing:
- **Email:** `claude@anthropic.local`
- **Password:** `ClaudeTestPassword123!`

### GraphQL Testing

The best way to test GraphQL queries is directly through Absinthe using `mcp__tidewave__project_eval`, bypassing HTTP entirely:

```elixir
# Run authenticated GraphQL query directly (via mcp__tidewave__project_eval)
user = Ambry.Accounts.get_user_by_email("claude@anthropic.local")

query = """
  query {
    me { email admin insertedAt }
  }
"""

Absinthe.run(query, AmbrySchema, context: %{current_user: user})
```

This avoids shell escaping issues and is faster than HTTP requests.
