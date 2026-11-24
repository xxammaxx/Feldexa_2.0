#!/usr/bin/env python3
"""Frozen contract test for the T264P adaptive-variant provenance artifact.

Covers the T264P decision that gates T264C: every raster variant that an
adaptive second pass may analyse carries a declared derivation, a correlation
group, and a hash binding, and variants that descend from the same rendering can
never be counted as two pieces of independent evidence.

The artifact is `tools/evaluation/adaptive-provenance.v1.json`, frozen before any
scored adaptive run (`status` `frozen-before-run`, `implementation` `BLOCKED`).
This test recomputes every in-tree hash it can recompute, so a silent edit of the
source document, the variant producer, or the frozen policy fails here.

Stdlib only, no network, no Dart, no emulator, no device.

Run:
  python3 -m unittest tools/evaluation/test_adaptive_provenance.py
  python3 tools/evaluation/test_adaptive_provenance.py
"""
import hashlib
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
ARTIFACT = ROOT / "tools" / "evaluation" / "adaptive-provenance.v1.json"
ARTIFACT_DOC = ROOT / "tools" / "evaluation" / "adaptive-provenance.v1.md"
POLICY = ROOT / "tools" / "evaluation" / "adaptive-policy.v1.json"
POLICY_DOC = ROOT / "tools" / "evaluation" / "adaptive-policy.v1.md"

HEX64 = re.compile(r"\A[0-9a-f]{64}\Z")
HASH_STATUSES = {"PENDING_RUN", "RECORDED"}
PENDING_STATUSES = {"PENDING_RUN"}

REQUIRED_TOP_LEVEL = {
    "schemaVersion",
    "artifactId",
    "version",
    "status",
    "implementation",
    "task",
    "issue",
    "feature",
    "purpose",
    "document",
    "hashConvention",
    "sources",
    "correlationGroups",
    "variants",
    "decisionRule",
    "policyArtifact",
    "notRun",
}
REQUIRED_VARIANT_FIELDS = {
    "id",
    "families",
    "derivedFrom",
    "correlationGroup",
    "independent",
    "rendering",
    "hashBinding",
    "documents",
}
REQUIRED_HASH_BINDING_FIELDS = {
    "sourceDocumentSha256",
    "sourceRasterSha256",
    "sourceRasterSha256Status",
    "variantRasterSha256",
    "variantRasterSha256Status",
}
REQUIRED_FAMILIES = {
    "scaling",
    "dpi",
    "jpegQuality",
    "shadow",
    "lowContrast",
    "skew",
}


def sha256_of(relative_path):
    digest = hashlib.sha256()
    with open(ROOT / relative_path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_artifact():
    if not ARTIFACT.is_file():
        raise AssertionError(
            f"missing frozen provenance artifact: {ARTIFACT.relative_to(ROOT)}; "
            "T264P requires the contract before any adaptive implementation"
        )
    with open(ARTIFACT, encoding="utf-8") as handle:
        return json.load(handle)


def variants_by_id(artifact):
    return {variant["id"]: variant for variant in artifact["variants"]}


def independent_group_count(artifact, selected_ids):
    """Count independent evidence groups the way `decisionRule` declares it.

    One observation occupies at most one slot per `correlationGroup`, so a
    selection never gains evidence by repeating a group.
    """
    variants = variants_by_id(artifact)
    unknown = sorted(set(selected_ids) - set(variants))
    if unknown:
        raise AssertionError(f"selection names undeclared variants: {unknown}")
    return len({variants[identifier]["correlationGroup"] for identifier in selected_ids})


def agreement_claim(artifact, selected_ids):
    """True only when the selection reaches the declared independent-group floor."""
    required = artifact["decisionRule"]["minIndependentGroups"]
    return independent_group_count(artifact, selected_ids) >= required


class AdaptiveProvenanceSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.artifact = load_artifact()

    def test_artifact_is_frozen_and_versioned(self):
        artifact = self.artifact
        self.assertLessEqual(
            REQUIRED_TOP_LEVEL, set(artifact), "artifact contract fields are missing"
        )
        self.assertEqual(artifact["schemaVersion"], 1)
        self.assertEqual(artifact["artifactId"], "feldexa.adaptive-provenance")
        self.assertEqual(artifact["status"], "frozen-before-run")
        self.assertEqual(artifact["implementation"], "BLOCKED")
        self.assertEqual(artifact["task"], "T264P")
        self.assertEqual(artifact["issue"], 264)
        self.assertEqual(artifact["feature"], "001-scanned-form-workflow")
        self.assertEqual(artifact["document"]["pages"], 2)
        self.assertGreaterEqual(len(artifact["variants"]), len(REQUIRED_FAMILIES))

    def test_document_identity_hash_is_recomputable(self):
        document = self.artifact["document"]
        self.assertEqual(
            document["sha256"], sha256_of(document["path"]), "source document drifted"
        )
        self.assertEqual(document["sha256OriginPath"], "tools/corpus/de-ocr/reference-de.ground-truth.json")
        ground_truth = json.loads((ROOT / document["sha256OriginPath"]).read_text())
        self.assertEqual(ground_truth["pdf"]["sha256"], document["sha256"])
        self.assertEqual(ground_truth["pages"].__len__(), document["pages"])

    def test_every_variant_declares_derivation_and_provenance(self):
        for variant in self.artifact["variants"]:
            with self.subTest(variant=variant["id"]):
                self.assertLessEqual(
                    REQUIRED_VARIANT_FIELDS,
                    set(variant),
                    f"{variant['id']} misses a provenance field",
                )
                self.assertIsInstance(variant["derivedFrom"], str)
                self.assertTrue(variant["derivedFrom"])
                self.assertIsInstance(variant["correlationGroup"], str)
                self.assertTrue(variant["correlationGroup"])
                self.assertIsInstance(variant["independent"], bool)
                self.assertTrue(variant["families"])
                self.assertLessEqual(set(variant["families"]), REQUIRED_FAMILIES)

    def test_derivation_and_group_references_resolve(self):
        artifact = self.artifact
        variants = variants_by_id(artifact)
        source_ids = {source["id"] for source in artifact["sources"]}
        group_ids = {group["id"] for group in artifact["correlationGroups"]}
        for variant in artifact["variants"]:
            with self.subTest(variant=variant["id"]):
                self.assertIn(
                    variant["derivedFrom"],
                    set(variants) | source_ids,
                    f"{variant['id']} derives from an undeclared node",
                )
                self.assertIn(
                    variant["correlationGroup"],
                    group_ids,
                    f"{variant['id']} names an undeclared correlation group",
                )
        for source in artifact["sources"]:
            self.assertEqual(
                source["sourceDocumentSha256"], artifact["document"]["sha256"]
            )

    def test_group_membership_agrees_with_the_declared_source(self):
        """A group may only hold variants of exactly its own source.

        Without this pin a consistent false edit stays green: moving a variant
        into another group, or promoting an excluded rendering into an
        independent group, would satisfy every other assertion while silently
        breaking the frozen contract that T264C consumes.
        """
        artifact = self.artifact
        groups = {group["id"]: group for group in artifact["correlationGroups"]}
        sources = {source["id"] for source in artifact["sources"]}
        variants = {variant["id"]: variant for variant in artifact["variants"]}
        for variant in artifact["variants"]:
            group = groups[variant["correlationGroup"]]
            self.assertIn(
                group["sourceId"],
                sources,
                f"{variant['id']}: group source must resolve to a declared source",
            )
            derived_from = variant["derivedFrom"]
            if derived_from in sources:
                self.assertEqual(
                    group["sourceId"],
                    derived_from,
                    f"{variant['id']}: a variant derived from a source must sit in that "
                    "source's group",
                )
            else:
                self.assertIn(
                    derived_from,
                    variants,
                    f"{variant['id']}: derivedFrom must be a source or a variant",
                )
                self.assertEqual(
                    group["id"],
                    variants[derived_from]["correlationGroup"],
                    f"{variant['id']}: a variant derived from another variant must stay in "
                    "that variant's correlation group",
                )
        self.assertEqual(
            len(groups),
            5,
            "the frozen contract declares exactly five correlation groups",
        )
        self.assertEqual(
            [entry["id"] for entry in artifact["excludedVariants"]],
            ["region-render-2x"],
            "the excluded rendering must stay excluded; it is not independent evidence",
        )

    def test_every_required_variant_family_is_covered(self):
        families = {
            family for variant in self.artifact["variants"] for family in variant["families"]
        }
        self.assertLessEqual(
            REQUIRED_FAMILIES, families, "a required variant family has no provenance row"
        )

    def test_variant_documents_exist_and_match_their_hashes(self):
        for variant in self.artifact["variants"]:
            with self.subTest(variant=variant["id"]):
                documents = variant["documents"]
                self.assertTrue(documents, f"{variant['id']} declares no documents")
                for document in documents:
                    self.assertTrue(document["role"])
                    self.assertTrue(
                        (ROOT / document["path"]).is_file(),
                        f"{document['path']} does not exist",
                    )
                    self.assertEqual(
                        document["sha256"],
                        sha256_of(document["path"]),
                        f"{document['path']} drifted from its recorded hash",
                    )

    def test_hash_bindings_are_recorded_or_explicitly_pending(self):
        artifact = self.artifact
        convention = artifact["hashConvention"]
        self.assertEqual(convention["algorithm"], "sha256")
        for variant in artifact["variants"]:
            with self.subTest(variant=variant["id"]):
                binding = variant["hashBinding"]
                self.assertLessEqual(REQUIRED_HASH_BINDING_FIELDS, set(binding))
                self.assertEqual(
                    binding["sourceDocumentSha256"], artifact["document"]["sha256"]
                )
                for value_key, status_key in (
                    ("sourceRasterSha256", "sourceRasterSha256Status"),
                    ("variantRasterSha256", "variantRasterSha256Status"),
                ):
                    status = binding[status_key]
                    self.assertIn(status, HASH_STATUSES)
                    value = binding[value_key]
                    if status == "RECORDED":
                        self.assertTrue(
                            HEX64.match(str(value)),
                            f"{variant['id']}.{value_key} is not a sha256 hex digest",
                        )
                    else:
                        self.assertIsNone(
                            value,
                            f"{variant['id']}.{value_key} must stay null while {status}",
                        )
        for variant in artifact["variants"]:
            self.assertIn(
                variant["hashBinding"]["variantRasterSha256Status"],
                PENDING_STATUSES,
                "no variant raster byte hash may be invented before the first run",
            )

    def test_policy_artifact_is_bound_and_still_frozen(self):
        artifact = self.artifact
        policy_artifact = artifact["policyArtifact"]
        self.assertEqual(
            policy_artifact["path"], "tools/evaluation/adaptive-policy.v1.json"
        )
        self.assertEqual(
            policy_artifact["sha256"],
            sha256_of(policy_artifact["path"]),
            "the frozen policy drifted; T264P may not retune a threshold",
        )
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        self.assertEqual(policy["status"], "frozen-before-run")
        self.assertEqual(policy["implementation"], "BLOCKED")
        self.assertEqual(policy["version"], policy_artifact["version"])
        self.assertFalse(policy["independence"]["twoIndependentOcrLinesAgree"])
        self.assertEqual(
            policy["independence"]["rule"], artifact["correlationRule"]["policyRule"]
        )

    def test_decision_rule_is_applicable_by_t264c(self):
        decision = self.artifact["decisionRule"]
        self.assertEqual(decision["appliesTo"], "T264C")
        self.assertGreaterEqual(decision["minIndependentGroups"], 2)
        self.assertEqual(decision["maxObservationsPerCorrelationGroup"], 1)
        self.assertFalse(decision["twoIndependentOcrLinesAgree"])
        self.assertTrue(decision["correlatedVariantsHaveEqualWeight"] is False)
        self.assertTrue(decision["insufficientGroupsOutcome"])
        self.assertIn(
            "twoIndependentOcrLinesAgree", decision["forbiddenClaims"]
        )


class AdaptiveProvenanceCorrelationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.artifact = load_artifact()
        cls.variants = variants_by_id(cls.artifact)

    def test_at_least_two_independent_correlation_groups_exist(self):
        groups = self.artifact["correlationGroups"]
        self.assertGreaterEqual(len(groups), 2)
        pixel_sources = {group["pixelSourceId"] for group in groups}
        self.assertEqual(
            len(pixel_sources), len(groups), "two groups share one pixel source"
        )
        for group in groups:
            self.assertTrue(group["independent"], f"{group['id']} is not independent")
        self.assertGreaterEqual(
            independent_group_count(
                self.artifact, [group["representative"] for group in groups]
            ),
            2,
        )

    def test_group_membership_and_representatives_are_consistent(self):
        for group in self.artifact["correlationGroups"]:
            with self.subTest(group=group["id"]):
                members = [
                    variant["id"]
                    for variant in self.artifact["variants"]
                    if variant["correlationGroup"] == group["id"]
                ]
                self.assertEqual(sorted(members), sorted(group["members"]))
                declared_independent = [
                    identifier
                    for identifier in members
                    if self.variants[identifier]["independent"]
                ]
                self.assertEqual(
                    declared_independent,
                    [group["representative"]],
                    f"{group['id']} must have exactly one independent representative",
                )

    def test_correlated_variants_never_count_as_independent_evidence(self):
        rule = self.artifact["correlationRule"]
        self.assertFalse(rule["twoIndependentOcrLinesAgree"])
        self.assertIn("same rendering", rule["rule"])

        # Two variants of one rendering: same group, one slot only.
        same_group = sorted(
            variant["id"]
            for variant in self.artifact["variants"]
            if variant["correlationGroup"] == "group-pdfium-200"
        )
        self.assertGreaterEqual(len(same_group), 2)
        self.assertEqual(independent_group_count(self.artifact, same_group), 1)
        self.assertFalse(
            agreement_claim(self.artifact, same_group),
            "two variants of the same 200 DPI rendering claim two independent lines",
        )

        # A degraded re-render of the same document page stays in its own group,
        # but three degradations of one capture are still one group.
        poppler_200 = sorted(
            variant["id"]
            for variant in self.artifact["variants"]
            if variant["correlationGroup"] == "group-poppler-200"
        )
        self.assertGreaterEqual(len(poppler_200), 2)
        self.assertEqual(independent_group_count(self.artifact, poppler_200), 1)
        self.assertFalse(agreement_claim(self.artifact, poppler_200))

        # Two distinct renderings do reach the floor.
        cross_group = ["clean-200dpi", "scan-150dpi-low-contrast"]
        self.assertEqual(independent_group_count(self.artifact, cross_group), 2)
        self.assertTrue(agreement_claim(self.artifact, cross_group))
        self.assertNotEqual(
            self.variants[cross_group[0]]["correlationGroup"],
            self.variants[cross_group[1]]["correlationGroup"],
        )

    def test_adaptive_same_dpi_variants_are_correlated_with_the_reference(self):
        for identifier in ("contrastStretch-200dpi", "deskew-200dpi"):
            variant = self.variants[identifier]
            self.assertEqual(variant["derivedFrom"], "clean-200dpi")
            self.assertEqual(variant["correlationGroup"], "group-pdfium-200")
            self.assertFalse(variant["independent"])
            self.assertFalse(
                agreement_claim(self.artifact, ["clean-200dpi", identifier]),
                f"{identifier} may not add an independent line to clean-200dpi",
            )

    def test_glyph_level_claims_collapse_per_source_document(self):
        collapse = self.artifact["correlationRule"]["glyphLevelCollapse"]
        self.assertTrue(collapse["appliesToAllVariants"])
        self.assertEqual(collapse["independentGroupsPerDocument"], 1)
        self.assertEqual(
            collapse["scope"],
            "character, glyph, umlaut, currency, and content claims",
        )
        document_ids = {variant["documentId"] for variant in self.artifact["variants"]}
        self.assertEqual(document_ids, {self.artifact["document"]["id"]})


class AdaptiveProvenanceDocumentationTest(unittest.TestCase):
    def test_provenance_doc_states_the_rule(self):
        self.assertTrue(ARTIFACT_DOC.is_file(), "provenance markdown is missing")
        text = ARTIFACT_DOC.read_text(encoding="utf-8")
        for needle in (
            "adaptive-provenance.v1.json",
            "frozen-before-run",
            "correlationGroup",
            "derivedFrom",
            "independent",
            "minIndependentGroups",
            "twoIndependentOcrLinesAgree",
            "T264C",
        ):
            self.assertIn(needle, text, f"provenance doc does not mention {needle}")

    def test_policy_doc_references_provenance_and_stays_frozen(self):
        text = POLICY_DOC.read_text(encoding="utf-8")
        self.assertIn("## 8. Provenance reference (T264P)", text)
        self.assertIn("tools/evaluation/adaptive-provenance.v1.json", text)
        self.assertIn("changes no threshold", text)
        for task in ("T142", "T136", "T141"):
            self.assertIn(task, text)
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        self.assertEqual(policy["status"], "frozen-before-run")
        self.assertEqual(policy["implementation"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
