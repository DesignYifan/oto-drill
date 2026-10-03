import SwiftUI

// 音声ドリルの iPhone アプリ：公開ページを WKWebView で開き、iCloud のフォルダと AI（Groq）への口を足すだけの薄い殻。
// ⭕ ページを直せば iPhone も変わる（アプリの入れ直しは要らない）。作り方：vault の 20261001_oto-drill-app_実現方式.md「段4」
@main
struct OtoDrillApp: App {
    var body: some Scene {
        WindowGroup {
            WebScreen()
                .ignoresSafeArea()   // 時刻の帯とホームの帯までページを描く（ページ側が safe-area で余白を取る）
        }
    }
}
