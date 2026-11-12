"""Detached Ed25519 release signatures. Private keys use current-user Windows DPAPI.

Install Scripts/requirements-release.txt before use. Verification is cross-platform.
The certificate fingerprint must come from a separately trusted source.
"""
import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.x509.oid import NameOID


def dpapi(data, decrypt=False):
    if sys.platform != "win32":
        raise ValueError("Private-key operations require the original Windows user account.")

    class Blob(ctypes.Structure):
        _fields_ = [("length", wintypes.DWORD), ("data", ctypes.POINTER(ctypes.c_ubyte))]

    buffer = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
    source = Blob(len(data), buffer)
    output = Blob()
    crypt = ctypes.WinDLL("crypt32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    if decrypt:
        fn = crypt.CryptUnprotectData
        fn.argtypes = [ctypes.POINTER(Blob), ctypes.c_void_p, ctypes.c_void_p,
                       ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
        arguments = [ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)]
    else:
        fn = crypt.CryptProtectData
        fn.argtypes = [ctypes.POINTER(Blob), wintypes.LPCWSTR, ctypes.c_void_p,
                       ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
        arguments = [ctypes.byref(source), "Pawster release signing", None, None, None, 1, ctypes.byref(output)]
    fn.restype = wintypes.BOOL
    if not fn(*arguments):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(output.data, output.length)
    finally:
        ctypes.memset(output.data, 0, output.length)
        kernel.LocalFree(output.data)


def initialize(key_dir, public_dir):
    key_file = key_dir / "private-key.dpapi"
    if key_file.exists() or any(public_dir.glob("Pawster-release-*")):
        raise ValueError("Signing identity already exists; refusing to overwrite it.")
    key_dir.mkdir(parents=True, exist_ok=True)
    public_dir.mkdir(parents=True, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "GotTal Pawster Release Signing")])
    now = datetime.now(timezone.utc)
    certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=5))
                   .not_valid_after(now + timedelta(days=3650))
                   .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                   .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
                                               key_encipherment=False, data_encipherment=False,
                                               key_agreement=False, key_cert_sign=False, crl_sign=False,
                                               encipher_only=False, decipher_only=False), critical=True)
                   .sign(key, algorithm=None))
    secret = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                               serialization.NoEncryption())
    with key_file.open("xb") as destination:
        destination.write(dpapi(secret))
    (public_dir / "Pawster-release-signing-cert.pem").write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    (public_dir / "Pawster-release-public-key.pem").write_bytes(key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
    fingerprint = certificate.fingerprint(hashes.SHA256()).hex()
    (public_dir / "trusted-key.json").write_text(json.dumps({
        "algorithm": "Ed25519", "certificate_sha256": fingerprint,
        "subject": name.rfc4514_string(), "created_utc": now.isoformat(),
        "identity": "Self-issued release key; not an Apple or public CA identity certificate"
    }, indent=2) + "\n", encoding="utf-8")
    print("Certificate SHA-256: " + fingerprint)


def trusted_certificate(path, fingerprint):
    if not re.fullmatch(r"[0-9a-fA-F]{64}", fingerprint):
        raise ValueError("Expected a 64-digit certificate SHA-256 fingerprint.")
    cert = x509.load_pem_x509_certificate(path.read_bytes())
    if cert.fingerprint(hashes.SHA256()).hex() != fingerprint.lower():
        raise ValueError("Untrusted certificate fingerprint.")
    public_key = cert.public_key()
    if not isinstance(public_key, Ed25519PublicKey) or cert.subject != cert.issuer:
        raise ValueError("Expected the self-issued Ed25519 release certificate.")
    public_key.verify(cert.signature, cert.tbs_certificate_bytes)
    return cert


def read_manifest(data):
    entries = []
    seen = set()
    for line in data.decode("utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        if not match:
            raise ValueError("Malformed or unsafe checksum entry.")
        digest, name = match.groups()
        if name in seen or name in (".", "..", "SHA256SUMS", "SHA256SUMS.sig"):
            raise ValueError("Duplicate or circular checksum entry.")
        seen.add(name)
        entries.append((digest, name))
    if not entries:
        raise ValueError("Empty checksum manifest.")
    return entries


def file_hash(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def sign_release(folder, key_dir, certificate, fingerprint):
    cert = trusted_certificate(certificate, fingerprint)
    key = serialization.load_der_private_key(dpapi((key_dir / "private-key.dpapi").read_bytes(), decrypt=True), None)
    if not isinstance(key, Ed25519PrivateKey) or key.public_key() != cert.public_key():
        raise ValueError("Private key does not match the trusted certificate.")
    if (folder / "SHA256SUMS").exists() or (folder / "SHA256SUMS.sig").exists():
        raise ValueError("Already signed; use a fresh release staging directory.")
    packages = list(folder.glob("*.ipa"))
    if len(packages) != 1:
        raise ValueError("Exactly one IPA must be staged.")
    ipa = packages[0]
    ipa.with_name(ipa.name + ".sig").write_bytes(key.sign(ipa.read_bytes()))
    files = sorted(folder.iterdir(), key=lambda item: item.name)
    if any(not item.is_file() or item.is_symlink() for item in files):
        raise ValueError("Release assets must be regular files in one directory.")
    data = "".join(f"{file_hash(item)}  {item.name}\n" for item in files).encode("utf-8")
    read_manifest(data)
    (folder / "SHA256SUMS").write_bytes(data)
    (folder / "SHA256SUMS.sig").write_bytes(key.sign(data))
    verify_release(folder, certificate, fingerprint)


def verify_release(folder, certificate, fingerprint):
    cert = trusted_certificate(certificate, fingerprint)
    data = (folder / "SHA256SUMS").read_bytes()
    cert.public_key().verify((folder / "SHA256SUMS.sig").read_bytes(), data)
    entries = read_manifest(data)
    for digest, name in entries:
        item = folder / name
        if item.is_symlink() or not item.is_file() or file_hash(item) != digest:
            raise ValueError("Missing or modified release file: " + name)
    packages = [name for _, name in entries if name.endswith(".ipa")]
    if len(packages) != 1 or packages[0] + ".sig" not in {name for _, name in entries}:
        raise ValueError("Signed manifest must contain one IPA and its detached signature.")
    ipa = folder / packages[0]
    cert.public_key().verify(ipa.with_name(ipa.name + ".sig").read_bytes(), ipa.read_bytes())
    print(f"Verified Ed25519 signatures and SHA-256 for {len(entries)} release files.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["init", "sign", "verify"])
    parser.add_argument("--key-dir", type=Path)
    parser.add_argument("--public-dir", type=Path)
    parser.add_argument("--folder", type=Path)
    parser.add_argument("--certificate", type=Path)
    parser.add_argument("--fingerprint")
    args = parser.parse_args()
    if args.operation == "init":
        if not args.key_dir or not args.public_dir:
            parser.error("init requires --key-dir and --public-dir")
        initialize(args.key_dir, args.public_dir)
    else:
        if not args.folder or not args.certificate or not args.fingerprint:
            parser.error("sign/verify requires --folder, --certificate and --fingerprint")
        if args.operation == "sign":
            if not args.key_dir:
                parser.error("sign requires --key-dir")
            sign_release(args.folder, args.key_dir, args.certificate, args.fingerprint)
        else:
            verify_release(args.folder, args.certificate, args.fingerprint)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Release verification/signing failed: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
