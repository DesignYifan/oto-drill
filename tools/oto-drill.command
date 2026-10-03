#!/bin/zsh
# 音声ドリルを Mac で開く（ダブルクリック1つ）
#
# ・ページを手元から配る        http://localhost:8790/
# ・手元のモデル（AI）を立てる   http://localhost:8791/  Qwen3.8-27B-8bit（mlx）
# ・Chrome で開く（フォルダの読み書きは Chrome・Edge だけ）
#
# ⭕ なぜ手元から開くか：公開ページ（https）からは手元のモデルを呼べない（ブラウザが止める）。
#    手元から開けば呼べる（2026-10-02 に試した）。記録は iCloud のフォルダで連動するので、公開ページと手元で分かれない。
# ⭕ このウィンドウを閉じるか control+C で、両方とも止まる。
# 実現方式：vault 008_project/AppBuilding/specs/20261001_oto-drill-app_実現方式.md

HERE="${0:A:h:h}"            # このファイルの1つ上（リポジトリの根）
PAGE_PORT=8790
AI_PORT=8791
MODEL="mlx-community/Qwen3.8-27B-8bit"
MLX="$HOME/.local/bin/mlx_lm.server"

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

if up "http://localhost:$AI_PORT/v1/models"; then
  echo "・AI：もう立っています"
elif [[ -x "$MLX" ]]; then
  # ⭕ HF_HUB_OFFLINE：モデルは手元にあるので、読み込むたびにネットへ確かめに行かない（2026-10-03 そこで落ちていた）
  # ⭕ 落ちたら立て直す（ページは10秒ごとに見直すので、立てば自然につながる）
  ( while true; do
      HF_HUB_OFFLINE=1 "$MLX" --model "$MODEL" --host 127.0.0.1 --port $AI_PORT >>/tmp/oto-drill-ai.log 2>&1
      echo "$(date '+%H:%M:%S') AI が止まったので立て直します" >>/tmp/oto-drill-ai.log; sleep 3
    done ) &
  pids+=($!); echo "・AI：立てました（$AI_PORT・メモリを約29GB使います）"
  for i in {1..30}; do up "http://localhost:$AI_PORT/v1/models" && break; sleep 1; done
  up "http://localhost:$AI_PORT/v1/models" && echo "・AI：答えられます" || echo "・AI：まだ起きていません（起きたらページが自分で気づきます。記録は /tmp/oto-drill-ai.log）"
else
  echo "・AI：mlx_lm.server が見つかりません。AI なしで開きます（質問は質問帳に貯まります）"
fi

sleep 1
open -a "Google Chrome" "http://localhost:$PAGE_PORT/"
echo "\n開きました。使い終わったら、このウィンドウを閉じてください。"
wait
