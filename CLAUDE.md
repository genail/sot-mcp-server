# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

SOT (Source of Truth) Server — a Ruby backend exposing structured data management via both REST API and MCP (Model Context Protocol) for AI agents. Built with Sinatra + Sequel ORM + SQLite. Tables are defined by admin-managed schemas; records are CRUD'd with precondition-based compare-and-swap, state transitions, and a full audit trail.

## Commands

```bash
bundle install                          # Install dependencies
rake db:migrate                         # Run pending migrations (also auto-runs on boot)
rake db:seed                            # Create admin user (prints token once)
rake spec                               # Run all tests (default rake task)
bundle exec rspec spec/models/user_spec.rb          # Run single test file
bundle exec rspec spec/models/user_spec.rb:42       # Run single example by line
rake server                             # Start server on port 39482
rake db:create_migration[name]          # Generate new migration file
rake db:rollback                        # Rollback last migration
```

No linter is configured.

## Architecture

### Request Routing (config.ru)

Three Rack-mounted paths, each behind `TokenAuth` middleware (Bearer token + BCrypt):

| Path          | Extra Middleware | Handler                     |
|---------------|------------------|-----------------------------|
| `/mcp/admin`  | `AdminGate`      | `RackMcpApp` with admin tools |
| `/mcp`        | —                | `RackMcpApp` with user tools  |
| `/api`        | —                | Sinatra `ApiApp` (REST JSON)  |

### Layers

- **Middleware** (`lib/sot/middleware/`) — `TokenAuth` authenticates and sets `env['sot.current_user']`; `AdminGate` checks `is_admin`.
- **MCP Tools** (`lib/sot/tools/`) — Inherit from `MCP::Tool`. Each defines `tool_name`, `description`, `input_schema`, and `self.call(server_context:, **params)`. User tools: `sot_query`, `sot_mutate`, `sot_describe_tables`, `sot_activity_log`, `sot_feedback`. Admin tools: `sot_admin_manage_schema`, `sot_admin_manage_users`, `sot_admin_view_feedback`.
- **Services** (`lib/sot/services/`) — Stateless business logic. `MutationService` wraps writes in transactions with precondition checks and activity logging. `QueryService` uses SQLite `json_extract()` for filtering JSON fields. `SchemaService` validates field types (`string`, `integer`, `float`, `boolean`, `text`).
- **Models** (`lib/sot/models/`) — Sequel models mapped to underscore-prefixed tables (`_users`, `_schemas`, `_records`, `_activity_log`, `_feedback`). `User.authenticate(token)` does BCrypt compare. `Schema` parses JSON `fields`/`states` columns. `Record` stores data as JSON.

### Database

SQLite with Sequel. Test env uses in-memory DB (`:memory:`); dev/prod uses `db/sot.db`. Migrations are numbered sequentially in `db/migrations/`. WAL mode and foreign keys are enabled via pragmas in `config/database.rb`. Boot (`config/boot.rb`) auto-runs pending migrations.

### Key Design Patterns

- **Compare-and-swap preconditions** on mutations prevent lost-update races (see `MutationService`).
- **Immutable activity log** records every create/update/delete with before/after diffs.
- **Feedback loop** — agents call `sot_feedback` to flag confusing schema descriptions; admins review via `sot_admin_view_feedback`.
- **Namespaced schemas** — tables scoped by `namespace.name` (e.g., `org.locks`).
- **Optional state machine** — schemas can define `states`; records transition between them.

## Testing

RSpec with FactoryBot (Sequel strategy) and `database_cleaner-sequel` (truncation). Helpers:

- `spec/support/api_helper.rb` — Rack::Test wrappers (`auth_header`, `post_json`, `json_body`). Used via `type: :api`.
- `spec/support/mcp_helper.rb` — `call_tool(tool_class, user:, **params)` and `response_text`/`response_error?`. Used via `type: :tool`.

Factories in `spec/factories/` for `users`, `schemas`, `records`.
