#!/bin/zsh
# 音声ドリルを Mac で開く（ダブルクリック1つ）
#
# ・ページを手元から配る        http://localhost:8790/
# ・Chrome で開く（フォルダの読み書きは Chrome・Edge だけ）
#
# ⭕ 2026-11-19 「AI に聞く」を外したので、手元のモデル（mlx の Qwen3.8-27B・8791番）はもう立てない。
#    前の版は _旧版/2026-11-19_AIに聞く/oto-drill.command。疑問は隣の Gemini に Chrome で聞く（本人 2026-11-19）。
# ⭕ 記録は iCloud のフォルダで連動するので、公開ページと手元で分かれない。
# ⭕ このウィンドウを閉じるか control+C で止まる。
# 実現方式：vault 008_project/AppBuilding/specs/20261001_oto-drill-app_実現方式.md

HERE="${0:A:h:h}"            # このファイルの1つ上（リポジトリの根）
PAGE_PORT=8790
pids=()
cleanup(){ for p in $pids; do pkill -P $p 2>/dev/null; kill $p 2>/dev/null; done; echo "\n止めました。"; }
trap cleanup EXIT INT TERM

up(){ curl -s -o /dev/null -m 1 "$1" }

echo "音声ドリル：$HERE"
if up "http://localhost:$PAGE_PORT/"; then
  echo "・ページ：もう立っています"
else
  # ⭕ 毎回いまのページを配る（Chrome が古いページを覚えて出していた：2026-10-03）
  python3 -c '
import http.server, functools, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store"); super().end_headers()
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
' $PAGE_PORT "$HERE" >/dev/null 2>&1 &
  pids+=($!); echo "・ページ：立てました（$PAGE_PORT）"
fi

sleep 1
open -a "Google Chrome" "http://localhost:$PAGE_PORT/"
echo "\n開きました。使い終わったら、このウィンドウを閉じてください。"
wait
