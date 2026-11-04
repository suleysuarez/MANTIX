"""Safety brake: the tests must never reach a database that is not a local, disposable one.

`conftest.py` calls `apply_test_database_guard` before anything from `app` is imported.
Why it matters: `Settings` also reads `backend/.env`, so without the brake the app's own
engine (`app.db.session`) could point at the real database, and the repository fixtures
run `drop_all`.

Rules for `TEST_DATABASE_URL` and `MIGRATED_DATABASE_URL` (when set):

* the host is `localhost` or `127.0.0.1`;
* the database name ends in `_test`.

Messages show only the variable, host and database name, never the credentials.
"""

from collections.abc import MutableMapping
from urllib.parse import parse_qs, urlparse

ALLOWED_HOSTS = frozenset({"localhost", "127.0.0.1"})
REQUIRED_SUFFIX = "_test"
GUARDED_VARIABLES = ("TEST_DATABASE_URL", "MIGRATED_DATABASE_URL")
# Nothing listens here, so a test that reaches the app's engine without a configured
# database fails with "connection refused" instead of touching anything.
UNREACHABLE_URL = "postgresql://nobody@127.0.0.1:1/unset_test"


class UnsafeTestDatabaseError(RuntimeError):
    """A test database URL points somewhere the tests must not write to."""


def assert_safe_test_database(variable: str, url: str) -> None:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    name = parsed.path.lstrip("/")
    problems = []
    if host not in ALLOWED_HOSTS:
        problems.append(
            f"the host is '{host or '(empty)'}', not localhost or 127.0.0.1"
        )
    if "host" in parse_qs(parsed.query) or "hostaddr" in parse_qs(parsed.query):
        problems.append("the query string overrides the host")
    if not name.endswith(REQUIRED_SUFFIX):
        problems.append(
            f"the database '{name or '(empty)'}' does not end in '{REQUIRED_SUFFIX}'"
        )
    if problems:
        raise UnsafeTestDatabaseError(
            f"{variable} is not a safe test database: "
            + "; ".join(problems)
            + ". Tests only run against a local database whose name ends in "
            f"'{REQUIRED_SUFFIX}'. See backend/README.md."
        )


def apply_test_database_guard(environ: MutableMapping[str, str]) -> None:
    """Validate the test URLs and make `DATABASE_URL` safe, whatever `.env` says."""
    for variable in GUARDED_VARIABLES:
        url = environ.get(variable, "")
        if url:
            assert_safe_test_database(variable, url)
    # `DATABASE_URL` (real database in `.env`) never survives into the tests: the app's
    # engine uses the migrated test database, or an unreachable address when there is none.
    environ["DATABASE_URL"] = (
        environ.get("MIGRATED_DATABASE_URL", "") or UNREACHABLE_URL
    )
