#!/usr/bin/env python3
"""Regression test for the T035 manual-baseline SC-003 decision rule.

The independent quality review of candidate 3f2ed3e found that the protocol
allowed SC-003 PASS from pooled R/U even when an individual form was below 80%.
SC-003 says "the share of a form's fields" and research.md D-18 says to compare
the reduction "for each corpus form"; no normative source defines a pooled
threshold. This test pins the per-form decision so the pooled-only rule cannot
return.

Run:
  python3 -m unittest tools/evaluation/test_manual_baseline.py
  python3 tools/evaluation/test_manual_baseline.py
"""
import pathlib
import unittest

PROTOCOL = pathlib.Path(__file__).with_name("manual-baseline.md")


class ManualBaselineDecisionTest(unittest.TestCase):
    @staticmethod
    def _flat(text):
        return " ".join(text.split())

    @classmethod
    def setUpClass(cls):
        cls.text = PROTOCOL.read_text(encoding="utf-8")
        before, separator, after = cls.text.partition("### 6.4")
        if not separator or "### 6.5" not in after:
            raise AssertionError("protocol must contain the §6.4 decision section")
        cls.decision = after.split("### 6.5", 1)[0]
        cls.decision_flat = cls._flat(cls.decision)

    def test_decision_is_per_form_for_both_measures(self):
        for token in (
            "For every form `f`, `R_f ≥ 0.80`",
            "For every form `f`, `U_f ≥ 0.80`",
            "No normative source defines a pooled corpus threshold",
            "If any single form is below 0.80 under either measure, SC-003 is `FAIL`",
            "No averaging, pooling, weighting, trimming, exclusion, or per-form selection",
        ):
            with self.subTest(token=token):
                self.assertIn(self._flat(token), self.decision_flat)

    def test_pooled_values_are_not_acceptance(self):
        for token in (
            "`R_pooled ≥ 0.80`",
            "`U_pooled ≥ 0.80`",
            "The pooled decision stands",
        ):
            with self.subTest(token=token):
                self.assertNotIn(self._flat(token), self.decision_flat)
        self.assertIn(
            self._flat("`R_pooled` and `U_pooled` are reported as context"),
            self.decision_flat,
        )

    def test_pooled_context_is_labelled_outside_the_decision(self):
        self.assertIn("### 6.2 Pooled context values (not acceptance)", self.text)
        self.assertIn("| `R_pooled` (context only) |", self.text)
        self.assertIn("| `U_pooled` (context only) |", self.text)

    def test_protocol_version_and_sources(self):
        self.assertIn("manual-baseline-protocol.v1.1.0", self.text)
        self.assertIn("v1.0.0", self.text)
        self.assertIn("research.md` D-18", self.text)
        self.assertIn("SC-003", self.text)


if __name__ == "__main__":
    unittest.main()
