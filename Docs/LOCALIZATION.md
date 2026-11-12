# Localization / 本地化贡献规范

当前内置 `zh-Hans`（现有简体中文）与 `en-US`（美式英语）。中文地区优先使用对应语言包，缺少时回落简体中文；非中文缺少语言包时回落英语。此文档同时定义贡献者使用的映射和占位符规范。

## Files and public contract

UI packs are UTF-8 JSON objects in `App/Resources/Localization/<BCP-47-tag>.json`. English (`en-US.json`) is the complete reference catalog. `LanguagePacks.json` is the versioned registry; adding a new language does not require editing Swift views or adding a switch statement. The registry is bundled with the app, not downloaded.

JSON schemas for editors and tooling are in `Docs/localization/strings.schema.json` and `language-packs.schema.json`. Run `python3 Scripts/check-localizations.py` before opening a pull request. It requires only Python’s standard library and also runs in the macOS test script and CI. The schemas describe structure; the script additionally checks key coverage, placeholder compatibility, ambiguous mappings, document availability, and resource names.

## Language resolution, in order

1. Read the first entry in `Locale.preferredLanguages` at app launch. This follows the device/app language preference exposed by iOS. Use this primary language only: an unsupported primary language falls back as below rather than unexpectedly choosing a secondary language. Restart the app after changing its system language.
2. Normalize comparison by replacing `_` with `-` and ignoring case. Registry IDs use conventional BCP-47 spelling, such as `en-US`, `zh-Hans`, or `pt-BR`.
3. Try the full tag against bundled pack IDs, then explicit `aliases`. If unmatched, remove the last subtag and try again. For example, `zh-Hant-TW` may match a bundled `zh-Hant` pack; `fr-CA` may match a `fr` pack. Aliases disambiguate region and script relationships; do not infer a translation solely from a filename.
4. Try `languageDefaults[baseLanguage]`, if that pack is bundled. For example, a contributor may map `fr` to `fr-FR` so `fr-BE` can use French even when there is no Belgian pack.
5. For an unmatched `zh` language, use `chineseFallback`, which is `zh-Hans`. All other unmatched languages use `fallback`, which is `en-US`.

Only registered, successfully loaded packs are eligible. A JSON file alone does not enable a locale. Registry mappings must not be ambiguous. Base language defaults must point to the same language family; do not map `ja` to Chinese or English as a claimed Japanese translation.

Current examples:

| Device primary language | Current result |
|---|---|
| zh-CN / zh-SG / zh-Hans | zh-Hans |
| zh-TW / zh-HK / zh-MO / zh-Hant | zh-Hans until the corresponding translation is contributed |
| en-US / en-GB / en-AU | en-US |
| Any unsupported non-Chinese language | en-US |

Future example: register `zh-Hant` with aliases `zh-TW`, `zh-HK`, and `zh-MO`. Those regions then use the contributed Traditional Chinese pack automatically; other Chinese requests keep the Simplified Chinese fallback. A separate Hong Kong pack can later use ID `zh-HK` and alias `zh-Hant-HK`; remove conflicting aliases from the broader pack. Exact regional matching happens before broader script/language matching.

## String keys, placeholders, and fallback

Keep existing English semantic keys, such as `action.cancel`, `pairing.failed`, and `guide.remaining`. Keys are identifiers, not translated text. Do not rename them simply because a translation changes. Add a new key to both base catalogs whenever adding an app-owned user-facing string, and call `L10n.text("the.key")` in Swift. The same API is used for UIKit/PiP, progress, accessibility, and errors, not only SwiftUI labels.

Placeholders are zero-based `{0}`, `{1}`, and so on. Preserve the same set of tokens as `en-US`; translators may reorder or repeat tokens. Example: `guide.remaining` has `{0}` = seconds remaining, `{1}` = the current pairing status. Swift supplies string arguments in that order. Do not translate braces, change indices, add format specifiers, or place executable Swift expressions in a translation. These are plain text templates, not printf, ICU MessageFormat, Markdown, or code. Counts currently use number labels without language-specific singular/plural branching. If a new sentence needs grammatical pluralization, extend the format contract and tests first.

Missing entries in a contributed Chinese pack fall back to `zh-Hans`, then `en-US`. Missing entries in any other contributed pack fall back to `en-US`. Empty values or incorrect placeholders are rejected by validation; the runtime also skips unsafe templates. Inserted filenames and error details are never rescanned for placeholders, so a filename containing `{1}` or `%` remains unchanged. Unknown programmer keys remain visible as keys rather than causing a crash.

Do not translate protocol identifiers, bundle IDs, paths, hashes, persisted transaction states, preference keys, PINs, package names, or user-imported wallpaper names. System and dependency errors can retain their original wording. Dates and app log timestamps use the resolved UI locale. Existing stored history failures retain their recorded text; do not rewrite transaction files merely to translate a previous error.

## Adding a language pack

Copy `en-US.json` to a canonical tag filename, translate its values, and add a registry entry. Example entry:

```json
{
  "id": "fr-FR",
  "nativeName": "Français (France)",
  "file": "fr-FR",
  "aliases": ["fr", "fr-CA"],
  "documents": {}
}
```

Add `"fr": "fr-FR"` to `languageDefaults` if this pack should be the family default. Keep `fallback: en-US`, `chineseFallback: zh-Hans`, and the current `en`/`zh` defaults. An intentionally partial contributed pack is allowed, but missing entries are reported and use the fallback above. Both base packs must remain complete. Do not leave untranslated placeholders as empty strings or claim a finished translation for an unreviewed partial pack.

## Legal documents and licenses

Long documents are separate UTF-8 Markdown files in `App/Resources/Legal`, referenced by resource basename (no extension) in the pack’s `documents` map. Supported document IDs are `Terms`, `Privacy`, `OpenSourceNotices`, `ThirdPartySources`, and `RustDependencies`. The English mapping uses `Terms.en-US`, `Privacy.en-US`, etc. Existing Simplified Chinese basenames are retained for compatibility.

Translate policy meaning, contact information, risks, rights, version, and retention accurately. Do not change the legal effect, hide unresolved upstream authorization, invent certification, or alter data-processing facts during translation. Keep the policy version aligned with the source; substantive policy changes require the developer to review the version and consent behavior. Documents not translated use the same language-family fallback order as UI strings. A declared document must exist; omit its mapping if it is intentionally untranslated.

Original GPL, MIT, and third-party license/copyright texts are kept verbatim. Do not replace authoritative license text with a translation. `Scripts/generate-license-notices.py` regenerates the Chinese and English Rust inventories together and retains available source license notices; other contributors may add an inventory translation or use the English document fallback. Regenerate translated source notices if `ThirdParty/SOURCES.md` changes.

## App name and iOS permission prompts

`InfoPlist.strings` under `<locale>.lproj` holds `CFBundleDisplayName`, `PawsterTestDisplayName`, and `NSLocalNetworkUsageDescription`. iOS chooses these through its own bundle localization system, separately from our JSON resolver. English is the bundle development language and base fallback. `zh-Hant.lproj` currently deliberately uses the same Simplified Chinese as `zh-Hans.lproj`; update it when contributing the corresponding translation. This metadata alias does not claim that a full Traditional Chinese UI pack already exists.

When adding a language, add its `.lproj` metadata and list the applicable locale in `CFBundleLocalizations` in `App/Info.plist`. For differing region/script behavior, add matching metadata variants as needed. XcodeGen includes the localization directory as resources. Verify the actual bundled `.lproj` layout with Xcode. `build-ipa.sh` reads `PawsterTestDisplayName` from every built localization so localized display names do not hide a test build’s identity. Do not change the app’s bundle identifier or signing groups for a translation.

## Validation and review

Run `python3 Scripts/check-localizations.py`, then the existing Xcode test workflow on a test branch when a build is authorized. `LocalizationTests` covers regional/script matching, future Chinese packs, unsupported languages, missing/malformed packs, per-key fallbacks, safe argument handling, offline documents, and bundled catalogs. Test English, Simplified Chinese, an unsupported language, and your new locale on a device/simulator. Check long buttons, large text, screen-reader labels, and the PiP guidance frame while Settings is foreground. Static checks do not establish Swift compilation or device rendering success. Follow the repository’s test-branch and real-device acceptance rules before merging or releasing.

API references: [Apple Locale.preferredLanguages](https://developer.apple.com/documentation/foundation/locale/preferredlanguages), [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).
