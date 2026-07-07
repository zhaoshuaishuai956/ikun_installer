# ============================================================
#  build.ps1  -  编译 ikun_installer 并复制到发布目录
#  用法: pwsh -ExecutionPolicy Bypass -File .\build.ps1
#
#  规则: 子项目目录放入 .ready 标记文件即视为"已完成",
#        build.ps1 自动同步其 dll+dlx 到安装器并编译。
#        .ready 内容可写一行功能描述 (可选)。
# ============================================================
$ErrorActionPreference = 'Stop'

# 用脚本自身路径定位项目 (避免 $PSScriptRoot 被循环污染)
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstDir     = $ScriptDir
$Publish     = Join-Path $InstDir "publish"
$Deploy      = "Y:\1.宛美机械管理资料\1.技术类别\1.常用软件\爱坤工具箱"
$ProjectsDir = "E:\NX二次开发\项目"
$AppRes      = Join-Path $InstDir "DeployResources\application"
$StartupRes  = Join-Path $InstDir "DeployResources\startup"

# 子项目名 → 图标文字映射 (BMP 24x24 按钮图标)
$subIcon = @{
    "ejector_layout"          = "顶针"
    "pmi_hole_dim - deepseek" = "PMI"
    "MultiEntityNester"       = "排样"
    "smart_ejector_heater"    = "加热"
    "block_boss_layout"       = "凸台"
    "single_line_text"        = "刻字"
}

# =============================================================
#  [1/5] 扫描 .ready 标记, 自动同步 dll+dlx
# =============================================================
Write-Host "[1/5] 扫描已完成子项目..." -ForegroundColor Cyan

$readyProjects = @()
Get-ChildItem $ProjectsDir -Directory | ForEach-Object {
    $marker = Join-Path $_.FullName ".ready"
    if (Test-Path $marker) { $readyProjects += $_ }
}

if ($readyProjects.Count -eq 0) { throw "没有找到 .ready 标记的子项目, 请在已完成的项目目录下创建 .ready 文件" }

# 确保 DeployResources 目录存在
New-Item -ItemType Directory -Force $AppRes | Out-Null
New-Item -ItemType Directory -Force $StartupRes | Out-Null

# 阶段 1a: 同步 dll+dlx
Write-Host "  -- 同步 DLL/DLX --" -ForegroundColor DarkGray
$synced = 0
foreach ($proj in $readyProjects) {
    $name = $proj.Name
    $dlls = Get-ChildItem "$($proj.FullName)\*.dll" -ErrorAction SilentlyContinue
    foreach ($dll in $dlls) {
        $dest = Join-Path $AppRes $dll.Name
        $needCopy = $true
        if (Test-Path $dest) {
            if ($dll.LastWriteTime -le (Get-Item $dest).LastWriteTime) { $needCopy = $false }
        }
        if ($needCopy) {
            Copy-Item $dll.FullName $dest -Force
            Write-Host "    $name -> $($dll.Name)" -ForegroundColor Green
            $synced++
        }
    }
    $dlxs = Get-ChildItem "$($proj.FullName)\*.dlx" -ErrorAction SilentlyContinue
    foreach ($dlx in $dlxs) {
        $dest = Join-Path $AppRes $dlx.Name
        $needCopy = $true
        if (Test-Path $dest) {
            if ($dlx.LastWriteTime -le (Get-Item $dest).LastWriteTime) { $needCopy = $false }
        }
        if ($needCopy) {
            Copy-Item $dlx.FullName $dest -Force
            Write-Host "    $name -> $($dlx.Name)" -ForegroundColor Green
            $synced++
        }
    }
    # 附带数据文件 (如 single_line_text 的 slfont.dat 单线字库), 与 dll 同目录部署
    $dats = Get-ChildItem "$($proj.FullName)\*.dat" -ErrorAction SilentlyContinue
    foreach ($dat in $dats) {
        $dest = Join-Path $AppRes $dat.Name
        $needCopy = $true
        if (Test-Path $dest) {
            if ($dat.LastWriteTime -le (Get-Item $dest).LastWriteTime) { $needCopy = $false }
        }
        if ($needCopy) {
            Copy-Item $dat.FullName $dest -Force
            Write-Host "    $name -> $($dat.Name)" -ForegroundColor Green
            $synced++
        }
    }
}
Write-Host "  同步文件: $synced 个" -ForegroundColor Green

# 阶段 1b: 生成缺失的工具栏 BMP 图标 (24x24, 橙色文字)
Write-Host "  -- 检查工具栏图标 --" -ForegroundColor DarkGray
$syncedBmp = 0; $missBmp = 0
foreach ($proj in $readyProjects) {
    $dlls = Get-ChildItem "$($proj.FullName)\*.dll" -ErrorAction SilentlyContinue
    $dllBase = ($dlls | Select-Object -First 1).BaseName
    if (-not $dllBase) { continue }
    $bmpName = "ikun_$dllBase.bmp"
    if (Test-Path (Join-Path $StartupRes $bmpName)) { continue }

    $missBmp++
    $iconText = if ($subIcon.ContainsKey($proj.Name)) { $subIcon[$proj.Name] } else { $dllBase.Substring(0, [Math]::Min(2, $dllBase.Length)) }
    Write-Host "    生成图标: $bmpName (文字: $iconText)" -ForegroundColor Cyan
    try {
        python -c @"
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (24,24), (255,255,255))
draw = ImageDraw.Draw(img)
try: font = ImageFont.truetype('C:/Windows/Fonts/simhei.ttf', 11)
except: font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 10)
bbox = draw.textbbox((0,0), '$iconText', font=font)
tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
x, y = (24-tw)//2, (24-th)//2-1
draw.text((x,y), '$iconText', fill=(255,140,0), font=font)
draw.rectangle([1,1,22,22], outline=(200,200,200))
img.save(r'$($StartupRes.Replace('\','\\'))\\$bmpName')
print('OK')
"@ 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "      -> 已生成" -ForegroundColor Green; $syncedBmp++ }
        else                     { Write-Host "      -> 失败 (需 pip install Pillow)" -ForegroundColor DarkYellow }
    } catch {
        Write-Host "      -> 失败: $_" -ForegroundColor DarkYellow
    }
}
if ($missBmp -eq 0) { Write-Host "  图标: 全部就绪" -ForegroundColor Green }
elseif ($syncedBmp -eq $missBmp) { Write-Host "  图标: 生成 $syncedBmp 个" -ForegroundColor Green }
else { Write-Host "  图标: 生成 $syncedBmp / 缺失 $missBmp (请检查)" -ForegroundColor DarkYellow }
Write-Host ""

# =============================================================
#  [2/5] 编译安装器
# =============================================================
Write-Host "[2/5] 编译 ikun_installer ..." -ForegroundColor Cyan
dotnet publish "$InstDir\ikun_installer.csproj" -c Release -o $Publish
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

$exe = Join-Path $Publish "ikun_installer.exe"
if (-not (Test-Path $exe)) { throw "未找到产出: $exe" }
$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host "  产出: ikun_installer.exe ($size MB)" -ForegroundColor Green
Write-Host ""

# =============================================================
#  [3/5] 复制到发布目录
# =============================================================
Write-Host "[3/5] 复制到 $Deploy ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force $Deploy | Out-Null
Copy-Item $exe $Deploy -Force
Write-Host "  已复制" -ForegroundColor Green
Write-Host ""

# =============================================================
#  [4/5] 生成更新说明
# =============================================================
Write-Host "[4/5] 生成更新说明 ..." -ForegroundColor Cyan

$dateStr  = Get-Date -Format "yyyy-MM-dd HH:mm"
$clPath   = Join-Path $Deploy "更新说明.txt"
$lines    = [System.Collections.Generic.List[string]]::new()

$lines.Add("========================================")
$lines.Add("  爱坤工具箱 更新说明")
$lines.Add("  生成时间: $dateStr")
$lines.Add("========================================")
$lines.Add("")

$dllCount = 0
foreach ($proj in $readyProjects) {
    $projDir  = $proj.FullName
    $projName = $proj.Name

    # 功能描述: 取 .ready 文件内容, 若无则用内置映射
    $readyContent = (Get-Content (Join-Path $projDir ".ready") -Raw -Encoding UTF8).Trim()
    $desc = if ($readyContent -and $readyContent -ne "已完成") { $readyContent }
            elseif ($subIcon.ContainsKey($projName)) { $subIcon[$projName] }
            else { $projName }

    $lines.Add("  ● $desc")

    # 最近更新
    $cl = Join-Path $projDir "CHANGELOG.md"
    if (Test-Path $cl) {
        $content = Get-Content $cl -Raw -Encoding UTF8
        if ($content -match "##\s*v?([\d.]+)\s*\((\d{4}-\d{2}-\d{2})\)") {
            $ver  = $Matches[1]
            $date = $Matches[2]
            $rest = $content.Substring($content.IndexOf($Matches[0]) + $Matches[0].Length)
            $firstLine = ($rest -split "\n" | Where-Object { $_ -match '\S' } | Select-Object -First 1)
            if ($firstLine -match '\*\*(.+?)\*\*') { $summary = $Matches[1].Trim() }
            else { $summary = ($firstLine -replace '\*\*', '' -replace '`[^`]*`', '').Trim() }
            if ($summary -and $summary.Length -gt 2) { $lines.Add("    最近更新: v$ver ($date) — $summary") }
            else                                     { $lines.Add("    最近更新: v$ver ($date)") }
        }
    } else {
        $srcDll = Get-ChildItem "$projDir\*.dll" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($srcDll) { $lines.Add("    更新于: $($srcDll.LastWriteTime.ToString('yyyy-MM-dd'))") }
    }
    $lines.Add("")
    $dllCount++
}

$lines.Add("本次安装包含 $dllCount 个工具插件, 安装后重启 NX 即可使用。")
$lines.Add("")

# --- 使用说明 ---
$lines.Add("========================================")
$lines.Add("  使用说明")
$lines.Add("========================================")
$lines.Add("")
$lines.Add("1. 运行安装器, 确认 NX 1847 路径后点击「安装」")
$lines.Add("2. 重启 NX 1847, 菜单栏 Help 右侧出现「爱坤工具箱」")
$lines.Add("3. 点击「爱坤工具箱」下拉, 选择对应工具:")
foreach ($proj in $readyProjects) {
    $readyContent = (Get-Content (Join-Path $proj.FullName ".ready") -Raw -Encoding UTF8).Trim()
    $desc = if ($readyContent -and $readyContent -ne "已完成") { $readyContent } else { $proj.Name }
    $lines.Add("   - $desc")
}
$lines.Add("4. 更新: 重新运行安装器覆盖安装即可")
$lines.Add("")

[System.IO.File]::WriteAllLines($clPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "  已生成 -> $clPath" -ForegroundColor Green
Write-Host ""

# =============================================================
#  [5/5] 备份 E:\NX二次开发 → X:\
# =============================================================
$BackupSrc  = "E:\NX二次开发"
$BackupDst  = "X:\NX二次开发"
Write-Host "[5/5] 备份 $BackupSrc → $BackupDst ..." -ForegroundColor Cyan

if (-not (Test-Path "X:\")) {
    Write-Host "  X: 盘不可用, 跳过备份" -ForegroundColor DarkYellow
} else {
    New-Item -ItemType Directory -Force $BackupDst | Out-Null
    # robocopy 增量镜像: 只复制变化的文件, 保留目录结构, 并行8线程
    $rc = robocopy $BackupSrc $BackupDst /MIR /R:2 /W:3 /MT:8 /NDL /NP /NJH /NJS
    # robocopy 返回码 0-7 均正常 (0=无变化,1=有复制,2=额外文件,3=1+2,4=不匹配,5=3+4,6=4+额外,7=5+额外)
    if ($LASTEXITCODE -ge 8) {
        Write-Host "  备份异常 (robocopy exit $LASTEXITCODE)" -ForegroundColor DarkYellow
    } else {
        Write-Host "  备份完成" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "完成!" -ForegroundColor Green