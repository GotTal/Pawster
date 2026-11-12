import XCTest
@testable import Pawster

final class LocalizationTests: XCTestCase {
    private var english: LanguageManifest.Pack {
        .init(id: "en-US", nativeName: "English", file: "en-US", aliases: ["en"],
              documents: ["Terms": "Terms.en-US", "Privacy": "Privacy.en-US"])
    }
    private var chinese: LanguageManifest.Pack {
        .init(id: "zh-Hans", nativeName: "Simplified Chinese", file: "zh-Hans", aliases: ["zh", "zh-CN", "zh-SG"],
              documents: ["Terms": "Terms", "Privacy": "Privacy"])
    }
    private func catalog(_ languages: [String], packs: [LanguageManifest.Pack] = [],
                         extra: [String: [String: String]] = [:]) -> LocalizationCatalog {
        let manifest = LanguageManifest(schemaVersion: 1, fallback: "en-US", chineseFallback: "zh-Hans",
            languageDefaults: ["en": "en-US", "zh": "zh-Hans", "fr": "fr-FR"], languages: [english, chinese] + packs)
        var values = ["en-US": ["label": "Settings", "welcome": "Hello {0}, {1}", "englishOnly": "English fallback"],
                      "zh-Hans": ["label": "设置", "welcome": "{0}，你好：{1}"]]
        values.merge(extra) { _, new in new }
        return LocalizationCatalog(manifest: manifest, catalogs: values, preferredLanguages: languages)
    }
    func testChineseRegionsAndScriptsInitiallyUseSimplifiedChinese() {
        for language in ["zh", "zh-CN", "zh-TW", "zh-HK", "zh-MO", "zh-SG", "zh-Hant", "zh-Hant-HK", "ZH_hant_TW", "zh-Hans-SG"] {
            XCTAssertEqual(catalog([language]).language, "zh-Hans", language)
        }
    }
    func testFutureTraditionalAndRegionalPacksTakePriority() {
        let traditional = LanguageManifest.Pack(id: "zh-Hant", nativeName: "Traditional Chinese", file: "zh-Hant",
            aliases: ["zh-TW", "zh-MO"], documents: [:])
        let hongKong = LanguageManifest.Pack(id: "zh-HK", nativeName: "Hong Kong", file: "zh-HK",
            aliases: ["zh-Hant-HK"], documents: [:])
        let extra = ["zh-Hant": ["label": "設定"], "zh-HK": ["label": "香港"]]
        XCTAssertEqual(catalog(["zh-TW"], packs: [traditional, hongKong], extra: extra).language, "zh-Hant")
        XCTAssertEqual(catalog(["zh-Hant-TW"], packs: [traditional, hongKong], extra: extra).language, "zh-Hant")
        XCTAssertEqual(catalog(["zh-Hant-HK"], packs: [traditional, hongKong], extra: extra).language, "zh-HK")
        XCTAssertEqual(catalog(["zh-SG"], packs: [traditional, hongKong], extra: extra).language, "zh-Hans")
    }
    func testFutureChinesePackMissingEntriesFallBackToSimplifiedThenEnglish() {
        let pack = LanguageManifest.Pack(id: "zh-Hant", nativeName: "Traditional Chinese", file: "zh-Hant",
            aliases: ["zh-TW"], documents: [:])
        let localized = catalog(["zh-TW"], packs: [pack], extra: ["zh-Hant": ["label": "設定"]])
        XCTAssertEqual(localized.text("label"), "設定")
        XCTAssertEqual(localized.text("welcome", ["A", "B"]), "A，你好：B")
        XCTAssertEqual(localized.text("englishOnly"), "English fallback")
        XCTAssertEqual(localized.documentResources("Terms"), ["Terms", "Terms.en-US"])
    }
    func testEnglishRegionsAndUnsupportedPrimaryLanguageUseUSEnglish() {
        for language in ["en", "en-US", "en-GB", "en-AU", "fr-CA", "ja-JP", "de-DE"] {
            XCTAssertEqual(catalog([language, "zh-CN"]).language, "en-US", language)
        }
        XCTAssertEqual(catalog([]).language, "en-US")
    }
    func testSupportedRegionalAliasAndLanguageDefault() {
        let pack = LanguageManifest.Pack(id: "fr-FR", nativeName: "French", file: "fr-FR", aliases: ["fr-CA"], documents: [:])
        for language in ["fr-CA", "fr-BE", "fr-FR", "FR_fr"] {
            let localized = catalog([language], packs: [pack], extra: ["fr-FR": ["label": "Réglages"]])
            XCTAssertEqual(localized.language, "fr-FR")
            XCTAssertEqual(localized.text("label"), "Réglages")
            XCTAssertEqual(localized.text("englishOnly"), "English fallback")
            XCTAssertEqual(localized.documentResources("Terms"), ["Terms.en-US"])
        }
    }
    func testDeclaredButUnbundledLanguagePackIsNotSelected() {
        let pack = LanguageManifest.Pack(id: "fr-FR", nativeName: "French", file: "fr-FR", aliases: ["fr"], documents: [:])
        XCTAssertEqual(catalog(["fr-FR"], packs: [pack]).language, "en-US")
    }
    func testInvalidPlaceholdersFallBackWithoutInterpretingArgumentsAgain() {
        let broken = catalog(["zh-CN"], extra: ["zh-Hans": ["welcome": "Wrong {9}", "label": ""]])
        XCTAssertEqual(broken.text("welcome", ["file{1}.tendies", "100% 🐱"]), "Hello file{1}.tendies, 100% 🐱")
        XCTAssertEqual(broken.text("label"), "Settings")
        XCTAssertEqual(broken.text("unknown.key"), "unknown.key")
    }
    func testReorderedAndRepeatedPlaceholdersArePreserved() {
        let changed = catalog(["zh-CN"], extra: ["zh-Hans": ["welcome": "{1} / {0} / {1}"]])
        XCTAssertEqual(changed.text("welcome", ["A", "B"]), "B / A / B")
    }
    func testResourceNamesCannotEscapeTheBundle() {
        for name in ["Terms.en-US", "zh-Hans", "en-US"] { XCTAssertTrue(L10n.safeResourceName(name)) }
        for name in ["", ".", "..", "../Terms", "/Terms", "a\\b", "a:b"] { XCTAssertFalse(L10n.safeResourceName(name)) }
    }
    func testBundledPacksContainTheSameKeysAndPlaceholders() throws {
        func load(_ name: String) throws -> Data {
            try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json")))
        }
        let manifest = try JSONDecoder().decode(LanguageManifest.self, from: load("LanguagePacks"))
        let english = try JSONDecoder().decode([String: String].self, from: load("en-US"))
        let chinese = try JSONDecoder().decode([String: String].self, from: load("zh-Hans"))
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        for (key, text) in chinese {
            XCTAssertFalse(text.isEmpty)
            XCTAssertEqual(LocalizationCatalog.placeholders(text), LocalizationCatalog.placeholders(try XCTUnwrap(english[key])), key)
        }
        for pack in manifest.languages {
            XCTAssertNotNil(Bundle.main.url(forResource: pack.file, withExtension: "json"))
            for resource in pack.documents.values {
                XCTAssertNotNil(Bundle.main.url(forResource: resource, withExtension: "md"), resource)
            }
        }
    }
}
