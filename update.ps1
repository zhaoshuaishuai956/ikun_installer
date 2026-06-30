# ============================================================
#  update.ps1  -  爱坤工具箱 快速更新
#  自动扫描 E:\NX二次开发\项目\ 下所有子项目
#  检查标题是否含"爱坤"、目录关系、时间戳，同步到 ikun tools
# ============================================================
$AppDir = "D:\Program Files\ikun tools\application"
$ProjectsDir = "E:\NX二次开发\项目"
if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Force $AppDir | Out-Null }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  爱坤工具箱 自动更新扫描" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$updated = 0; $skipped = 0; $errors = 0

# 扫描所有子项目目录
Get-ChildItem $ProjectsDir -Directory | ForEach-Object {
    $projDir = $_.FullName
    $projName = $_.Name

    # 跳过非项目目录
    $dlls = Get-ChildItem "$projDir\*.dll" -ErrorAction SilentlyContinue
    $dlxs = Get-ChildItem "$projDir\*.dlx" -ErrorAction SilentlyContinue
    if (-not $dlls -and -not $dlxs) { return }

    Write-Host "[$projName]" -ForegroundColor Yellow

    # 检查 dlx 标题是否含"爱坤"
    $dlxMissTitle = $false
    foreach ($dlx in $dlxs) {
        $content = Get-Content $dlx.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($content -and $content -notmatch "爱坤") {
            Write-Host "  ! 标题未含'爱坤': $($dlx.Name)" -ForegroundColor DarkYellow
            $dlxMissTitle = $true
        }
    }
    if ($dlxMissTitle) {
        Write-Host "  建议: 在 dlx 标题前添加'爱坤工具箱-'" -ForegroundColor DarkGray
    }

    # 同步 DLL
    foreach ($dll in $dlls) {
        $dest = Join-Path $AppDir $dll.Name
        $needUpdate = $true
        if (Test-Path $dest) {
            if ($dll.LastWriteTime -le (Get-Item $dest).LastWriteTime) { $needUpdate = $false }
        }
        if ($needUpdate) {
            try {
                Copy-Item $dll.FullName $dest -Force
                Write-Host "  -> $($dll.Name) (已更新)" -ForegroundColor Green
                $updated++
            } catch {
                Write-Host "  -> $($dll.Name) (失败: $_)" -ForegroundColor Red
                $errors++
            }
        } else {
            Write-Host "  -> $($dll.Name) (已是最新)" -ForegroundColor DarkGray
            $skipped++
        }
    }

    # 同步 DLX
    foreach ($dlx in $dlxs) {
        $dest = Join-Path $AppDir $dlx.Name
        $needUpdate = $true
        if (Test-Path $dest) {
            if ($dlx.LastWriteTime -le (Get-Item $dest).LastWriteTime) { $needUpdate = $false }
        }
        if ($needUpdate) {
            try {
                Copy-Item $dlx.FullName $dest -Force
                Write-Host "  -> $($dlx.Name) (已更新)" -ForegroundColor Green
                $updated++
            } catch {
                Write-Host "  -> $($dlx.Name) (失败: $_)" -ForegroundColor Red
                $errors++
            }
        } else {
            Write-Host "  -> $($dlx.Name) (已是最新)" -ForegroundColor DarkGray
            $skipped++
        }
    }
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  已更新: $updated  已是最新: $skipped  错误: $errors" -ForegroundColor White
if ($updated -gt 0) { Write-Host "  重启 NX 生效" -ForegroundColor Green }
Write-Host "========================================" -ForegroundColor Cyan
