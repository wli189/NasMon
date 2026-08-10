# Issue Tracker: Gitea (via MCP)

Issues for this repo live in the self-hosted **Gitea** instance, accessed through the **gitea-mcp** server.

## Location

- **Base URL**: `http://10.0.0.84:3001/brian/NasMon`
- **API Endpoint**: `http://10.0.0.84:3001/api/v1/repos/brian/NasMon/issues`
- **Access method**: Global `gitea` MCP server (stdio) registered in `~/.codex/config.toml` — no direct token use.

## Workflow Conventions

- All issue operations go through the **gitea MCP server** tools (e.g. `list issues`, `create issue`, `update issue`, `add labels`).
- The access token lives only on this machine at `~/.codex/mcp/gitea_token` (0600). Never read it into agent context.
- Do **not** use escalated `curl` against the Gitea API — MCP is the sanctioned path.
- Local mirrors of remote issues are kept in `.scratch/issues/NN-slug.md` with a `Status:` line.

## Operations

### When a skill says "create an issue"
Use the gitea MCP `create issue` tool with title, body, and optional labels.

### When a skill says "fetch the relevant ticket"
Use the gitea MCP `list issues` / `get issue` tools, or read the local mirror at `.scratch/issues/`.

### When a skill says "update or close an issue"
Use the gitea MCP `update issue` tool (e.g. `state: closed`), then update the matching `.scratch/issues/` mirror.

## Labels

The `triage-labels.md` file maps the five canonical triage roles to the label strings used in Gitea.
