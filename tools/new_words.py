"""課ごとに「初めて出る語」を数える。課の手引き（聴く前に）の材料。

    python3 tools/new_words.py <教材のフォルダ> <課の id>          その課の初めて出る語（JSON）
    python3 tools/new_words.py <教材のフォルダ> --全部              全部の課の数だけ

⭕ 2026-10-04 本人「説明してない単語はどれなのか、そういうのはちゃんとあった方がいい」。
⭕ 語の切れ目と訳は gloss.json（文ごとの語の組）から取る。課の並びは practice.json の decks の順。
⭕ 数え方：その課の文に出る語 − 前の課までに出た語。そのうち、その課の単語欄（group が「単語」）に無いものに
  「単語欄に無い」の印を付ける。単語欄の語は、文に出ていなくても初めて出る語に入れる。
⛔ 教材のパスはここに書かない（引数で渡す）。
"""
import json, re, sys
from pathlib import Path

PUNCT = re.compile(r"[\s.,!?;:…\"“”'()（）、。]+")


def norm(t):
    return PUNCT.sub(" ", (t or "").lower()).strip()


class Seg:
    """語の切り方をそろえる：gloss・単語欄・lexicon に出てくる複数音節の語を集め、長いほうから当てて切る。
    ⭕ gloss は文ごとに切り方がぶれる（bao nhiêu が bao と nhiêu に分かれる文がある）ので、そのままは使わない。"""
    def __init__(self, root, decks, gloss):
        self.ja = {}
        multi = set()
        for g in gloss.values():
            for w, ja in g.get("words", []):
                w = norm(w)
                if not w: continue
                self.ja.setdefault(w, ja)
                if " " in w: multi.add(w)
        lx = json.load(open(root / "lexicon.json")).get("words", {})
        for w, v in lx.items():
            w = norm(w)
            if " " in w: multi.add(w)
            if isinstance(v, dict) and v.get("ja"): self.ja.setdefault(w, v["ja"])
        for d in decks:
            for it in d.get("items", []):
                w = norm(it.get("show"))
                if it.get("group") == "単語" and " " in w and len(w.split()) <= 3: multi.add(w)
        self.multi = {tuple(w.split()) for w in multi if 2 <= len(w.split()) <= 4}
        self.maxn = max((len(m) for m in self.multi), default=1)

    def __call__(self, text):
        syl, i, out = norm(text).split(), 0, []
        while i < len(syl):
            for n in range(min(self.maxn, len(syl) - i), 0, -1):
                if n == 1 or tuple(syl[i:i + n]) in self.multi:
                    w = " ".join(syl[i:i + n]); out.append((w, self.ja.get(w))); i += n; break
        return out


def is_number(w):
    return bool(re.fullmatch(r"[\d\s]+", w))


def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    root = Path(sys.argv[1])
    decks = json.load(open(root / "practice.json"))["decks"]
    gloss = json.load(open(root / "gloss.json"))["sentences"]
    seg = Seg(root, decks, gloss)
    words_of = lambda it, _g=None: seg(it.get("show"))
    seen, out = set(), {}
    for d in decks:
        items = d.get("items", [])
        vocab = {}   # 単語欄の語と、公式の中で1語だけで示された語（Chiều・Đêm など）＝教科書が説明している語
        for it in items:
            w = norm(it.get("show"))
            if it.get("group") == "単語" or (w and len(w.split()) <= 2 and not re.search(r"[.?!]", it.get("show", ""))):
                if w: vocab.setdefault(w, seg.ja.get(w))
                for x, ja in words_of(it):
                    if it.get("group") == "単語": vocab.setdefault(x, ja)
        found = {}
        for it in items:
            if it.get("group") == "単語":
                continue
            for w, ja in words_of(it):
                if is_number(w) or w in seen:
                    continue
                f = found.setdefault(w, {"word": w, "ja": ja, "in_vocab": w in vocab, "first": it.get("show")})
                if not f["ja"] and ja: f["ja"] = ja
        for w, ja in vocab.items():
            if w not in seen and w not in found:
                found[w] = {"word": w, "ja": ja, "in_vocab": True, "first": None}
        out[d["id"]] = {"title": (d.get("section", "") + " " + d.get("title", "")).strip(), "new": list(found.values())}
        for it in items:
            for w, _ in words_of(it):
                seen.add(w)
            w = norm(it.get("show"))
            if w and it.get("group") == "単語": seen.add(w)
    if sys.argv[2] == "--全部":
        for k, v in out.items():
            miss = sum(1 for x in v["new"] if not x["in_vocab"])
            print(f"{k}\t{v['title']}\t初めて {len(v['new'])}\t単語欄に無い {miss}")
        return
    v = out.get(sys.argv[2])
    if not v:
        print("その課は無い：" + sys.argv[2]); sys.exit(1)
    print(json.dumps(v, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
