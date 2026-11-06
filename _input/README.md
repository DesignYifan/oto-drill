# _input（中身は git に入れない）

音声ドリル（oto-drill）が使う教材の元の置き場。市販の著作物なので、本人の学習と動作の確かめにだけ使う。公開しない。

| 何 | どこから | 置き方 |
|---|---|---|
| ゼロからスタート ベトナム語（26295）の音声158本と、そこから作った book.json・gloss.json・practice.json・images/ など | 本人が買った教材の付属音声。2026-11-07 に `~/Downloads/26295` から移した（AppBuilding_RULES ④「Downloads の下にインプットを置かない」） | `26295/`（実体） |

- 作るスクリプトは `~/Downloads/WIP/_course/26295/*.py`。iPhone 向けの写しは `sync_to_icloud.py` が iCloud Drive の `音声ドリル/教材/26295` へ作る
- `~/Programming/jibun-kyozai/_input/zero` はここへのシンボリックリンク
