import Foundation

// swiftlint:disable type_body_length file_length

/// Centralized UI string localization.
/// Every user-facing string lives here; the compiler enforces exhaustive switches.
enum L10n {

    // MARK: - Common

    enum Common {
        static func ok(_ l: UILanguage) -> String {
            switch l { case .ko: "확인"; case .en: "OK"; case .ja: "OK" }
        }
        static func cancel(_ l: UILanguage) -> String {
            switch l { case .ko: "취소"; case .en: "Cancel"; case .ja: "キャンセル" }
        }
        static func save(_ l: UILanguage) -> String {
            switch l { case .ko: "저장"; case .en: "Save"; case .ja: "保存" }
        }
        static func close(_ l: UILanguage) -> String {
            switch l { case .ko: "닫기"; case .en: "Close"; case .ja: "閉じる" }
        }
        static func delete(_ l: UILanguage) -> String {
            switch l { case .ko: "삭제"; case .en: "Delete"; case .ja: "削除" }
        }
        static func error(_ l: UILanguage) -> String {
            switch l { case .ko: "오류"; case .en: "Error"; case .ja: "エラー" }
        }
        static func unknownError(_ l: UILanguage) -> String {
            switch l { case .ko: "알 수 없는 오류"; case .en: "Unknown error"; case .ja: "不明なエラー" }
        }
    }

    // MARK: - Menu

    enum Menu {
        static func checkForUpdates(_ l: UILanguage) -> String {
            switch l { case .ko: "업데이트 확인…"; case .en: "Check for Updates…"; case .ja: "アップデートを確認…" }
        }
        static func newProject(_ l: UILanguage) -> String {
            switch l { case .ko: "새 프로젝트"; case .en: "New Project"; case .ja: "新規プロジェクト" }
        }
        static func openProject(_ l: UILanguage) -> String {
            switch l { case .ko: "프로젝트 열기..."; case .en: "Open Project..."; case .ja: "プロジェクトを開く..." }
        }
        static func saveProject(_ l: UILanguage) -> String {
            switch l { case .ko: "프로젝트 저장"; case .en: "Save Project"; case .ja: "プロジェクトを保存" }
        }
        static func saveProjectAs(_ l: UILanguage) -> String {
            switch l { case .ko: "다른 이름으로 저장..."; case .en: "Save Project As..."; case .ja: "名前を付けて保存..." }
        }
        static func importVideo(_ l: UILanguage) -> String {
            switch l { case .ko: "비디오 가져오기..."; case .en: "Import Video..."; case .ja: "動画を読み込む..." }
        }
    }

    // MARK: - Toolbar

    enum Toolbar {
        static func importVideo(_ l: UILanguage) -> String {
            switch l { case .ko: "비디오 가져오기"; case .en: "Import Video"; case .ja: "動画を読み込む" }
        }
        static func urlImport(_ l: UILanguage) -> String {
            switch l { case .ko: "URL 가져오기"; case .en: "URL Import"; case .ja: "URLインポート" }
        }
        static func languageHelp(_ l: UILanguage) -> String {
            switch l { case .ko: "주 언어 설정 (음성 인식 언어)"; case .en: "Primary language (speech recognition)"; case .ja: "主言語設定（音声認識言語）" }
        }
        static func autoAlign(_ l: UILanguage) -> String {
            switch l { case .ko: "자동 정렬"; case .en: "Auto-Align"; case .ja: "自動整列" }
        }
        static func aligning(_ l: UILanguage) -> String {
            switch l { case .ko: "정렬 중..."; case .en: "Aligning..."; case .ja: "整列中..." }
        }
        static func export(_ l: UILanguage) -> String {
            switch l { case .ko: "내보내기"; case .en: "Export"; case .ja: "書き出し" }
        }
        static func open(_ l: UILanguage) -> String {
            switch l { case .ko: "열기"; case .en: "Open"; case .ja: "開く" }
        }
        static func save(_ l: UILanguage) -> String {
            switch l { case .ko: "저장"; case .en: "Save"; case .ja: "保存" }
        }
        static func experimentalNotAvailable(_ l: UILanguage) -> String {
            switch l {
            case .ko: "실험적 파이프라인 사용 불가. 실행: cd Scripts && ./setup_alignment.sh"
            case .en: "Experimental pipeline not available. Run: cd Scripts && ./setup_alignment.sh"
            case .ja: "実験パイプライン利用不可。実行: cd Scripts && ./setup_alignment.sh"
            }
        }
    }

    // MARK: - Tabs

    enum Tab {
        static func block(_ l: UILanguage) -> String {
            switch l { case .ko: "블록"; case .en: "Block"; case .ja: "ブロック" }
        }
        static func trim(_ l: UILanguage) -> String {
            switch l { case .ko: "트림"; case .en: "Trim"; case .ja: "トリム" }
        }
        static func crop(_ l: UILanguage) -> String {
            switch l { case .ko: "크롭"; case .en: "Crop"; case .ja: "クロップ" }
        }
        static func style(_ l: UILanguage) -> String {
            switch l { case .ko: "스타일"; case .en: "Style"; case .ja: "スタイル" }
        }
        static func overlay(_ l: UILanguage) -> String {
            switch l { case .ko: "오버레이"; case .en: "Overlay"; case .ja: "オーバーレイ" }
        }
        static func ignore(_ l: UILanguage) -> String {
            switch l { case .ko: "무시"; case .en: "Ignore"; case .ja: "除外" }
        }
        static func info(_ l: UILanguage) -> String {
            switch l { case .ko: "정보"; case .en: "Info"; case .ja: "情報" }
        }
    }

    // MARK: - Block Inspector

    enum Block {
        static func title(_ l: UILanguage, index: Int) -> String {
            switch l { case .ko: "블록 #\(index)"; case .en: "Block #\(index)"; case .ja: "ブロック #\(index)" }
        }
        static func primaryLine(_ l: UILanguage) -> String {
            switch l { case .ko: "주 언어 (Line 1)"; case .en: "Primary (Line 1)"; case .ja: "主言語 (Line 1)" }
        }
        static func secondaryLine(_ l: UILanguage) -> String {
            switch l { case .ko: "부 언어 (Line 2)"; case .en: "Secondary (Line 2)"; case .ja: "副言語 (Line 2)" }
        }
        static func timing(_ l: UILanguage) -> String {
            switch l { case .ko: "타이밍"; case .en: "Timing"; case .ja: "タイミング" }
        }
        static func start(_ l: UILanguage) -> String {
            switch l { case .ko: "시작:"; case .en: "Start:"; case .ja: "開始:" }
        }
        static func end(_ l: UILanguage) -> String {
            switch l { case .ko: "종료:"; case .en: "End:"; case .ja: "終了:" }
        }
        static func notSet(_ l: UILanguage) -> String {
            switch l { case .ko: "미설정"; case .en: "Not set"; case .ja: "未設定" }
        }
        static func setNow(_ l: UILanguage) -> String {
            switch l { case .ko: "현재 설정"; case .en: "Set Now"; case .ja: "現在位置に設定" }
        }
        static func confidence(_ l: UILanguage) -> String {
            switch l { case .ko: "신뢰도:"; case .en: "Confidence:"; case .ja: "信頼度:" }
        }
        static func seekToStart(_ l: UILanguage) -> String {
            switch l { case .ko: "시작으로 이동"; case .en: "Seek to Start"; case .ja: "開始位置へ" }
        }
        static func seekToEnd(_ l: UILanguage) -> String {
            switch l { case .ko: "종료로 이동"; case .en: "Seek to End"; case .ja: "終了位置へ" }
        }
        static func correction(_ l: UILanguage) -> String {
            switch l { case .ko: "보정"; case .en: "Correction"; case .ja: "補正" }
        }
        static func setStartShiftFollowing(_ l: UILanguage) -> String {
            switch l {
            case .ko: "시작 설정 & 이후 블록 이동"
            case .en: "Set Start & Shift Following"
            case .ja: "開始設定＆以降シフト"
            }
        }
        static func setStartShiftHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "이 블록의 시작을 현재 시간으로 설정하고 이후 블록을 동일 간격으로 이동합니다"
            case .en: "Set this block's start to current time and shift all following blocks by the same delta"
            case .ja: "このブロックの開始を現在時刻に設定し、以降のブロックを同じ分だけシフトします"
            }
        }
        static func selectBlock(_ l: UILanguage) -> String {
            switch l { case .ko: "가사 블록을 선택하세요"; case .en: "Select a lyric block"; case .ja: "歌詞ブロックを選択" }
        }
        static func noTiming(_ l: UILanguage) -> String {
            switch l { case .ko: "타이밍 없음"; case .en: "No timing"; case .ja: "タイミングなし" }
        }
        static func manual(_ l: UILanguage) -> String {
            switch l { case .ko: "수동"; case .en: "Manual"; case .ja: "手動" }
        }
    }

    // MARK: - Anchor

    enum Anchor {
        static func anchorCorrection(_ l: UILanguage) -> String {
            switch l { case .ko: "앵커 & 재보정"; case .en: "Anchor & Correction"; case .ja: "アンカー＆補正" }
        }
        static func userAnchor(_ l: UILanguage) -> String {
            switch l { case .ko: "사용자 앵커"; case .en: "User Anchor"; case .ja: "ユーザーアンカー" }
        }
        static func releaseAnchor(_ l: UILanguage) -> String {
            switch l { case .ko: "앵커 해제"; case .en: "Release Anchor"; case .ja: "アンカー解除" }
        }
        static func autoAnchor(_ l: UILanguage) -> String {
            switch l { case .ko: "자동 앵커"; case .en: "Auto Anchor"; case .ja: "自動アンカー" }
        }
        static func promoteToUser(_ l: UILanguage) -> String {
            switch l { case .ko: "사용자 앵커로 승격"; case .en: "Promote to User Anchor"; case .ja: "ユーザーアンカーに昇格" }
        }
        static func promoteHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "이 자동 앵커를 사용자 앵커로 승격하여 재보정 기준점으로 사용합니다"
            case .en: "Promote this auto anchor to a user anchor for use as a correction reference point"
            case .ja: "この自動アンカーをユーザーアンカーに昇格し、補正の基準点として使用します"
            }
        }
        static func setAsAnchor(_ l: UILanguage) -> String {
            switch l { case .ko: "이 줄을 앵커로 고정"; case .en: "Set as Anchor"; case .ja: "アンカーに固定" }
        }
        static func setAsAnchorHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "이 블록의 타이밍을 신뢰할 수 있는 기준점으로 고정합니다"
            case .en: "Pin this block's timing as a trusted reference point"
            case .ja: "このブロックのタイミングを信頼できる基準点として固定します"
            }
        }
        static func manuallyAdjustedHint(_ l: UILanguage) -> String {
            switch l {
            case .ko: "수동 조정됨 — 앵커로 고정 권장"
            case .en: "Manually adjusted — recommend setting as anchor"
            case .ja: "手動調整済み — アンカー固定を推奨"
            }
        }
        static func correctBetween(_ l: UILanguage) -> String {
            switch l { case .ko: "이전 앵커 ~ 다음 앵커 재보정"; case .en: "Correct Between Anchors"; case .ja: "前後アンカー間を補正" }
        }
        static func correctBetweenHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "양쪽 앵커 사이의 블록 타이밍을 비례 배분합니다"
            case .en: "Redistribute block timing proportionally between surrounding anchors"
            case .ja: "両側のアンカー間のブロックタイミングを比例配分します"
            }
        }
        static func correctAll(_ l: UILanguage) -> String {
            switch l { case .ko: "전체 앵커 구간 재보정"; case .en: "Correct All Anchor Regions"; case .ja: "全アンカー区間を補正" }
        }
        static func correctAllHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "모든 앵커 쌍 사이의 블록 타이밍을 재보정합니다"
            case .en: "Recalibrate block timing between all anchor pairs"
            case .ja: "すべてのアンカーペア間のブロックタイミングを再補正します"
            }
        }
        static func localRealign(_ l: UILanguage) -> String {
            switch l {
            case .ko: "이 구간 재정렬 (레거시 엔진)"
            case .en: "Re-align Region (Legacy)"
            case .ja: "この区間を再整列（レガシー）"
            }
        }
        static func localRealignHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "이전~다음 앵커 사이를 whisper-cpp로 다시 정렬합니다"
            case .en: "Re-align between surrounding anchors using whisper-cpp"
            case .ja: "前後アンカー間をwhisper-cppで再整列します"
            }
        }
    }

    // MARK: - Crop Inspector

    enum Crop {
        static func settings(_ l: UILanguage) -> String {
            switch l { case .ko: "크롭 설정"; case .en: "Crop Settings"; case .ja: "クロップ設定" }
        }
        static func mode(_ l: UILanguage) -> String {
            switch l { case .ko: "모드"; case .en: "Mode"; case .ja: "モード" }
        }
        static func modeVertical(_ l: UILanguage) -> String {
            switch l { case .ko: "세로모드"; case .en: "Vertical"; case .ja: "縦モード" }
        }
        static func modeHorizontal(_ l: UILanguage) -> String {
            switch l { case .ko: "가로모드"; case .en: "Horizontal"; case .ja: "横モード" }
        }
        static func horizontalPosition(_ l: UILanguage) -> String {
            switch l { case .ko: "수평 위치"; case .en: "Horizontal Position"; case .ja: "水平位置" }
        }
        static func verticalPosition(_ l: UILanguage) -> String {
            switch l { case .ko: "수직 위치"; case .en: "Vertical Position"; case .ja: "垂直位置" }
        }
        static func videoPosition(_ l: UILanguage) -> String {
            switch l { case .ko: "영상 위치"; case .en: "Video Position"; case .ja: "映像位置" }
        }
        static func centerH(_ l: UILanguage) -> String {
            switch l { case .ko: "수평 중앙"; case .en: "Center H"; case .ja: "水平中央" }
        }
        static func centerV(_ l: UILanguage) -> String {
            switch l { case .ko: "수직 중앙"; case .en: "Center V"; case .ja: "垂直中央" }
        }
        static func zoom(_ l: UILanguage) -> String {
            switch l { case .ko: "줌"; case .en: "Zoom"; case .ja: "ズーム" }
        }
        static func resetZoom(_ l: UILanguage) -> String {
            switch l { case .ko: "줌 초기화"; case .en: "Reset Zoom"; case .ja: "ズームリセット" }
        }
        static func blur(_ l: UILanguage) -> String {
            switch l { case .ko: "블러"; case .en: "Blur"; case .ja: "ブラー" }
        }
        static func blurWeak(_ l: UILanguage) -> String {
            switch l { case .ko: "약"; case .en: "Low"; case .ja: "弱" }
        }
        static func blurStrong(_ l: UILanguage) -> String {
            switch l { case .ko: "강"; case .en: "High"; case .ja: "強" }
        }
        static func blurIntensity(_ l: UILanguage, value: Int) -> String {
            switch l {
            case .ko: "배경 블러 강도: \(value)"
            case .en: "Background blur: \(value)"
            case .ja: "背景ブラー強度: \(value)"
            }
        }
        static func output(_ l: UILanguage) -> String {
            switch l { case .ko: "출력"; case .en: "Output"; case .ja: "出力" }
        }
    }

    // MARK: - Style Inspector

    enum Style {
        static func subtitleStyle(_ l: UILanguage) -> String {
            switch l { case .ko: "자막 스타일"; case .en: "Subtitle Style"; case .ja: "字幕スタイル" }
        }
        static func presets(_ l: UILanguage) -> String {
            switch l { case .ko: "프리셋"; case .en: "Presets"; case .ja: "プリセット" }
        }
        static func applyPreset(_ l: UILanguage) -> String {
            switch l { case .ko: "프리셋 적용"; case .en: "Apply Preset"; case .ja: "プリセット適用" }
        }
        static func noPresets(_ l: UILanguage) -> String {
            switch l { case .ko: "저장된 프리셋 없음"; case .en: "No presets saved"; case .ja: "保存されたプリセットなし" }
        }
        static func saveCurrentStyle(_ l: UILanguage) -> String {
            switch l { case .ko: "현재 스타일 저장"; case .en: "Save Current Style"; case .ja: "現在のスタイルを保存" }
        }
        static func manage(_ l: UILanguage) -> String {
            switch l { case .ko: "관리"; case .en: "Manage"; case .ja: "管理" }
        }
        static func primaryFont(_ l: UILanguage) -> String {
            switch l { case .ko: "주 언어 폰트 (Line 1)"; case .en: "Primary Font (Line 1)"; case .ja: "主言語フォント (Line 1)" }
        }
        static func secondaryFont(_ l: UILanguage) -> String {
            switch l { case .ko: "부 언어 폰트 (Line 2)"; case .en: "Secondary Font (Line 2)"; case .ja: "副言語フォント (Line 2)" }
        }
        static func size(_ l: UILanguage) -> String {
            switch l { case .ko: "크기:"; case .en: "Size:"; case .ja: "サイズ:" }
        }
        static func appearance(_ l: UILanguage) -> String {
            switch l { case .ko: "외관"; case .en: "Appearance"; case .ja: "外観" }
        }
        static func outline(_ l: UILanguage) -> String {
            switch l { case .ko: "외곽선:"; case .en: "Outline:"; case .ja: "アウトライン:" }
        }
        static func shadow(_ l: UILanguage) -> String {
            switch l { case .ko: "그림자"; case .en: "Shadow"; case .ja: "シャドウ" }
        }
        static func position(_ l: UILanguage) -> String {
            switch l { case .ko: "위치"; case .en: "Position"; case .ja: "位置" }
        }
        static func bottom(_ l: UILanguage) -> String {
            switch l { case .ko: "하단:"; case .en: "Bottom:"; case .ja: "下部:" }
        }
        static func gap(_ l: UILanguage) -> String {
            switch l { case .ko: "간격:"; case .en: "Gap:"; case .ja: "間隔:" }
        }
        static func recommended(_ l: UILanguage) -> String {
            switch l { case .ko: "추천"; case .en: "Recommended"; case .ja: "おすすめ" }
        }
        static func allFonts(_ l: UILanguage) -> String {
            switch l { case .ko: "전체 폰트"; case .en: "All Fonts"; case .ja: "全フォント" }
        }
        static func colorWhite(_ l: UILanguage) -> String {
            switch l { case .ko: "흰색"; case .en: "White"; case .ja: "白" }
        }
        static func colorCyan(_ l: UILanguage) -> String {
            switch l { case .ko: "시안"; case .en: "Cyan"; case .ja: "シアン" }
        }
        static func colorYellow(_ l: UILanguage) -> String {
            switch l { case .ko: "노란색"; case .en: "Yellow"; case .ja: "黄色" }
        }
        static func colorMint(_ l: UILanguage) -> String {
            switch l { case .ko: "민트"; case .en: "Mint"; case .ja: "ミント" }
        }
        static func colorPink(_ l: UILanguage) -> String {
            switch l { case .ko: "핑크"; case .en: "Pink"; case .ja: "ピンク" }
        }
    }

    // MARK: - Preset Sheets

    enum Preset {
        static func saveTitle(_ l: UILanguage) -> String {
            switch l {
            case .ko: "현재 스타일을 프리셋으로 저장"
            case .en: "Save Current Style as Preset"
            case .ja: "現在のスタイルをプリセットとして保存"
            }
        }
        static func presetName(_ l: UILanguage) -> String {
            switch l { case .ko: "프리셋 이름"; case .en: "Preset Name"; case .ja: "プリセット名" }
        }
        static func saveNote(_ l: UILanguage) -> String {
            switch l {
            case .ko: "자막 스타일과 오버레이 스타일이 저장됩니다.\n곡 제목/아티스트 텍스트는 포함되지 않습니다."
            case .en: "Subtitle and overlay styles will be saved.\nSong title/artist text is not included."
            case .ja: "字幕スタイルとオーバーレイスタイルが保存されます。\n曲タイトル/アーティストテキストは含まれません。"
            }
        }
        static func enterName(_ l: UILanguage) -> String {
            switch l { case .ko: "이름을 입력하세요."; case .en: "Please enter a name."; case .ja: "名前を入力してください。" }
        }
        static func duplicateName(_ l: UILanguage) -> String {
            switch l {
            case .ko: "이미 같은 이름의 프리셋이 있습니다."
            case .en: "A preset with this name already exists."
            case .ja: "同じ名前のプリセットが既に存在します。"
            }
        }
        static func manageTitle(_ l: UILanguage) -> String {
            switch l { case .ko: "프리셋 관리"; case .en: "Manage Presets"; case .ja: "プリセット管理" }
        }
        static func noPresetsStored(_ l: UILanguage) -> String {
            switch l { case .ko: "저장된 프리셋이 없습니다."; case .en: "No presets stored."; case .ja: "保存されたプリセットはありません。" }
        }
        static func name(_ l: UILanguage) -> String {
            switch l { case .ko: "이름"; case .en: "Name"; case .ja: "名前" }
        }
        static func apply(_ l: UILanguage) -> String {
            switch l { case .ko: "적용"; case .en: "Apply"; case .ja: "適用" }
        }
        static func rename(_ l: UILanguage) -> String {
            switch l { case .ko: "이름 변경"; case .en: "Rename"; case .ja: "名前変更" }
        }
        static func duplicate(_ l: UILanguage) -> String {
            switch l { case .ko: "복제"; case .en: "Duplicate"; case .ja: "複製" }
        }
        static func copySuffix(_ l: UILanguage) -> String {
            switch l { case .ko: " (복사)"; case .en: " (Copy)"; case .ja: "（コピー）" }
        }
    }

    // MARK: - Trim Inspector

    enum Trim {
        static func settings(_ l: UILanguage) -> String {
            switch l { case .ko: "트림 설정"; case .en: "Trim Settings"; case .ja: "トリム設定" }
        }
        static func importVideoFirst(_ l: UILanguage) -> String {
            switch l { case .ko: "비디오를 먼저 가져오세요"; case .en: "Import a video first"; case .ja: "先に動画を読み込んでください" }
        }
        static func trimStart(_ l: UILanguage) -> String {
            switch l { case .ko: "시작 지점"; case .en: "Trim Start"; case .ja: "トリム開始" }
        }
        static func trimEnd(_ l: UILanguage) -> String {
            switch l { case .ko: "종료 지점"; case .en: "Trim End"; case .ja: "トリム終了" }
        }
        static func setToCurrent(_ l: UILanguage) -> String {
            switch l { case .ko: "현재 위치로"; case .en: "Set to Current"; case .ja: "現在位置に設定" }
        }
        static func duration(_ l: UILanguage) -> String {
            switch l { case .ko: "길이"; case .en: "Duration"; case .ja: "再生時間" }
        }
        static func range(_ l: UILanguage) -> String {
            switch l { case .ko: "범위"; case .en: "Range"; case .ja: "範囲" }
        }
        static func resetTrim(_ l: UILanguage) -> String {
            switch l { case .ko: "트림 초기화 (전체 길이)"; case .en: "Reset Trim (Full Duration)"; case .ja: "トリムリセット（全長）" }
        }
    }

    // MARK: - Overlay Inspector

    enum Overlay {
        static func title(_ l: UILanguage) -> String {
            switch l { case .ko: "제목/아티스트 오버레이"; case .en: "Title / Artist Overlay"; case .ja: "タイトル/アーティスト オーバーレイ" }
        }
        static func enableOverlay(_ l: UILanguage) -> String {
            switch l { case .ko: "오버레이 활성화"; case .en: "Enable Overlay"; case .ja: "オーバーレイを有効化" }
        }
        static func titleLabel(_ l: UILanguage) -> String {
            switch l { case .ko: "제목"; case .en: "Title"; case .ja: "タイトル" }
        }
        static func songTitle(_ l: UILanguage) -> String {
            switch l { case .ko: "곡 제목"; case .en: "Song title"; case .ja: "曲タイトル" }
        }
        static func artist(_ l: UILanguage) -> String {
            switch l { case .ko: "아티스트"; case .en: "Artist"; case .ja: "アーティスト" }
        }
        static func artistName(_ l: UILanguage) -> String {
            switch l { case .ko: "아티스트 이름"; case .en: "Artist name"; case .ja: "アーティスト名" }
        }
        static func font(_ l: UILanguage) -> String {
            switch l { case .ko: "폰트"; case .en: "Font"; case .ja: "フォント" }
        }
        static func background(_ l: UILanguage) -> String {
            switch l { case .ko: "배경"; case .en: "Background"; case .ja: "背景" }
        }
        static func opacity(_ l: UILanguage) -> String {
            switch l { case .ko: "불투명도:"; case .en: "Opacity:"; case .ja: "不透明度:" }
        }
        static func radius(_ l: UILanguage) -> String {
            switch l { case .ko: "모서리:"; case .en: "Radius:"; case .ja: "角丸:" }
        }
        static func top(_ l: UILanguage) -> String {
            switch l { case .ko: "상단:"; case .en: "Top:"; case .ja: "上部:" }
        }
        static func left(_ l: UILanguage) -> String {
            switch l { case .ko: "좌측:"; case .en: "Left:"; case .ja: "左:" }
        }
        static func padding(_ l: UILanguage) -> String {
            switch l { case .ko: "패딩"; case .en: "Padding"; case .ja: "パディング" }
        }
    }

    // MARK: - Ignore Regions

    enum Ignore {
        static func title(_ l: UILanguage) -> String {
            switch l { case .ko: "무시 구간"; case .en: "Ignore Regions"; case .ja: "除外区間" }
        }
        static func help(_ l: UILanguage) -> String {
            switch l {
            case .ko: "음성 인식에서 제외할 구간을 설정합니다.\n(MC 멘트, 관객 대화 등)"
            case .en: "Set time ranges to exclude from speech recognition.\n(MC talk, audience interaction, etc.)"
            case .ja: "音声認識から除外する区間を設定します。\n（MC トーク、観客の会話など）"
            }
        }
        static func addAtCurrent(_ l: UILanguage) -> String {
            switch l { case .ko: "현재 위치에 무시 구간 추가"; case .en: "Add Ignore Region at Current"; case .ja: "現在位置に除外区間を追加" }
        }
        static func noRegions(_ l: UILanguage) -> String {
            switch l { case .ko: "설정된 무시 구간이 없습니다"; case .en: "No ignore regions set"; case .ja: "除外区間は設定されていません" }
        }
        static func label(_ l: UILanguage) -> String {
            switch l { case .ko: "라벨"; case .en: "Label"; case .ja: "ラベル" }
        }
        static func ignoreRegion(_ l: UILanguage) -> String {
            switch l { case .ko: "무시 구간"; case .en: "Ignore Region"; case .ja: "除外区間" }
        }
        static func startLabel(_ l: UILanguage) -> String {
            switch l { case .ko: "시작"; case .en: "Start"; case .ja: "開始" }
        }
        static func endLabel(_ l: UILanguage) -> String {
            switch l { case .ko: "종료"; case .en: "End"; case .ja: "終了" }
        }
        static func current(_ l: UILanguage) -> String {
            switch l { case .ko: "현재"; case .en: "Now"; case .ja: "現在" }
        }
        static func length(_ l: UILanguage, time: String) -> String {
            switch l { case .ko: "길이: \(time)"; case .en: "Length: \(time)"; case .ja: "長さ: \(time)" }
        }
        static func seekToRegion(_ l: UILanguage) -> String {
            switch l { case .ko: "이 구간으로 이동"; case .en: "Seek to Region"; case .ja: "この区間へ移動" }
        }
    }

    // MARK: - Info Inspector

    enum Info {
        static func projectInfo(_ l: UILanguage) -> String {
            switch l { case .ko: "프로젝트 정보"; case .en: "Project Info"; case .ja: "プロジェクト情報" }
        }
        static func project(_ l: UILanguage) -> String {
            switch l { case .ko: "프로젝트"; case .en: "Project"; case .ja: "プロジェクト" }
        }
        static func title(_ l: UILanguage) -> String {
            switch l { case .ko: "제목"; case .en: "Title"; case .ja: "タイトル" }
        }
        static func created(_ l: UILanguage) -> String {
            switch l { case .ko: "생성일"; case .en: "Created"; case .ja: "作成日" }
        }
        static func video(_ l: UILanguage) -> String {
            switch l { case .ko: "비디오"; case .en: "Video"; case .ja: "動画" }
        }
        static func resolution(_ l: UILanguage) -> String {
            switch l { case .ko: "해상도"; case .en: "Resolution"; case .ja: "解像度" }
        }
        static func frameRate(_ l: UILanguage) -> String {
            switch l { case .ko: "프레임 레이트"; case .en: "Frame Rate"; case .ja: "フレームレート" }
        }
        static func fileSize(_ l: UILanguage) -> String {
            switch l { case .ko: "파일 크기"; case .en: "File Size"; case .ja: "ファイルサイズ" }
        }
        static func tools(_ l: UILanguage) -> String {
            switch l { case .ko: "도구"; case .en: "Tools"; case .ja: "ツール" }
        }
        static func found(_ l: UILanguage) -> String {
            switch l { case .ko: "설치됨"; case .en: "Found"; case .ja: "インストール済み" }
        }
        static func notFound(_ l: UILanguage) -> String {
            switch l { case .ko: "미설치"; case .en: "Not found"; case .ja: "未インストール" }
        }
        static func installMissing(_ l: UILanguage) -> String {
            switch l {
            case .ko: "누락된 도구 설치 (Homebrew):"
            case .en: "Install missing tools via Homebrew:"
            case .ja: "不足ツールをHomebrewでインストール:"
            }
        }
        static func recheckTools(_ l: UILanguage) -> String {
            switch l { case .ko: "도구 재확인"; case .en: "Recheck Tools"; case .ja: "ツールを再確認" }
        }
    }

    // MARK: - Lyrics Panel

    enum Lyrics {
        static func lyrics(_ l: UILanguage) -> String {
            switch l { case .ko: "가사"; case .en: "Lyrics"; case .ja: "歌詞" }
        }
        static func blocks(_ l: UILanguage, count: Int) -> String {
            switch l { case .ko: "\(count) 블록"; case .en: "\(count) blocks"; case .ja: "\(count) ブロック" }
        }
        static func pasteEdit(_ l: UILanguage) -> String {
            switch l { case .ko: "가사 붙여넣기/편집"; case .en: "Paste/Edit Lyrics"; case .ja: "歌詞を貼り付け/編集" }
        }
        static func noLyrics(_ l: UILanguage) -> String {
            switch l { case .ko: "가사 없음"; case .en: "No lyrics yet"; case .ja: "歌詞なし" }
        }
        static func pasteLyrics(_ l: UILanguage) -> String {
            switch l { case .ko: "가사 붙여넣기"; case .en: "Paste Lyrics"; case .ja: "歌詞を貼り付け" }
        }
        static func pasteBilingual(_ l: UILanguage) -> String {
            switch l { case .ko: "이중 언어 가사 붙여넣기"; case .en: "Paste Bilingual Lyrics"; case .ja: "バイリンガル歌詞を貼り付け" }
        }
        static func formatHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "블록 사이는 빈 줄로 구분합니다. 주 언어만 입력하거나, 주 언어 + 부 언어 2줄로 입력할 수 있습니다."
            case .en: "Separate blocks with blank lines. Enter primary language only, or primary + secondary (2 lines per block)."
            case .ja: "ブロック間は空行で区切ります。主言語のみ、または主言語＋副言語の2行で入力できます。"
            }
        }
        static func parseImport(_ l: UILanguage) -> String {
            switch l { case .ko: "파싱 & 가져오기"; case .en: "Parse & Import"; case .ja: "解析＆取り込み" }
        }
    }

    // MARK: - Playback

    enum Playback {
        static func back5s(_ l: UILanguage) -> String {
            switch l { case .ko: "5초 뒤로 (Cmd+Left)"; case .en: "Back 5s (Cmd+Left)"; case .ja: "5秒戻る (Cmd+Left)" }
        }
        static func back1s(_ l: UILanguage) -> String {
            switch l { case .ko: "1초 뒤로"; case .en: "Back 1s"; case .ja: "1秒戻る" }
        }
        static func playPause(_ l: UILanguage) -> String {
            switch l { case .ko: "재생/일시정지 (Space)"; case .en: "Play/Pause (Space)"; case .ja: "再生/一時停止 (Space)" }
        }
        static func forward1s(_ l: UILanguage) -> String {
            switch l { case .ko: "1초 앞으로"; case .en: "Forward 1s"; case .ja: "1秒進む" }
        }
        static func forward5s(_ l: UILanguage) -> String {
            switch l { case .ko: "5초 앞으로 (Cmd+Right)"; case .en: "Forward 5s (Cmd+Right)"; case .ja: "5秒進む (Cmd+Right)" }
        }
        static func setStart(_ l: UILanguage) -> String {
            switch l { case .ko: "시작 설정"; case .en: "Set Start"; case .ja: "開始を設定" }
        }
        static func setStartHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "현재 시간으로 블록 시작 설정 (Cmd+[)"
            case .en: "Set block start to current time (Cmd+[)"
            case .ja: "現在時刻をブロック開始に設定 (Cmd+[)"
            }
        }
        static func setEnd(_ l: UILanguage) -> String {
            switch l { case .ko: "종료 설정"; case .en: "Set End"; case .ja: "終了を設定" }
        }
        static func setEndHelp(_ l: UILanguage) -> String {
            switch l {
            case .ko: "현재 시간으로 블록 종료 설정 (Cmd+])"
            case .en: "Set block end to current time (Cmd+])"
            case .ja: "現在時刻をブロック終了に設定 (Cmd+])"
            }
        }
    }

    // MARK: - Status Bar

    enum Status {
        static func preparingExport(_ l: UILanguage) -> String {
            switch l { case .ko: "내보내기 준비 중..."; case .en: "Preparing export..."; case .ja: "書き出し準備中..." }
        }
        static func exporting(_ l: UILanguage) -> String {
            switch l { case .ko: "내보내기 중..."; case .en: "Exporting..."; case .ja: "書き出し中..." }
        }
        static func exportComplete(_ l: UILanguage) -> String {
            switch l { case .ko: "내보내기 완료"; case .en: "Export complete"; case .ja: "書き出し完了" }
        }
        static func unsavedChanges(_ l: UILanguage) -> String {
            switch l { case .ko: "저장되지 않은 변경"; case .en: "Unsaved changes"; case .ja: "未保存の変更" }
        }
        // ViewModel status messages
        static func ignoreRegionAdded(_ l: UILanguage, from: String, to: String) -> String {
            switch l {
            case .ko: "무시 구간 추가됨: \(from)–\(to)"
            case .en: "Ignore region added: \(from)–\(to)"
            case .ja: "除外区間を追加: \(from)–\(to)"
            }
        }
        static func anchorSet(_ l: UILanguage, index: Int) -> String {
            switch l {
            case .ko: "블록 #\(index) 앵커 고정"
            case .en: "Block #\(index) anchor set"
            case .ja: "ブロック #\(index) アンカー固定"
            }
        }
        static func anchorReleased(_ l: UILanguage, index: Int) -> String {
            switch l {
            case .ko: "블록 #\(index) 앵커 해제"
            case .en: "Block #\(index) anchor released"
            case .ja: "ブロック #\(index) アンカー解除"
            }
        }
        static func needTwoAnchors(_ l: UILanguage) -> String {
            switch l {
            case .ko: "앵커가 2개 이상 필요합니다. 타이밍을 수정한 줄을 앵커로 고정하세요."
            case .en: "Need 2+ anchors. Set anchors on blocks with adjusted timing."
            case .ja: "アンカーが2つ以上必要です。タイミングを修正した行をアンカーに固定してください。"
            }
        }
        static func allCorrectionDone(_ l: UILanguage, anchors: Int, blocks: Int) -> String {
            switch l {
            case .ko: "앵커 \(anchors)개 사이 \(blocks)개 블록 재보정 완료"
            case .en: "\(blocks) blocks corrected between \(anchors) anchors"
            case .ja: "アンカー\(anchors)個の間の\(blocks)ブロックを補正完了"
            }
        }
        static func needSurroundingAnchors(_ l: UILanguage) -> String {
            switch l {
            case .ko: "선택한 블록 양쪽에 앵커가 필요합니다."
            case .en: "Need anchors on both sides of selected block."
            case .ja: "選択ブロックの両側にアンカーが必要です。"
            }
        }
        static func regionCorrectionDone(_ l: UILanguage, left: Int, right: Int, count: Int) -> String {
            switch l {
            case .ko: "앵커 #\(left) ~ #\(right) 사이 \(count)개 블록 재보정 완료"
            case .en: "\(count) blocks corrected between anchors #\(left)–#\(right)"
            case .ja: "アンカー #\(left)～#\(right) の間の\(count)ブロックを補正完了"
            }
        }
        static func importVideoFirst(_ l: UILanguage) -> String {
            switch l { case .ko: "비디오를 먼저 가져오세요."; case .en: "Import a video first."; case .ja: "先に動画を読み込んでください。" }
        }
        static func needTools(_ l: UILanguage) -> String {
            switch l { case .ko: "FFmpeg과 whisper-cpp가 필요합니다."; case .en: "FFmpeg and whisper-cpp are required."; case .ja: "FFmpegとwhisper-cppが必要です。" }
        }
        static func preparingRealign(_ l: UILanguage) -> String {
            switch l { case .ko: "구간 재정렬 준비 중..."; case .en: "Preparing re-alignment..."; case .ja: "区間再整列の準備中..." }
        }
        static func extractingAudio(_ l: UILanguage) -> String {
            switch l { case .ko: "오디오 추출 중..."; case .en: "Extracting audio..."; case .ja: "音声抽出中..." }
        }
        static func recognizingSpeech(_ l: UILanguage) -> String {
            switch l { case .ko: "음성 인식 중..."; case .en: "Recognizing speech..."; case .ja: "音声認識中..." }
        }
        static func realigning(_ l: UILanguage, from: Int, to: Int) -> String {
            switch l {
            case .ko: "블록 \(from)–\(to) 재정렬 중..."
            case .en: "Re-aligning blocks \(from)–\(to)..."
            case .ja: "ブロック \(from)–\(to) を再整列中..."
            }
        }
        static func realignComplete(_ l: UILanguage, from: Int, to: Int) -> String {
            switch l {
            case .ko: "블록 \(from)–\(to) 구간 재정렬 완료"
            case .en: "Blocks \(from)–\(to) re-alignment complete"
            case .ja: "ブロック \(from)–\(to) の区間再整列完了"
            }
        }
        static func presetApplied(_ l: UILanguage, name: String) -> String {
            switch l { case .ko: "프리셋 적용됨: \(name)"; case .en: "Preset applied: \(name)"; case .ja: "プリセット適用: \(name)" }
        }
        static func presetSaved(_ l: UILanguage, name: String) -> String {
            switch l { case .ko: "프리셋 저장됨: \(name)"; case .en: "Preset saved: \(name)"; case .ja: "プリセット保存: \(name)" }
        }
        static func featureDisabled(_ l: UILanguage) -> String {
            switch l { case .ko: "이 기능은 현재 비활성화 상태입니다."; case .en: "This feature is currently disabled."; case .ja: "この機能は現在無効です。" }
        }
    }

    // MARK: - URL Import

    enum URLImport {
        static func title(_ l: UILanguage) -> String {
            switch l { case .ko: "URL 가져오기"; case .en: "URL Import"; case .ja: "URLインポート" }
        }
        static func enterURL(_ l: UILanguage) -> String {
            switch l {
            case .ko: "다운로드할 비디오 URL을 입력하세요."
            case .en: "Enter a video URL to download and import."
            case .ja: "ダウンロードする動画のURLを入力してください。"
            }
        }
        static func validating(_ l: UILanguage) -> String {
            switch l { case .ko: "확인 중..."; case .en: "Validating..."; case .ja: "確認中..." }
        }
        static func downloadComplete(_ l: UILanguage) -> String {
            switch l {
            case .ko: "다운로드 완료, 가져오는 중..."
            case .en: "Download complete, importing..."
            case .ja: "ダウンロード完了、取り込み中..."
            }
        }
        static func downloadImport(_ l: UILanguage) -> String {
            switch l { case .ko: "다운로드 & 가져오기"; case .en: "Download & Import"; case .ja: "ダウンロード＆取り込み" }
        }
        static func disabled(_ l: UILanguage) -> String {
            switch l {
            case .ko: "이 기능은 현재 비활성화 상태입니다."
            case .en: "This feature is currently disabled."
            case .ja: "この機能は現在無効です。"
            }
        }
        static func installScript(_ l: UILanguage) -> String {
            switch l {
            case .ko: "yt_download.sh 스크립트를 아래 경로에 설치하세요:"
            case .en: "Install the yt_download.sh script at:"
            case .ja: "yt_download.shスクリプトを以下のパスにインストールしてください："
            }
        }
    }

    // MARK: - Video Preview

    enum Preview {
        static func importToStart(_ l: UILanguage) -> String {
            switch l { case .ko: "비디오를 가져와서 시작하세요"; case .en: "Import a video to get started"; case .ja: "動画を読み込んで始めましょう" }
        }
        static func importHint(_ l: UILanguage) -> String {
            switch l {
            case .ko: "파일 > 비디오 가져오기 또는 위의 '비디오 가져오기' 버튼 클릭"
            case .en: "File > Import Video or click 'Import Video' above"
            case .ja: "ファイル > 動画を読み込む、または上の「動画を読み込む」ボタンをクリック"
            }
        }
    }

    // MARK: - PrimaryLanguage display names

    enum PrimaryLang {
        static func displayName(_ lang: PrimaryLanguage, _ l: UILanguage) -> String {
            switch (lang, l) {
            case (.japanese, _): return "日本語"
            case (.korean, _): return "한국어"
            case (.english, _): return "English"
            case (.chinese, _): return "中文"
            case (.auto, .ko): return "다중언어 (Auto)"
            case (.auto, .en): return "Multi-language (Auto)"
            case (.auto, .ja): return "多言語 (Auto)"
            }
        }
    }

    // MARK: - CropMode display names

    enum CropModeName {
        static func displayName(_ mode: CropMode, _ l: UILanguage) -> String {
            switch (mode, l) {
            case (.vertical, .ko): return "세로모드"
            case (.vertical, .en): return "Vertical"
            case (.vertical, .ja): return "縦モード"
            case (.horizontal, .ko): return "가로모드"
            case (.horizontal, .en): return "Horizontal"
            case (.horizontal, .ja): return "横モード"
            }
        }
    }
}

// swiftlint:enable type_body_length file_length
