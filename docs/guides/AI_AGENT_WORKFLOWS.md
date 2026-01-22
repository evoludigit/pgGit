# AI Agent Workflows with pgGit

This guide explains how to use pgGit to coordinate multiple AI agents working on database schema changes simultaneously.

## The Problem

When multiple AI agents (Claude, GPT, local models, or automated systems) work on the same codebase:

- **Schema collisions**: Two agents create conflicting migrations
- **Undetected conflicts**: Both modify the same table differently
- **No isolation**: One agent's experiment breaks another's work
- **Coordination overhead**: Manual tracking of "who's working on what"

## The Solution

pgGit provides **branch-based isolation** for AI agents, just like Git does for developers.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Agent A       │     │   Agent B       │     │   Agent C       │
│   (Claude)      │     │   (Local LLM)   │     │   (Automation)  │
│                 │     │                 │     │                 │
│ feature/auth    │     │ feature/search  │     │ feature/metrics │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │      pgGit (main)      │
                    │                        │
                    │  Merge, detect         │
                    │  conflicts, coordinate │
                    └────────────────────────┘
```

---

## Setup for AI Agents

### 1. Create Agent-Specific Branches

```sql
-- Each agent gets its own branch
SELECT pggit.create_branch('agent/claude-auth-feature');
SELECT pggit.create_branch('agent/local-llm-search');
SELECT pggit.create_branch('agent/automation-metrics');
```

### 2. Register Agent Intent (Optional)

Track what each agent is working on:

```sql
-- Create intent tracking table
CREATE TABLE IF NOT EXISTS pggit_agent_intents (
    id SERIAL PRIMARY KEY,
    agent_id TEXT NOT NULL,
    branch_name TEXT NOT NULL,
    intent TEXT NOT NULL,
    tables_affected TEXT[],
    started_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP,
    status TEXT DEFAULT 'in_progress'
);

-- Agent registers intent before starting
INSERT INTO pggit_agent_intents (agent_id, branch_name, intent, tables_affected)
VALUES ('claude-session-123', 'agent/claude-auth-feature',
        'Add OAuth2 support to users table',
        ARRAY['users', 'oauth_tokens']);
```

### 3. Check for Conflicts Before Starting

```sql
-- Before an agent starts, check if other agents are modifying same tables
SELECT * FROM pggit_agent_intents
WHERE status = 'in_progress'
  AND tables_affected && ARRAY['users'];  -- Overlapping tables

-- If conflict detected, coordinate or wait
```

---

## Agent Workflow Patterns

### Pattern 1: Independent Features

Agents work on completely separate features with no overlap.

```sql
-- Agent A: Authentication (users, oauth_tokens)
SELECT pggit.checkout('agent/claude-auth');
ALTER TABLE users ADD COLUMN oauth_provider TEXT;
CREATE TABLE oauth_tokens (id SERIAL, user_id INT, token TEXT);

-- Agent B: Search (search_index, search_logs) - no overlap
SELECT pggit.checkout('agent/local-llm-search');
CREATE TABLE search_index (id SERIAL, content TSVECTOR);
CREATE TABLE search_logs (id SERIAL, query TEXT, results INT);

-- Both can merge independently
SELECT pggit.checkout('main');
SELECT pggit.merge('agent/claude-auth', 'main');
SELECT pggit.merge('agent/local-llm-search', 'main');
```

### Pattern 2: Coordinated Modification

Multiple agents need to modify the same table.

```sql
-- Agent A wants to add: users.oauth_provider
-- Agent B wants to add: users.search_preferences

-- Step 1: Both register intent
INSERT INTO pggit_agent_intents (agent_id, branch_name, intent, tables_affected)
VALUES
  ('claude', 'agent/claude-auth', 'Add oauth_provider', ARRAY['users']),
  ('local-llm', 'agent/llm-search', 'Add search_preferences', ARRAY['users']);

-- Step 2: Detect overlap
SELECT a.agent_id, a.intent, b.agent_id, b.intent
FROM pggit_agent_intents a
JOIN pggit_agent_intents b ON a.tables_affected && b.tables_affected
WHERE a.agent_id != b.agent_id
  AND a.status = 'in_progress'
  AND b.status = 'in_progress';

-- Step 3: Coordinate - let both proceed, merge sequentially
SELECT pggit.checkout('main');
SELECT pggit.merge('agent/claude-auth', 'main');  -- First
SELECT pggit.merge('agent/llm-search', 'main');   -- Second, pgGit detects if conflict
```

### Pattern 3: Review Before Merge

Human reviews agent changes before merging to main.

```sql
-- Agent completes work
SELECT pggit.checkout('agent/claude-auth');
-- ... makes changes ...

-- Mark for review (don't merge yet)
UPDATE pggit_agent_intents
SET status = 'pending_review'
WHERE branch_name = 'agent/claude-auth';

-- Human reviews
SELECT * FROM pggit.diff('main', 'agent/claude-auth');
SELECT * FROM pggit.log('agent/claude-auth');

-- Human approves and merges
SELECT pggit.checkout('main');
SELECT pggit.merge('agent/claude-auth', 'main');
```

### Pattern 4: Automated Pipeline

CI/CD system coordinates agent changes automatically.

```bash
#!/bin/bash
# ci-agent-merge.sh

# Get all completed agent branches
BRANCHES=$(psql -t -c "
  SELECT branch_name FROM pggit_agent_intents
  WHERE status = 'completed'
  ORDER BY completed_at;
")

# Merge each in order
for branch in $BRANCHES; do
  echo "Merging $branch..."

  # Check for conflicts first
  CONFLICTS=$(psql -t -c "SELECT pggit.detect_conflicts('main', '$branch');")

  if [ -z "$CONFLICTS" ]; then
    psql -c "SELECT pggit.merge('$branch', 'main');"
    psql -c "UPDATE pggit_agent_intents SET status = 'merged' WHERE branch_name = '$branch';"
  else
    echo "Conflicts detected in $branch, skipping"
    psql -c "UPDATE pggit_agent_intents SET status = 'conflict' WHERE branch_name = '$branch';"
  fi
done

# Generate combined migration
confiture generate from-range main~10..main --name "agent_changes_$(date +%Y%m%d)"
```

---

## Multi-Agent Coordination Strategies

### Strategy 1: Lock-Based

Agents acquire locks on tables before modifying.

```sql
-- Agent acquires lock
INSERT INTO pggit_table_locks (agent_id, table_name, locked_at)
VALUES ('claude-123', 'users', NOW())
ON CONFLICT (table_name) DO NOTHING
RETURNING *;

-- If insert succeeded, agent has lock
-- If returned nothing, another agent has lock - wait or abort

-- Agent releases lock when done
DELETE FROM pggit_table_locks WHERE agent_id = 'claude-123';
```

### Strategy 2: Intent-Based (Optimistic)

Agents declare intent, proceed optimistically, resolve conflicts at merge.

```sql
-- All agents declare intent upfront
-- No blocking, just awareness

-- At merge time, pgGit detects actual conflicts
SELECT pggit.merge('agent/a', 'main');
-- Returns: 'CONFLICTS_DETECTED' or 'MERGE_SUCCESS'

-- If conflicts, human or coordinator resolves
SELECT pggit.resolve_conflict(conflict_id, 'custom',
  'Combined solution SQL here');
```

### Strategy 3: Partition-Based

Assign table ownership to specific agents.

```sql
-- Define partitions
CREATE TABLE pggit_agent_partitions (
    agent_type TEXT PRIMARY KEY,
    owned_tables TEXT[],
    owned_schemas TEXT[]
);

INSERT INTO pggit_agent_partitions VALUES
  ('auth-agent', ARRAY['users', 'sessions', 'oauth_tokens'], ARRAY['auth']),
  ('search-agent', ARRAY['search_index', 'search_logs'], ARRAY['search']),
  ('analytics-agent', ARRAY['events', 'metrics'], ARRAY['analytics']);

-- Agents only modify their owned tables
-- No coordination needed within partition
-- Cross-partition changes require explicit coordination
```

---

## Example: Claude + Local LLM Coordination

A realistic scenario with Claude (powerful, expensive) and a local LLM (fast, cheap).

### Setup

```sql
-- Claude handles complex architectural changes
SELECT pggit.create_branch('agent/claude-architecture');

-- Local LLM handles repetitive tasks
SELECT pggit.create_branch('agent/local-llm-indexes');
SELECT pggit.create_branch('agent/local-llm-constraints');
```

### Workflow

```python
# coordinator.py
import psycopg
from anthropic import Anthropic

def coordinate_agents():
    conn = psycopg.connect("postgresql://localhost/myapp_dev")

    # 1. Claude designs the architecture
    claude = Anthropic()
    architecture_plan = claude.messages.create(
        model="claude-sonnet-4-20250514",
        messages=[{"role": "user", "content": "Design user authentication schema..."}]
    )

    # 2. Apply Claude's changes to its branch
    with conn.cursor() as cur:
        cur.execute("SELECT pggit.checkout('agent/claude-architecture')")
        cur.execute(architecture_plan.content)  # DDL from Claude
        cur.execute("""
            INSERT INTO pggit_agent_intents (agent_id, branch_name, intent, tables_affected)
            VALUES ('claude', 'agent/claude-architecture', 'Auth schema design',
                    ARRAY['users', 'sessions', 'oauth_tokens'])
        """)
    conn.commit()

    # 3. Local LLM adds indexes (parallel, non-conflicting)
    local_tasks = [
        ("agent/local-llm-indexes", "CREATE INDEX idx_users_email ON users(email)"),
        ("agent/local-llm-indexes", "CREATE INDEX idx_sessions_user ON sessions(user_id)"),
    ]

    for branch, sql in local_tasks:
        with conn.cursor() as cur:
            cur.execute(f"SELECT pggit.checkout('{branch}')")
            cur.execute(sql)
    conn.commit()

    # 4. Merge in order: architecture first, then indexes
    with conn.cursor() as cur:
        cur.execute("SELECT pggit.checkout('main')")
        cur.execute("SELECT pggit.merge('agent/claude-architecture', 'main')")
        cur.execute("SELECT pggit.merge('agent/local-llm-indexes', 'main')")
    conn.commit()

    # 5. Generate migration
    subprocess.run(["confiture", "generate", "from-branch", "main",
                    "--name", "auth_feature"])
```

---

## Conflict Resolution for Agents

When agents create conflicting changes:

### Automatic Resolution

```sql
-- pgGit can auto-resolve some conflicts
SELECT pggit.merge('agent/a', 'main', auto_resolve => true);

-- Auto-resolution strategies:
-- - Column additions: Keep both (no conflict)
-- - Index additions: Keep both (no conflict)
-- - Constraint modifications: Flag for human review
```

### Human-in-the-Loop Resolution

```sql
-- Get conflicts
SELECT * FROM pggit.conflicts WHERE resolved = false;

-- Human reviews and resolves
SELECT pggit.resolve_conflict(
    conflict_id => 123,
    resolution => 'custom',
    custom_sql => 'ALTER TABLE users ADD COLUMN combined_field TEXT'
);
```

### Coordinator Agent Resolution

A dedicated "coordinator" agent resolves conflicts:

```python
# coordinator resolves conflicts using Claude
conflicts = db.query("SELECT * FROM pggit.conflicts WHERE resolved = false")

for conflict in conflicts:
    resolution = claude.messages.create(
        model="claude-sonnet-4-20250514",
        messages=[{
            "role": "user",
            "content": f"""
            Resolve this schema conflict:
            Branch A change: {conflict.branch_a_sql}
            Branch B change: {conflict.branch_b_sql}

            Provide combined SQL that preserves both intents.
            """
        }]
    )

    db.execute(f"""
        SELECT pggit.resolve_conflict({conflict.id}, 'custom', '{resolution.content}')
    """)
```

---

## Monitoring Agent Activity

### Dashboard Query

```sql
-- Agent activity overview
SELECT
    agent_id,
    branch_name,
    intent,
    tables_affected,
    status,
    started_at,
    completed_at,
    EXTRACT(EPOCH FROM (COALESCE(completed_at, NOW()) - started_at)) as duration_seconds
FROM pggit_agent_intents
ORDER BY started_at DESC
LIMIT 20;
```

### Conflict Rate Tracking

```sql
-- Track conflict rate over time
SELECT
    DATE(created_at) as date,
    COUNT(*) as total_merges,
    COUNT(*) FILTER (WHERE had_conflicts) as conflicts,
    ROUND(100.0 * COUNT(*) FILTER (WHERE had_conflicts) / COUNT(*), 2) as conflict_rate
FROM pggit_merge_history
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

### Agent Performance

```sql
-- Which agents create most conflicts?
SELECT
    agent_id,
    COUNT(*) as total_branches,
    COUNT(*) FILTER (WHERE status = 'merged') as successful,
    COUNT(*) FILTER (WHERE status = 'conflict') as conflicts
FROM pggit_agent_intents
GROUP BY agent_id
ORDER BY conflicts DESC;
```

---

## Best Practices

### Do

- **Create descriptive branch names**: `agent/claude-auth-oauth2-support`
- **Register intent before starting**: Helps detect conflicts early
- **Merge frequently**: Don't let branches diverge too far
- **Use partition strategy**: When possible, assign table ownership
- **Review before production**: Human approval for generated migrations

### Don't

- **Don't let agents modify main directly**: Always use branches
- **Don't ignore conflicts**: Resolve immediately
- **Don't run multiple agents on same branch**: One branch per agent task
- **Don't skip testing**: Test merged changes on staging

---

## Summary

| Strategy | Best For | Coordination Overhead |
|----------|----------|----------------------|
| Independent features | Non-overlapping work | Low |
| Intent-based | Occasional overlap | Medium |
| Lock-based | Frequent overlap | High |
| Partition-based | Predictable ownership | Low (after setup) |

pgGit enables safe multi-agent development by providing:
- **Isolation**: Each agent works in its own branch
- **Visibility**: See what each agent is doing
- **Conflict detection**: Know when agents conflict
- **Resolution**: Tools to merge conflicting changes

---

## Related Documentation

- [Development Workflow Guide](DEVELOPMENT_WORKFLOW.md) - Core pgGit workflows
- [Migration Integration](MIGRATION_INTEGRATION.md) - Generating migrations from agent work
- [Production Considerations](PRODUCTION_CONSIDERATIONS.md) - Deploying agent-generated changes
