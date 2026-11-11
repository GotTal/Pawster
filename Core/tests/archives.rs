use posterbridge_core::archive::{extract, safe_relative};
use std::{fs, io::Write};
use zip::{write::SimpleFileOptions, ZipWriter};

fn zip_at(path: &std::path::Path, entries: &[(&str, &[u8])]) {
    let mut zip = ZipWriter::new(fs::File::create(path).unwrap());
    for (name, content) in entries {
        zip.start_file(*name, SimpleFileOptions::default()).unwrap();
        zip.write_all(content).unwrap();
    }
    zip.finish().unwrap();
}
#[test]
fn rejects_escape_paths_across_platforms() {
    for path in [
        "../outside",
        "/absolute",
        "a/../b",
        "a/./b",
        "C:/file",
        "a\\b",
        "a//b",
        "a./x",
        "a /x",
        "a\nname",
    ] {
        assert!(safe_relative(path).is_err(), "accepted {path}");
    }
}
#[test]
fn preserves_descriptor_bytes_and_reports_hash() {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("pack.tendies");
    let target = temp.path().join("stage");
    let payload = b"7400.DYNAMIC\0binary";
    zip_at(
        &source,
        &[
            ("descriptors/id/Wallpaper.plist", payload),
            ("descriptors/id/assets/a.png", b"image"),
        ],
    );
    let report = extract(&source, &target).unwrap();
    assert_eq!(
        fs::read(target.join("descriptors/id/Wallpaper.plist")).unwrap(),
        payload
    );
    assert_eq!(report.files.len(), 2);
    assert_eq!(report.sha256.len(), 64);
}
#[test]
fn refuses_overwriting_existing_destination() {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("pack");
    let target = temp.path().join("stage");
    zip_at(&source, &[("a", b"new")]);
    fs::create_dir(&target).unwrap();
    fs::write(target.join("a"), b"original").unwrap();
    assert!(extract(&source, &target).is_err());
    assert_eq!(fs::read(target.join("a")).unwrap(), b"original");
}
#[test]
fn case_collisions_rejected_before_writing() {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("pack");
    let target = temp.path().join("stage");
    zip_at(
        &source,
        &[("Assets/A.png", b"one"), ("assets/a.PNG", b"two")],
    );
    assert!(extract(&source, &target).is_err());
    assert!(!target.exists());
}
#[test]
fn file_directory_conflict_cleans_partial_extraction() {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("pack");
    let target = temp.path().join("stage");
    zip_at(&source, &[("assets", b"file"), ("assets/image", b"image")]);
    assert!(extract(&source, &target).is_err());
    assert!(!target.exists());
}
#[test]
fn corrupt_archive_leaves_no_stage() {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("pack");
    let target = temp.path().join("stage");
    fs::write(&source, b"not a zip").unwrap();
    assert!(extract(&source, &target).is_err());
    assert!(!target.exists());
}
