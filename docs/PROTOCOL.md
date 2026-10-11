# 主題市集協議（Protocol）

本文件是 `campus-toolkit-theme-marketplace` 與 host app `campus-toolkit` 之間的正式對接協議。市集與主程式的任何變更都必須符合本文件；契約變更時須提升對應版本號。

## 1. 責任分工

| 角色 | 負責 | 不負責 |
| --- | --- | --- |
| 主題市集（本 repo） | 主題資產、`theme.json`、`index.json`、版本、release zip、checksum | 安裝、套用、帳號同步 |
| host app（campus-toolkit） | 讀取索引、安全驗證、下載、解壓、註冊、套用 | 主題內容發佈 |
| 使用者端 | 挑選、啟用、更新、停用主題 | 來源驗證 |

## 2. themeId 來源協議

所有主題在系統中以一個字串識別，格式為 `{source}:{id}`：

| 前綴 | 意義 | 例子 | 來源 |
| --- | --- | --- | --- |
| `builtin:` | 主程式內建主題 | `builtin:default` | host app 程式碼內 |
| `market:` | 市集下載主題 | `market:campus-dark` | 本市集安裝 |
| `custom:` | 使用者自訂主題 | `custom:my-own` | 使用者上傳／編輯 |

規則：

- 市集主題包的 `theme.json.themeId` 必須為 `market:{id}`，且 `{id}` 必須等於 `theme.json.id` 與索引條目的 `id`。
- 前綴不可混用；host app 必須先以前綴分派來源，再依來源查找。

## 3. 主題解析優先序

host app 決定「最終套用哪個主題」時，必須依下列固定順序，先命中者優先：

```text
1. 主程式強制主題（管理端 settings.cssThemeId）
2. 使用者帳號主題（登入後同步的 themeId）
3. localStorage 快取主題
4. 系統預設主題（builtin:default）
```

- 強制主題一旦設定，忽略其餘三層。
- 登出時保留 localStorage 快取；登入時以帳號主題覆蓋快取。
- 解析結果僅是一個 `themeId` 字串；真正的樣式內容由該來源對應的 CSS 檔提供。

## 4. 資料契約

### 4.1 市集入口 `index.json`

- 位於市集根目錄，可被 GET 直接讀取。
- 正式契約見 [`schema/index.schema.json`](../schema/index.schema.json)。
- 陣列鍵名為 `modules`（為相容 campus-toolkit 既有模組市集解析器，第一版不改為 `themes`）。
- 條目最少欄位：`id`、`name`、`description`、`version`、`latestVersion`、`minHostVersion`、`repoUrl`、`downloadUrl`、`checksumSha256`、`category`、`tags`。
- `category` 固定為 `"theme"`。
- `checksumSha256` 為對應 zip 的 SHA-256，64 碼小寫 hex。

### 4.2 主題包 manifest `theme.json`

- 位於主題包（zip）根目錄。
- 正式契約見 [`schema/theme.schema.json`](../schema/theme.schema.json)。
- 主題包最少包含：`theme.json`、`cssFile` 指定的 CSS 檔、`preview` 指定的預覽圖。

### 4.3 主題包目錄結構

```text
theme.zip
├─ theme.json      # manifest，必須在壓縮根目錄
├─ styles.css      # 實際樣式（檔名由 cssFile 決定）
└─ preview.png     # 預覽圖（路徑由 preview 決定）
```

## 5. CSS Token 契約（contractVersion 1）

主題包**只負責覆寫全域 CSS variables**，不得包含任何元件樣式規則。host app 的所有元件必須以 `var(--*)` 取色。

### 5.1 Token 白名單（詞彙以 campus-toolkit `ThemeColors` 為準）

host app（campus-toolkit）的全域 token 共 33 鍵（見主程式 `src/types/theme.ts` 的 `ThemeColors`）。主題包**只能覆寫下列白名單內的鍵**，鍵名必須完全一致：

| 分組 | Token |
| --- | --- |
| 版面 | `--bg`（頁面背景）、`--bg2`（次層背景）、`--card`（卡片背景）、`--sh`（陰影，完整 shadow 簡寫值） |
| 文字 | `--t1`（主要）、`--t2`（次要）、`--t3`（輔助） |
| 邊框 | `--bd`、`--bd2` |
| 主要色 | `--primary`、`--primary-hover`、`--primary-text`、`--primary-text-hover`、`--primary-block` |
| 狀態色 | `--danger`、`--success`、`--warning` |
| 次要按鈕 | `--btn-secondary`、`--btn-secondary-hover`、`--btn-secondary-text`、`--btn-secondary-text-hover` |
| 危險按鈕 | `--btn-danger`、`--btn-danger-hover`、`--btn-danger-text`、`--btn-danger-text-hover` |
| 停用按鈕 | `--btn-disabled`、`--btn-disabled-text` |
| 連結 | `--link`、`--link-hover` |
| 其他 | `--radius`（如 `8px`）、`--font-sans`、`--font-mono`、`--transition`（如 `0.2s ease`） |

規則：

- 每個主題**至少必須覆寫** `--bg`、`--card`、`--t1`（身分與可讀性最低集合）；其餘鍵可省略，省略者由 host app 以預設主題補底
- 值必須是安全的 CSS 宣告值：不得含 `;`、`{`、`}`、`url(`、`expression(`、`@import` 等構造（host app 安裝時會強制驗證）
- host app 套用主題時以 `setProperty` 逐鍵注入，**不會載入主題包的 CSS 檔本身**——CSS 檔的角色是「交換格式」，讓建置工具與審核者可讀

### 5.2 覆寫方式

主題 CSS 必須以 `html[data-theme="market:{id}"]` 作為選擇器掛載，且檔案中**只允許這一個區塊**（純變數覆寫，不含元件規則）。host app 套用主題時會設定：

```js
document.documentElement.dataset.theme = "market:campus-dark";
```

範例：

```css
html[data-theme="market:campus-dark"] {
  --bg: #0f172a;
  --bg2: #1f2937;
  --card: #111827;
  --t1: #e5e7eb;
  --t2: #cbd5e1;
  --t3: #94a3b8;
  --bd: rgba(148, 163, 184, 0.25);
  --primary: #60a5fa;
  --primary-hover: #3b82f6;
}
```

### 5.3 禁止事項

- 不得寫死品牌色於 host app 新元件（一律走 token）。
- 不得依賴圖片背景承載關鍵視覺（圖片不受 variables 影響）。
- **styles.css 不得包含任何元件／版面規則**（如 `.card { ... }`）——只允許 `html[data-theme="market:{id}"]` 的變數覆寫區塊；元件樣式由 host app 統一管理。

## 6. 安全協議（安裝前強制檢查，全部通過才可下載）

1. `index.json` 必須可正確解析為 JSON 且通過 schema。
2. `downloadUrl` 必須為 HTTPS（僅開發環境允許 localhost 的 http）。
3. `downloadUrl.hostname` 必須與市集索引來源 hostname 一致。
4. `checksumSha256` 必須為 64 碼小寫 hex，且與下載檔案實際 SHA-256 相符。
5. host app 版本必須 ≥ `minHostVersion`（semver 比較），否則拒絕安裝。
6. zip 檔案大小須低於上限（建議預設 5 MB）。
7. 解壓時須拒絕路徑穿越（zip slip）：解壓目標不得超出臨時目錄之外。
8. 解壓後必須存在 `theme.json`，且通過 `theme.schema.json` 驗證；`themeId` 必須等於 `market:{id}`。
9. `styles.css` 中解析出的 token 鍵必須屬於 §5.1 白名單；值不得含 `;`、`{`、`}`、`url(`、`expression(`、`@import` 等危險構造。

任一項失敗，安裝流程必須中止並回報具體原因（版本不符／checksum 失敗／來源不可信等）。

> **campus-toolkit 實作註記**：主程式部署於 Vercel，production 檔案系統唯讀，因此安裝不寫入伺服器磁碟——伺服器僅負責「下載、驗證、解析 token」，將驗證通過的主題內容回傳瀏覽器，由前端存入 localStorage，帳號層則以 `users.cssThemeId` / `users.installedThemes` 欄位保存（見主程式 `docs/CSS主題個性化規劃書.md`）。

## 7. 安裝流程與本機註冊

```text
GET 市集 index.json
  → 驗證 schema
  → 使用者點選安裝
  → 執行第 6 章全部安全檢查
  → 下載 zip 至暫存
  → 驗證 checksumSha256
  → 解壓到 themes/{id}/（含 zip slip 防護）
  → 讀取並驗證 theme.json
  → 寫入安裝紀錄
  → 列為可選主題
```

安裝紀錄的保存方式由 host app 決定，二選一：

1. **檔案系統方案**（有可寫磁碟的部署環境）：`theme.lock.json`（或 `themes/registry.json`）
2. **資料儲存方案**（如 campus-toolkit 部署於 Vercel、production 檔案系統唯讀）：localStorage 保存主題內容＋帳號資料庫欄位保存 `themeId` 與已安裝清單

每筆安裝紀錄至少包含：

```json
{
  "themeId": "market:campus-dark",
  "id": "campus-dark",
  "version": "1.0.0",
  "source": "market",
  "installedAt": "2026-10-11T08:00:00+08:00",
  "checksumSha256": "…64 hex…",
  "status": "installed"
}
```

`status` 取值：`active`（目前套用中）、`installed`（已安裝未套用）、`outdated`（市集有較新版本）。更新、卸載、回滾都依賴此紀錄。

## 8. 版本策略

- 主題版本與市集索引皆使用 semver（`major.minor.patch`）。
- host app 以「已安裝 version < 索引 latestVersion」判定可更新。
- `contractVersion` 為主題包格式版本（整數）；host app 不支援的 contractVersion 應拒絕安裝。
- 破壞性契約變更（欄位刪除、語義變更）必須提升 `marketplaceVersion` major，並於本文件記錄。

## 9. host app 端建議環境變數

```env
# 主題市集（建議新增，與模組市集分開）
THEME_MARKET_INDEX_URL=https://raw.githubusercontent.com/takan003/campus-toolkit-theme-marketplace/main/index.json
```

## 10. 契約版本紀錄

| 日期 | marketplaceVersion | 變更 |
| --- | --- | --- |
| 2026-10-11 | 1.0.0 | 初始契約：index/theme schema、themeId 來源協議、CSS token 契約、安全檢查清單 |
| 2026-10-11 | 1.1.0 | CSS token 詞彙改以 campus-toolkit `ThemeColors` 33 鍵為準（§5.1）；styles.css 改為僅允許單一變數覆寫區塊（§5.3）；§6 增訂 token 白名單與值安全驗證；§7 補充 Vercel 環境的安裝紀錄替代方案 |
