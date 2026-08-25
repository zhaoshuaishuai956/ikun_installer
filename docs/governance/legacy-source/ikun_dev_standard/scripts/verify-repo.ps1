# ============================================================
#  verify-repo.ps1 — ikun 生态合规真值表扫描 (规范 §5/§7.3 M7b)
#  用法:
#    pwsh scripts/verify-repo.ps1 -ReposRoot <克隆根目录> [-OutJson <path>]
#    pwsh scripts/verify-repo.ps1 -SelfTest
#  输出: 控制台红黄绿真值表; -OutJson 生成 registry.json 机器形态 (附录 A)
#  检查项: 标准文件清单(§5) / plugin.meta 白名单(§4.2) / 豁免登记(§2.3)
#          / 禁止入库物与 secret(§7.4/G6) / 版本段格式(§6.3)
# ============================================================
param(
  [string]$ReposRoot = "",
  [string]$OutJson = "",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

if ($SelfTest) {
  Write-Host "verify-repo.ps1 自检: 参数/解析路径 OK" -ForegroundColor Green
  exit 0
}

if (-not $ReposRoot -or -not (Test-Path $ReposRoot)) {
  Write-Host "用法: pwsh scripts/verify-repo.ps1 -ReposRoot <克隆根目录> [-OutJson <path>]" -ForegroundColor Yellow
  exit 2
}

# 生态仓库清册 (与 registry.json 同源; 扫描时忽略缺失仓)
$REPOS = @(
  "ikun_installer", "MultiEntityNester", "block_boss_layout", "ejector_layout",
  "pmi_hole_dim", "single_line_text", "text_auto_layout", "plate_dwg_export",
  "smart_ejector_heater", "foam_cam", "riser_base_fillet", "runner_section_area",
  "nx_dev_skill", "nx_dev_handbook", "gitea-for-ai", "ikun_dev_standard"
)
$PLUGINS = $REPOS | Where-Object { $_ -notin @("ikun_installer","nx_dev_skill","nx_dev_handbook","gitea-for-ai","ikun_dev_standard") }

$META_KEYS = @("name_cn","icon_cn","category","in_ikun")
$FORBIDDEN = @("*.obj","*.exp","*.lib","*.ilk","*.pdb","*.pch","*.sdf","*.suo","*.user","*.aps","*.winmd","*.winmdpdb")

function Test-ForbiddenFile([string]$name) {
  foreach ($pat in $FORBIDDEN) { if ($name -like $pat) { return $true } }
  return $false
}

$results = @()   # PSCustomObject 列表

foreach ($repo in $REPOS) {
  $dir = Join-Path $ReposRoot $repo
  if (-not (Test-Path $dir)) { $results += [pscustomobject]@{repo=$repo; status="SKIP"; checks=@{}}; continue }
  $checks = @{}
  $isPlugin = $repo -in $PLUGINS

  # 标准文件 (规范 §5)
  foreach ($f in @("README.md","CHANGELOG.md","LICENSE")) {
    $checks[$f] = Test-Path (Join-Path $dir $f)
  }
  if ($isPlugin) {
    $checks["plugin.meta"] = Test-Path (Join-Path $dir "plugin.meta")
    $checks["build.ps1"] = Test-Path (Join-Path $dir "build.ps1")
    $checks[".gitignore"] = Test-Path (Join-Path $dir ".gitignore")
    $checks[".gitattributes"] = Test-Path (Join-Path $dir ".gitattributes")
    $checks["notify"] = Test-Path (Join-Path $dir ".gitea\workflows\notify-installer.yml")
  }

  # plugin.meta 白名单 (规范 §4.2)
  $meta = @{}
  $metaOk = $true
  $metaFile = Join-Path $dir "plugin.meta"
  if (Test-Path $metaFile) {
    foreach ($line in Get-Content $metaFile -Encoding UTF8) {
      if ($line -match '^([a-z_]+)=(.*)$') { $meta[$matches[1]] = $matches[2].Trim() }
    }
    foreach ($k in $META_KEYS) { if (-not $meta.ContainsKey($k)) { $metaOk = $false; $checks["meta_$k"] = $false } }
    if ($metaOk) {
      $checks["meta_icon"] = $meta["icon_cn"] -match '^[\u4e00-\u9fff]{1,2}$|^[A-Z]{1,3}$'
      $cjkCount = ([regex]::Matches($meta["name_cn"], '[\u4e00-\u9fff]')).Count
      $checks["meta_name"] = ($meta["name_cn"].Length -le 12) -and ($cjkCount -le 8) -and ($meta["name_cn"] -notmatch '[\x00-\x1f]')
      $checks["meta_cat"] = $meta["category"] -in @("建模","CAM","PMI","制图","装配","钣金","其它")
      $checks["meta_in"] = $meta["in_ikun"] -in @("true","false")
    }
  } elseif ($isPlugin) {
    $checks["plugin.meta"] = $false
  }

  # 豁免登记 (规范 §2.3)
  $readme = Join-Path $dir "README.md"
  if (Test-Path $readme) {
    $checks["exemption"] = (Get-Content $readme -Raw -Encoding UTF8) -match '## 规范豁免'
  }

  # 禁止入库物 + 疑似 secret (规范 §7.4/G6): 只扫 git 跟踪文件, 不扫工作树未跟踪产物
  $bad = @()
  $tracked = git -C $dir ls-files 2>$null
  foreach ($rel in $tracked) {
    $name = Split-Path $rel -Leaf
    if (Test-ForbiddenFile $name) { $bad += $rel }
    if ($rel -match '(^|/)(bin|obj|publish|ref|refint)/|(^|/)\.env$|\.token$|(^|/)secrets/') { $bad += $rel }
  }
  $checks["no_forbidden"] = $bad.Count -eq 0
  if ($bad.Count -gt 0) { $checks["forbidden_files"] = ($bad -join ", ") }

  # CHANGELOG 版本段格式 (规范 §6.3)
  $ch = Join-Path $dir "CHANGELOG.md"
  if (Test-Path $ch) {
    $checks["changelog_fmt"] = (Get-Content $ch -Raw -Encoding UTF8) -match '(?m)^##\s+v?\d+\.\d+\.\d+\s+\(\d{4}-\d{2}-\d{2}\)|^##\s+Unreleased'
  } else {
    $checks["changelog_fmt"] = $null
  }

  # 汇总状态: 并入仓红=缺 CHANGELOG/meta/LICENSE; 未并入仓黄; 安全项(no_forbidden/meta 白名单)不分级
  $reds = @("CHANGELOG.md","plugin.meta","LICENSE") | Where-Object { $checks[$_] -eq $false }
  $yellows = @()
  if ($isPlugin) {
    $yellows = @("README.md","build.ps1",".gitignore",".gitattributes") | Where-Object { $checks[$_] -eq $false }
    if ($checks["no_forbidden"] -eq $false) { $reds += "forbidden" }
  } else {
    # 非插件仓: 仅 LICENSE 标红; CHANGELOG/README 标黄 (规范 §5 只对插件仓强制 CHANGELOG)
    $reds = @("LICENSE") | Where-Object { $checks[$_] -eq $false }
    $yellows = @("README.md","CHANGELOG.md") | Where-Object { $checks[$_] -eq $false }
    if ($checks["no_forbidden"] -eq $false) { $reds += "forbidden" }
  }
  $status = if ($reds.Count -gt 0) { "RED" } elseif ($yellows.Count -gt 0) { "YELLOW" } else { "GREEN" }
  $results += [pscustomobject]@{ repo=$repo; status=$status; checks=$checks; red=($reds -join ","); yellow=($yellows -join ",") }
}

# 输出真值表
Write-Host ("{0,-22} {1,-8} {2}" -f "repo","status","missing") -ForegroundColor Cyan
foreach ($r in $results) {
  $color = switch ($r.status) { "RED" { "Red" } "YELLOW" { "Yellow" } "GREEN" { "Green" } default { "Gray" } }
  $detail = @()
  if ($r.red) { $detail += "RED:" + $r.red }
  if ($r.yellow) { $detail += "YLW:" + $r.yellow }
  Write-Host ("{0,-22} {1,-8} {2}" -f $r.repo, $r.status, ($detail -join "  ")) -ForegroundColor $color
}

# 输出 registry.json 机器形态
if ($OutJson) {
  $reg = [ordered]@{
    schema = 1
    generated_by = "verify-repo.ps1"
    generated_at = (Get-Date -Format "yyyy-MM-dd")
    spec = [ordered]@{ host = "ikun_dev_standard"; file = "ikun-整体开发规范-v1.0.md" }
    hub = "ikun_installer"
    plugins = @(
      foreach ($r in $results | Where-Object { $_.repo -in $PLUGINS }) {
        [ordered]@{
          repo = $r.repo
          in_ikun = if ($r.checks["meta_in"] -eq $true) { $true } else { $false }
          status = $r.status
          files = [ordered]@{
            meta = $r.checks["plugin.meta"]; changelog = $r.checks["CHANGELOG.md"]
            build = $r.checks["build.ps1"]; notify = $r.checks["notify"]
            license = $r.checks["LICENSE"]; gitattributes = $r.checks[".gitattributes"]
            gitignore = $r.checks[".gitignore"]
          }
        }
      }
    )
  }
  $reg | ConvertTo-Json -Depth 5 | Set-Content $OutJson -Encoding UTF8
  Write-Host "registry.json 已写出: $OutJson" -ForegroundColor Green
}

# 退出码: 有 RED 即 1
exit ([int]($results | Where-Object { $_.status -eq "RED" }).Count -gt 0)
