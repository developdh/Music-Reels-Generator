import AppKit

enum FontUtility {
    /// All installed font family names, sorted
    static var allFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    /// Font families that are good defaults for Japanese text
    static var japaneseFamilies: [String] {
        let preferred = [
            "Hiragino Sans",
            "Hiragino Kaku Gothic ProN",
            "Hiragino Mincho ProN",
            "Hiragino Maru Gothic ProN",
            "YuGothic",
            "YuMincho",
            "Osaka",
            "Noto Sans CJK JP",
            "Noto Serif CJK JP"
        ]
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return preferred.filter { installed.contains($0) }
    }

    /// Font families that are good defaults for Korean text
    static var koreanFamilies: [String] {
        let preferred = [
            "Apple SD Gothic Neo",
            "AppleMyungjo",
            "Nanum Gothic",
            "NanumMyeongjo",
            "Noto Sans CJK KR",
            "Noto Serif CJK KR"
        ]
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return preferred.filter { installed.contains($0) }
    }
}
