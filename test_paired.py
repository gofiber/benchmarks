import contextlib
import csv
import io
import tempfile
import unittest
from pathlib import Path

import paired


class PairedTest(unittest.TestCase):
    def test_sign_ci_order_statistics(self):
        self.assertEqual(paired.sign_ci(range(10)), (1, 8, 1 - 22 / 1024))
        lo, hi, confidence = paired.sign_ci(range(20))
        self.assertEqual((lo, hi), (5, 14))
        self.assertAlmostEqual(confidence, 1 - 2 * 21700 / 2**20)
        self.assertIsNone(paired.sign_ci(range(5)))

    def test_pairs_cancel_drift(self):
        drift = [1.0, 1.6] * 5
        runs = {
            # v3 is 5% slower in every round, while the drift spreads each version by 60%
            "static": ([100 * d for d in drift], [105 * d for d in drift]),
            "parameter": ([100.0] * 10, [101.0, 99.0] * 5),
            "fasthttp_floor": ([100.0] * 10, [50.0, 200.0] * 5),
        }
        with tempfile.TemporaryDirectory() as tmp:
            for i, version in enumerate(("v2", "v3")):
                lines = [f"BenchmarkRequest/{name}  1000  {samples[i][n]:.3f} ns/op" for n in range(10) for name, samples in runs.items()]
                Path(tmp, f"{version}.txt").write_text("\n".join(lines) + "\n")
            with contextlib.redirect_stdout(io.StringIO()):
                paired.main(tmp)
            with open(Path(tmp, "paired.csv"), newline="") as f:
                rows = {r["name"]: r for r in csv.DictReader(f)}
            self.assertAlmostEqual(float(rows["static"]["delta"]), 5)
            self.assertEqual(rows["static"]["significant"], "True")
            self.assertEqual(rows["parameter"]["significant"], "False")
            # with fasthttp_floor the median half-width would be 1.0
            self.assertEqual(Path(tmp, "noise").read_text(), "0.5\n")


if __name__ == "__main__":
    unittest.main()
