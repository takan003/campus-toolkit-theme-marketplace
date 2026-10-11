# 校園主題市集

這是為 `campus-toolkit` 特別建立的獨立主題市集專案，避免與現有的模組市集倉庫 `campus-toolkit-marketplace` 互相混用。

## 目標

- 以獨立 repo 發佈與管理主題包
- 供 host app 透過 `index.json` 讀取可用主題
- 只負責主題發行、版本索引與資產分發
- 讓 `campus-toolkit` 專注於讀取、驗證、下載與套用主題

## 內容

- [主題市集規劃書](./主題市集規劃書.md)
- [主題市集協議（正式對接規格）](./docs/PROTOCOL.md)
- 資料契約：[`schema/index.schema.json`](./schema/index.schema.json)、[`schema/theme.schema.json`](./schema/theme.schema.json)

## 目錄結構

```text
campus-toolkit-theme-marketplace/
├─ README.md
├─ 主題市集規劃書.md
├─ index.json              # 市集入口索引（由腳本自動產出，勿手改）
├─ schema/                 # index / theme.json 的 JSON Schema 契約
├─ docs/PROTOCOL.md        # 與 host app 的正式對接協議
├─ scripts/
│  └─ build-release.ps1    # 打包 zip、算 checksum、重建 index.json
├─ themes/
│  ├─ campus-dark/         # theme.json + styles.css + preview.png
│  └─ campus-light/
├─ releases/               # 打包產物（由腳本產出）
│  ├─ campus-dark.zip
│  └─ campus-light.zip
├─ LICENSE
└─ .github/
```

## 如何新增／更新主題

1. 在 `themes/{id}/` 內維護 `theme.json`、`styles.css`、`preview.png`
   - 樣式必須以 `html[data-theme="market:{id}"]` 掛載，並覆寫協議定義的 CSS variables
   - 詳見 [docs/PROTOCOL.md](./docs/PROTOCOL.md) 第 5 章
2. 若為更新版本，把 `theme.json` 的 `version` 提升（semver）
3. 執行建置腳本（Windows PowerShell 內建，無需額外安裝）：

   ```powershell
   .\scripts\build-release.ps1
   ```

4. 腳本會自動：產生缺漏的 `preview.png` → 打包 `releases/{id}.zip` → 計算 SHA-256 → 重建 `index.json`
5. 驗證產物一致性：

   ```powershell
   .\scripts\build-release.ps1 -CheckOnly
   ```

6. 將 `themes/`、`releases/`、`index.json` 一併 commit

## 版本與安全策略

- 採用 `{source}:{id}` 格式作為主題來源識別（`builtin:` / `market:` / `custom:`）
- 下載 URL 必須受限於市集來源主機（HTTPS）
- 安裝前須驗證 `checksumSha256`（64 碼小寫 hex）與 `minHostVersion`
- host app 安裝時的安全檢查清單見 [docs/PROTOCOL.md](./docs/PROTOCOL.md) 第 6 章
- 版本資訊與索引資料集中於 `index.json`

## host app 對接

```env
THEME_MARKET_INDEX_URL=https://raw.githubusercontent.com/takan003/campus-toolkit-theme-marketplace/main/index.json
```

安裝鏈（讀取索引 → 安全檢查 → 下載 → 驗證 checksum → 解壓 → 註冊）由 `campus-toolkit` 執行，規格見協議文件第 6–7 章。
