# ============================================================
#  build.ps1 - 编译 NX 插件 ikun_updater.dll (检查更新按钮)
#  用法: pwsh -ExecutionPolicy Bypass -File .\build.ps1
#  依赖: Visual Studio 2022 (C++ 工具集) + NX 1847 (UGOPEN)
#  产物: nxplugin\ikun_updater.dll (随安装器 csproj 嵌入打包)
# ============================================================
$ErrorActionPreference = 'Stop'
$Proj = $PSScriptRoot
$Name = 'ikun_updater'

# ---- 探测 vcvars64.bat ----
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$VcVars = $null
if (Test-Path $vswhere) {
    $vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsRoot) { $VcVars = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat" }
}
if (-not $VcVars -or -not (Test-Path $VcVars)) {
    $VcVars = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
}
if (-not (Test-Path $VcVars)) { throw "找不到 vcvars64.bat" }

# ---- 探测 NX UGOPEN ----
$NxOpen = $null
if ($env:UGII_ROOT_DIR -and (Test-Path $env:UGII_ROOT_DIR)) {
    $cand = Join-Path (Split-Path $env:UGII_ROOT_DIR -Parent) "UGOPEN"
    if (Test-Path (Join-Path $cand "uf.h")) { $NxOpen = $cand }
}
if (-not $NxOpen) { $NxOpen = "C:\Program Files\Siemens\NX 1847\UGOPEN" }
if (-not (Test-Path (Join-Path $NxOpen "uf.h"))) { throw "找不到 NX UGOPEN (缺 uf.h)" }

Write-Host "VS  : $VcVars" -ForegroundColor DarkGray
Write-Host "NX  : $NxOpen" -ForegroundColor DarkGray

# ---- 导入 VS x64 编译环境 ----
cmd /c "`"$VcVars`" >nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2] }
}

# ---- 编译 (/utf-8; /MD 动态运行时与 NX 一致) ----
Write-Host "[1/2] 编译 $Name.cpp ..." -ForegroundColor Cyan
& cl /nologo /c /EHsc /MD /W3 /utf-8 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS `
    /I"$NxOpen" "$Proj\$Name.cpp" /Fo"$Proj\$Name.obj"
if ($LASTEXITCODE -ne 0) { throw "编译失败 (cl exit $LASTEXITCODE)" }

# ---- 链接 (UF API: libufun.lib + libugopenint.lib; NXOpen UI 消息框: libnxopenuicpp.lib; 注册表: advapi32.lib) ----
Write-Host "[2/2] 链接 $Name.dll ..." -ForegroundColor Cyan
& link /nologo /DLL /MACHINE:X64 `
    /OUT:"$Proj\$Name.dll" /LIBPATH:"$NxOpen" `
    "$Proj\$Name.obj" libufun.lib libugopenint.lib libnxopenuicpp.lib advapi32.lib
if ($LASTEXITCODE -ne 0) { throw "链接失败 (link exit $LASTEXITCODE)" }

# ---- 清理副产物 ----
Remove-Item "$Proj\$Name.exp", "$Proj\$Name.lib" -ErrorAction SilentlyContinue
Write-Host "构建成功 -> $Proj\$Name.dll" -ForegroundColor Green
