# 校園主題市集

這是為 `campus-toolkit` 特別建立的獨立主題市集專案，避免與現有的模組市集倉庫 `campus-toolkit-marketplace` 互相混用。

## 目標

- 以獨立 repo 發佈與管理主題包
- 供 host app 透過 `index.json` 讀取可用主題
- 只負責主題發行、版本索引與資產分發
- 讓 `campus-toolkit` 專注於讀取、驗證、下載與套用主題

## 內容

- [主題市集規劃書](./主題市集規劃書.md)

## 建議目錄結構

```text
campus-toolkit-theme-marketplace/
├─ README.md
├─ 主題市集規劃書.md
├─ index.json
├─ themes/
│  ├─ campus-dark/
│  └─ campus-light/
├─ releases/
│  ├─ campus-dark.zip
│  └─ campus-light.zip
├─ .gitignore
├─ LICENSE
└─ .github/
```

## 版本策略

- 採用 `market:{uuid}` 格式作為主題來源識別
- 下載 URL 必須受限於市集來源主機
- 安裝前須驗證 `checksumSha256` 與 `minHostVersion`
- 版本資訊與索引資料集中於 `index.json`
