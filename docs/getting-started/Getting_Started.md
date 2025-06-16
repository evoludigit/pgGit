# Getting Started with pggit

*A story-driven guide to your first steps with automatic PostgreSQL schema versioning*

## Chapter 1: The Problem We're Solving

Meet Sarah, a backend developer at a growing startup. It's Tuesday morning, and she's staring at her terminal with that familiar pit in her stomach. Yesterday's deployment changed something in the database schema, but she can't remember what. The staging environment works fine, but production is throwing errors about a missing column.

Sound familiar?

Sarah needs to answer three urgent questions:
1. What changed in the schema between last week and now?
2. Who made the changes?
3. How can she make sure this never happens again?

This is exactly the problem pggit solves. Let's walk through Sarah's journey from chaos to clarity.

---

## Chapter 2: The Five-Minute Setup

**What you'll need:**

- A PostgreSQL database (9.5 or later)
- PostgreSQL development headers installed
- About 5 minutes of your time
- A healthy dose of curiosity

**Sarah's first step: Installation**

```bash
# Sarah clones the repository
git clone https://github.com/your-repo/pggit
cd pggit

# She builds and installs (fingers crossed)
make
sudo make install

# The moment of truth - enabling the extension
psql -d her_database -c "CREATE EXTENSION pggit;"
```

If that worked without errors, congratulations! You now have a quiet assistant tracking every schema change. If it didn't work, don't panic - check our [Troubleshooting Guide](Troubleshooting.md).

**What just happened?**

Behind the scenes, pggit installed two event triggers that will automatically capture every CREATE, ALTER, and DROP command from now on. Sarah doesn't need to remember to track anything - it just happens.

---

## Chapter 3: Your First Automatic Tracking

**Sarah's scenario: Adding a feature**

The product team wants to add user profiles. Sarah starts with a simple table:

```sql
-- Sarah creates a basic user table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

Behind the scenes, pggit just:

1. Captured the exact DDL command
2. Assigned it version 1.0.0 (major version for new table)
3. Stored the timestamp and user information
4. Noted all the columns and constraints

**Let's see what happened:**

```sql
-- Check the version
SELECT * FROM pggit.get_version('public.users');
```

Results:
```
 object_name | schema_name | version | version_string |     created_at      
-------------|-------------|---------|----------------|--------------------
 users       | public      |       1 | 1.0.0          | 2024-06-14 09:15:23
```

**Sarah's reaction:** "Wait, I didn't have to do anything? It just... tracked it automatically?"

Exactly. That's the point.

---

## Chapter 4: Watching Changes Evolve

**The product team strikes again**

Two days later, the product team requests user names and bio fields:

```sql
-- Sarah adds the requested fields
ALTER TABLE users 
ADD COLUMN name VARCHAR(100),
ADD COLUMN bio TEXT;
```

**Let's see what pg_gitversion captured:**

```sql
-- Check the new version
SELECT * FROM pggit.get_version('public.users');
```

Results:
```
 object_name | schema_name | version | version_string |     created_at      
-------------|-------------|---------|----------------|--------------------
 users       | public      |       2 | 1.1.0          | 2024-06-14 11:42:18
```

Notice how the version went from 1.0.0 to 1.1.0? That's because adding nullable columns is a minor change - it doesn't break existing code.

**Now let's see the complete history:**

```sql
-- Sarah wants to see the full story
SELECT * FROM pggit.get_history('public.users');
```

Results:
```
 version | change_type |                    change_description                     |     created_at      | created_by 
---------|-------------|-----------------------------------------------------------|--------------------|-----------
       2 | ALTER       | ADD COLUMN name VARCHAR(100), ADD COLUMN bio TEXT        | 2024-06-14 11:42:18 | sarah
       1 | CREATE      | CREATE TABLE users (id SERIAL PRIMARY KEY, email VA...   | 2024-06-14 09:15:23 | sarah
```

**Sarah's growing confidence:** "I can actually see what I did and when I did it. This is amazing."

---

## Chapter 5: The Safety Net (Impact Analysis)

**A week later: The dangerous request**

The product team decides they don't need the bio field anymore and asks Sarah to remove it. In the past, Sarah would have just run the ALTER TABLE command and hoped for the best.

But now she has pggit, so she can check what might break:

```sql
-- Before making changes, Sarah checks for dependencies
SELECT * FROM pggit.get_impact_analysis('public.users');
```

Results show that the `user_reports` table has a foreign key reference to `users`, and there's also a view called `user_summary` that selects from the users table.

**Sarah's relief:** "I almost dropped a column that other things depend on. Let me check those dependencies first."

This is the power of having visibility into your schema changes - you can make informed decisions instead of just hoping for the best.

---

## Chapter 6: Migration Magic

**Deployment day approaches**

Sarah has made several changes in her development environment over the past week. Now she needs to apply those same changes to staging and production. In the old days, this meant manually writing migration scripts and hoping she didn't forget anything.

With pggit, she can generate migration scripts automatically:

```sql
-- Generate a migration for all changes since the last deployment
SELECT pggit.generate_migration(
    'user_profile_features',
    'Added user name and bio fields, created user_reports table'
);
```

This creates both "up" and "down" migration scripts that Sarah can review, test, and apply to other environments.

**What the migration script contains:**

- All the DDL changes in the correct order
- Dependency information to avoid conflicts
- Rollback instructions (where possible)
- Timestamps and change descriptions

**Sarah's new deployment confidence:** "I know exactly what changes I'm deploying, and I have a rollback plan if something goes wrong."

---

## Chapter 7: Team Collaboration

**Sarah's not alone**

When other developers join the project, they can immediately see the schema evolution history:

```sql
-- New team member wants to understand the schema
SELECT 
    object_name,
    version_string,
    created_at,
    created_by,
    change_description
FROM pggit.get_history('public.users', 10)
ORDER BY created_at DESC;
```

This gives the new developer a complete timeline of how the schema evolved, who made changes, and why.

**The team's collective sigh of relief:** "Finally, we can see what everyone has been doing to the database."

---

## Chapter 8: What's Next?

Now that you've seen Sarah's journey from schema chaos to clarity, here are some next steps:

### Immediate Next Steps

1. **Install pggit** in your development environment
2. **Create a test table** and watch it get tracked automatically
3. **Make some changes** and explore the history functions
4. **Try the impact analysis** before dropping something

### Advanced Features to Explore

- **Custom dependencies** for logical relationships pggit can't detect
- **Version reports** for comprehensive schema documentation
- **Circular dependency detection** for complex schemas
- **Cross-schema tracking** for multi-schema applications

### Integration Ideas

- **CI/CD pipelines** that use migration scripts
- **Database documentation** generated from version history
- **Change approval workflows** based on impact analysis
- **Automated testing** that validates schema compatibility

---

## Chapter 9: When Things Don't Go As Planned

**Real talk: Common situations and solutions**

### "I installed it, but nothing seems to be tracked"

Check if the extension is actually enabled:
```sql
SELECT * FROM pg_extension WHERE extname = 'pggit';
```

If it's not there, the CREATE EXTENSION command might have failed silently. Check PostgreSQL logs.

### "The version numbers don't make sense to me"

pggit uses semantic versioning with database-specific rules. Check the [Version Numbering Logic](README.md#version-numbering-logic) section in our main documentation.

### "I'm getting permission errors"

Event triggers require superuser privileges to install. Make sure you're running the installation commands as a database superuser.

### "It's tracking too much/too little"

By default, pggit tracks all schema changes. You can configure what gets tracked by modifying the event trigger conditions.

---

## The Happy Ending

Six months later, Sarah's team has complete visibility into their schema changes. They deploy with confidence, new team members onboard quickly, and that sinking feeling about mysterious database changes is just a memory.

**Sarah's testimonial:** "pggit didn't just solve our schema tracking problem - it changed how we think about database evolution. We're not afraid of database changes anymore because we can see exactly what's happening."

**Your turn:** Ready to start your own journey from schema chaos to clarity?

---

## Quick Reference: Essential Commands

```sql
-- Check version of any object
SELECT * FROM pggit.get_version('schema.object_name');

-- See change history
SELECT * FROM pggit.get_history('schema.object_name', 20);

-- Check impact before dropping
SELECT * FROM pggit.get_impact_analysis('schema.object_name');

-- Generate migration script
SELECT pggit.generate_migration('migration_name', 'description');

-- See all current versions
SELECT * FROM pggit.show_table_versions();
```

---

*Remember: The best database version control system is the one you actually use. pggit works automatically, so you don't have to remember to use it.*

**Need help?** Check our [API Documentation](../API_Reference.md), [Troubleshooting Guide](Troubleshooting.md), or open an issue on GitHub. We're here to help!