#requires -Version 5
<#
  skill-env.ps1 —— NX 二次开发知识库工具链的「环境与仓库解析」共享函数。
  职责：把 add-pitfall.ps1 / doctor.ps1 里所有对目录、仓库、Gitea 的假设，
  统一收敛成运行时探测 + 自愈。被这两个脚本 dot-source 使用，不单独执行。

  设计原则（见 CONTRIBUTING.md 的强健性一节）：
  - 目录/发现类问题：完全自动（动态发现、必要时自动克隆）。
  - 网络自签证书 / 非快进：自动处理。
  - 离线：降级为仅本地提交，绝不丢数据。
  - 凭证缺失 / 工具未安装：无法凭空生成，给出确切的修复命令。
#>

# 公开仓库名（发现与自动克隆用）；私有仓与公开仓都以「坑账文件」为根标记。
$script:PublicRepoName  = 'nx_dev_handbook'
$script:LedgerGlob      = '*踩坑*.md'   # 坑账文件：改名/重编号也能认出，作为仓库根标记

# 分类 → 在坑账标题里查找的关键词（对编号/标题改写免疫）
$script:CategoryKeyword = [ordered]@{
    '中文编码' = '中文编码'
    '控件读值' = '控件读值'
    '保留字'   = '保留字'
    '链接库'   = '链接库'
    'API'      = 'API'
    '几何算法' = '几何'
    '流程协作' = '流程'
    'CAM'      = 'CAM'
    '模块专属' = '其它模块'
}

function Write-Step { param([string]$Msg,[string]$Color='Cyan') Write-Host $Msg -ForegroundColor $Color }

# ---- 仓库根：从起点向上找含坑账文件的目录（目录名无关）----
function Resolve-RepoRoot {
    param([string]$Start = $PSScriptRoot)
    $dir = Resolve-Path $Start -ErrorAction SilentlyContinue
    if (-not $dir) { return $null }
    $dir = $dir.Path
    while ($dir) {
        if (Get-ChildItem -LiteralPath $dir -Filter $script:LedgerGlob -File -ErrorAction SilentlyContinue) { return $dir }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Resolve-Ledger {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $f = Get-ChildItem -LiteralPath $RepoRoot -Filter $script:LedgerGlob -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName } else { return $null }
}

# ---- Gitea 配置：全部从环境变量读，规范化 host / API base ----
function Get-GiteaConfig {
    $raw = $env:GITEA_HOST
    $ok  = [bool]($raw -and $env:GITEA_USER -and $env:GITEA_TOKEN)
    $hostNoProto = if ($raw) { $raw -replace '^https?://','' } else { $null }
    $scheme = if ($raw -match '^http://') { 'http' } else { 'https' }
    [pscustomobject]@{
        Ok       = $ok
        Host     = $hostNoProto
        ApiBase  = if ($hostNoProto) { "${scheme}://$hostNoProto" } else { $null }
        User     = $env:GITEA_USER
        Token    = $env:GITEA_TOKEN
        Insecure = [bool]$env:GITEA_INSECURE -or ($scheme -eq 'https')  # 该 Gitea 用自签名证书，https 默认宽松（可用 GITEA_INSECURE 显式控制）
    }
}

# ---- 跨 PS5/PS7 的 Gitea API 调用（处理自签证书）----
function Invoke-GiteaApi {
    param([Parameter(Mandatory)][string]$Url, [hashtable]$Headers=@{}, [int]$TimeoutSec=15)
    $p = @{ Uri=$Url; Headers=$Headers; TimeoutSec=$TimeoutSec; ErrorAction='Stop' }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $p['SkipCertificateCheck'] = $true
    } else {
        try {
            Add-Type -ErrorAction SilentlyContinue @"
using System.Net;
public static class _NxCertOK { public static void On(){ ServicePointManager.ServerCertificateValidationCallback = delegate { return true; }; ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12; } }
"@
            [_NxCertOK]::On()
        } catch {}
    }
    Invoke-RestMethod @p
}

function Test-GiteaReachable { param([Parameter(Mandatory)]$Cfg)
    if (-not $Cfg.ApiBase) { return $false }
    try { Invoke-GiteaApi -Url "$($Cfg.ApiBase)/api/v1/version" -TimeoutSec 8 | Out-Null; return $true } catch { return $false }
}

function Test-GiteaAuth { param([Parameter(Mandatory)]$Cfg)
    if (-not $Cfg.Ok) { return $false }
    try { Invoke-GiteaApi -Url "$($Cfg.ApiBase)/api/v1/user" -Headers @{ Authorization = "token $($Cfg.Token)" } -TimeoutSec 8 | Out-Null; return $true } catch { return $false }
}

function Test-GiteaRepoExists { param([Parameter(Mandatory)]$Cfg,[Parameter(Mandatory)][string]$Name)
    try { Invoke-GiteaApi -Url "$($Cfg.ApiBase)/api/v1/repos/$($Cfg.User)/$Name" -Headers @{ Authorization = "token $($Cfg.Token)" } -TimeoutSec 8 | Out-Null; return $true } catch { return $false }
}

# ---- 公开仓工作副本：多策略发现 ----
function Resolve-PublicRoot {
    param([Parameter(Mandatory)][string]$PrivateRoot)
    # 1) 显式环境变量覆盖
    if ($env:NX_HANDBOOK_DIR -and (Test-Path (Join-Path $env:NX_HANDBOOK_DIR '.git'))) { return (Resolve-Path $env:NX_HANDBOOK_DIR).Path }
    $parent = Split-Path $PrivateRoot -Parent
    # 2) 同级同名目录
    $sib = Join-Path $parent $script:PublicRepoName
    if (Test-Path (Join-Path $sib '.git')) { return $sib }
    # 3) 扫描同级所有 git 仓库，按 remote url 认领
    foreach ($d in Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue) {
        if (-not (Test-Path (Join-Path $d.FullName '.git'))) { continue }
        $url = (& git -C $d.FullName remote get-url origin 2>$null)
        if ($url -and ($url -match "$($script:PublicRepoName)(\.git)?/?$")) { return $d.FullName }
    }
    return $null
}

# ---- 自动克隆公开仓到私有仓同级（目录/发现类问题的自愈核心）----
function Install-PublicClone {
    param([Parameter(Mandatory)][string]$PrivateRoot,[Parameter(Mandatory)]$Cfg)
    if (-not $Cfg.Ok)                              { return @{ Ok=$false; Reason='GITEA_* 环境变量未设，无法自动克隆公开仓' } }
    if (-not (Test-GiteaRepoExists -Cfg $Cfg -Name $script:PublicRepoName)) {
        return @{ Ok=$false; Reason="Gitea 上不存在仓库 $($Cfg.User)/$($script:PublicRepoName)（或无权限/不可达）" }
    }
    $dest = Join-Path (Split-Path $PrivateRoot -Parent) $script:PublicRepoName
    $url  = "$($Cfg.ApiBase)/$($Cfg.User)/$($script:PublicRepoName).git"
    $args = @('-c','http.sslVerify=false','-c',"http.extraheader=AUTHORIZATION: token $($Cfg.Token)",'clone',$url,$dest)
    & git @args 2>&1 | Out-Null
    if (Test-Path (Join-Path $dest '.git')) { return @{ Ok=$true; Path=$dest } }
    return @{ Ok=$false; Reason='git clone 失败' }
}

# ---- 在坑账里按分类关键词动态定位标题行（对编号/标题改写免疫）----
function Get-LedgerHeadingIndex {
    # 注意：$Lines 不能标 Mandatory —— Mandatory 的 [string[]] 会拒绝含空行的数组
    param([string[]]$Lines,[Parameter(Mandatory)][string]$Category)
    $kw = $script:CategoryKeyword[$Category]
    if (-not $kw) { return -1 }
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^##\s' -and $Lines[$i] -like "*$kw*") { return $i }
    }
    return -1
}

# ---- 安全 git push：处理自签证书、缺凭证、非快进（自动 pull --rebase 重试一次）----
function Invoke-SafeGitPush {
    param([Parameter(Mandatory)][string]$Dir,[Parameter(Mandatory)]$Cfg)
    $branch = (& git -C $Dir symbolic-ref --short HEAD 2>$null); if (-not $branch) { $branch = 'main' }
    $remoteUrl = (& git -C $Dir remote get-url origin 2>$null)
    if (-not $remoteUrl) { return @{ Ok=$false; Reason='本仓库没有配置 origin remote' } }
    $hasEmbedded = $remoteUrl -match '://[^/@]+@'   # remote 里已内嵌凭证
    $base = @('-C',$Dir)
    if ($Cfg.Insecure) { $base += @('-c','http.sslVerify=false') }
    if (-not $hasEmbedded -and $Cfg.Ok) { $base += @('-c',"http.extraheader=AUTHORIZATION: token $($Cfg.Token)") }

    $out = (& git @base push origin $branch 2>&1); $code = $LASTEXITCODE
    if ($code -eq 0) { return @{ Ok=$true } }
    # 非快进：远端有新提交 → 先 rebase 再推
    if ($out -match 'non-fast-forward|fetch first|rejected') {
        & git @base pull --rebase origin $branch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return @{ Ok=$false; Reason="远端有分叉且 rebase 冲突，需人工解决：$out" } }
        $out2 = (& git @base push origin $branch 2>&1)
        if ($LASTEXITCODE -eq 0) { return @{ Ok=$true; Rebased=$true } }
        return @{ Ok=$false; Reason="rebase 后推送仍失败：$out2" }
    }
    return @{ Ok=$false; Reason=($out | Out-String).Trim() }
}
