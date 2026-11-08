from app.services.code_email_limiter import HOUR_SECONDS, CodeEmailLimiter


def test_first_send_is_allowed_and_a_second_one_must_wait_the_minimum_interval():
    limiter = CodeEmailLimiter()
    assert limiter.allow("ana@example.com", now=0)
    assert not limiter.allow("ana@example.com", now=30)
    assert limiter.allow("ana@example.com", now=61)


def test_other_accounts_are_not_held_back_by_the_wait():
    limiter = CodeEmailLimiter()
    assert limiter.allow("ana@example.com", now=0)
    assert limiter.allow("luis@example.com", now=1)


def test_the_account_is_capped_per_hour_and_recovers_after_it():
    limiter = CodeEmailLimiter()
    assert all(limiter.allow("ana@example.com", now=i * 61) for i in range(5))
    assert not limiter.allow("ana@example.com", now=5 * 61)
    assert limiter.allow("ana@example.com", now=HOUR_SECONDS + 1)


def test_the_account_key_ignores_case_and_spaces():
    limiter = CodeEmailLimiter()
    assert limiter.allow("Ana@Example.com ", now=0)
    assert not limiter.allow("ana@example.com", now=10)


def test_the_whole_system_is_capped_per_hour():
    limiter = CodeEmailLimiter(global_per_hour=3)
    assert all(limiter.allow(f"user{i}@example.com", now=i) for i in range(3))
    assert not limiter.allow("other@example.com", now=10)
    assert limiter.allow("other@example.com", now=HOUR_SECONDS + 10)


def test_a_blocked_attempt_is_not_recorded():
    limiter = CodeEmailLimiter(global_per_hour=1, per_account_per_hour=5)
    assert limiter.allow("ana@example.com", now=0)
    assert not limiter.allow("luis@example.com", now=1)
    assert limiter.allow("luis@example.com", now=HOUR_SECONDS + 1)
