#!/usr/bin/env python3
"""音声ドリルのページを http://127.0.0.1:8790/ で配る（launchd が常駐させる）。

○ 2026-11-22 から launchd（local.otodrill.web）が Mac にログインしているあいだ動かす。
  前は oto-drill.command をダブルクリックして立てていたので、閉じると「接続が拒否されました」になった（本人 2026-11-22）。
○ 毎回いまのページを配る（Cache-Control: no-store。Chrome が古いページを覚えて出していた：2026-10-03）。
"""
import functools, http.server, os, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8790
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def log_message(self, *a):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", PORT), functools.partial(H, directory=ROOT)).serve_forever()
