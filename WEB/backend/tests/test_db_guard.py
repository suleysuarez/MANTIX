"""The safety brake for test databases. Pure string checks: no database is contacted."""

import pytest

from tests.db_guard import (
    UNREACHABLE_URL,
    UnsafeTestDatabaseError,
    apply_test_database_guard,
    assert_safe_test_database,
)

# Made-up URLs: no real host, user or password.
SAFE_URLS = [
    "postgresql://u:p@localhost:5433/mantix_test",
    "postgresql://u:p@127.0.0.1:5432/mantix_ci_test",
    "postgresql+asyncpg://u@LOCALHOST/mantix_migrated_test",
]
UNSAFE_URLS = [
    "postgresql://u:p@db.example.com/mantix_test",  # remote host
    "postgresql://u:p@ep-fake-123.neon.example/mantix_test",  # cloud host
    "postgresql://u:p@localhost.example.com/mantix_test",  # host that only starts with localhost
    "postgresql://u:p@localhost:5432/mantix",  # not a *_test database
    "postgresql://u:p@localhost:5432/mantix_test_backup",  # suffix must be at the end
    "postgresql://u:p@localhost:5432/",  # no database name
    "postgresql://u:p@/mantix_test",  # no host
    "postgresql://u:p@db.example.com:5432/mantix_test?host=localhost",  # host in the query
    "postgresql://u:p@localhost/mantix_test?host=db.example.com",
]


@pytest.mark.parametrize("url", SAFE_URLS)
def test_safe_urls_pass(url: str) -> None:
    assert_safe_test_database("TEST_DATABASE_URL", url)


@pytest.mark.parametrize("url", UNSAFE_URLS)
def test_unsafe_urls_are_rejected(url: str) -> None:
    with pytest.raises(UnsafeTestDatabaseError):
        assert_safe_test_database("TEST_DATABASE_URL", url)


def test_error_message_never_contains_the_credentials() -> None:
    with pytest.raises(UnsafeTestDatabaseError) as error:
        assert_safe_test_database(
            "TEST_DATABASE_URL", "postgresql://someuser:s3cret-pass@db.example.com/prod"
        )
    message = str(error.value)
    assert "s3cret-pass" not in message
    assert "someuser" not in message
    assert "db.example.com" in message
    assert "TEST_DATABASE_URL" in message


@pytest.mark.parametrize("variable", ["TEST_DATABASE_URL", "MIGRATED_DATABASE_URL"])
def test_guard_checks_both_variables(variable: str) -> None:
    environ = {variable: "postgresql://u:p@db.example.com/mantix"}
    with pytest.raises(UnsafeTestDatabaseError, match=variable):
        apply_test_database_guard(environ)


def test_a_real_database_url_from_env_never_survives() -> None:
    environ = {"DATABASE_URL": "postgresql://u:p@db.example.com/real"}
    apply_test_database_guard(environ)
    assert environ["DATABASE_URL"] == UNREACHABLE_URL


def test_database_url_follows_the_migrated_test_database() -> None:
    migrated = "postgresql://u:p@localhost:5433/mantix_migrated_test"
    environ = {
        "DATABASE_URL": "postgresql://u:p@db.example.com/real",
        "MIGRATED_DATABASE_URL": migrated,
        "TEST_DATABASE_URL": "postgresql://u:p@localhost:5433/mantix_test",
    }
    apply_test_database_guard(environ)
    assert environ["DATABASE_URL"] == migrated


def test_nothing_set_is_allowed_and_leaves_an_unreachable_database() -> None:
    environ: dict[str, str] = {}
    apply_test_database_guard(environ)
    assert environ == {"DATABASE_URL": UNREACHABLE_URL}
