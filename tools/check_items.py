"""教材パックの練習の項目（practice.json）に、抜き出しの失敗が混ざっていないかを見る。

    python3 tools/check_items.py <教材のフォルダ>            怪しい項目の一覧
    python3 tools/check_items.py <教材のフォルダ> --数だけ

⭕ 2026-10-03 本人「単語のところに単語以外の音も混ざっている。抽出するときに気をつけて」。
⭕ 見るもの：
  ・単語の組なのに文の形（? . ! で終わる・音節が多い）
  ・同じ言い回しが2回続く（「Bác sĩ Bác sĩ」）
  ・途中に大文字で始まる語がある＝2つの項目がつながった疑い（「Tên tôi là Tôi tên là」）
  ・同じ組の中に同じ文が2回
⛔ 直さない。一覧を出すだけ。直すのは教材ごとのスクリプト（~/Downloads/WIP/_course/<教材>/）の側。
"""
import json, re, sys, collections
from pathlib import Path

WORD = re.compile(r"単語|語$")


def syllables(t):
    return [w for w in re.split(r"\s+", re.sub(r"[.,!?;:\"'()…]", " ", t)) if w]


def issues(it, group):
    t = it.get("show", "").strip()
    sy = syllables(t)
    out = []
    if WORD.search(group or ""):
        if re.search(r"[?.!？。]$", t):
            out.append("単語の組なのに文の終わり方")
        elif len(sy) > 4:
            out.append(f"単語の組なのに {len(sy)} 音節")
    # ⚠️ 重ね語（từ từ・chiều chiều）や字の名前（A a）は正しい。2回目も大文字で始まるときだけ疑う（Gần Gần・Bác sĩ Bác sĩ）
    for n in range(1, 4):
        hit = next((i for i in range(len(sy) - 2 * n + 1)
                    if sy[i:i + n] == sy[i + n:i + 2 * n] and sy[i + n][:1].isupper() and len(sy[i]) > 1), None)
        if hit is not None:
            out.append("同じ言い回しが2回続く")
            break
    # 固有名詞（Việt Nam・Nhật Bản・人名）は大文字が続くので、前の語が小文字のときだけ見る
    for i in range(1, len(sy)):
        if sy[i][:1].isupper() and sy[i - 1][:1].islower() and not re.search(r"[.?!]$", sy[i - 1]):
            if sy[i].lower() in {w.lower() for w in sy[:i]}:
                out.append("途中に大文字の語（2つの項目がつながった疑い）")
                break
    return out


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__); sys.exit(2)
    only_count = "--数だけ" in a
    folder = Path([x for x in a if not x.startswith("--")][0])
    decks = json.loads((folder / "practice.json").read_text(encoding="utf-8"))["decks"]
    hits, total = [], 0
    for d in decks:
        seen = collections.Counter(i.get("show", "").strip().lower() for i in d.get("items", []))
        for it in d.get("items", []):
            total += 1
            iss = issues(it, it.get("group", ""))
            if seen[it.get("show", "").strip().lower()] > 1:
                iss.append("同じ組に同じ項目が2回")
            if iss:
                hits.append((d["id"], d.get("title", ""), it.get("group", ""), it.get("show", ""), iss))
    kinds = collections.Counter(x for h in hits for x in h[4])
    print(f"項目 {total}・怪しい {len(hits)}")
    for k, n in kinds.most_common():
        print(f"  {n:4d}  {k}")
    if not only_count:
        for did, title, g, show, iss in hits:
            print(f"\n■ {did}  {title}  〔{g}〕\n  {show}\n  → {'／'.join(iss)}")
    sys.exit(1 if hits else 0)


if __name__ == "__main__":
    main()
