# ============================================================
#  build.ps1  -  编译 NX BlockStyler 工程为可加载 dll
#  用法: pwsh -ExecutionPolicy Bypass -File .\build.ps1
#  依赖: Visual Studio 2022 (C++ 工具集) + NX 1847 (UGOPEN)
#
#  路径策略: 自动探测 VS(vswhere) 与 NX(UGII_ROOT_DIR), 探测
#  不到再回退到产品默认安装路径。换机器一般无需改动。
# ============================================================
$ErrorActionPreference = 'Stop'

# ---- 工程名: 默认取本目录里唯一的 .cpp 文件名 ----
$Proj = $PSScriptRoot
$cpp  = Get-ChildItem $Proj -Filter *.cpp | Select-Object -First 1
if (-not $cpp) { throw "本目录找不到 .cpp 源文件" }
$Name = $cpp.BaseName

# ---- 校验 dlx 是合法 XML (cl/link 不碰 dlx, 坏 XML 要到 NX 加载才炸, 这里提前拦截) ----
# 读法必须固定 UTF-8: PS5.1 的 Get-Content 无 BOM 时按 ANSI 解码, 中文尾字节吞掉引号 → 好文件误报非法
foreach ($dlx in Get-ChildItem $Proj -Filter *.dlx) {
    try { [xml][IO.File]::ReadAllText($dlx.FullName, [Text.Encoding]::UTF8) | Out-Null }
    catch { throw "dlx 不是合法 XML ($($dlx.Name)): $($_.Exception.Message)`n常见根因: 手改/手拼控件块后丢了 </PropertyList></item></Property> 关闭标签" }
}
Write-Host "dlx : XML 校验通过" -ForegroundColor DarkGray

# ---- 探测 vcvars64.bat ----
$VcVars = $null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsRoot) { $VcVars = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat" }
}
if (-not $VcVars -or -not (Test-Path $VcVars)) {
    $VcVars = $env:VS_VCVARS_PATH  # 兜底1：环境变量
}
if (-not $VcVars -or -not (Test-Path $VcVars)) {
    # 兜底2：扫描默认安装路径 (Community/Professional/BuildTools 任意版本)
    $g = Get-ChildItem 'C:\Program Files*\Microsoft Visual Studio\*\*\VC\Auxiliary\Build\vcvars64.bat' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { $VcVars = $g.FullName }
}
if (-not $VcVars -or -not (Test-Path $VcVars)) {
    throw "找不到 vcvars64.bat。请安装 VS2022 的『使用 C++ 的桌面开发』(可跑 templates/setup-nx-dev-env.ps1 自动装)，或设环境变量 `$env:VS_VCVARS_PATH 指向 vcvars64.bat" }

# ---- 探测 NX UGOPEN 目录 ----
$NxOpen = $null
if ($env:UGII_ROOT_DIR -and (Test-Path $env:UGII_ROOT_DIR)) {
    # UGII_ROOT_DIR 通常是 ...\NX xxxx\UGII, UGOPEN 是其同级目录
    $cand = Join-Path (Split-Path $env:UGII_ROOT_DIR -Parent) "UGOPEN"
    if (Test-Path (Join-Path $cand "uf.h")) { $NxOpen = $cand }
}
if (-not $NxOpen) {
    $NxOpen = $env:NX_UGOPEN_PATH  # 兜底1：环境变量
}
if (-not $NxOpen -or -not (Test-Path (Join-Path $NxOpen "uf.h"))) {
    # 兜底2：扫描默认安装路径 (任意 NX 版本)
    $c = Get-ChildItem 'C:\Program Files\Siemens\NX*\UGOPEN\uf.h' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $NxOpen = Split-Path $c.FullName -Parent }
}
if (-not $NxOpen -or -not (Test-Path (Join-Path $NxOpen "uf.h"))) {
    throw "找不到 NX UGOPEN (缺 uf.h)。请确认 NX 已安装，或设环境变量 `$env:NX_UGOPEN_PATH 指向 UGOPEN 目录" }

Write-Host "VS  : $VcVars"  -ForegroundColor DarkGray
Write-Host "NX  : $NxOpen"  -ForegroundColor DarkGray
Write-Host "工程: $Name"     -ForegroundColor DarkGray

# ---- 导入 VS x64 编译环境到当前会话 ----
cmd /c "`"$VcVars`" >nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2] }
}

# ---- M14 (规范 §7.3 G8): 生成构建 SHA 头, dll 内嵌当前 git HEAD 短 SHA ----
# CI 用 strings 提取并与此仓 HEAD 比对, 实现「源码-制品绑定」的机器证伪。
# 源码须包含 #include "build_sha.h" (模板 cpp 已带); build_sha.h 为生成物, 应 gitignore。
$Sha = "unknown"
try { $Sha = (git -C $Proj rev-parse --short HEAD 2>$null).Trim() } catch { }
if (-not $Sha -or $Sha -eq "") { $Sha = "unknown" }
Set-Content -Path "$Proj\build_sha.h" -Value "#pragma once`nstatic const char IKUN_BUILD_SHA[] = `"$Sha`";" -Encoding ASCII
Write-Host "构建 SHA: $Sha -> build_sha.h" -ForegroundColor DarkGray

# ---- 编译 (/utf-8 让中文字符串正确; /MD 用动态运行时, 与 NX 一致) ----
Write-Host "[1/2] 编译 $Name.cpp ..." -ForegroundColor Cyan
& cl /nologo /c /EHsc /MD /W3 /utf-8 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS `
    /I"$NxOpen" `
    "$Proj\$Name.cpp" /Fo"$Proj\$Name.obj"
if ($LASTEXITCODE -ne 0) { throw "编译失败 (cl exit $LASTEXITCODE)" }

# ---- 链接 (BlockStyler/UI 符号在 libnxopenuicpp.lib, 不能漏) ----
Write-Host "[2/2] 链接 $Name.dll ..." -ForegroundColor Cyan
& link /nologo /DLL /MACHINE:X64 `
    /OUT:"$Proj\$Name.dll" `
    /LIBPATH:"$NxOpen" `
    "$Proj\$Name.obj" `
    libufun.lib libnxopencpp.lib libnxopenuicpp.lib
if ($LASTEXITCODE -ne 0) { throw "链接失败 (link exit $LASTEXITCODE)" }

# ---- 清理链接副产物 ----
Remove-Item "$Proj\$Name.exp","$Proj\$Name.lib","$Proj\$Name.obj" -ErrorAction SilentlyContinue

Write-Host "构建成功 -> $Proj\$Name.dll" -ForegroundColor Green
