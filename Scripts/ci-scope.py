"""Classify trusted Git diff paths without executing event-supplied shell text."""
import json
import os
from pathlib import Path
import subprocess

BUILD_FILES = {"project.yml", "Scripts/build-core.sh", "Scripts/build-ipa.sh", "Scripts/test-macos.sh"}
WORKFLOW_FILES = {".github/workflows/build.yml", "Scripts/ci-scope.py", "Scripts/capture-doc-screenshots.sh"}


def classify(paths, event_name):
    package = any(p.startswith(("App/", "Core/")) or p in BUILD_FILES for p in paths)
    native = package or any(p.startswith("Tests/") for p in paths)
    workflow = any(p in WORKFLOW_FILES for p in paths)
    # PRs validate native workflow edits before merge. A docs/workflow-only merge
    # does not repeat the native build or produce an unsolicited IPA on main.
    return native or (event_name == "pull_request" and workflow), package


def main():
    event_name = os.environ["GITHUB_EVENT_NAME"]
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
    if event_name == "workflow_dispatch":
        native = True
        package = event.get("inputs", {}).get("package_ipa", True) in (True, "true")
    else:
        before = event["pull_request"]["base"]["sha"] if event_name == "pull_request" else event.get("before", "")
        if before and set(before) != {"0"}:
            data = subprocess.check_output(["git", "diff", "--name-only", "-z", before, "HEAD"])
        else:
            data = subprocess.check_output(["git", "ls-files", "-z"])
        paths = data.decode("utf-8").split("\0")
        native, code_changed = classify(paths, event_name)
        package = code_changed and event_name == "push"
    output = f"native={str(native).lower()}\npackage={str(package).lower()}\n"
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as file:
        file.write(output)
    print(output, end="")


if __name__ == "__main__":
    main()
