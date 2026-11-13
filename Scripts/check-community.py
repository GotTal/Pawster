"""Validate community files, issue forms and repository-relative Markdown links."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit
import yaml

root = Path(__file__).resolve().parents[1]
documents = ["README.md", "README_CN.md", "CONTRIBUTING.md", "CONTRIBUTING_CN.md", "CODE_OF_CONDUCT.md", "SECURITY.md",
             "Docs/VERIFYING_RELEASES.md", "Docs/ARCHITECTURE.md", "Docs/FAQ.md", "Docs/COMPATIBILITY.md", "Docs/ROADMAP.md", "Docs/MAINTAINING.md"]
for name in documents:
    path = root / name
    text = path.read_text(encoding="utf-8")
    assert text.strip(), name
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    targets = re.findall(r"\]\(([^)]+)\)", text) + re.findall(r'<img[^>]+src="([^"]+)"', text)
    for target in targets:
        target = target.strip("<>")
        parsed = urlsplit(target)
        if parsed.scheme or target.startswith("#"):
            continue
        local = (path.parent / unquote(parsed.path)).resolve()
        assert local.is_relative_to(root) and local.exists(), f"Broken local link in {name}: {target}"
    if name.startswith("README"):
        assert "https://github.com/GotTal/Pawster/releases/latest" in text
        assert not re.search(r"https://github\.com/GotTal/Pawster/releases/(?:tag|download)/", text), f"Version-pinned release link: {name}"

forms = list((root / ".github/ISSUE_TEMPLATE").glob("*.yml"))
for path in forms:
    form = yaml.safe_load(path.read_text(encoding="utf-8"))
    if path.name == "config.yml":
        assert isinstance(form["blank_issues_enabled"], bool)
        assert all(urlsplit(item["url"]).scheme == "https" for item in form["contact_links"])
        continue
    assert form["name"] and form["description"] and form["body"], path.name
    ids = [item["id"] for item in form["body"] if item["type"] != "markdown"]
    assert len(ids) == len(set(ids)), path.name
    for item in form["body"]:
        assert item["type"] in {"markdown", "input", "textarea", "dropdown", "checkboxes"}
        if item["type"] != "markdown":
            assert item["attributes"]["label"]
assert (root / ".github/PULL_REQUEST_TEMPLATE.md").is_file()
for path in (root / ".github/workflows").glob("*.yml"):
    workflow = yaml.safe_load(path.read_text(encoding="utf-8"))
    assert workflow["permissions"] == {"contents": "read"}, path.name
    # PyYAML's YAML 1.1 parser treats the GitHub Actions 'on' key as True.
    triggers = workflow.get("on", workflow.get(True))
    assert "pull_request" in triggers and "pull_request_target" not in triggers, path.name
print(f"Validated {len(documents)} documents, {len(forms)-1} issue forms, PR template and read-only PR workflows.")
