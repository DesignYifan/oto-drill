"""「文法を使う」問い（書き換える・質問に答える）を、別のモデルに確かめさせる。

    python3 tools/verify_drills.py <drills_src.json> <教材のフォルダ>/drills.json

⭕ 2026-10-03 本人「定着する問い」B案：Claude が書き、別のモデル（Groq の qwen3.8-27b）が確かめ、通った物だけ出す。
⭕ 罠（わざと間違えた答え。src の traps）を同じ束に混ぜる。罠を1つでも「正しい」としたら、その回の判定は使わない。
⭕ 通らなかった問いは checked=false で残し、理由を書く（⛔ 消さない。Claude が直して回し直す）。
⚠️ 検査役は正しい文にも × を出しがち（AITeam_モデル台帳 ②.7）。落ちた問いは捨てずに見直す。

Groq には vault の ask_groq.py（枠の待ちとログを持つ）を通して投げる。場所は環境変数 OTO_ASK_GROQ で変えられる。
⛔ 鍵は ask_groq.py が ~/.config/groq/key から読む。ここには書かない。
"""
import json, os, random, re, subprocess, sys, tempfile, time
from pathlib import Path

ASK = os.environ.get("OTO_ASK_GROQ", str(Path.home() / "Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian/008_project/AITeam/scripts/ask_groq.py"))
BATCH = 8
PAUSE = 65   # ⛔ qwen3.8-27b は返答だけで1分1,000トークン（OTPM）。束ごとに1分あける（2026-10-03 に 429 を踏んだ）

PROMPT = """あなたはベトナム語（北部標準）の文法を厳しく確かめる校閲者です。日本語を話す初級の学習者向けの問題を確かめます。
各問いには「元の文」「指示」「答え」「ほかの答え」「答えの意味」があります。次の3つを確かめてください。
1. 答えとほかの答えは、文法として正しく自然なベトナム語か（1つでも誤りがあれば ok=false）
2. 答えは、指示どおりに元の文を書き換えたもの、または元の文（質問）への指示どおりの答えになっているか
3. 答えの意味（日本語）は、答えの意味と合っているか
厳しく見てください。語順・類別詞・là の使い方・否定の位置に特に注意してください。
JSON の配列だけを返してください。形：[{"id": "…", "ok": true/false, "problem": "問題があれば日本語で短く。無ければ空"}]

問い：
"""


def ask(items):
    body = PROMPT + json.dumps([{k: it[k] for k in ("id", "base", "instr", "answer", "alts", "ja")} for it in items], ensure_ascii=False, indent=0)
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(body)
    out = subprocess.run([sys.executable, ASK, "--prompt", "@" + f.name, "--max-tokens", "2000"], capture_output=True, text=True)
    os.unlink(f.name)
    m = re.search(r"\[\s*\{.*\}\s*\]", out.stdout, re.S)
    if not m:
        raise RuntimeError("答えの形が読めない：" + (out.stdout[-400:] or out.stderr[-400:]))
    return {r["id"]: r for r in json.loads(m.group(0))}


def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(2)
    src = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    dst = Path(sys.argv[2])
    drills, traps = src["drills"], src.get("traps", [])
    if not traps:
        sys.exit("罠が無い。罠を混ぜずに判定させない（検査が生きているか分からない）")
    random.seed(3)
    order = drills[:]
    random.shuffle(order)
    batches = [order[i:i + BATCH] for i in range(0, len(order), BATCH)]
    # 罠を束に1つずつ配る（足りなければ使い回す）
    verdict, trap_fail = {}, []
    for k, b in enumerate(batches):
        t = dict(traps[k % len(traps)])
        group = b + [t]
        random.shuffle(group)
        v = None
        for tries in range(3):
            if k or tries:
                time.sleep(PAUSE)
            try:
                v = ask(group); break
            except Exception as e:
                print(f"束 {k + 1}/{len(batches)}：失敗（{tries + 1}回目）{str(e)[:120]}")
        if v is None:
            continue
        tv = v.get(t["id"])
        if not tv or tv.get("ok"):
            trap_fail.append(t["id"])
            print(f"束 {k + 1}/{len(batches)}：罠 {t['id']} を見逃した → この束の判定は使わない")
            continue
        for it in b:
            if it["id"] in v:
                verdict[it["id"]] = v[it["id"]]
        ok = sum(1 for it in b if verdict.get(it["id"], {}).get("ok"))
        print(f"束 {k + 1}/{len(batches)}：{ok}/{len(b)} 通過（罠は見抜いた）")
    out = []
    for it in drills:
        v = verdict.get(it["id"])
        row = {k: it[k] for k in ("id", "deck", "kind", "pattern", "base", "base_ja", "instr", "answer", "alts", "ja", "note")}
        row["checked"] = bool(v and v.get("ok"))
        if v and not v.get("ok"):
            row["problem"] = v.get("problem", "")
        if not v:
            row["problem"] = "判定なし（罠を見逃した束か、失敗した束）"
        out.append(row)
    dst.write_text(json.dumps({"version": 1, "book": src.get("book"), "checked_by": "groq qwen/qwen3.8-27b", "drills": out},
                              ensure_ascii=False, indent=1), encoding="utf-8")
    n = sum(r["checked"] for r in out)
    print(f"\n通過 {n}/{len(out)}・罠の見逃し {len(trap_fail)} → {dst}")
    for r in out:
        if not r["checked"]:
            print(f"  × {r['id']}  {r['answer']}  ／ {r.get('problem', '')}")


if __name__ == "__main__":
    main()
