# Local OpenCode Config

The checked-in `opencode.json` must not contain bearer tokens or private MCP
headers. The project keeps the `rube_mcp` entry disabled so repository scans do
not leak credentials.

To use Rube locally, create a private config outside this repository, for
example:

```text
~/.hermes/secrets/opencode/ezcar24-opencode.json
```

Use this shape and replace the token locally only:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "rube_mcp": {
      "type": "remote",
      "url": "https://rube.app/mcp",
      "enabled": true,
      "headers": {
        "Authorization": "Bearer <local-rube-token>"
      }
    }
  }
}
```

Run OpenCode with:

```bash
OPENCODE_CONFIG="$HOME/.hermes/secrets/opencode/ezcar24-opencode.json" opencode
```

If the previous checked-in token was real, revoke or rotate it before relying on
it again.
