import importlib.util
from datetime import datetime, timedelta, timezone
import hashlib
from pathlib import Path
import tempfile
import unittest
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.x509.oid import NameOID

spec = importlib.util.spec_from_file_location("integrity", Path(__file__).parents[1] / "release-integrity.py")
integrity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(integrity)


class ReleaseIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.key = Ed25519PrivateKey.generate()
        now = datetime.now(timezone.utc)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Test only")])
        self.cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                     .public_key(self.key.public_key()).serial_number(1)
                     .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=1))
                     .sign(self.key, None))
        self.certificate = self.folder / "certificate.pem"
        self.certificate.write_bytes(self.cert.public_bytes(serialization.Encoding.PEM))
        self.fingerprint = self.cert.fingerprint(hashes.SHA256()).hex()
        self.ipa = self.folder / "Pawster-0.2.0.ipa"
        self.ipa.write_bytes(b"Synthetic release package, no device operations")
        signature = self.folder / (self.ipa.name + ".sig")
        signature.write_bytes(self.key.sign(self.ipa.read_bytes()))
        entries = [self.certificate, self.ipa, signature]
        manifest = "".join(f"{integrity.file_hash(p)}  {p.name}\n" for p in entries).encode()
        (self.folder / "SHA256SUMS").write_bytes(manifest)
        (self.folder / "SHA256SUMS.sig").write_bytes(self.key.sign(manifest))

    def verify(self):
        integrity.verify_release(self.folder, self.certificate, self.fingerprint)

    def test_authentic_release(self):
        self.verify()

    def test_modified_ipa(self):
        self.ipa.write_bytes(self.ipa.read_bytes() + b"modified")
        with self.assertRaisesRegex(ValueError, "modified"):
            self.verify()

    def test_modified_manifest(self):
        path = self.folder / "SHA256SUMS"
        path.write_bytes(path.read_bytes().replace(b"Pawster", b"pawster"))
        with self.assertRaises(InvalidSignature):
            self.verify()

    def test_replaced_signature(self):
        (self.folder / "SHA256SUMS.sig").write_bytes(b"\0" * 64)
        with self.assertRaises(InvalidSignature):
            self.verify()

    def test_wrong_trust_anchor(self):
        with self.assertRaisesRegex(ValueError, "Untrusted"):
            integrity.verify_release(self.folder, self.certificate, "0" * 64)

    def test_missing_asset(self):
        self.ipa.unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            self.verify()

    def test_unsafe_duplicate_or_circular_names(self):
        digest = "0" * 64
        for name in ["../escape", "/absolute", "a/b", "a\\b", "a:b", "..", "SHA256SUMS", "SHA256SUMS.sig"]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                integrity.read_manifest(f"{digest}  {name}\n".encode())
        with self.assertRaises(ValueError):
            integrity.read_manifest(f"{digest}  a\n{digest}  a\n".encode())

    def test_valid_manifest_cannot_bypass_ipa_signature(self):
        signature = self.folder / (self.ipa.name + ".sig")
        signature.write_bytes(b"\0" * 64)
        manifest = "".join(f"{integrity.file_hash(p)}  {p.name}\n" for p in [self.ipa, signature]).encode()
        (self.folder / "SHA256SUMS").write_bytes(manifest)
        (self.folder / "SHA256SUMS.sig").write_bytes(self.key.sign(manifest))
        with self.assertRaises(InvalidSignature):
            self.verify()


if __name__ == "__main__":
    unittest.main()
