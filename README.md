# SOT Server

Source of Truth server — structured data management via REST API and [MCP](https://modelcontextprotocol.io/) for AI agents. Built with Sinatra, Sequel, and SQLite.

Admin-defined schemas describe tables with typed fields and optional state machines. Records are CRUD'd with compare-and-swap preconditions and a full audit trail.

## Quick start

### Docker (recommended)

```bash
docker compose up -d
docker compose run --rm sot-server bundle exec rake db:seed   # creates admin user, prints token
```

### Local

```bash
bundle install
rake server            # starts on port 39482
curl -X POST http://localhost:39482/install   # creates admin user, returns token
```

Save the token — it won't be shown again. Use it as a Bearer token for all subsequent requests.

## API

All endpoints (except `/install`) require `Authorization: Bearer <token>`.

| Path | Description |
|------|-------------|
| `POST /install` | Bootstrap admin user (once) |
| `/api/schemas` | List schemas |
| `/api/records/:table` | Query records |
| `/api/records` | Create / update / delete records |
| `/api/admin/schemas` | Manage schemas (admin) |
| `/api/activity_log` | Audit trail |
| `/mcp` | MCP endpoint for AI agents |
| `/mcp/admin` | MCP admin endpoint |

## Connecting as MCP

The server exposes Streamable HTTP MCP transport on `/mcp` (user tools) and `/mcp/admin` (admin tools). Bearer token auth is required.

### Claude Code (CLI)

```bash
claude mcp add sot-user -t http http://localhost:39482/mcp \
  -H "Authorization: Bearer <token>"

claude mcp add sot-admin -t http http://localhost:39482/mcp/admin \
  -H "Authorization: Bearer <token>"
```

### JSON config (`.mcp.json` or `claude mcp add-json`)

```json
{
  "mcpServers": {
    "sot-user": {
      "type": "http",
      "url": "http://localhost:39482/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    },
    "sot-admin": {
      "type": "http",
      "url": "http://localhost:39482/mcp/admin",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

## Docker

The app runs in a multi-stage Docker build with `ruby:3.3-slim`. SQLite database is stored on a bind-mounted host directory (`./data/`).

Migrations run automatically on every container start. To run them manually:

```bash
docker compose run --rm sot-server bundle exec rake db:migrate
```

Configuration via environment variables in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `RACK_ENV` | `production` | Rack/Sinatra environment |
| `SOT_DB_PATH` | `/data/sot.sqlite3` | SQLite database file path |
| `PORT` | `39482` | Server listen port |

## Development

```bash
rake spec              # run tests
rake db:create_migration[name]   # generate migration
```
