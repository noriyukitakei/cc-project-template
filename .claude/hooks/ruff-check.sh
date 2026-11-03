#!/bin/bash
# Pythonファイル編集後にruffで検査するフック
# 警告のみ(ブロックはしない)

# stdinから全データを読む
INPUT=$(cat)

# stdoutに元のJSONを必ず流す(これ忘れるとClaudeに空入力が渡る)
echo "$INPUT"

# 編集されたファイルパスを取り出す
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('tool_input', {}).get('file_path', ''))")

# .pyファイルでなければ何もしない
if [[ ! "$FILE_PATH" =~ \.py$ ]]; then
    exit 0
fi

# ファイルが存在しなければ何もしない
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# ruffで検査(エラー時はexit 2でフィードバックをClaudeに渡す)
RUFF_OUTPUT=$(ruff check "$FILE_PATH" 2>&1)
if [ $? -ne 0 ]; then
    echo "[ruff-check] Lint issues in $FILE_PATH:" >&2
    echo "$RUFF_OUTPUT" >&2
    exit 2
fi

exit 0