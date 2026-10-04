#!/bin/zsh
# Mac の試す版（音声ドリル（試験用））を、Claude が確かめるときだけ立ち上げ、終わったら片付ける。
#   ./dev_mac.sh build                     試す版を作る（build.noindex に出す）
#   ./dev_mac.sh run [-selftest 1] [...]   試す版を開く（引数はそのままアプリへ。例：-page http://localhost:8793/?app=1）
#   ./dev_mac.sh stop                      閉じて、Mac のアプリ一覧から外す
#   ./dev_mac.sh release                   普段使いの版を作り、~/Applications/音声ドリル.app に入れ替える
#   ./dev_mac.sh iphone                    iPhone の版を作って入れる（7日ごとの入れ直し。iPhone のロックを外してもらう）
#
# ⭕ 2026-10-04 本人「毎回間違えた方を開いちゃうから、あなたが立ち上げる時だけそっちを開いてほしい」。
#   作ったものは build.noindex（Spotlight が見ない名前）に置き、開いたあとは stop で登録を外す。
#   × build/ に置くと、試す版・シミュレーター版・iPhone 版が全部「音声ドリル」として検索に出てきた
HERE="${0:A:h}"
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DEV="$HERE/build.noindex/mac/Build/Products/Debug-maccatalyst/OtoDrill.app"
cd "$HERE"
case "$1" in
  build)
    xcodebuild -project OtoDrill.xcodeproj -scheme OtoDrill -destination 'platform=macOS,variant=Mac Catalyst' \
      -configuration Debug -derivedDataPath build.noindex/mac build 2>&1 | grep -E " error:|BUILD"
    "$LS" -u "$DEV" 2>/dev/null ;;
  run)
    shift
    pkill -f "Debug-maccatalyst/OtoDrill.app/Contents/MacOS" 2>/dev/null; sleep 1
    open -n "$DEV" --args "$@" ;;
  stop)
    pkill -f "Debug-maccatalyst/OtoDrill.app/Contents/MacOS" 2>/dev/null
    for p in $(find "$HERE/build.noindex" -maxdepth 6 -name "OtoDrill.app" -type d 2>/dev/null); do "$LS" -u "$p" 2>/dev/null; done
    rm -f ~/Documents/oto.log
    echo "試す版を閉じて、一覧から外しました" ;;
  release)
    xcodebuild -project OtoDrill.xcodeproj -scheme OtoDrill -destination 'platform=macOS,variant=Mac Catalyst' \
      -configuration Release -derivedDataPath build.noindex/mac build 2>&1 | grep -E " error:|BUILD"
    pkill -f "Applications/音声ドリル.app/Contents/MacOS" 2>/dev/null; sleep 1
    rm -rf ~/Applications/音声ドリル.app
    ditto "$HERE/build.noindex/mac/Build/Products/Release-maccatalyst/OtoDrill.app" ~/Applications/音声ドリル.app
    for p in $(find "$HERE/build.noindex" -maxdepth 6 -name "OtoDrill.app" -type d 2>/dev/null); do "$LS" -u "$p" 2>/dev/null; done
    echo "~/Applications/音声ドリル.app を入れ替えました" ;;
  iphone)
    ./make_secrets.sh >/dev/null && xcodegen generate >/dev/null
    xcodebuild -project OtoDrill.xcodeproj -scheme OtoDrill -configuration Release -destination 'generic/platform=iOS' \
      -derivedDataPath build.noindex/ios -allowProvisioningUpdates build 2>&1 | grep -E " error:|BUILD"
    xcrun devicectl device install app --device 22BB3920-393A-5F45-BE14-99F1735BB8FE build.noindex/ios/Build/Products/Release-iphoneos/OtoDrill.app
    for p in $(find "$HERE/build.noindex" -maxdepth 6 -name "OtoDrill.app" -type d 2>/dev/null); do "$LS" -u "$p" 2>/dev/null; done ;;
  *) sed -n 2,7p "$0" ;;
esac
