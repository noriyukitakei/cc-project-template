---
name: playwright-conventions
description: 実行手段=playwright のテスト実装プロファイル（配置・命名・トレーサビリティ・セレクタ戦略・待機方針・Page Object・証跡/レポート・Tの症状カタログ・診断方法）。test-to-code が playwright でコードを書くとき、test-runner が playwright で診断するときに必ず参照する。本テンプレートの既定は Playwright + TypeScript。別のブラウザE2Eツールに替えるなら、このファイル相当を <新ツール>-conventions として用意する。
---

# 実装プロファイル：playwright（既定 Playwright + TypeScript）

実行手段=playwright のときの**ツール固有の作法**をまとめる。ループ・分類スキーム（T/I/E）・「assert を緩めない」「ID対応」などツール非依存の原則は [[test-loop]] / test-to-code / test-runner 側が持つ。本書はそれらを **playwright で具体化**する。

## ディレクトリ・配置
- テスト: `tests/e2e/*.spec.ts`
- Page Object: `tests/e2e/pages/*.page.ts`
- 共有フィクスチャ: `tests/e2e/fixtures.ts`（証跡スクショの afterEach を集約）
- 証跡の出力先: `tests/evidence/`（実行で自動生成。コミット対象外でよい）
- レポートの出力先: `tests/playwright-report/`（HTML）・`tests/test-results/junit.xml`（JUnit）

## 命名・トレーサビリティ
- test 名は「ケースID テスト内容」（例: `'TC-LOGIN-001 正しい認証情報でログイン成功'`）
- `test.describe` で機能単位にグルーピング
- **先頭のケースIDが仕様書との紐づけキー**。レポートも証跡も全部ケースIDで並ぶので、名前の体裁を崩さない

## セレクタ優先順位（実画面で確認したものを最優先・推測禁止）
1. `getByRole('button', { name: '送信' })`
2. `getByLabel('メールアドレス')`
3. `getByTestId('login-submit')`
4. CSS（最終手段）

## 待機方針
- `waitForTimeout` 禁止。auto-retry な expect / `page.waitForResponse` を使う
- API待ちは `page.waitForResponse`

## 実行コマンド・レポート（結果の正本）
- 実行は `npx playwright test`（`--reporter=...` で上書きしない＝HTML と JUnit の両方を残す）
- HTML（`tests/playwright-report/`）… `npx playwright show-report tests/playwright-report` で開く
- JUnit XML（`tests/test-results/junit.xml`）… CI/TestRail/Xray 等への取り込み用。`<testcase name="TC-... ">` にケースIDが入る

## 証跡（スクリーンショット）
- 全テストで証跡スクショを必ず残す。**ケースIDで命名**し成否が一目で分かるようにする。
- 各 spec に直書きせず `tests/e2e/fixtures.ts` の `afterEach` に集約。spec は import を `@playwright/test` から `./fixtures` に差し替えるだけ。
- ファイル名は `tests/evidence/{ケースID}_{PASS|FAIL}.png`、`fullPage: true`。
- 証跡取得のために expect を緩めたり try/catch で握りつぶさない。

```ts
// tests/e2e/fixtures.ts
import { test as base } from '@playwright/test';
export const test = base;
export { expect } from '@playwright/test';

test.afterEach(async ({ page }, testInfo) => {
  const status = testInfo.status === 'passed' ? 'PASS' : 'FAIL';
  const id = testInfo.title.match(/[A-Z]+-[A-Z]+-\d+/)?.[0] ?? testInfo.title;
  await page.screenshot({ path: `tests/evidence/${id}_${status}.png`, fullPage: true });
});
```

## 雛形
```ts
import { test, expect } from './fixtures';
import { LoginPage } from './pages/login.page';

test.describe('ログイン機能', () => {
  test('TC-LOGIN-001 正しい認証情報でログイン成功', async ({ page }) => {
    const login = new LoginPage(page);
    await login.goto();
    await login.login('user@example.com', 'pass1234');
    await expect(page).toHaveURL(/dashboard/);
    await expect(page.getByText('ようこそ')).toBeVisible();
  });
});
```

## Page Object パターン
```ts
import { Page } from '@playwright/test';
export class LoginPage {
  constructor(private page: Page) {}
  async goto() { await this.page.goto('/login'); }
  async login(email: string, password: string) {
    await this.page.getByLabel('メール').fill(email);
    await this.page.getByLabel('パスワード').fill(password);
    await this.page.getByRole('button', { name: 'ログイン' }).click();
  }
}
```

## test-runner 向け：Tの症状カタログと診断方法
失敗時、実画面を MCP（`browser_navigate`→`browser_snapshot`）で確認してから分類する。

| 症状 | 分類 | 例 |
|---|---|---|
| セレクタずれ（画面は正常なのに要素が見つからずタイムアウト） | **T** | `getByTestId('username')` が `data-testid` を探すが実DOMは `data-test` |
| 待ち不足（描画完了前に評価して落ちる） | **T** | ログイン直後、一覧描画前に `toHaveCount(6)` を評価し一瞬0件で落ちる |
| 仕様書の期待と実画面が食い違う | **I** | 仕様は `Total: $43.18` 期待だが実画面は `$40.00`（テストは正しくバグ検出） |
| 接続不可・アカウント失効・Chromium未導入 | **E** | サイト障害、`locked_out_user` 残置、ブラウザ未インストール |

T の直し方（test-to-code 向け）：
- セレクタずれ → `browser_snapshot` で実セレクタを再確認し、`getByRole`/`getByLabel` 優先で直す
- 待ち不足 → `waitForTimeout` でなく auto-retry expect / `waitForResponse` で直す
