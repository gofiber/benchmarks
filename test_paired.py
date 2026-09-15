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
            # v3 is 5% slower and main 5% faster in every round, while the drift spreads each target by 60%
            "v2": {"static": [100 * d for d in drift], "parameter": [100.0] * 10, "fasthttp_floor": [100.0] * 10},
            "v3": {"static": [105 * d for d in drift], "parameter": [101.0, 99.0] * 5, "fasthttp_floor": [50.0, 200.0] * 5},
            "main": {"static": [95 * d for d in drift], "parameter": [102.0, 98.0] * 5, "fasthttp_floor": [50.0, 200.0] * 5},
        }
        with tempfile.TemporaryDirectory() as tmp:
            for target, scenarios in runs.items():
                lines = [f"BenchmarkRequest/{name}  1000  {samples[n]:.3f} ns/op" for n in range(10) for name, samples in scenarios.items()]
                Path(tmp, f"{target}.txt").write_text("\n".join(lines) + "\n")
            with contextlib.redirect_stdout(io.StringIO()):
                paired.main(tmp, list(runs))
            with open(Path(tmp, "paired.csv"), newline="") as f:
                rows = {(r["target"], r["name"]): r for r in csv.DictReader(f)}
            self.assertNotIn(("v2", "static"), rows)
            self.assertAlmostEqual(float(rows["v3", "static"]["delta"]), 5)
            self.assertAlmostEqual(float(rows["main", "static"]["delta"]), -5)
            self.assertAlmostEqual(float(rows["main", "static"]["value"]) / float(rows["main", "static"]["base"]), 0.95)
            self.assertEqual(rows["v3", "static"]["significant"], "True")
            self.assertEqual(rows["v3", "parameter"]["significant"], "False")
            # with fasthttp_floor the median half-width would be 1.5
            self.assertEqual(Path(tmp, "noise").read_text(), "0.5\n")


if __name__ == "__main__":
    unittest.main()
