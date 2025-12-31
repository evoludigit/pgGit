# Mutmut configuration for pgGit
# https://mutmut.readthedocs.io/

def pre_mutation(context):
    """Called before each mutation."""
    # Skip test files themselves (we're testing the test quality, not mutating tests)
    if 'conftest' in context.filename:
        context.skip = True

    # Skip fixtures and utilities
    if 'fixtures' in context.filename or 'utils' in context.filename:
        context.skip = True

    # Skip examples
    if 'examples' in context.filename:
        context.skip = True


def post_mutation(context):
    """Called after each mutation test."""
    pass  # Can add custom logging here
