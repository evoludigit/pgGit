# pggit Local LLM Quick Start

Get AI-powered migrations running in 15 minutes

## 🚀 Zero to AI Migrations

### Step 1: Run the Setup Script (5 minutes)

```bash
# Clone pggit
git clone https://github.com/evoludigit/pggit
cd pggit

# Run automated setup
./scripts/setup-local-ai.sh

# If you're not root, install system deps first:
sudo apt install build-essential python3-dev python3-pip git curl wget
```

### Step 2: Test the Integration (2 minutes)

```sql
-- Connect to PostgreSQL
psql

-- Test AI functions
SELECT * FROM pggit.test_llm_integration();

-- Expected output:
-- test_name          | status | details
-- LLM Availability   | PASS   | Local LLM function exists
-- Embedding Generation| PASS   | MiniLM embeddings are 384-dimensional
-- Migration Analysis | PASS   | Analyzed simple CREATE TABLE, confidence: 0.95
```

### Step 3: Your First AI Migration (30 seconds)

```sql
-- Analyze a Flyway migration
SELECT * FROM pggit.analyze_migration_with_llm(
    'CREATE TABLE users (id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE);',
    'flyway',
    'V1__create_users.sql'
);
```

### Expected Result:
```
intent          | Create users table with unique email constraint
pattern_type    | CREATE_TABLE
confidence      | 0.97
pggit_sql      | CREATE TABLE main.users (id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE);
rollback_sql   | DROP TABLE main.users;
semantic_version| 1.0.0
risk_assessment | LOW - Standard table creation
```

Done! You now have AI-powered migrations running locally.


---

## 📦 What Just Happened?

The setup script installed:

1. **llama.cpp** - Fast LLM inference engine
2. **CodeLlama-SQL-7B** - 4GB quantized model specialized for SQL
3. **sentence-transformers** - For semantic similarity matching
4. **pgvector** - PostgreSQL extension for embeddings
5. **plpython3u** - PostgreSQL Python integration

---

## 🧪 Test Different Migration Types

### Flyway Migration
```sql
SELECT * FROM pggit.analyze_migration_with_llm(
    'ALTER TABLE customers ADD COLUMN loyalty_points INTEGER DEFAULT 0;',
    'flyway',
    'V47__add_loyalty_points.sql'
);
```

### Rails Migration
```sql
SELECT * FROM pggit.analyze_migration_with_llm(
    'class AddIndexToUsers < ActiveRecord::Migration[7.0]
      def change
        add_index :users, :email
      end
    end',
    'rails',
    '20240315_add_index_to_users.rb'
);
```

### Liquibase Changeset
```sql
SELECT * FROM pggit.analyze_migration_with_llm(
    '<addColumn tableName="products">
        <column name="description" type="TEXT"/>
    </addColumn>',
    'liquibase',
    'changelog-add-description.xml'
);
```

---

## 🚀 Batch Processing

Process multiple migrations at once:

```sql
SELECT * FROM pggit.ai_migrate_batch(
    '[
        {"name": "V1__init.sql", "content": "CREATE TABLE products (id SERIAL PRIMARY KEY);"},
        {"name": "V2__add_name.sql", "content": "ALTER TABLE products ADD COLUMN name VARCHAR(255);"}
    ]'::jsonb,
    'flyway'
);
```

### Expected Output:
```
migration_name | status  | confidence | message
V1__init.sql   | SUCCESS | 0.98       | Migrated with 0.98 confidence
V2__add_name.sql| SUCCESS | 0.95       | Migrated with 0.95 confidence
SUMMARY        | COMPLETE| 0.97       | 2 migrations successful, 0 need review
```

---

## 🎯 Edge Case Handling

The AI automatically flags complex migrations:

```sql
SELECT * FROM pggit.analyze_migration_with_llm(
    'CREATE OR REPLACE FUNCTION complex_business_logic() 
     RETURNS TRIGGER AS $$ 
     BEGIN 
         -- Complex logic here
         UPDATE stats SET value = calculate_complex_metric(NEW.id);
         RETURN NEW;
     END; 
     $$ LANGUAGE plpgsql;',
    'flyway',
    'V99__complex_function.sql'
);
```

### Expected Result:
```
confidence      | 0.73
risk_assessment | MEDIUM - Custom function with business logic
```

Low confidence triggers manual review automatically.


---

## 🔧 Troubleshooting

### Model Too Slow?
```bash
# Use smaller 3B model instead
wget https://huggingface.co/TheBloke/CodeLlama-3B-SQL-GGUF/resolve/main/codellama-3b-sql.Q4_K_M.gguf -O /models/codellama-3b-sql.gguf

# Update model path in function calls
SELECT pggit.call_local_llm('test', '/models/codellama-3b-sql.gguf');
```

### Out of Memory?
```bash
# Monitor memory usage
htop

# Use quantized model (already done) or reduce context
SELECT pggit.call_local_llm('test', p_max_tokens := 256);
```

### Missing Dependencies?
```bash
# Check PostgreSQL extensions
psql -c "\dx"

# Install missing extensions
sudo apt install postgresql-plpython3-16
sudo apt install postgresql-16-pgvector
```

---

## 📊 Performance Expectations

### Hardware Requirements
- **Minimum**: 8GB RAM, 4 CPU cores
- **Recommended**: 16GB RAM, 8 CPU cores
- **GPU**: Optional, CPU inference works fine

### Processing Speed
- **Simple migrations**: ~200ms per migration
- **Complex migrations**: ~500ms per migration
- **Batch processing**: ~5 migrations per second

### Accuracy
- **Standard DDL**: 95%+ confidence
- **Complex logic**: 70-85% confidence (flagged for review)
- **Edge cases**: <70% confidence (manual review required)

---

## 🎪 Advanced Features

### Pattern Learning
The AI learns from your migrations:

```sql
-- Check what patterns it has learned
SELECT pattern_type, usage_count, confidence_threshold
FROM pggit.migration_patterns
ORDER BY usage_count DESC;
```

### Confidence Tuning
Adjust confidence thresholds:

```sql
-- Require higher confidence for auto-approval
UPDATE pggit.migration_patterns 
SET confidence_threshold = 0.95 
WHERE pattern_type = 'DROP_COLUMN';
```

### Custom Patterns
Add your own patterns:

```sql
INSERT INTO pggit.migration_patterns (
    pattern_type, 
    source_tool, 
    pattern_sql, 
    semantic_meaning
) VALUES (
    'ADD_AUDIT_COLUMNS',
    'custom',
    'ALTER TABLE % ADD COLUMN created_at TIMESTAMP, ADD COLUMN updated_at TIMESTAMP',
    'Adding standard audit columns to table'
);
```

---

## 🔒 Privacy & Security

Your migrations never leave your server:

- **No cloud API calls**
- **No data transmission**
- **Local model inference only**
- **Full audit trail** in `pggit.ai_decisions`

---

## 🚀 Next Steps

1. **Run the demo**: `psql -f examples/06_local_ai_demo.sql`
2. **Try your real migrations**: Point it at your Flyway/Liquibase files
3. **Tune confidence levels**: Adjust thresholds for your risk tolerance
4. **Add custom patterns**: Teach it your organization's migration patterns

---

## 📞 Getting Help

- **Check logs**: `SELECT * FROM pggit.ai_decisions ORDER BY created_at DESC LIMIT 10;`
- **Test integration**: `SELECT * FROM pggit.test_llm_integration();`
- **View patterns**: `SELECT * FROM pggit.migration_patterns;`
- **Monitor performance**: Watch `inference_time_ms` in `ai_decisions`

---

*From traditional 12-week migrations to 3-minute AI-powered ones. Welcome to
the future!* 🤖
