"""質問帳を読み、確かめた答えを足す（Claude が使う）。

    python3 tools/qa.py 未回答 <音声ドリルのフォルダ> [--lang vi]
    python3 tools/qa.py 答える <音声ドリルのフォルダ> --qid <id> --lang vi --status verified --answer "…" [--note "…"]
    python3 tools/qa.py よく聞く <音声ドリルのフォルダ> [--lang vi]     何度も聞いた文・語の一覧

フォルダは vault の 008_project/LanguageCourse/音声ドリル/（iCloud で Mac と iPhone に連動）。
⭕ 質問は端末ごとのファイル 質問帳/<言語>/<端末>.jsonl。答えは 質問帳/<言語>/claude.jsonl に足すだけ（⛔ 端末のファイルを書き換えない）。
⭕ status：verified（一次資料か文法メモで確かめた）／unverifiable（確かめられなかった。そう書く）。
⛔ 確かめていないのに verified にしない。出典を note に書く。
"""
import argparse, json, time, collections
from pathlib import Path


def read(folder, lang):
    d = Path(folder) / "質問帳" / lang
    qs, ans, later = [], {}, {}
    if not d.exists():
        return qs, ans
    for f in sorted(d.glob("*.jsonl")):
        for line in f.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            e = json.loads(line)
            if e.get("k") == "q":
                qs.append(e)
            elif e.get("k") == "a":
                ans[e["qid"]] = e
            elif e.get("k") == "ai":   # 答え待ちだった問いに、あとから AI が答えた
                later[e["qid"]] = e
    for q in qs:
        if not q.get("ai") and q["id"] in later:
            q["ai"], q["model"] = later[q["id"]]["ai"], later[q["id"]].get("model")
    return sorted(qs, key=lambda e: e["t"]), ans


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["未回答", "答える", "よく聞く"])
    ap.add_argument("folder")
    ap.add_argument("--lang", default="vi")
    ap.add_argument("--qid"); ap.add_argument("--status", choices=["verified", "unverifiable"])
    ap.add_argument("--answer"); ap.add_argument("--note", default="")
    a = ap.parse_args()
    qs, ans = read(a.folder, a.lang)
    if a.cmd == "未回答":
        todo = [q for q in qs if q["id"] not in ans]
        print(f"質問 {len(qs)}・答え待ち {len(todo)}")
        for q in todo:
            print(f"\n■ {q['id']}  {time.strftime('%Y-%m-%d %H:%M', time.localtime(q['t'] / 1000))}  {q.get('book')}  {q.get('dev')}")
            print(f"  文：{q['text']}\n  訳：{q.get('ja', '')}\n  問：{q['q']}")
            if q.get("ai"):
                print(f"  AI（{q.get('model')}・未確認）：{q['ai'][:300]}")
    elif a.cmd == "答える":
        if not (a.qid and a.status and a.answer):
            ap.error("--qid --status --answer が要る")
        if a.qid not in {q["id"] for q in qs}:
            ap.error(f"その質問はありません：{a.qid}")
        out = Path(a.folder) / "質問帳" / a.lang / "claude.jsonl"
        e = {"id": f"claude.a{int(time.time() * 1000)}", "t": int(time.time() * 1000), "dev": "claude", "k": "a", "lang": a.lang,
             "qid": a.qid, "status": a.status, "answer": a.answer, "note": a.note}
        with out.open("a", encoding="utf-8") as f:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
        print("足した:", out)
    else:
        c = collections.Counter(q["text"] for q in qs)
        for t, n in c.most_common(30):
            print(f"{n:3d}  {t}")


if __name__ == "__main__":
    main()
