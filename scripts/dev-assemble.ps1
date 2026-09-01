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
$DeployRoot = Join-Path $Root "DeployResources"
$AppDir = Join-Path $DeployRoot "application"
$MetaTsv = Join-Path $Root "ci\_plugin_meta.tsv"
$RunId = [guid]::NewGuid().ToString("N")
$StageDir = Join-Path $DeployRoot ".application-stage-$RunId"
$BackupDir = Join-Path $DeployRoot ".application-backup-$RunId"
$CloneRoot = Join-Path ([IO.Path]::GetTempPath()) "ikun-assemble-$RunId"
$MetaTemp = "$MetaTsv.stage-$RunId"
$MetaBackup = "$MetaTsv.backup-$RunId"

function Invoke-GiteaClone {
  param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Ref,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (-not $env:GITEA_HOST -or -not $env:GITEA_USER -or -not $env:GITEA_TOKEN) {
    throw "远程克隆需要 GITEA_HOST、GITEA_USER、GITEA_TOKEN 环境变量"
  }

  $hostNoProto = $env:GITEA_HOST -replace '^https?://', ''
  $scheme = if ($env:GITEA_HOST -match '^http://') { 'http' } else { 'https' }
  $cloneUrl = "${scheme}://${hostNoProto}/$($env:GITEA_USER)/${Repo}.git"
  $askPass = Join-Path ([IO.Path]::GetTempPath()) ("ikun-git-askpass-" + [guid]::NewGuid().ToString("N") + ".cmd")
  $askPassBody = @'
@echo off
echo %~1 | %SystemRoot%\System32\findstr.exe /I "Username" >nul
if not errorlevel 1 (
  echo %GITEA_USER%
) else (
  echo %GITEA_TOKEN%
)
'@

  $oldAskPass = $env:GIT_ASKPASS
  $oldTerminalPrompt = $env:GIT_TERMINAL_PROMPT
  try {
    [IO.File]::WriteAllText($askPass, $askPassBody, [Text.Encoding]::ASCII)
    $env:GIT_ASKPASS = $askPass
    $env:GIT_TERMINAL_PROMPT = "0"
    # URL 与 askpass 文件均不含 Token；临时脚本只从当前进程环境读取凭证。
    git clone --quiet --depth 1 -b $Ref $cloneUrl $Destination
    if ($LASTEXITCODE -ne 0) { throw "克隆失败: $Repo ($Ref)" }
  }
  finally {
    $env:GIT_ASKPASS = $oldAskPass
    $env:GIT_TERMINAL_PROMPT = $oldTerminalPrompt
    if ([IO.File]::Exists($askPass)) { [IO.File]::Delete($askPass) }
  }
}

New-Item -ItemType Directory -Path $StageDir, $CloneRoot -Force | Out-Null
$plugins = (Get-Content (Join-Path $Root "plugins.json") -Raw | ConvertFrom-Json).plugins
if (-not $plugins) { throw "plugins.json 无插件登记" }

$tsv = New-Object System.Collections.Generic.List[string]
$appMovedToBackup = $false
$stageInstalled = $false
$hadMeta = Test-Path -LiteralPath $MetaTsv

try {
  foreach ($p in $plugins) {
    $repo = $p.repo
    $ref = if ($p.ref) { $p.ref } else { "master" }
    $src = Join-Path $ReposRoot $repo
    if ($UseRemote -or -not (Test-Path $src)) {
      $src = Join-Path $CloneRoot $repo
      # 规范 §11.6: 不用 sslVerify=false — 本机需已信任自签 CA (更新链同样要求, 见 §9.3.5)
      Invoke-GiteaClone -Repo $repo -Ref $ref -Destination $src
    }
    if (-not (Test-Path $src)) { throw "找不到 $repo 源目录: $src" }

    $globs = @("*.dll", "*.dlx", "*.dat")
    $deployTxt = Join-Path $src "ikun-deploy.txt"
    if (Test-Path $deployTxt) {
      $g = Get-Content $deployTxt | Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") }
      if ($g) { $globs = $g | ForEach-Object { $_.Trim() } }
    }

    $n = 0
    foreach ($glob in $globs) {
      if ($glob -match '[/\\]') { throw "不安全部署 glob: $repo / $glob" }
      foreach ($f in Get-ChildItem $src -File -Filter $glob) {
        $dest = Join-Path $StageDir $f.Name
        if (Test-Path -LiteralPath $dest) { throw "部署文件名冲突: $($f.Name)" }
        Copy-Item -LiteralPath $f.FullName -Destination $dest
        $n++
      }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $StageDir "$repo.dll"))) {
      throw "$repo 缺少必需产物 $repo.dll"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $StageDir "$repo.dlx"))) {
      throw "$repo 缺少必需产物 $repo.dlx"
    }
    Write-Host ("{0,-22} +{1} 文件" -f $repo, $n) -ForegroundColor Green

    $m = @{ name_cn=""; icon_cn=""; category=""; in_ikun="" }
    $metaFile = Join-Path $src "plugin.meta"
    if (-not (Test-Path -LiteralPath $metaFile)) { throw "$repo 缺少 plugin.meta" }
    Get-Content $metaFile -Encoding UTF8 | ForEach-Object {
      if ($_ -match '^([a-z_]+)=(.*)$') { $m[$matches[1]] = $matches[2].Trim() }
    }
    $tsv.Add("$repo|$($m.name_cn)|$($m.icon_cn)|$($m.category)|$($m.in_ikun)")
  }

  if ($tsv.Count -ne $plugins.Count) { throw "插件收集不完整: $($tsv.Count)/$($plugins.Count)" }
  $keep = Join-Path $AppDir ".gitkeep"
  if (Test-Path -LiteralPath $keep) {
    Copy-Item -LiteralPath $keep -Destination (Join-Path $StageDir ".gitkeep")
  } else {
    [IO.File]::WriteAllText((Join-Path $StageDir ".gitkeep"), "", [Text.UTF8Encoding]::new($false))
  }
  [IO.File]::WriteAllLines($MetaTemp, $tsv, [Text.UTF8Encoding]::new($false))
  if ($hadMeta) { Copy-Item -LiteralPath $MetaTsv -Destination $MetaBackup }

  # 同卷目录改名：只有全部仓库和 meta 均收集成功后才替换，失败则恢复旧目录。
  if (Test-Path -LiteralPath $AppDir) {
    [IO.Directory]::Move($AppDir, $BackupDir)
    $appMovedToBackup = $true
  }
  try {
    [IO.Directory]::Move($StageDir, $AppDir)
    $stageInstalled = $true
    [IO.File]::Move($MetaTemp, $MetaTsv, $true)
  }
  catch {
    if ($stageInstalled -and (Test-Path -LiteralPath $AppDir)) {
      [IO.Directory]::Move($AppDir, $StageDir)
      $stageInstalled = $false
    }
    if ($appMovedToBackup -and (Test-Path -LiteralPath $BackupDir)) {
      [IO.Directory]::Move($BackupDir, $AppDir)
      $appMovedToBackup = $false
    }
    if ($hadMeta -and (Test-Path -LiteralPath $MetaBackup)) {
      Copy-Item -LiteralPath $MetaBackup -Destination $MetaTsv -Force
    } elseif (-not $hadMeta -and (Test-Path -LiteralPath $MetaTsv)) {
      [IO.File]::Delete($MetaTsv)
    }
    throw
  }

  if (Test-Path -LiteralPath $BackupDir) { Remove-Item -LiteralPath $BackupDir -Recurse -Force }
  if (Test-Path -LiteralPath $MetaBackup) { [IO.File]::Delete($MetaBackup) }
  Write-Host "meta 摘要已写: $MetaTsv" -ForegroundColor Green
  Write-Host "完成。本地出真包: dotnet publish ikun_installer.csproj -c Release (图标由 CI 生成)" -ForegroundColor Cyan
}
finally {
  if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
  if (Test-Path -LiteralPath $CloneRoot) { Remove-Item -LiteralPath $CloneRoot -Recurse -Force }
  if (Test-Path -LiteralPath $MetaTemp) { [IO.File]::Delete($MetaTemp) }
  # 恢复失败时保留 BackupDir/MetaBackup，便于人工恢复，不在 finally 中破坏证据。
}
