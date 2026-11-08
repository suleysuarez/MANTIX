from pydantic import BaseModel, EmailStr, Field, field_validator


class MobileRegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)

    @field_validator("password")
    @classmethod
    def strong_password(cls, value: str) -> str:
        if (
            not any(c.islower() for c in value)
            or not any(c.isupper() for c in value)
            or not any(c.isdigit() for c in value)
        ):
            raise ValueError(
                "La contraseña debe incluir mayúsculas, minúsculas y números."
            )
        return value


class MobileLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class MobileVerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str = Field(pattern=r"^\d{6}$")
    # The password is set here, by whoever holds the code (the mailbox owner), so a
    # password chosen by someone who only pre-registered the address never takes effect.
    password: str = Field(min_length=10, max_length=128)

    @field_validator("password")
    @classmethod
    def strong_password(cls, value: str) -> str:
        if (
            not any(c.islower() for c in value)
            or not any(c.isupper() for c in value)
            or not any(c.isdigit() for c in value)
        ):
            raise ValueError(
                "La contraseña debe incluir mayúsculas, minúsculas y números."
            )
        return value


class MobileResendCodeRequest(BaseModel):
    email: EmailStr


class MobileForgotPasswordRequest(BaseModel):
    email: EmailStr


class MobileResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str = Field(pattern=r"^\d{6}$")
    new_password: str = Field(min_length=10, max_length=128)

    @field_validator("new_password")
    @classmethod
    def strong_password(cls, value: str) -> str:
        if (
            not any(c.islower() for c in value)
            or not any(c.isupper() for c in value)
            or not any(c.isdigit() for c in value)
        ):
            raise ValueError(
                "La contraseña debe incluir mayúsculas, minúsculas y números."
            )
        return value


class MobileAuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict
