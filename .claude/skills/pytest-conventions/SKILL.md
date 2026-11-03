---
name: pytest-conventions
description: 実行手段=pytest のテスト実装プロファイル（配置・命名・トレーサビリティ・モック方針・フィクスチャ・実行コマンド/レポート・Tの症状カタログ・診断方法）。test-to-code が pytest でコードを書くとき、test-runner が pytest で診断するときに必ず参照する。別のコード実行ランナー（Vitest/Jest 等）に替えるなら、このファイル相当を <新ツール>-conventions として用意する。
---

# 実装プロファイル：pytest

実行手段=pytest のときの**ツール固有の作法**をまとめる。ループ・分類スキーム（T/I/E）・「assert を緩めない」「ID対応」などツール非依存の原則は [[test-loop]] / test-to-code / test-runner 側が持つ。本書はそれらを **pytest で具体化**する。

## ディレクトリ・配置
- テスト: `tests/unit/test_*.py`（単体）・`tests/integration/test_*.py`（結合）。プロジェクトに既存のテスト配置があればそれに合わせる。
- 共有フィクスチャ: `tests/conftest.py`（複数テストで使う fixture・モックを集約）
- レポートの出力先: `tests/reports/junit.xml`（JUnit）・カバレッジは `tests/reports/coverage/`

## 命名・トレーサビリティ
- テスト関数名は `test_{ケースID小文字}_{内容}`（例: `def test_ut_cart_003_合計金額の丸め(): ...`）。または `@pytest.mark` でケースIDを付与する。
- **ケースID（UT-*/IT-*）を必ず関数名かマーカーに含める**。JUnit の `<testcase>` 名で仕様書と突合できるようにする。
- `class Test{機能}` で機能単位にグルーピングしてよい。

## モック・決定性方針（フレーキー禁止）
- 時刻・乱数・ネットワーク・ファイルI/O・外部サービスは固定する：
  - 時刻 → `freezegun` か `monkeypatch` で固定
  - 乱数 → シード固定、または対象に注入
  - 外部依存 → `monkeypatch.setattr` / `unittest.mock.patch` / `pytest-mock` の `mocker`
- **単体は対象の責務に閉じ依存をモックする。結合は実際にまたぐ連携を検証し、連携自体をモックで消さない。**
- パラメータ化は `@pytest.mark.parametrize` を使い、ケースIDと期待値を対応づける。

## 実行コマンド・レポート（結果の正本）
- 実行は `pytest`（レポーター設定は `pyproject.toml`/`pytest.ini` に従い、`--reporter` 等で上書きしない）
- JUnit: `pytest --junitxml=tests/reports/junit.xml`
- カバレッジ: `pytest --cov --cov-report=html:tests/reports/coverage`
- 結果は仕様書に書き戻さず、JUnit/カバレッジを正本とする。

## 雛形
```python
import pytest
from app.cart import calc_total

class TestCartCalculator:
    @pytest.mark.parametrize("items, expected", [
        ([("apple", 100, 2), ("milk", 150, 1)], 350),  # UT-CART-001 正常系
    ])
    def test_ut_cart_001_合計金額(self, items, expected):
        assert calc_total(items) == expected

    def test_ut_cart_003_税の丸め(self, monkeypatch):
        # 外部依存（税率取得）を固定して決定的にする
        monkeypatch.setattr("app.cart.fetch_tax_rate", lambda: 0.10)
        assert calc_total([("apple", 100, 1)]) == 110
```

## test-runner 向け：Tの症状カタログと診断方法
失敗時、**ログのアサーション差分・スタックトレース・収集エラーを読んで**分類する（実画面確認は不要）。

| 症状 | 分類 | 例 |
|---|---|---|
| 順序非保証の比較で落ちる | **T** | 集合的な結果を `==`/`assertEqual` で順序比較 → 集合比較か事前ソートに |
| モック漏れで非決定要素に依存 | **T** | 時刻・乱数・I/O を固定せず落ちる → `monkeypatch`/`freezegun` で固定 |
| 浮動小数の厳密一致 | **T** | `assert x == 0.1+0.2` → `pytest.approx` を使う |
| ロケール/タイムゾーン依存 | **T** | 環境依存の整形 → 固定する |
| 仕様書の期待値と実装の挙動が食い違う | **I** | 詳細設計は丸め後 `100` 期待だが実装は `99`（テストは正しくバグ検出） |
| 収集エラー（import/構文/型）・依存欠落・データ未整備 | **E** | `ModuleNotFoundError`、フィクスチャ用データ未投入、pytest 未導入 |

T の直し方（test-to-code 向け）：**期待値（assert）は変えず、テスト側の前提（モック・比較方法）を直す**。
