#requires -Version 5
<#
.SYNOPSIS
  一键体检 + 自愈：任何新用户遇到环境/目录/仓库/网络问题，先跑这个。
.DESCRIPTION
  逐项探测工具链与仓库状态，能自动修的直接修（自动发现/克隆公开仓、配 remote、
  设自签证书豁免），修不了的给出「确切的下一步命令」。幂等，可反复运行。
.EXAMPLE
  pwsh -File scripts/doctor.ps1
.EXAMPLE
  pwsh -File scripts/doctor.ps1 -Fix    # 允许自动修复（默认即开；-Fix 仅为显式表达意图）
.NOTES
  退出码：0 = 无致命问题（可能有 WARN）；1 = 有 FAIL（需照提示处理）。
#>
param([switch]$Fix)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'skill-env.ps1')

$results = New-Object System.Collections.Generic.List[object]
function Add-Result { param([string]$Name,[ValidateSet('OK','FIXED','WARN','FAIL')]$Status,[string]$Detail,[string]$Fix='')
    $results.Add([pscustomobject]@{ Name=$Name; Status=$Status; Detail=$Detail; Fix=$Fix }) }

Write-Host "`n=== NX 二次开发知识库 · 环境体检 ===`n" -ForegroundColor Cyan

# 1) PowerShell
$psv = $PSVersionTable.PSVersion
if ($psv.Major -ge 7)      { Add-Result 'PowerShell' OK   "v$psv" }
elseif ($psv.Major -ge 5)  { Add-Result 'PowerShell' WARN "v$psv（建议装 PowerShell 7：winget install Microsoft.PowerShell）" }
else                       { Add-Result 'PowerShell' FAIL "v$psv 过低" 'winget install Microsoft.PowerShell' }

# 2) git
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Add-Result 'git' OK ((& git --version)) }
else      { Add-Result 'git' FAIL '未找到 git' 'winget install Git.Git 然后重开终端' }

# 3) 私有仓根（坑账定位）
$PrivateRoot = Resolve-RepoRoot -Start $PSScriptRoot
if ($PrivateRoot) {
    $ledger = Resolve-Ledger -RepoRoot $PrivateRoot
    Add-Result '私有仓根/坑账' OK "$PrivateRoot`n           坑账: $(Split-Path $ledger -Leaf)"
} else {
    Add-Result '私有仓根/坑账' FAIL '从脚本位置向上找不到坑账文件（*踩坑*.md）' '确认在 nx_dev_skill 工作副本内运行本脚本'
}

# 4) 私有仓 remote
if ($PrivateRoot -and (Test-Path (Join-Path $PrivateRoot '.git'))) {
    $pr = (& git -C $PrivateRoot remote get-url origin 2>$null)
    if ($pr) { Add-Result '私有仓 remote' OK ($pr -replace '://[^/@]+@','://***@') }
    else     { Add-Result '私有仓 remote' WARN '未配置 origin（仅本地提交可用，无法 push）' '按 GITEA_* 设置后 git remote add origin <url>' }
} elseif ($PrivateRoot) {
    Add-Result '私有仓 remote' WARN '当前副本不是 git 仓库（可读知识，不能同步）' ''
}

# 5) Gitea 环境变量
$cfg = Get-GiteaConfig
if ($cfg.Ok) { Add-Result 'GITEA_* 环境变量' OK "host=$($cfg.Host) user=$($cfg.User) token=***" }
else {
    Add-Result 'GITEA_* 环境变量' WARN '未完整设置（离线可用：只本地提交，不推送）' `
      '设三个用户环境变量：setx GITEA_HOST ... ; setx GITEA_USER ... ; setx GITEA_TOKEN ..（重开终端生效）'
}

# 6) Gitea 可达性 + 鉴权（仅在环境变量齐全时）
if ($cfg.Ok) {
    if (Test-GiteaReachable -Cfg $cfg) {
        Add-Result 'Gitea 可达' OK $cfg.ApiBase
        if (Test-GiteaAuth -Cfg $cfg) { Add-Result 'Gitea 鉴权' OK 'token 有效' }
        else { Add-Result 'Gitea 鉴权' FAIL 'token 无效/过期（HTTP 401）' "到 $($cfg.ApiBase)/user/settings/applications 重新生成后更新 GITEA_TOKEN" }
    } else {
        Add-Result 'Gitea 可达' WARN "连不上 $($cfg.ApiBase)（离线/VPN/防火墙？）—— 本地提交不受影响，联网后再 push" ''
    }
}

# 7) 公开仓工作副本（目录/发现类：自动发现，找不到则自动克隆）
if ($PrivateRoot) {
    $pub = Resolve-PublicRoot -PrivateRoot $PrivateRoot
    if ($pub) { Add-Result '公开仓工作副本' OK $pub }
    else {
        $cloned = Install-PublicClone -PrivateRoot $PrivateRoot -Cfg $cfg
        if ($cloned.Ok) { Add-Result '公开仓工作副本' FIXED "已自动克隆到 $($cloned.Path)" }
        else            { Add-Result '公开仓工作副本' WARN "未找到且未能自动克隆：$($cloned.Reason)。坑仍会进私有仓，公开仓本次跳过。" "把公开仓克隆到 $(Split-Path $PrivateRoot -Parent)\nx_dev_handbook，或设 `$env:NX_HANDBOOK_DIR 指向它" }
    }
}

# 8) VS 工具链（编译模板/插件用）
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsRoot  = $null
if (Test-Path $vswhere) { $vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null }
if ($vsRoot) { Add-Result 'VS C++ 工具链' OK $vsRoot }
else {
    $guess = Get-ChildItem 'C:\Program Files*\Microsoft Visual Studio\*\*\VC\Auxiliary\Build\vcvars64.bat' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($guess) { Add-Result 'VS C++ 工具链' WARN "vswhere 未命中，但找到 $($guess.FullName)" '' }
    else        { Add-Result 'VS C++ 工具链' FAIL '未装 VS 的「使用 C++ 的桌面开发」' 'VS Installer 里勾选该工作负载（付费软件，无法自动安装）' }
}

# 9) NX SDK（UGOPEN）
$nx = $null
if ($env:UGII_ROOT_DIR) { $c = Join-Path (Split-Path $env:UGII_ROOT_DIR -Parent) 'UGOPEN'; if (Test-Path (Join-Path $c 'uf.h')) { $nx = $c } }
if (-not $nx) { $c = Get-ChildItem 'C:\Program Files\Siemens\NX*\UGOPEN\uf.h' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $nx = Split-Path $c.FullName -Parent } }
if ($nx) { Add-Result 'NX SDK (UGOPEN)' OK $nx }
else     { Add-Result 'NX SDK (UGOPEN)' FAIL '未找到 UGOPEN\uf.h' '装 NX，或设 UGII_ROOT_DIR 指向 NX 的 UGII 目录（付费软件，无法自动安装）' }

# ---- 汇总 ----
Write-Host ""
$icon = @{ OK='  ✓'; FIXED=' 🔧'; WARN=' ⚠'; FAIL=' ✗' }
$col  = @{ OK='Green'; FIXED='Green'; WARN='Yellow'; FAIL='Red' }
foreach ($r in $results) {
    Write-Host ("{0} {1,-16} {2}" -f $icon[$r.Status], $r.Name, $r.Detail) -ForegroundColor $col[$r.Status]
    if ($r.Fix) { Write-Host ("      ↳ 修复: {0}" -f $r.Fix) -ForegroundColor DarkGray }
}
$fails = @($results | Where-Object Status -eq 'FAIL')
$warns = @($results | Where-Object Status -eq 'WARN')
Write-Host ""
if ($fails.Count -eq 0 -and $warns.Count -eq 0) { Write-Host "全部通过：环境就绪。" -ForegroundColor Green; exit 0 }
if ($fails.Count -eq 0) { Write-Host "可用（有 $($warns.Count) 项告警，多为离线/公开仓未克隆，不阻塞核心流程）。" -ForegroundColor Yellow; exit 0 }
Write-Host "有 $($fails.Count) 项致命问题，按上面「修复」处理后重跑本脚本。" -ForegroundColor Red
exit 1
