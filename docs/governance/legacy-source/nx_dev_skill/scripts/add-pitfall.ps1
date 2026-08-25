#requires -Version 5
<#
.SYNOPSIS
  为一条新坑生成「待确认的建议」；人工确认后才写入坑账、commit 并推送（私有仓+公开仓）。
.DESCRIPTION
  「同步协议」的可执行落地（见 CONTRIBUTING.md）。**默认不自动提交**：
  - 默认（无 -Commit）：只计算并**弹出建议**（要加的条目、落在哪个小节），不改动任何文件、不提交。
    · 在真人终端里运行会追加一句 y/N 确认，回答 y 才执行。
    · 被 agent/管道非交互调用时，只打印建议并退出——由人工确认后再执行。
  - 加 -Commit（或在终端回答 y）：写入坑账 → commit → push 私有仓 → 同步同一条坑到公开仓并 push。
  强健性：仓库根/坑账/标题运行时探测；自签证书、非快进、离线均自动处理（见 skill-env.ps1 / doctor.ps1）。
.EXAMPLE
  # 生成建议（不提交）——agent 默认这样调，然后把建议交给用户确认
  pwsh -File scripts/add-pitfall.ps1 -Category 控件读值 -Phenomenon "运行时抛『属性类型不正确』" -Cause "枚举用 GetInteger 读值" -Fix "改用 GetEnum"
.EXAMPLE
  # 人工确认后：同一条命令末尾加 -Commit，才真正写入+提交+推送
  pwsh -File scripts/add-pitfall.ps1 -Category 控件读值 -Phenomenon "..." -Cause "..." -Fix "..." -Commit
#>
param(
    [Parameter(Mandatory)][ValidateSet('中文编码','控件读值','保留字','链接库','API','几何算法','流程协作','CAM','模块专属')]
    [string]$Category,
    [Parameter(Mandatory)][string]$Phenomenon,
    [Parameter(Mandatory)][string]$Cause,
    [Parameter(Mandatory)][string]$Fix,
    [switch]$Commit,     # 人工确认：真正写入 + 提交 + 推送
    [switch]$Yes,        # -Commit 的同义词（跳过交互确认）
    [switch]$NoPush,     # 确认后只本地提交，不 push（也不同步公开仓）
    [switch]$NoMirror    # 确认后只更新私有仓，不同步公开仓
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'skill-env.ps1')

# ---- 运行时探测仓库根与坑账（目录名无关；文件改名也能认）----
$RepoRoot = Resolve-RepoRoot -Start $PSScriptRoot
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }   # 兜底
$Ledger   = Resolve-Ledger -RepoRoot $RepoRoot
if (-not $Ledger) { throw "在 $RepoRoot 找不到坑账文件（*踩坑*.md）。先跑 doctor.ps1 体检。" }
$LedgerName = Split-Path $Ledger -Leaf

# ---- 动态定位分类标题，计算插入结果（纯计算，无任何副作用）----
$lines    = Get-Content -LiteralPath $Ledger -Encoding UTF8
$startIdx = Get-LedgerHeadingIndex -Lines $lines -Category $Category
if ($startIdx -lt 0) {
    $have = ($lines | Where-Object { $_ -match '^##\s' }) -join '; '
    throw "坑账里找不到【$Category】对应的分类标题。现有标题：$have"
}
$entry  = "- **$Phenomenon** → $Cause → **$Fix**"
$endIdx = $lines.Count
for ($i = $startIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s' -or $lines[$i] -match '^---\s*$') { $endIdx = $i; break }
}
$insertAt = $endIdx
while ($insertAt -gt $startIdx + 1 -and [string]::IsNullOrWhiteSpace($lines[$insertAt - 1])) { $insertAt-- }
$newLines = @()
$newLines += $lines[0..($insertAt - 1)]
$newLines += $entry
if ($insertAt -le $lines.Count - 1) { $newLines += $lines[$insertAt..($lines.Count - 1)] }

# ---- 弹出建议 ----
$sectionTitle = ($lines[$startIdx] -replace '^#+\s*','').Trim()
Write-Host ""
Write-Host "── 建议新增坑（待人工确认，尚未写入/提交）──" -ForegroundColor Cyan
Write-Host "  文件 : $LedgerName" -ForegroundColor DarkGray
Write-Host "  小节 : $sectionTitle" -ForegroundColor DarkGray
Write-Host "  条目 : $entry" -ForegroundColor Green
Write-Host ""

# ---- 是否已确认？----
$confirmed = $false
if ($Commit -or $Yes) {
    $confirmed = $true
} elseif (-not [Console]::IsInputRedirected) {
    # 真人终端：追加交互确认
    $ans = Read-Host "确认写入坑账并提交推送(私有仓+公开仓)？[y/N]"
    $confirmed = ($ans -match '^(y|yes)$')
    if (-not $confirmed) { Write-Host "已取消，未改动任何文件。" -ForegroundColor Yellow; return }
} else {
    # 非交互(agent/管道)：只给建议，交人工确认
    Write-Host "这是建议，未改动任何文件、未提交。" -ForegroundColor Yellow
    Write-Host "人工确认无误后，在同一条命令末尾加  -Commit  重跑即可写入+提交+推送。" -ForegroundColor Yellow
    return
}

# ================= 以下仅在确认后执行 =================

# ---- 写回坑账（UTF-8 无 BOM）----
[System.IO.File]::WriteAllLines($Ledger, $newLines, (New-Object System.Text.UTF8Encoding $false))
Write-Host "✓ 已写入 $LedgerName" -ForegroundColor Green

# ---- 提交信息（署名/设备名可用环境变量覆盖）----
$cfg      = Get-GiteaConfig
$device   = if ($env:GITEA_DEVICE) { $env:GITEA_DEVICE } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'unknown-device' }
$coauthor = if ($env:GITEA_COAUTHOR) { $env:GITEA_COAUTHOR } else { 'Claude Code <noreply@anthropic.com>' }
$subject  = "docs(pitfall): $Phenomenon"; if ($subject.Length -gt 72) { $subject = $subject.Substring(0,69) + '...' }
$body     = "[$Category] $Phenomenon`n根因: $Cause`n解法: $Fix"

function Commit-And-Push {
    param([string]$Dir,[string[]]$Paths)
    Push-Location $Dir
    try {
        if (-not (Test-Path (Join-Path $Dir '.git'))) { Write-Warning "$Dir 不是 git 仓库，跳过提交。"; return }
        & git add @Paths | Out-Null
        if (-not (& git status --porcelain)) { Write-Host "(无变化，无需提交)" -ForegroundColor Yellow; return }
        & git commit -m $subject -m $body -m "Co-Authored-By: $coauthor" -m "Agent: $coauthor" -m "Device: $device" | Out-Null
        Write-Host "✓ 已提交：$subject  @ $(Split-Path $Dir -Leaf)" -ForegroundColor Green
        if ($NoPush) { Write-Host "(已跳过 push，-NoPush)" -ForegroundColor Yellow; return }
        $r = Invoke-SafeGitPush -Dir $Dir -Cfg $cfg
        if ($r.Ok) { Write-Host ("✓ 已推送 @ {0}{1}" -f (Split-Path $Dir -Leaf), $(if ($r.Rebased){'（已自动 rebase）'}else{''})) -ForegroundColor Green }
        else       { Write-Warning "推送失败（提交已在本地保存，不会丢；联网/修好后 git push 即可）：$($r.Reason)" }
    } finally { Pop-Location }
}

# ---- 私有仓 ----
Commit-And-Push -Dir $RepoRoot -Paths @($LedgerName)

# ---- 公开仓 nx_dev_handbook：默认同步（找不到就自动克隆）----
if (-not $NoMirror -and -not $NoPush) {
    $PublicRoot = Resolve-PublicRoot -PrivateRoot $RepoRoot
    if (-not $PublicRoot) {
        Write-Host "未发现公开仓工作副本，尝试自动克隆…" -ForegroundColor DarkGray
        $c = Install-PublicClone -PrivateRoot $RepoRoot -Cfg $cfg
        if ($c.Ok) { $PublicRoot = $c.Path; Write-Host "✓ 已自动克隆公开仓到 $PublicRoot" -ForegroundColor Green }
        else       { Write-Warning "公开仓不可用（$($c.Reason)）：本条坑只进了私有仓。修复后可跑 doctor.ps1 或手动同步。" }
    }
    if ($PublicRoot) {
        try {
            $knowledge = Get-ChildItem -LiteralPath $RepoRoot -Filter '0*.md' -File | ForEach-Object { $_.Name }
            foreach ($f in $knowledge) { Copy-Item -LiteralPath (Join-Path $RepoRoot $f) -Destination (Join-Path $PublicRoot $f) -Force }
            if (Test-Path (Join-Path $RepoRoot 'templates')) { Copy-Item -LiteralPath (Join-Path $RepoRoot 'templates') -Destination $PublicRoot -Recurse -Force }
            Commit-And-Push -Dir $PublicRoot -Paths (@($knowledge) + 'templates')
        } catch { Write-Warning "同步公开仓失败（不影响私有仓已完成的提交）：$($_.Exception.Message)" }
    }
}
