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

### Option 1: Manual Branch Management

For simple scenarios, agents can use pgGit branches directly:

```sql
-- Each agent gets its own branch
SELECT pggit.create_branch('agent/claude-auth-feature');
SELECT pggit.create_branch('agent/local-llm-search');
SELECT pggit.create_branch('agent/automation-metrics');
```

### Option 2: Confiture Coordination (Recommended)

[Confiture](https://github.com/fraiseql/confiture) provides a complete multi-agent coordination system with automatic conflict detection.

#### CLI-Based Coordination

```bash
# Register agent intent (auto-creates pgGit branch)
confiture coordinate register \
    --agent-id claude-payments \
    --feature-name stripe_integration \
    --schema-changes "ALTER TABLE users ADD COLUMN stripe_id TEXT" \
    --tables-affected users \
    --risk-level medium

# Pre-flight conflict check (before registering)
confiture coordinate check \
    --agent-id claude-auth \
    --feature-name oauth2 \
    --schema-changes "ALTER TABLE users ADD COLUMN oauth_provider TEXT" \
    --tables-affected users

# List all active intents
confiture coordinate list-intents --status-filter in_progress

# View conflicts for an intent
confiture coordinate conflicts --format json

# Resolve a conflict
confiture coordinate resolve \
    --conflict-id 42 \
    --notes "Coordinated with team: applying sequentially"
```

#### Python API Coordination

```python
from confiture.integrations.pggit.coordination import IntentRegistry, RiskLevel

registry = IntentRegistry(connection)

# Register intent (automatically detects conflicts)
intent = registry.register(
    agent_id="claude-payments",
    feature_name="stripe_integration",
    schema_changes=["ALTER TABLE users ADD COLUMN stripe_id TEXT"],
    tables_affected=["users"],
    risk_level=RiskLevel.MEDIUM
)

# Check for conflicts immediately
conflicts = registry.get_conflicts(intent.id)
for conflict in conflicts:
    print(f"{conflict.severity}: {conflict.affected_objects}")
    print(f"  Suggestion: {conflict.resolution_suggestions}")

# Update status as agent works
registry.mark_in_progress(intent.id)
# ... agent does work ...
registry.mark_completed(intent.id)

# After human review and merge
registry.mark_merged(intent.id)
```

### Conflict Detection

Confiture detects conflicts at **registration time**, not merge time:

| Conflict Type | Severity | Example |
|---------------|----------|---------|
| **TABLE** | WARNING | Both agents modify `users` table |
| **COLUMN** | ERROR | Both modify `users.email` column |
| **FUNCTION** | ERROR | Both redefine `process_payment()` |
| **INDEX** | WARNING | Both create index on same columns |
| **CONSTRAINT** | WARNING | Both add foreign keys to same table |

This "conflict-first" design means agents know about conflicts **before** they start coding.

---

## Agent Workflow Patterns

### Pattern 1: Independent Features (No Coordination Needed)

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

### Pattern 2: Coordinated Modification with Confiture

Multiple agents need to modify the same table. Confiture detects conflicts automatically.

```bash
# Agent A registers intent
confiture coordinate register \
    --agent-id claude-auth \
    --feature-name oauth_support \
    --schema-changes "ALTER TABLE users ADD COLUMN oauth_provider TEXT" \
    --tables-affected users

# Agent B registers intent - Confiture immediately warns about conflict
confiture coordinate register \
    --agent-id local-llm-search \
    --feature-name search_prefs \
    --schema-changes "ALTER TABLE users ADD COLUMN search_preferences JSONB" \
    --tables-affected users

# Output:
# ⚠️ WARNING: TABLE conflict detected
#   Affected: users
#   Conflicting intent: claude-auth (oauth_support)
#   Suggestion: Coordinate with claude-auth agent, consider sequential application

# Agents coordinate (discuss, adjust scope, etc.)

# After coordination, resolve the conflict
confiture coordinate resolve \
    --conflict-id 1 \
    --notes "Agreed to apply sequentially: auth first, then search"

# Both agents proceed, merge in agreed order
```

**Python equivalent:**

```python
from confiture.integrations.pggit.coordination import IntentRegistry, RiskLevel

registry = IntentRegistry(connection)

# Agent A registers
intent_a = registry.register(
    agent_id="claude-auth",
    feature_name="oauth_support",
    schema_changes=["ALTER TABLE users ADD COLUMN oauth_provider TEXT"],
    tables_affected=["users"],
    risk_level=RiskLevel.MEDIUM
)

# Agent B registers - conflicts detected automatically
intent_b = registry.register(
    agent_id="local-llm-search",
    feature_name="search_prefs",
    schema_changes=["ALTER TABLE users ADD COLUMN search_preferences JSONB"],
    tables_affected=["users"],
    risk_level=RiskLevel.LOW
)

# Both agents see conflict immediately
for conflict in registry.get_conflicts(intent_b.id):
    print(f"Conflict: {conflict.conflict_type} on {conflict.affected_objects}")
    # Output: Conflict: TABLE on ['users']
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

### Pattern 4: Automated Pipeline with Confiture

CI/CD system coordinates agent changes using Confiture's intent system.

```python
#!/usr/bin/env python3
# ci_agent_merge.py
"""Automated agent merge pipeline using Confiture coordination."""

from confiture.integrations.pggit import PgGitClient, MigrationGenerator
from confiture.integrations.pggit.coordination import IntentRegistry, IntentStatus
import psycopg

def merge_completed_intents():
    conn = psycopg.connect("postgresql://localhost/myapp_dev")
    client = PgGitClient(conn)
    registry = IntentRegistry(conn)

    # Get all completed intents (agents finished their work)
    completed = registry.list_intents(status_filter=IntentStatus.COMPLETED)

    for intent in completed:
        print(f"Processing: {intent.feature_name} by {intent.agent_id}")

        # Check for unresolved conflicts
        conflicts = [c for c in registry.get_conflicts(intent.id) if not c.reviewed]
        if conflicts:
            print(f"  ⚠️ Unresolved conflicts, skipping")
            continue

        # Merge to main
        client.checkout("main")
        result = client.merge(intent.branch_name, target_branch="main")

        if result.has_conflicts:
            print(f"  ❌ Merge conflicts detected")
            intent.status = IntentStatus.CONFLICTED
        else:
            print(f"  ✅ Merged successfully")
            registry.mark_merged(intent.id)
            client.delete_branch(intent.branch_name)

    # Generate combined migration from all merged changes
    generator = MigrationGenerator(client)
    migration = generator.generate_from_commits(
        commits=client.log("main", limit=10),
        name=f"agent_changes_{datetime.now():%Y%m%d}"
    )
    migration.write_to_file(Path("db/migrations/"))

if __name__ == "__main__":
    merge_completed_intents()
```

**Or as a shell script using Confiture CLI:**

```bash
#!/bin/bash
# ci-agent-merge.sh

# List completed intents
INTENTS=$(confiture coordinate list-intents --status-filter completed --format json | jq -r '.[].id')

for intent_id in $INTENTS; do
    echo "Processing intent $intent_id..."

    # Check for unresolved conflicts
    CONFLICTS=$(confiture coordinate conflicts --intent-id $intent_id --format json | jq 'length')
    if [ "$CONFLICTS" -gt 0 ]; then
        echo "  Skipping: unresolved conflicts"
        continue
    fi

    # Get branch name and merge
    BRANCH=$(confiture coordinate status --intent-id $intent_id --format json | jq -r '.branch_name')
    psql -c "SELECT pggit.checkout('main'); SELECT pggit.merge('$BRANCH', 'main');"

    # Mark as merged
    confiture coordinate mark-merged --intent-id $intent_id
done
```

---

## Multi-Agent Coordination Strategies

### Strategy 1: Intent-Based with Confiture (Recommended)

Confiture's coordination system uses an intent-first approach with automatic conflict detection.

```python
from confiture.integrations.pggit.coordination import IntentRegistry, RiskLevel

registry = IntentRegistry(connection)

# Agent declares intent BEFORE starting work
# Confiture immediately detects conflicts with other agents
intent = registry.register(
    agent_id="claude-auth",
    feature_name="oauth2_support",
    schema_changes=["ALTER TABLE users ADD COLUMN oauth_provider TEXT"],
    tables_affected=["users"],
    risk_level=RiskLevel.MEDIUM
)

# Check conflicts immediately
conflicts = registry.get_conflicts(intent.id)
if conflicts:
    # Coordinate before proceeding
    for c in conflicts:
        print(f"Conflict with {c.affected_objects}: {c.resolution_suggestions}")
```

**Key advantage**: Conflicts detected at registration time, not merge time.

### Strategy 2: Lock-Based (Manual)

For simple setups without Confiture, agents can use explicit locks.

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

### Strategy 3: Partition-Based

Assign table ownership to specific agent types. Best when agents have clear domain boundaries.

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

### Workflow with Confiture Coordination

```python
# coordinator.py
"""Multi-agent coordination using Confiture's intent system."""

import psycopg
from anthropic import Anthropic
from pathlib import Path

from confiture.integrations.pggit import PgGitClient, MigrationGenerator
from confiture.integrations.pggit.coordination import IntentRegistry, RiskLevel

def coordinate_agents():
    conn = psycopg.connect("postgresql://localhost/myapp_dev")
    client = PgGitClient(conn)
    registry = IntentRegistry(conn)
    claude = Anthropic()

    # 1. Claude registers intent for complex architecture work
    claude_intent = registry.register(
        agent_id="claude-architecture",
        feature_name="auth_system",
        schema_changes=[
            "CREATE TABLE users (id UUID PRIMARY KEY, email TEXT UNIQUE)",
            "CREATE TABLE sessions (id UUID PRIMARY KEY, user_id UUID REFERENCES users)",
            "CREATE TABLE oauth_tokens (id UUID PRIMARY KEY, user_id UUID REFERENCES users)"
        ],
        tables_affected=["users", "sessions", "oauth_tokens"],
        risk_level=RiskLevel.HIGH
    )

    # 2. Local LLM registers intent for index optimization
    #    Confiture automatically detects overlap on 'users' table
    local_intent = registry.register(
        agent_id="local-llm-indexes",
        feature_name="performance_indexes",
        schema_changes=[
            "CREATE INDEX idx_users_email ON users(email)",
            "CREATE INDEX idx_sessions_user ON sessions(user_id)"
        ],
        tables_affected=["users", "sessions"],
        risk_level=RiskLevel.LOW
    )

    # 3. Check conflicts - Confiture detected overlap
    conflicts = registry.get_conflicts(local_intent.id)
    if conflicts:
        print("Conflicts detected - coordinating...")
        for c in conflicts:
            # Resolve: indexes depend on tables existing first
            registry.resolve_conflict(
                c.id,
                resolution_notes="Apply architecture first, then indexes"
            )

    # 4. Claude designs and implements architecture
    registry.mark_in_progress(claude_intent.id)
    client.checkout(claude_intent.branch_name)

    architecture_ddl = claude.messages.create(
        model="claude-sonnet-4-20250514",
        messages=[{"role": "user", "content": "Design user authentication schema..."}]
    ).content[0].text

    conn.execute(architecture_ddl)
    client.commit("Implement auth schema")
    registry.mark_completed(claude_intent.id)

    # 5. Local LLM adds indexes (after architecture is ready)
    registry.mark_in_progress(local_intent.id)
    client.checkout(local_intent.branch_name)
    conn.execute("CREATE INDEX idx_users_email ON users(email)")
    conn.execute("CREATE INDEX idx_sessions_user ON sessions(user_id)")
    client.commit("Add performance indexes")
    registry.mark_completed(local_intent.id)

    # 6. Merge in dependency order
    client.checkout("main")
    client.merge(claude_intent.branch_name, target_branch="main")
    registry.mark_merged(claude_intent.id)

    client.merge(local_intent.branch_name, target_branch="main")
    registry.mark_merged(local_intent.id)

    # 7. Generate production migration
    generator = MigrationGenerator(client)
    migration = generator.generate_from_branch("main", name="auth_feature")
    migration.write_to_file(Path("db/migrations/"))

    print(f"✅ Generated migration: {migration.version}_{migration.name}")

if __name__ == "__main__":
    coordinate_agents()
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

| Strategy | Best For | Coordination Overhead | Tooling |
|----------|----------|----------------------|---------|
| Confiture Intent-Based | Any multi-agent work | Low (automatic) | `confiture coordinate` CLI |
| Independent features | Non-overlapping work | None | pgGit only |
| Lock-based | Simple setups | High (manual) | Custom tables |
| Partition-based | Predictable ownership | Low (after setup) | Custom tables |

**Recommended**: Use Confiture's coordination system for any multi-agent workflow. It provides:
- **Conflict-first detection**: Know about conflicts before coding starts
- **Automatic branch allocation**: Intents auto-create pgGit branches
- **Full audit trail**: All intent status changes tracked
- **CLI and Python API**: Use whichever fits your workflow

pgGit + Confiture enables safe multi-agent development by providing:
- **Isolation**: Each agent works in its own pgGit branch
- **Visibility**: `confiture coordinate list-intents` shows all agent activity
- **Early conflict detection**: Conflicts detected at registration, not merge
- **Resolution workflow**: Review, discuss, resolve, then proceed

---

## Related Documentation

- [Development Workflow Guide](DEVELOPMENT_WORKFLOW.md) - Core pgGit workflows
- [Migration Integration](MIGRATION_INTEGRATION.md) - Generating migrations from agent work
- [Production Considerations](PRODUCTION_CONSIDERATIONS.md) - Deploying agent-generated changes
- [Confiture Multi-Agent Guide](https://github.com/fraiseql/confiture/blob/main/docs/guides/multi-agent-coordination.md) - Full Confiture coordination docs
