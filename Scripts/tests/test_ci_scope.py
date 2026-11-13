import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("ci_scope", Path(__file__).parents[1] / "ci-scope.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class CIScopeTests(unittest.TestCase):
    def test_documentation_and_forms_do_not_require_native_build(self):
        self.assertEqual(scope.classify(["README.md", "Docs/FAQ.md", ".github/ISSUE_TEMPLATE/bug_report.yml"], "pull_request"), (False, False))

    def test_native_changes_always_require_validation(self):
        for path in ["App/ContentView.swift", "App/Resources/Localization/en-US.json", "Core/src/lib.rs", "project.yml", "Scripts/build-ipa.sh"]:
            with self.subTest(path=path):
                self.assertEqual(scope.classify(["README.md", path], "pull_request"), (True, True))
                self.assertEqual(scope.classify([path], "push"), (True, True))

    def test_test_changes_validate_without_requesting_a_package(self):
        self.assertEqual(scope.classify(["Tests/PolicyTests.swift"], "pull_request"), (True, False))
        self.assertEqual(scope.classify(["Tests/PolicyTests.swift"], "push"), (True, False))

    def test_workflow_edits_are_validated_on_pr_without_repackaging_main(self):
        for path in [".github/workflows/build.yml", "Scripts/ci-scope.py"]:
            self.assertEqual(scope.classify([path], "pull_request"), (True, False))
            self.assertEqual(scope.classify([path], "push"), (False, False))


if __name__ == "__main__":
    unittest.main()
