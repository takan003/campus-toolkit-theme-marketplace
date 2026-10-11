<#
.SYNOPSIS
  主題市集建置腳本：掃描 themes/、產生預覽圖（必要時）、打包 zip、
  計算 SHA-256、重新產出 index.json。

.DESCRIPTION
  資料流（詳見 docs/PROTOCOL.md）：
    themes/{id}/theme.json  --驗證-->  releases/{id}.zip  --SHA256-->  index.json

  執行後 index.json 與 releases/ 必然一致，請將兩者一併 commit。

.EXAMPLE
  .\scripts\build-release.ps1
  .\scripts\build-release.ps1 -BaseUrl "https://example.com/releases"
  .\scripts\build-release.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = 'https://raw.githubusercontent.com/takan003/campus-toolkit-theme-marketplace/main/releases',
  [string]$MarketplaceVersion = '1.0.0',
  [string]$RepoUrl = 'https://github.com/takan003/campus-toolkit-theme-marketplace',
  [switch]$CheckOnly,
  [switch]$ForcePreview
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$themesDir = Join-Path $root 'themes'
$releasesDir = Join-Path $root 'releases'
$indexPath = Join-Path $root 'index.json'

$requiredIndexFields = @(
  'id', 'name', 'description', 'version', 'latestVersion', 'minHostVersion',
  'repoUrl', 'downloadUrl', 'checksumSha256', 'category', 'tags'
)
$requiredThemeFields = @(
  'id', 'name', 'version', 'themeId', 'minHostVersion', 'author', 'description',
  'preview', 'category', 'tags', 'contractVersion', 'cssFile'
)
$semverPattern = '^\d+\.\d+\.\d+$'
$idPattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
$checksumPattern = '^[a-f0-9]{64}$'

function Fail([string]$message) {
  throw "[build-release] $message"
}

function Read-JsonFile([string]$path) {
  $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  try { return $raw | ConvertFrom-Json }
  catch { Fail "無法解析 JSON：$path（$($_.Exception.Message)）" }
}

function Assert-Fields($obj, [string[]]$fields, [string]$label) {
  foreach ($f in $fields) {
    if ($null -eq $obj.PSObject.Properties[$f]) { Fail "$label 缺少必要欄位：$f" }
    if ($obj.PSObject.Properties[$f].Value -is [string] -and [string]::IsNullOrWhiteSpace($obj.$f)) {
      Fail "$label 欄位不得為空：$f"
    }
  }
}

function New-PreviewImage([string]$path, [string]$bg, [string]$surface, [string]$accent, [string]$muted, [string]$label) {
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object System.Drawing.Bitmap(640, 400)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.Clear([System.Drawing.ColorTranslator]::FromHtml($bg))

  $card = New-Object System.Drawing.Rectangle(60, 70, 520, 260)
  $g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($surface))), $card)
  $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($muted), 2)
  $g.DrawRectangle($pen, $card)

  $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($accent))
  $g.FillRectangle($accentBrush, 90, 110, 140, 16)
  $g.FillRectangle($accentBrush, 90, 250, 120, 36)
  $mutedBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($muted))
  $g.FillRectangle($mutedBrush, 90, 150, 400, 10)
  $g.FillRectangle($mutedBrush, 90, 175, 320, 10)
  $g.FillRectangle($mutedBrush, 90, 200, 360, 10)

  $font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
  $textBrush = $accentBrush
  $g.DrawString($label, $font, $textBrush, 90, 256)

  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# --- 掃描與驗證主題 ---
$themeDirs = Get-ChildItem -LiteralPath $themesDir -Directory
if ($themeDirs.Count -eq 0) { Fail "themes/ 下沒有任何主題資料夾" }

$entries = @()
foreach ($dir in $themeDirs) {
  $themeJsonPath = Join-Path $dir.FullName 'theme.json'
  if (-not (Test-Path -LiteralPath $themeJsonPath)) { Fail "缺少 theme.json：$($dir.Name)" }
  $theme = Read-JsonFile $themeJsonPath
  Assert-Fields $theme $requiredThemeFields "themes/$($dir.Name)/theme.json"

  if ($theme.id -ne $dir.Name) { Fail "theme.json 的 id（$($theme.id)）必須與資料夾名稱（$($dir.Name)）一致" }
  if ($theme.id -notmatch $idPattern) { Fail "themes/$($dir.Name)：id 不符合 kebab-case（$($theme.id)）" }
  if ($theme.version -notmatch $semverPattern) { Fail "themes/$($dir.Name)：version 不是 semver（$($theme.version)）" }
  if ($theme.minHostVersion -notmatch $semverPattern) { Fail "themes/$($dir.Name)：minHostVersion 不是 semver" }
  if ($theme.themeId -ne "market:$($theme.id)") { Fail "themes/$($dir.Name)：themeId 必須為 market:$($theme.id)" }
  if ($theme.category -ne 'theme') { Fail "themes/$($dir.Name)：category 必須為 theme" }
  if ($theme.contractVersion -lt 1) { Fail "themes/$($dir.Name)：contractVersion 必須 >= 1" }

  $cssPath = Join-Path $dir.FullName $theme.cssFile
  if (-not (Test-Path -LiteralPath $cssPath)) { Fail "themes/$($dir.Name)：找不到 cssFile（$($theme.cssFile)）" }

  $cssRaw = [System.IO.File]::ReadAllText($cssPath, [System.Text.Encoding]::UTF8)
  if ($cssRaw -notmatch [regex]::Escape("html[data-theme=`"market:$($theme.id)`"]")) {
    Fail "themes/$($dir.Name)：styles.css 必須以 html[data-theme=`"market:$($theme.id)`"] 掛載（見 docs/PROTOCOL.md 第 5 章）"
  }

  $previewPath = Join-Path $dir.FullName $theme.preview
  if ($ForcePreview -or -not (Test-Path -LiteralPath $previewPath)) {
    $palette = switch ($theme.id) {
      'campus-dark'  { @{ bg = '#0f172a'; surface = '#111827'; accent = '#60a5fa'; muted = '#334155' } }
      'campus-light' { @{ bg = '#f8fafc'; surface = '#ffffff'; accent = '#2563eb'; muted = '#cbd5e1' } }
      default        { @{ bg = '#f8fafc'; surface = '#ffffff'; accent = '#2563eb'; muted = '#cbd5e1' } }
    }
    New-PreviewImage -path $previewPath -bg $palette.bg -surface $palette.surface -accent $palette.accent -muted $palette.muted -label $theme.name
    Write-Host "  [preview] 已產生 $($dir.Name)/$($theme.preview)"
  }

  $entries += [pscustomobject]@{ Dir = $dir.FullName; Theme = $theme }
}

if ($CheckOnly) {
  # 僅驗證既有產物一致性
  if (-not (Test-Path -LiteralPath $indexPath)) { Fail 'index.json 不存在' }
  $index = Read-JsonFile $indexPath
  foreach ($e in $entries) {
    $id = $e.Theme.id
    $mod = $index.modules | Where-Object { $_.id -eq $id }
    if (-not $mod) { Fail "index.json 缺少主題條目：$id" }
    Assert-Fields $mod $requiredIndexFields "index.json modules[$id]"
    if ($mod.checksumSha256 -notmatch $checksumPattern) { Fail "index.json $id：checksumSha256 不是 64 碼小寫 hex" }
    $zipPath = Join-Path $releasesDir "$id.zip"
    if (-not (Test-Path -LiteralPath $zipPath)) { Fail "缺少 release zip：releases/$id.zip（請執行建置腳本）" }
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $mod.checksumSha256) {
      Fail "checksum 不一致：$id`n  index.json : $($mod.checksumSha256)`n  $id.zip : $actual"
    }
    if ($mod.version -ne $e.Theme.version) {
      Fail "version 不一致：$id（theme.json=$($e.Theme.version), index.json=$($mod.version)）"
    }
  }
  Write-Host "[build-release] CheckOnly 通過：index.json 與 releases/ 一致（$($entries.Count) 個主題）"
  return
}

# --- 打包與產出索引 ---
if (-not (Test-Path -LiteralPath $releasesDir)) { New-Item -ItemType Directory -Path $releasesDir | Out-Null }

$modules = @()
foreach ($e in $entries) {
  $theme = $e.Theme
  $zipPath = Join-Path $releasesDir "$($theme.id).zip"
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

  # 打包主題資料夾內容（theme.json 位於 zip 根目錄）
  Compress-Archive -Path (Join-Path $e.Dir '*') -DestinationPath $zipPath -CompressionLevel Optimal

  $checksum = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($checksum -notmatch $checksumPattern) { Fail "計算 checksum 失敗：$($theme.id)" }

  $modules += [ordered]@{
    id              = $theme.id
    name            = $theme.name
    description     = $theme.description
    version         = $theme.version
    latestVersion   = $theme.version
    minHostVersion  = $theme.minHostVersion
    repoUrl         = "$RepoUrl/tree/main/themes/$($theme.id)"
    downloadUrl     = "$BaseUrl/$($theme.id).zip"
    checksumSha256  = $checksum
    category        = 'theme'
    tags            = @($theme.tags)
  }
  Write-Host "  [zip] $($theme.id).zip  v$($theme.version)  sha256=$checksum"
}

$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:sszzz")
$index = [ordered]@{
  generatedAt        = $generatedAt
  marketplaceVersion = $MarketplaceVersion
  modules            = $modules
}

$json = $index | ConvertTo-Json -Depth 6
# ConvertTo-Json 會把空陣列輸出為 null 的情況，tags 保證非空即可
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($indexPath, $json + "`n", $utf8NoBom)
Write-Host "[build-release] 已產出 index.json（$($modules.Count) 個主題，marketplaceVersion $MarketplaceVersion）"
Write-Host '[build-release] 完成。請將 themes/、releases/、index.json 一併 commit。'
