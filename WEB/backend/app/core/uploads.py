"""Safe handling of uploaded files: size, extension and content checks.

The client-declared `Content-Type` and file name are never trusted on their
own: the extension must be on an allow-list *and* the first bytes must match
the format (magic numbers), and the body is read in chunks so an oversized
upload is rejected without being fully buffered.
"""

from pathlib import PurePosixPath, PureWindowsPath

from fastapi import UploadFile

from app.core.exceptions import PayloadTooLargeError, UnsupportedMediaTypeError

CHUNK_SIZE = 64 * 1024

#: extension -> (canonical media type, accepted leading bytes; empty = text check)
SIGNATURES: dict[str, tuple[str, tuple[bytes, ...]]] = {
    ".pdf": ("application/pdf", (b"%PDF-",)),
    ".png": ("image/png", (b"\x89PNG\r\n\x1a\n",)),
    ".jpg": ("image/jpeg", (b"\xff\xd8\xff",)),
    ".jpeg": ("image/jpeg", (b"\xff\xd8\xff",)),
    ".xlsx": (
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        (b"PK\x03\x04",),
    ),
    ".csv": ("text/csv", ()),
    ".txt": ("text/plain", ()),
}


def safe_filename(name: str | None) -> str:
    """Basename only (no directories), no control characters, bounded length."""
    base = PurePosixPath(PureWindowsPath(name or "").as_posix()).name
    cleaned = "".join(ch for ch in base if ch.isprintable() and ch not in '<>:"|?*\\/')
    cleaned = cleaned.strip(" .")
    return cleaned[:200] or "file"


def extension_of(filename: str) -> str:
    return PurePosixPath(filename.lower()).suffix


async def read_limited(upload: UploadFile, *, max_bytes: int) -> bytes:
    """Read the whole upload, failing as soon as it exceeds `max_bytes`."""
    chunks: list[bytes] = []
    total = 0
    while chunk := await upload.read(CHUNK_SIZE):
        total += len(chunk)
        if total > max_bytes:
            raise PayloadTooLargeError(
                f"file exceeds the {max_bytes // (1024 * 1024)} MB limit"
            )
        chunks.append(chunk)
    return b"".join(chunks)


def validate_content(filename: str, content: bytes, allowed: frozenset[str]) -> str:
    """Check extension allow-list and magic bytes; return the canonical media type."""
    extension = extension_of(filename)
    if extension not in allowed or extension not in SIGNATURES:
        accepted = ", ".join(sorted(allowed))
        raise UnsupportedMediaTypeError(f"file type not allowed (accepted: {accepted})")
    media_type, signatures = SIGNATURES[extension]
    if not content:
        raise UnsupportedMediaTypeError("the file is empty")
    if signatures:
        if not content.startswith(signatures):
            raise UnsupportedMediaTypeError(
                f"file content does not match the '{extension}' format"
            )
    elif b"\x00" in content[:8192]:
        raise UnsupportedMediaTypeError(
            f"file content does not match the '{extension}' format"
        )
    return media_type
