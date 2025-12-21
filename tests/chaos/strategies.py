"""
Custom Hypothesis strategies for generating pggit domain objects.

These strategies generate valid inputs for property-based testing of pggit functionality,
including PostgreSQL identifiers, table definitions, Git-like branch names, and data.
"""

import string
from typing import Any

from hypothesis import strategies as st

# Valid PostgreSQL identifier characters
PG_IDENTIFIER_START = string.ascii_lowercase + "_"
PG_IDENTIFIER_CHARS = string.ascii_lowercase + string.digits + "_"

# PostgreSQL identifier strategy
pg_identifier = (
    st.builds(
        lambda start, rest: start + rest,
        st.sampled_from(PG_IDENTIFIER_START),
        st.text(alphabet=PG_IDENTIFIER_CHARS, min_size=0, max_size=62),
    )
    .filter(lambda x: 1 <= len(x) <= 63)
    .filter(
        lambda ident: ident
        not in {
            # Basic SQL keywords
            "select",
            "from",
            "where",
            "table",
            "create",
            "drop",
            "alter",
            "user",
            "group",
            "order",
            "index",
            "primary",
            "key",
            "constraint",
            "unique",
            "not",
            "null",
            "default",
            "serial",
            "bigint",
            "text",
            "varchar",
            "integer",
            "boolean",
            "timestamp",
            "date",
            "time",
            # Common PostgreSQL reserved keywords
            "to",
            "into",
            "as",
            "on",
            "by",
            "with",
            "having",
            "limit",
            "offset",
            "union",
            "all",
            "distinct",
            "case",
            "when",
            "then",
            "else",
            "end",
            "and",
            "or",
            "in",
            "exists",
            "between",
            "like",
            "is",
            "ilike",
            "any",
            "some",
            "true",
            "false",
            # Additional problematic identifiers
            "column",
            "schema",
            "database",
            "function",
            "procedure",
            "trigger",
            "view",
            "sequence",
            "type",
            "domain",
            "rule",
            "language",
            "cast",
            "operator",
            "aggregate",
            "collation",
            "conversion",
            "extension",
            "foreign",
            "server",
            "wrapper",
            "event",
            "publication",
            "subscription",
        },
    )
)

# Table name strategy
table_name = pg_identifier

# Column definition strategy
# Compatible type/constraint combinations
type_constraints = {
    "INTEGER": ["", "NOT NULL", "DEFAULT 0", "UNIQUE"],
    "BIGINT": ["", "NOT NULL", "DEFAULT 0", "UNIQUE"],
    "TEXT": ["", "NOT NULL", "DEFAULT ''", "UNIQUE"],
    "VARCHAR(255)": ["", "NOT NULL", "DEFAULT ''", "UNIQUE"],
    "BOOLEAN": ["", "NOT NULL", "DEFAULT true", "DEFAULT false", "UNIQUE"],
    "TIMESTAMP": ["", "NOT NULL", "DEFAULT CURRENT_TIMESTAMP", "UNIQUE"],
    "DATE": ["", "NOT NULL", "DEFAULT CURRENT_DATE", "UNIQUE"],
    "NUMERIC(10,2)": ["", "NOT NULL", "DEFAULT 0.00", "UNIQUE"],
    "SERIAL": ["", "PRIMARY KEY"],  # SERIAL usually gets PRIMARY KEY separately
}

column_definition = st.builds(
    lambda name, col_type, constraint: f"{name} {col_type} {constraint}".strip(),
    pg_identifier.filter(
        lambda x: len(x) <= 63
        and x
        not in {
            # Additional SQL reserved keywords that can cause issues in column names
            "do",
            "if",
            "then",
            "else",
            "case",
            "when",
            "end",
            "begin",
            "commit",
            "rollback",
            "savepoint",
            "lock",
            "unlock",
            "select",
            "insert",
            "update",
            "delete",
            "create",
            "drop",
            "alter",
            "table",
            "column",
            "index",
            "view",
            "function",
            "procedure",
            "trigger",
            "constraint",
            "primary",
            "foreign",
            "unique",
            "check",
            "default",
            "null",
            "not",
            "and",
            "or",
            "in",
            "exists",
            "between",
            "like",
            "ilike",
            "any",
            "all",
            "some",
            "union",
            "intersect",
            "except",
            "limit",
            "offset",
            "order",
            "group",
            "having",
            "where",
            "join",
            "inner",
            "outer",
            "left",
            "right",
            "full",
            "on",
            "using",
            "natural",
            "cross",
            "with",
            "recursive",
            "distinct",
            "as",
            "from",
            "into",
            "values",
        },
    ),
    st.sampled_from(
        [
            "INTEGER",
            "BIGINT",
            "TEXT",
            "VARCHAR(255)",
            "BOOLEAN",
            "TIMESTAMP",
            "DATE",
            "NUMERIC(10,2)",
            "SERIAL",
        ],
    ),
    st.sampled_from(
        ["", "NOT NULL", "UNIQUE"],  # Remove problematic defaults for now
    ),
)


def _validate_table_definition(tbl) -> bool:
    """Validate that a table definition generates valid PostgreSQL DDL."""
    try:
        # PostgreSQL reserved keywords that can't be used as identifiers
        reserved_keywords = {
            "user",
            "table",
            "column",
            "index",
            "constraint",
            "select",
            "insert",
            "update",
            "delete",
            "create",
            "drop",
            "alter",
            "as",
            "from",
            "where",
            "join",
            "group",
            "order",
            "by",
            "having",
            "limit",
            "offset",
            "union",
            "all",
            "distinct",
            "null",
            "not",
            "and",
            "or",
            "in",
            "exists",
            "case",
            "when",
            "then",
            "else",
            "end",
            "begin",
            "commit",
            "rollback",
        }

        # Check for duplicate column names and reserved keywords
        column_names = []
        for col in tbl["columns"]:
            col_name = col.split()[0].lower()
            if col_name in column_names or col_name in reserved_keywords:
                return False
            column_names.append(col_name)

        # Check for reserved table names
        if tbl["name"].lower() in reserved_keywords:
            return False

        # Basic SQL syntax check - ensure no obviously invalid combinations
        sql = tbl["create_sql"].upper()
        if "BOOLEAN DEFAULT CURRENT_TIMESTAMP" in sql:
            return False
        if "TEXT DEFAULT 0" in sql or ("VARCHAR" in sql and "DEFAULT 0" in sql):
            return False

        return True
    except:
        return False


# Table definition strategy
@st.composite
def table_definition(draw) -> dict[str, Any]:
    """Generate complete table definition."""
    # Generate more unique table names to avoid collisions
    base_name = draw(table_name)
    # Add random suffix to make names more unique
    unique_suffix = draw(st.integers(min_value=1000, max_value=999999))
    tbl_name = f"{base_name}_{unique_suffix}"

    # Generate 1-10 columns
    num_cols = draw(st.integers(min_value=1, max_value=10))
    columns = []
    column_names = set()

    for _ in range(num_cols):
        col_def = draw(column_definition)
        # Extract column name from definition
        col_name = col_def.split()[0]
        # Ensure unique column names
        if col_name in column_names:
            continue
        column_names.add(col_name)
        columns.append(col_def)

    # Add primary key sometimes
    if draw(st.booleans()) and len(columns) > 0:
        pk_name = draw(
            pg_identifier.filter(lambda x: len(x) <= 20 and x not in column_names),
        )
        columns.insert(0, f"{pk_name} SERIAL PRIMARY KEY")

    create_sql = f"CREATE TABLE {tbl_name} ({', '.join(columns)})"

    # Validate the table definition
    tbl_def = {
        "name": tbl_name,
        "columns": columns,
        "create_sql": create_sql,
    }

    if not _validate_table_definition(tbl_def):
        # If invalid, try again (Hypothesis will handle retries)
        return draw(table_definition)

    return tbl_def


# Git branch name strategy (for general git operations)
git_branch_name = st.builds(
    lambda parts, add_prefix: "/".join(parts)
    if not add_prefix
    else f"feature/{'/'.join(parts)}",
    st.lists(
        st.text(
            alphabet=string.ascii_lowercase + string.digits + "-_",
            min_size=1,
            max_size=20,
        ).filter(lambda x: not x.startswith(("-", "."))),
        min_size=1,
        max_size=3,
    ),
    st.booleans(),
)

# PostgreSQL identifier branch name strategy (for data branching)
# Must start with letter/underscore, contain only alphanumeric/underscore
pg_branch_name = st.builds(
    lambda start, rest: start + rest,
    st.sampled_from(string.ascii_lowercase + "_"),
    st.text(
        alphabet=string.ascii_lowercase + string.digits + "_",
        min_size=0,
        max_size=20,
    ),
).filter(lambda x: 1 <= len(x) <= 63)

# Commit message strategy
commit_message = st.builds(
    lambda subject, body: f"{subject}\n\n{body}" if body else subject,
    st.text(
        alphabet=string.ascii_letters + string.digits + " _-.",
        min_size=10,
        max_size=72,
    ),
    st.one_of(st.none(), st.text(min_size=10, max_size=200)),
).filter(lambda x: x is not None and "\x00" not in x)

# Version triple strategy
version_triple = st.tuples(
    st.integers(min_value=0, max_value=1000),
    st.integers(min_value=0, max_value=1000),
    st.integers(min_value=0, max_value=1000),
)

# Version increment type strategy
version_increment_type = st.sampled_from(["major", "minor", "patch"])


# Data row strategy (simplified)
@st.composite
def data_row(draw, columns=None) -> dict[str, Any]:
    """Generate data row. If columns provided, match their types."""
    if columns is None:
        # Simple case: just generate some basic data
        return {
            "id": draw(st.integers(min_value=1, max_value=1000)),
            "name": draw(st.text(max_size=100)),
            "active": draw(st.booleans()),
        }

    # Complex case: match column definitions
    row = {}
    for col_def in columns:
        col_parts = col_def.split()
        if len(col_parts) < 2:
            continue

        col_name = col_parts[0]
        col_type = col_parts[1].upper()

        if "INTEGER" in col_type or "BIGINT" in col_type or "SERIAL" in col_type:
            row[col_name] = draw(st.integers(min_value=1, max_value=1000))
        elif "TEXT" in col_type or "VARCHAR" in col_type:
            row[col_name] = draw(st.text(max_size=100))
        elif "BOOLEAN" in col_type:
            row[col_name] = draw(st.booleans())
        else:
            row[col_name] = draw(st.text(max_size=50))

    return row


# Trinity ID components strategy
trinity_id_components = st.builds(
    lambda table, branch, commit: {
        "table_name": table,
        "branch_name": branch,
        "commit_hash": commit,
    },
    table_name,
    git_branch_name,
    st.text(alphabet=string.ascii_lowercase + string.digits, min_size=7, max_size=40),
)
