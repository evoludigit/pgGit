"""
Custom Hypothesis strategies for generating pggit domain objects.

These strategies generate valid inputs for property-based testing of pggit functionality,
including PostgreSQL identifiers, table definitions, Git-like branch names, and data.
"""

from hypothesis import strategies as st
import string

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
        }
    )
)

# Table name strategy
table_name = pg_identifier

# Column definition strategy
column_definition = st.builds(
    lambda name, col_type, constraint: f"{name} {col_type} {constraint}".strip(),
    pg_identifier.filter(lambda x: len(x) <= 63),
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
        ]
    ),
    st.sampled_from(
        ["", "NOT NULL", "DEFAULT 0", "DEFAULT CURRENT_TIMESTAMP", "UNIQUE"]
    ),
)


# Table definition strategy
@st.composite
def table_definition(draw):
    """Generate complete table definition."""
    tbl_name = draw(table_name)

    # Generate 1-10 columns
    num_cols = draw(st.integers(min_value=1, max_value=10))
    columns = []
    for _ in range(num_cols):
        col_def = draw(column_definition)
        columns.append(col_def)

    # Add primary key sometimes
    if draw(st.booleans()):
        pk_name = draw(pg_identifier.filter(lambda x: len(x) <= 20))
        columns.insert(0, f"{pk_name} SERIAL PRIMARY KEY")

    return {
        "name": tbl_name,
        "columns": columns,
        "create_sql": f"CREATE TABLE {tbl_name} ({', '.join(columns)})",
    }


# Git branch name strategy
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

# Commit message strategy
commit_message = st.builds(
    lambda subject, body: f"{subject}\n\n{body}" if body else subject,
    st.text(
        alphabet=string.ascii_letters + string.digits + " _-.", min_size=10, max_size=72
    ),
    st.one_of(st.none(), st.text(min_size=10, max_size=200)),
).filter(lambda x: x is not None)

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
def data_row(draw, columns=None):
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
