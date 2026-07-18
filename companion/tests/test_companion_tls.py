# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "companion" / "scripts"))

from companion_tls import cert_fingerprint, ensure_cert, verify_pair  # noqa: E402


class CompanionTLSTests(unittest.TestCase):
    def test_fingerprint_is_der_sha256(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)
            cert, _, _ = ensure_cert(state)
            fp_py = cert_fingerprint(cert)
            der = subprocess.run(
                ["openssl", "x509", "-in", str(cert), "-outform", "DER"],
                check=True,
                capture_output=True,
            ).stdout
            fp_openssl = hashlib.sha256(der).hexdigest()
            self.assertEqual(fp_py, fp_openssl)
            self.assertEqual(len(fp_py), 64)

    def test_pair_pin_accept_reject(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)
            from companion_tls import fresh_pin

            pin = fresh_pin(state)
            ok, token, err = verify_pair({"pin": pin}, pin, state)
            self.assertTrue(ok)
            self.assertIsNotNone(token)
            self.assertIsNone(err)

            ok2, _, err2 = verify_pair({"pin": "000000"}, pin, state)
            self.assertFalse(ok2)
            self.assertIsNotNone(err2)


if __name__ == "__main__":
    unittest.main()
