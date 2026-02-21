# SOT Server

Source of Truth server — structured data management via REST API and [MCP](https://modelcontextprotocol.io/) for AI agents. Built with Sinatra, Sequel, and SQLite.

Admin-defined schemas describe entity types with typed fields and optional state machines. Records are CRUD'd with compare-and-swap preconditions and a full audit trail.

## Quick start

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
| `/api/records/:entity` | Query records |
| `/api/records` | Create / update / delete records |
| `/api/admin/schemas` | Manage schemas (admin) |
| `/api/activity_log` | Audit trail |
| `/mcp` | MCP endpoint for AI agents |
| `/mcp/admin` | MCP admin endpoint |

## Connecting as MCP

The server exposes Streamable HTTP MCP transport. Both user (`/mcp`) and admin (`/mcp/admin`) endpoints require a Bearer token.

### Claude Code (CLI)

```bash
claude mcp add sot-user -- \
  curl -N -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  http://localhost:39482/mcp
```

For admin tools:

```bash
claude mcp add sot-admin -- \
  curl -N -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  http://localhost:39482/mcp/admin
```

### JSON config

Add to your MCP client config (e.g. `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "sot-user": {
      "url": "http://localhost:39482/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    },
    "sot-admin": {
      "url": "http://localhost:39482/mcp/admin",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

## Development

```bash
rake spec              # run tests
rake db:create_migration[name]   # generate migration
```
