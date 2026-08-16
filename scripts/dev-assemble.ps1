# ============================================================
#  dev-assemble.ps1 — 本地重建 DeployResources/application (规范 M5)
#  用途: 本地 dotnet publish 出真包前, 先跑本脚本收集子项目制品
#  用法: pwsh scripts/dev-assemble.ps1 -ReposRoot <插件克隆根目录>
#  依赖: 本地已有各插件仓克隆 (远程 URL 从 plugins.json 读, 可传 -UseRemote 自动 clone)
#  说明: 图标(bmp)由 CI gen-icons.sh 生成, 本地不生成; meta 摘要写入 ci/_plugin_meta.tsv
# ============================================================
param(
  [string]$ReposRoot = ".",
  [switch]$UseRemote
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$AppDir = Join-Path $Root "DeployResources\application"
$MetaTsv = Join-Path $Root "ci\_plugin_meta.tsv"
$HostApi = "https://gt.h.zss.fan:2233"

if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Force $AppDir | Out-Null }
Get-ChildItem $AppDir -File | Remove-Item -Force

$plugins = (Get-Content (Join-Path $Root "plugins.json") -Raw | ConvertFrom-Json).plugins
if (-not $plugins) { throw "plugins.json 无插件登记" }

$tsv = New-Object System.Collections.Generic.List[string]
foreach ($p in $plugins) {
  $repo = $p.repo
  $ref = if ($p.ref) { $p.ref } else { "master" }
  $src = Join-Path $ReposRoot $repo
  if ($UseRemote -or -not (Test-Path $src)) {
    if (-not $env:GITEA_TOKEN) { throw "需要 \$env:GITEA_TOKEN (克隆私有仓)" }
    $src = Join-Path $env:TEMP "ikun-assemble-$repo"
    if (Test-Path $src) { Remove-Item $src -Recurse -Force }
    # 规范 §11.6: 不用 sslVerify=false — 本机需已信任自签 CA (更新链同样要求, 见 §9.3.5)
    git clone --quiet --depth 1 -b $ref "https://zhaoshen:$($env:GITEA_TOKEN)@gt.h.zss.fan:2233/zhaoshen/$repo.git" $src
  }
  if (-not (Test-Path $src)) { Write-Host "跳过 $repo (找不到 $src)" -ForegroundColor Yellow; continue }

  $globs = @("*.dll","*.dlx","*.dat")
  $deployTxt = Join-Path $src "ikun-deploy.txt"
  if (Test-Path $deployTxt) {
    $g = Get-Content $deployTxt | Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") }
    if ($g) { $globs = $g | ForEach-Object { $_.Trim() } }
  }
  $n = 0
  foreach ($glob in $globs) {
    if ($glob -match '[/\\]') { Write-Host "跳过不安全 glob: $glob" -ForegroundColor DarkYellow; continue }
    foreach ($f in Get-ChildItem $src -File -Filter $glob) {
      Copy-Item $f.FullName $AppDir -Force
      $n++
    }
  }
  Write-Host ("{0,-22} +{1} 文件" -f $repo, $n) -ForegroundColor Green

  $m = @{ name_cn=""; icon_cn=""; category=""; in_ikun="" }
  $metaFile = Join-Path $src "plugin.meta"
  if (Test-Path $metaFile) {
    Get-Content $metaFile -Encoding UTF8 | ForEach-Object {
      if ($_ -match '^([a-z_]+)=(.*)$') { $m[$matches[1]] = $matches[2].Trim() }
    }
  }
  $tsv.Add("$repo|$($m.name_cn)|$($m.icon_cn)|$($m.category)|$($m.in_ikun)")
}
$tsv | Set-Content $MetaTsv -Encoding UTF8
Write-Host "meta 摘要已写: $MetaTsv" -ForegroundColor Green
Write-Host "完成。本地出真包: dotnet publish ikun_installer.csproj -c Release (图标由 CI 生成)" -ForegroundColor Cyan
