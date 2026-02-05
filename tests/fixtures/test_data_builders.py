"""
pgGit Functional Tests - Test Data Builders

Provides reusable builders for creating test data across all modules:
- BaseTestBuilder: Common operations
- ConfigurationTestBuilder: Configuration-specific
- CQRSTestBuilder: CQRS-specific
- FunctionVersioningTestBuilder: Function versioning-specific
- MigrationTestBuilder: Migration-specific
- ConflictTestBuilder: Conflict resolution-specific
"""


class BaseTestBuilder:
    """Base builder with common operations for all test builders"""

    def __init__(self, db_connection):
        self.conn = db_connection

    def execute(self, sql: str, params=None):
        """Execute SQL"""
        if params:
            return self.conn.execute(sql, params)
        else:
            return self.conn.execute(sql)

    def fetch_one(self, sql: str, params=None):
        """Execute SQL and return first row"""
        result = self.execute(sql, params)
        return result.fetchone()

    def fetch_value(self, sql: str, params=None):
        """Execute SQL and return first column of first row"""
        result = self.fetch_one(sql, params)
        return result[0] if result else None

    def create_schema(self, name: str) -> str:
        """Create schema"""
        self.execute(f"CREATE SCHEMA IF NOT EXISTS {name}")
        return name

    def create_schemas(self, names: list) -> list:
        """Create multiple schemas"""
        return [self.create_schema(name) for name in names]

    def drop_schema(self, name: str):
        """Drop schema"""
        self.execute(f"DROP SCHEMA IF EXISTS {name} CASCADE")

    def create_table(self, schema: str, name: str, columns: dict = None) -> str:
        """Create table"""
        if columns is None:
            columns = {
                "id": "SERIAL PRIMARY KEY",
                "data": "TEXT",
                "created_at": "TIMESTAMP DEFAULT NOW()"
            }

        col_defs = ", ".join([f"{k} {v}" for k, v in columns.items()])
        full_name = f"{schema}.{name}"
        self.execute(f"CREATE TABLE {full_name} ({col_defs})")
        return full_name

    def insert_rows(self, table: str, count: int, data_template: str = None) -> list:
        """Insert test rows"""
        rows = []
        for i in range(count):
            data = data_template or f"Row {i}"
            result = self.execute(
                f"INSERT INTO {table} (data) VALUES (%s) RETURNING id",
                (data,)
            )
            row_id = result.fetchone()[0]
            rows.append(row_id)
        return rows

    def get_table_count(self, table: str) -> int:
        """Get row count for table"""
        return self.fetch_value(f"SELECT COUNT(*) FROM {table}")

    def create_function(self, schema: str, name: str, params: list = None,
                       returns: str = "text", body: str = None) -> str:
        """Create function"""
        if params is None:
            params = []
        if body is None:
            body = "RETURN 'test'"

        param_str = ", ".join(params)
        func_sig = f"{schema}.{name}({param_str})"

        self.execute(f"""
            CREATE OR REPLACE FUNCTION {func_sig} RETURNS {returns} AS $$
            BEGIN
                {body};
            END;
            $$ LANGUAGE plpgsql;
        """)

        return func_sig


class ConfigurationTestBuilder(BaseTestBuilder):
    """Builder for configuration system tests"""

    def setup_deployment_scenario(self) -> dict:
        """Setup complete deployment scenario"""
        # Create test schemas
        schema = self.create_schema("app_schema")
        self.create_schema("internal_schema")
        self.create_schema("backup_schema")

        # Create test table with data
        table = self.create_table(schema, "users", {
            "id": "SERIAL PRIMARY KEY",
            "username": "TEXT NOT NULL",
            "email": "TEXT",
            "created_at": "TIMESTAMP DEFAULT NOW()"
        })

        # Insert test data
        rows = self.insert_rows(table, 100, "user_{}")

        return {
            "schema": schema,
            "table": table,
            "rows": rows,
            "schemas": [schema, "internal_schema", "backup_schema"]
        }

    def setup_tracking_configuration(self, track_schemas: list,
                                     ignore_schemas: list) -> dict:
        """Setup tracking configuration"""
        # Call pggit.configure_tracking
        self.execute("""
            SELECT pggit.configure_tracking(%s, %s)
        """, (track_schemas, ignore_schemas))

        return {
            "track_schemas": track_schemas,
            "ignore_schemas": ignore_schemas
        }

    def begin_test_deployment(self, name: str = "test-deploy") -> str:
        """Begin deployment mode"""
        result = self.execute("""
            SELECT pggit.begin_deployment(%s)
        """, (name,))
        return result.fetchone()[0]


class CQRSTestBuilder(BaseTestBuilder):
    """Builder for CQRS support tests"""

    def create_cqrs_scenario(self) -> dict:
        """Create complete CQRS scenario with command and query schemas"""
        # Create command and query schemas
        command_schema = self.create_schema("command")
        query_schema = self.create_schema("query")

        # Create command table (events/writes)
        command_table = self.create_table(command_schema, "events", {
            "id": "SERIAL PRIMARY KEY",
            "event_type": "TEXT NOT NULL",
            "event_data": "JSONB",
            "timestamp": "TIMESTAMP DEFAULT NOW()"
        })

        # Create query table (read model)
        query_table = self.create_table(query_schema, "read_model", {
            "id": "SERIAL PRIMARY KEY",
            "entity_id": "INT",
            "count": "INT DEFAULT 0",
            "last_updated": "TIMESTAMP DEFAULT NOW()"
        })

        return {
            "command_schema": command_schema,
            "query_schema": query_schema,
            "command_table": command_table,
            "query_table": query_table
        }

    def create_cqrs_scenario_advanced(self) -> dict:
        """Create advanced CQRS scenario with multiple tables and views"""
        command_schema = self.create_schema("command")
        query_schema = self.create_schema("query")

        # Create multiple command tables
        users_cmd = self.create_table(command_schema, "users_cmd", {
            "id": "SERIAL PRIMARY KEY",
            "name": "TEXT NOT NULL",
            "email": "TEXT",
            "created_at": "TIMESTAMP DEFAULT NOW()"
        })

        orders_cmd = self.create_table(command_schema, "orders_cmd", {
            "id": "SERIAL PRIMARY KEY",
            "user_id": "INT",
            "amount": "DECIMAL(10,2)",
            "created_at": "TIMESTAMP DEFAULT NOW()"
        })

        # Create materialized view on query side
        self.execute(f"""
            CREATE MATERIALIZED VIEW {query_schema}.users_view AS
            SELECT id, name, email, created_at FROM {command_schema}.users_cmd
        """)

        return {
            "command_schema": command_schema,
            "query_schema": query_schema,
            "users_cmd": users_cmd,
            "orders_cmd": orders_cmd,
            "view": f"{query_schema}.users_view"
        }

    def track_cqrs_change(self, command_ops: list, query_ops: list,
                         description: str = "Test changeset", atomic: bool = True) -> dict:
        """Track a CQRS change and return changeset metadata"""
        result = self.execute(f"""
            SELECT pggit.track_cqrs_change(
                ROW(%s, %s, %s, '1.0')::pggit.cqrs_change,
                %s
            )
        """, (command_ops, query_ops, description, atomic))

        changeset_id = result.fetchone()[0]
        return {
            "changeset_id": changeset_id,
            "description": description,
            "command_ops": command_ops,
            "query_ops": query_ops,
            "atomic": atomic
        }

    def execute_changeset(self, changeset_id) -> None:
        """Execute a CQRS changeset"""
        self.execute("SELECT pggit.execute_cqrs_changeset(%s)", (changeset_id,))

    def get_changeset_status(self, changeset_id) -> dict:
        """Get status of a CQRS changeset"""
        result = self.execute("""
            SELECT status, created_at, updated_at
            FROM pggit.cqrs_changesets
            WHERE id = %s
        """, (changeset_id,))

        row = result.fetchone()
        if row:
            return {
                "status": row[0],
                "created_at": row[1],
                "updated_at": row[2]
            }
        return None


class FunctionVersioningTestBuilder(BaseTestBuilder):
    """Builder for function versioning tests"""

    def create_test_functions(self) -> dict:
        """Create test schema with sample functions"""
        schema = self.create_schema("test_functions")

        # Create simple function
        func1 = self.create_function(
            schema, "greet",
            params=["p_name text"],
            returns="text",
            body="RETURN 'Hello, ' || p_name"
        )

        # Create overloaded function (different parameter types)
        func2 = self.create_function(
            schema, "greet",
            params=["p_first text", "p_last text"],
            returns="text",
            body="RETURN 'Hello, ' || p_first || ' ' || p_last"
        )

        return {
            "schema": schema,
            "functions": [func1, func2]
        }

    def create_function_family(self, schema: str, base_name: str,
                              overload_count: int = 3) -> dict:
        """Create function with multiple overloads"""
        param_types = ["int", "text", "numeric", "boolean", "timestamp"]
        functions = []

        for i in range(overload_count):
            param_type = param_types[i % len(param_types)]
            func = self.create_function(
                schema,
                base_name,
                params=[f"p_val {param_type}"],
                returns=param_type,
                body="RETURN p_val"
            )
            functions.append(func)

        return {
            "base_name": base_name,
            "schema": schema,
            "functions": functions,
            "count": overload_count
        }

    def track_function_version(self, function_signature: str, version: str = None,
                              metadata: dict = None) -> dict:
        """Track a function version"""
        try:
            result = self.execute(f"""
                SELECT pggit.track_function(%s, %s, %s::jsonb)
            """, (function_signature, version, metadata))
            return {
                "function_signature": function_signature,
                "version": version,
                "metadata": metadata,
                "tracked": True
            }
        except Exception as e:
            # Function tracking might have dependencies
            return {
                "function_signature": function_signature,
                "version": version,
                "metadata": metadata,
                "tracked": False,
                "error": str(e)
            }

    def get_function_overloads(self, schema: str, function_name: str) -> dict:
        """Get all overloads of a function"""
        try:
            result = self.execute(f"""
                SELECT signature, argument_types, return_type, current_version, last_modified
                FROM pggit.list_function_overloads(%s, %s)
            """, (schema, function_name))

            overloads = []
            for row in result.fetchall():
                overloads.append({
                    "signature": row[0],
                    "argument_types": row[1],
                    "return_type": row[2],
                    "current_version": row[3],
                    "last_modified": row[4]
                })

            return {
                "schema": schema,
                "function_name": function_name,
                "overloads": overloads,
                "count": len(overloads)
            }
        except Exception as e:
            return {
                "schema": schema,
                "function_name": function_name,
                "overloads": [],
                "count": 0,
                "error": str(e)
            }

    def get_function_version_info(self, function_signature: str) -> dict:
        """Get version information for a function"""
        try:
            result = self.execute(f"""
                SELECT version, created_at, created_by, metadata
                FROM pggit.get_function_version(%s)
                LIMIT 1
            """, (function_signature,))

            row = result.fetchone()
            if row:
                return {
                    "version": row[0],
                    "created_at": row[1],
                    "created_by": row[2],
                    "metadata": row[3],
                    "found": True
                }
            return {"found": False}
        except Exception:
            return {"found": False}

    def diff_function_versions(self, function_signature: str, version1: str = None,
                              version2: str = None) -> dict:
        """Get diff between two function versions"""
        try:
            result = self.execute(f"""
                SELECT line_number, change_type, version1_line, version2_line
                FROM pggit.diff_function_versions(%s, %s, %s)
            """, (function_signature, version1, version2))

            diffs = []
            for row in result.fetchall():
                diffs.append({
                    "line_number": row[0],
                    "change_type": row[1],
                    "version1_line": row[2],
                    "version2_line": row[3]
                })

            return {
                "function_signature": function_signature,
                "version1": version1,
                "version2": version2,
                "diffs": diffs,
                "change_count": len(diffs)
            }
        except Exception as e:
            return {
                "function_signature": function_signature,
                "version1": version1,
                "version2": version2,
                "diffs": [],
                "change_count": 0,
                "error": str(e)
            }


class MigrationTestBuilder(BaseTestBuilder):
    """Builder for migration integration tests"""

    def create_migration_scenario(self) -> dict:
        """Create migration test scenario"""
        schema = self.create_schema("test_migrations")

        # Create a table to migrate
        table = self.create_table(schema, "users", {
            "id": "SERIAL PRIMARY KEY",
            "name": "TEXT NOT NULL",
            "email": "TEXT",
            "created_at": "TIMESTAMP DEFAULT NOW()"
        })

        return {
            "schema": schema,
            "migrations": [],
            "table": table
        }

    def create_flyway_schema_history(self) -> str:
        """Create Flyway schema_history table"""
        table_name = "public.flyway_schema_history"
        self.execute(f"""
            CREATE TABLE IF NOT EXISTS {table_name} (
                installed_rank INT PRIMARY KEY,
                version VARCHAR(50),
                description VARCHAR(255) NOT NULL,
                type VARCHAR(20) NOT NULL,
                script VARCHAR(1000) NOT NULL,
                checksum INT,
                installed_by VARCHAR(100),
                installed_on TIMESTAMP DEFAULT NOW(),
                execution_time INT,
                success BOOLEAN
            )
        """)
        return table_name

    def insert_flyway_migration(self, version: str, description: str,
                               rank: int = None) -> dict:
        """Insert Flyway migration record"""
        if rank is None:
            # Get next rank
            result = self.fetch_value(
                "SELECT COALESCE(MAX(installed_rank), 0) + 1 FROM public.flyway_schema_history"
            )
            rank = result or 1

        self.execute("""
            INSERT INTO public.flyway_schema_history
            (installed_rank, version, description, type, script, success)
            VALUES (%s, %s, %s, 'SQL', %s, true)
        """, (rank, version, description, f"V{version}__{'_'.join(description.split())}.sql"))

        return {
            "version": version,
            "description": description,
            "rank": rank
        }

    def create_liquibase_databasechangelog(self) -> str:
        """Create Liquibase databasechangelog table"""
        table_name = "public.databasechangelog"
        self.execute(f"""
            CREATE TABLE IF NOT EXISTS {table_name} (
                id VARCHAR(255) NOT NULL,
                author VARCHAR(255) NOT NULL,
                filename VARCHAR(255) NOT NULL,
                dateexecuted TIMESTAMP NOT NULL,
                orderexecuted INT NOT NULL,
                exectype VARCHAR(10) NOT NULL,
                md5sum VARCHAR(35),
                description VARCHAR(255),
                comments VARCHAR(255),
                tag VARCHAR(255),
                liquibase VARCHAR(20),
                contexts VARCHAR(255),
                labels VARCHAR(255),
                deployment_id VARCHAR(10),
                PRIMARY KEY (id, author, filename)
            )
        """)
        return table_name

    def insert_liquibase_migration(self, changelog_id: str, author: str,
                                  filename: str, description: str = None) -> dict:
        """Insert Liquibase migration record"""
        self.execute("""
            INSERT INTO public.databasechangelog
            (id, author, filename, dateexecuted, orderexecuted, exectype, description)
            VALUES (%s, %s, %s, NOW(), 1, 'EXECUTED', %s)
        """, (changelog_id, author, filename, description or "Migration"))

        return {
            "changelog_id": changelog_id,
            "author": author,
            "filename": filename,
            "description": description
        }

    def create_migration_history_record(self, migration_name: str,
                                       status: str = "completed") -> dict:
        """Create a migration history record in pggit"""
        # Insert into pggit.migrations if table exists
        try:
            result = self.execute("""
                INSERT INTO pggit.migrations (version, description, up_script, down_script, checksum)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
            """, (migration_name, f"Migration {migration_name}", "SELECT 1", "SELECT 1", "abc123"))

            row = result.fetchone()
            migration_id = row[0] if row else None

            return {
                "migration_name": migration_name,
                "migration_id": migration_id,
                "status": status,
                "tracked": migration_id is not None
            }
        except Exception:
            # Table might not exist or have different schema
            return {
                "migration_name": migration_name,
                "migration_id": None,
                "status": status,
                "tracked": False
            }

    def detect_schema_changes(self, schema: str = "public") -> dict:
        """Detect schema changes"""
        try:
            result = self.execute("""
                SELECT object_type, object_name, change_type, change_severity
                FROM pggit.detect_schema_changes(%s)
            """, (schema,))

            changes = []
            for row in result.fetchall():
                changes.append({
                    "object_type": row[0],
                    "object_name": row[1],
                    "change_type": row[2],
                    "change_severity": row[3]
                })

            return {
                "schema": schema,
                "changes": changes,
                "change_count": len(changes)
            }
        except Exception:
            return {
                "schema": schema,
                "changes": [],
                "change_count": 0
            }

    def generate_migration(self, version: str = None,
                          description: str = None) -> dict:
        """Generate a migration"""
        try:
            result = self.execute("""
                SELECT pggit.generate_migration(%s, %s)
            """, (version, description))

            migration_sql = result.fetchone()[0] if result.fetchone() else None

            return {
                "version": version or "auto",
                "description": description or "Auto-generated",
                "migration_sql": migration_sql,
                "generated": migration_sql is not None
            }
        except Exception as e:
            return {
                "version": version or "auto",
                "description": description or "Auto-generated",
                "migration_sql": None,
                "generated": False,
                "error": str(e)
            }


class ConflictTestBuilder(BaseTestBuilder):
    """Builder for conflict resolution tests"""

    def create_conflict_scenario(self) -> dict:
        """Create conflict test scenario"""
        # Create two branches with different changes
        schema1 = self.create_schema("branch_1")
        schema2 = self.create_schema("branch_2")

        table1 = self.create_table(schema1, "users", {
            "id": "SERIAL PRIMARY KEY",
            "username": "TEXT",
            "email": "TEXT",
            "role": "TEXT DEFAULT 'user'"
        })

        table2 = self.create_table(schema2, "users", {
            "id": "SERIAL PRIMARY KEY",
            "username": "TEXT",
            "email": "TEXT",
            "verified": "BOOLEAN DEFAULT false"
        })

        return {
            "branch_1": schema1,
            "branch_2": schema2,
            "table_1": table1,
            "table_2": table2
        }

    def register_test_conflict(self, conflict_type: str = "merge",
                              object_type: str = "table",
                              object_id: str = "test_table") -> str:
        """Register a test conflict"""
        result = self.execute("""
            SELECT pggit.register_conflict(%s, %s, %s, %s)
        """, (conflict_type, object_type, object_id, '{"test": "data"}'))

        return result.fetchone()[0]


class AITestBuilder(BaseTestBuilder):
    """Builder for advanced AI feature tests"""

    def create_ai_scenario(self) -> dict:
        """Create AI testing scenario"""
        # Create tables for AI predictions
        self.execute("""
            CREATE TABLE IF NOT EXISTS test_predictions (
                id SERIAL PRIMARY KEY,
                model_name TEXT NOT NULL,
                prediction NUMERIC,
                confidence NUMERIC,
                ground_truth NUMERIC,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)

        return {
            "predictions_table": "test_predictions"
        }

    def record_prediction(self, model_name: str, prediction: float,
                         confidence: float) -> int:
        """Record a test prediction"""
        result = self.execute("""
            INSERT INTO test_predictions (model_name, prediction, confidence)
            VALUES (%s, %s, %s)
            RETURNING id
        """, (model_name, prediction, confidence))

        return result.fetchone()[0]

    def record_ground_truth(self, prediction_id: int, actual: float):
        """Record ground truth for a prediction"""
        self.execute("""
            UPDATE test_predictions
            SET ground_truth = %s
            WHERE id = %s
        """, (actual, prediction_id))


class ZeroDowntimeTestBuilder(BaseTestBuilder):
    """Builder for zero-downtime deployment tests"""

    def create_production_table(self, table_name: str = "orders",
                               row_count: int = 1000) -> dict:
        """Create production-like table with sample data"""
        schema = "public"
        table = self.create_table(schema, table_name, {
            "id": "SERIAL PRIMARY KEY",
            "customer_id": "INT NOT NULL",
            "amount": "DECIMAL(10, 2) NOT NULL",
            "status": "TEXT DEFAULT 'pending'",
            "created_at": "TIMESTAMP DEFAULT NOW()"
        })

        # Insert sample data
        for i in range(row_count):
            self.execute("""
                INSERT INTO {table} (customer_id, amount, status)
                VALUES (%s, %s, %s)
            """.format(table=table), (i % 100, 99.99 + i, "pending"))

        return {
            "table": table,
            "schema": schema,
            "row_count": row_count
        }

    def verify_table_integrity(self, table: str) -> dict:
        """Verify table has valid structure and data"""
        # Check row count
        count = self.fetch_value(f"SELECT COUNT(*) FROM {table}")

        # Check for NULL violations
        null_count = self.fetch_value(f"""
            SELECT COUNT(*) FROM {table}
            WHERE customer_id IS NULL OR amount IS NULL
        """)

        return {
            "row_count": count,
            "null_violations": null_count,
            "is_valid": null_count == 0
        }
