"""Generate offline notices from Cargo.lock and locally available source metadata.

Usage: python Scripts/generate-license-notices.py --registry-dir <cargo registry src>
This is an inventory, not a license compatibility or binary inclusion audit.
"""
import argparse
import pathlib
import shutil
import tomllib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parents[1]
    destination = repo / "App/Resources/Legal"
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(repo / "LICENSE", destination / "GPL-3.0.txt")
    shutil.copyfile(repo / "ThirdParty/AirCard-MIT.txt", destination / "AirCard-MIT.txt")
    shutil.copyfile(repo / "ThirdParty/idevice-MIT.txt", destination / "idevice-MIT.txt")
    shutil.copyfile(repo / "ThirdParty/SOURCES.md", destination / "ThirdPartySources.md")

    packages = tomllib.loads((repo / "Core/Cargo.lock").read_text(encoding="utf-8"))["package"]
    lines = ["# Rust 依赖许可证清单", "",
             "依据 Core/Cargo.lock 与构建缓存中的 Cargo.toml 生成。包含开发、多平台及可选依赖，"
             "不代表每个包均进入 iOS 成品，也不代表已完成兼容性审计。未找到元数据时明确标注。"
             "完整可取得的版权及许可文本见 Rust 依赖版权与许可文本。", ""]
    english = ["# Rust Dependency License Inventory", "",
               "Generated from Core/Cargo.lock and cached Cargo.toml metadata. Includes development, "
               "optional, and multiple-platform packages; not every package enters the iOS binary. "
               "This is not a license compatibility audit. Unavailable metadata is explicitly marked. "
               "Available copyright and license texts are in Rust Copyright & License Texts.", ""]
    notices = ["Pawster Rust dependency notices\n\n"
               "Generated from Cargo.lock and locally available source files.\n"
               "Includes build, development, optional and platform-specific dependencies.\n"
               "This is not a complete distribution clearance or binary inclusion audit.\n"]
    missing, no_text = [], []
    for package in sorted(packages, key=lambda p: (p["name"], p["version"])):
        name, version = package["name"], package["version"]
        if "source" in package:
            root = args.registry_dir / f"{name}-{version}"
        elif name == "posterbridge-core":
            root = repo / "Core"
        else:
            root = repo / "Core/vendor" / name
        manifest = root / "Cargo.toml"
        label = f"{name} {version}"
        if not manifest.is_file():
            lines += [f"{label} — 未取得本地元数据；需在发行前核实。", ""]
            english += [f"{label} — Local metadata unavailable; verify before distribution.", ""]
            missing.append(label)
            continue
        metadata = tomllib.loads(manifest.read_text(encoding="utf-8"))["package"]
        declared_license = metadata.get("license")
        license_id = declared_license or "No SPDX license declared; authorization must be verified"
        lines += [f"{label} — {declared_license or '未声明 SPDX 许可；需核实授权'}", ""]
        english += [f"{label} — {license_id}", ""]
        files = set()
        for path in root.iterdir():
            if path.is_file() and path.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "COPYRIGHT", "NOTICE")):
                files.add(path)
        if metadata.get("license-file"):
            specified = (root / metadata["license-file"]).resolve()
            # A manifest is not allowed to pull unrelated local files into notices.
            if specified.is_relative_to(root.resolve()) and specified.is_file():
                files.add(specified)
        for folder in (root / "LICENSES", root / "licenses"):
            if folder.is_dir():
                files.update(path for path in folder.rglob("*") if path.is_file())
        if name == "posterbridge-core":
            files.add(repo / "LICENSE")
        notices.append(f"\n{'=' * 72}\n{label}\nDeclared license: {license_id}\n")
        if not files:
            no_text.append(label)
            notices.append("No standalone license/notice text found in this source snapshot; verification required.\n")
        for path in sorted(files):
            notices.append(f"\n--- {path.name} ---\n{path.read_text(encoding='utf-8', errors='replace')}\n")
    lines += ["## 核实提示", "",
              f"锁定包数量：{len(packages)}。未取得元数据：{len(missing)}；"
              f"未找到独立许可文本：{len(no_text)}。声明的许可证不等于已确认全部版权或授权链。", ""]
    if missing:
        lines += ["未取得元数据：" + "、".join(missing), ""]
    if no_text:
        lines += ["未找到独立许可文本：" + "、".join(no_text), ""]
    english += ["## Verification Notes", "",
                f"Locked packages: {len(packages)}. Metadata unavailable: {len(missing)}. "
                f"No standalone license text found: {len(no_text)}. A declared license does not establish "
                "that all copyrights or the full authorization chain have been verified.", ""]
    if missing:
        english += ["Metadata unavailable: " + ", ".join(missing), ""]
    if no_text:
        english += ["No standalone license text found: " + ", ".join(no_text), ""]
    (destination / "RustDependencies.md").write_text("\n".join(lines), encoding="utf-8")
    (destination / "RustDependencies.en-US.md").write_text("\n".join(english), encoding="utf-8")
    (destination / "RustLicenseNotices.txt").write_text("\n".join(notices), encoding="utf-8")
    print(f"{len(packages)} packages; {len(missing)} metadata unavailable; {len(no_text)} without standalone license text")


if __name__ == "__main__":
    main()
