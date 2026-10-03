#!/bin/zsh
# Groq の鍵を ~/.config/groq/key から Secrets.xcconfig に写す（⛔ このファイルは git に入れない・会話に貼らない）
HERE="${0:A:h}"
K=$(cat ~/.config/groq/key 2>/dev/null)
[[ -z "$K" ]] && { echo "~/.config/groq/key が無い"; exit 1; }
print -r -- "GROQ_KEY = $K" > "$HERE/Secrets.xcconfig"
echo "Secrets.xcconfig を作りました"
