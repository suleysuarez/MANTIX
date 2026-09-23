from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.core.config import Settings
from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    hash_token,
    verify_password,
)


def test_password_hash_is_verifiable_and_not_plaintext() -> None:
    password = "correct horse battery staple"
    hashed = hash_password(password)
    assert hashed != password
    assert verify_password(password, hashed)
    assert not verify_password("wrong password", hashed)


def test_access_token_round_trip_and_invalid_token_rejected() -> None:
    settings = Settings(jwt_secret_key="test-secret")
    token = create_access_token("42", settings)
    assert decode_access_token(token, settings)["sub"] == "42"
    with pytest.raises(HTTPException) as error:
        decode_access_token(token + "x", settings)
    assert error.value.status_code == 401


def test_expired_access_token_is_rejected() -> None:
    settings = Settings(jwt_secret_key="test-secret")
    from jose import jwt

    expired = jwt.encode(
        {
            "sub": "42",
            "type": "access",
            "exp": datetime.now(UTC) - timedelta(minutes=1),
        },
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )
    with pytest.raises(HTTPException) as error:
        decode_access_token(expired, settings)
    assert error.value.status_code == 401


def test_refresh_hash_is_one_way_and_deterministic() -> None:
    token = "opaque-refresh-token"
    assert hash_token(token) == hash_token(token)
    assert hash_token(token) != token
