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

主題包**只負責覆寫全域 CSS variables**，不得直接堆砌頁面樣式。host app 的所有元件必須以 `var(--*)` 取色。

### 5.1 必須支援的 token

| Token | 用途 |
| --- | --- |
| `--bg` | 頁面背景 |
| `--surface` | 卡片／面板背景 |
| `--surface-2` | 次層面板背景 |
| `--text` | 主要文字 |
| `--muted` | 次要文字 |
| `--border` | 邊框 |
| `--shadow` | 陰影顏色 |
| `--primary` | 主要色 |
| `--primary-strong` | 主要色（強調） |
| `--success` | 成功狀態 |
| `--warning` | 警告狀態 |
| `--danger` | 危險／錯誤狀態 |

### 5.2 覆寫方式

主題 CSS 必須以 `html[data-theme="market:{id}"]` 作為選擇器掛載，host app 套用主題時會設定：

```js
document.documentElement.dataset.theme = "market:campus-dark";
```

範例：

```css
html[data-theme="market:campus-dark"] {
  --bg: #0f172a;
  --surface: #111827;
  --text: #e5e7eb;
  --primary: #60a5fa;
}
```

### 5.3 禁止事項

- 不得寫死品牌色於 host app 新元件（一律走 token）。
- 不得依賴圖片背景承載關鍵視覺（圖片不受 variables 影響）。
- 主題包內允許少量 theme-specific 補充規則，但不得覆蓋 host app 的結構性版面。

## 6. 安全協議（安裝前強制檢查，全部通過才可下載）

1. `index.json` 必須可正確解析為 JSON 且通過 schema。
2. `downloadUrl` 必須為 HTTPS（僅開發環境允許 localhost 的 http）。
3. `downloadUrl.hostname` 必須與市集索引來源 hostname 一致。
4. `checksumSha256` 必須為 64 碼小寫 hex，且與下載檔案實際 SHA-256 相符。
5. host app 版本必須 ≥ `minHostVersion`（semver 比較），否則拒絕安裝。
6. zip 檔案大小須低於上限（建議預設 5 MB）。
7. 解壓時須拒絕路徑穿越（zip slip）：解壓目標不得超出 `themes/{id}/` 之外。
8. 解壓後必須存在 `theme.json`，且通過 `theme.schema.json` 驗證。

任一項失敗，安裝流程必須中止並回報具體原因（版本不符／checksum 失敗／來源不可信等）。

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

安裝紀錄建議以 `theme.lock.json`（或 `themes/registry.json`）保存，每筆至少包含：

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
