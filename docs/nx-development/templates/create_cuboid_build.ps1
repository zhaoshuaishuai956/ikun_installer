# ============================================================
#  build.ps1  -  编译 create_cuboid.dll (VS2022 + NX 1847)
#  用法: pwsh -ExecutionPolicy Bypass -File .\build.ps1
#  输出: create_cuboid.dll (Ctrl+U 加载)
# ============================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$project   = "create_cuboid"

Write-Host "========== build.ps1: $project ==========" -ForegroundColor Cyan

# --- 校验 dlx 是合法 XML (cl/link 不碰 dlx, 坏 XML 要到 NX 加载才炸, 提前拦截) ---
# 读法必须固定 UTF-8: PS5.1 的 Get-Content 无 BOM 时按 ANSI 解码, 中文尾字节吞掉引号 → 好文件误报非法
foreach ($dlx in Get-ChildItem $scriptDir -Filter *.dlx) {
    try { [xml][IO.File]::ReadAllText($dlx.FullName, [Text.Encoding]::UTF8) | Out-Null }
    catch { Write-Error "dlx 不是合法 XML ($($dlx.Name)): $($_.Exception.Message)`n常见根因: 手改控件块后丢了 </PropertyList></item></Property> 关闭标签"; exit 1 }
}
Write-Host "  dlx XML 校验通过" -ForegroundColor Gray

# --- 查找 VS2022 安装路径 ---
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Error "未找到 vswhere.exe, 请安装 VS2022"
    exit 1
}
$vsRoot = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath 2>$null
if (-not $vsRoot) {
    Write-Error "未找到带 C++ x64 工具的 VS2022"
    exit 1
}
$vcvars = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    Write-Error "未找到 vcvars64.bat: $vcvars"
    exit 1
}

# --- 导入 VS 编译环境 ---
Write-Host "  导入 VS 环境: $vcvars" -ForegroundColor Gray
$cmd = "`"$vcvars`" > NUL 2>&1 && set"
$envVars = cmd /c $cmd 2>$null | Out-String
foreach ($line in $envVars -split "`n") {
    if ($line -match '^([^=]+)=(.*)$') {
        $key = $Matches[1].Trim()
        $val = $Matches[2].Trim()
        if ($key -match '^(PATH|INCLUDE|LIB|LIBPATH)$') {
            Set-Item -Path "env:$key" -Value $val -ErrorAction SilentlyContinue
        }
    }
}

# --- 查找 NX 1847 路径 ---
$nxRoot = $env:UGII_ROOT_DIR
if (-not $nxRoot) {
    $nxTry = @(
        "C:\Program Files\Siemens\NX 1847"
        "C:\Program Files\Siemens\NX1847"
        "C:\Siemens\NX 1847"
    )
    foreach ($p in $nxTry) {
        if (Test-Path (Join-Path $p "UGOPEN")) { $nxRoot = $p; break }
    }
}
if (-not $nxRoot) {
    Write-Error "未找到 NX 1847, 请设置 UGII_ROOT_DIR 环境变量"
    exit 1
}
# UGII_ROOT_DIR 指向 UGII 子目录, 需取父目录再拼接 UGOPEN
$nxBase = if (Test-Path (Join-Path $nxRoot "UGOPEN")) { $nxRoot } else { Split-Path $nxRoot -Parent }
$nxInc = Join-Path $nxBase "UGOPEN"
$nxLib = $nxInc
Write-Host "  NX 路径: $nxBase" -ForegroundColor Gray

# --- 编译 ---
Push-Location $scriptDir
try {
    $inc = "/I`"$nxInc`""
    $cpp = "$project.cpp"
    $obj = "$project.obj"
    $dll = "$project.dll"
    $dlx = "$project.dlx"

    Write-Host "  [1/2] 编译 $cpp ..." -ForegroundColor Yellow
    $clArgs = @(
        "/c", "/nologo", "/utf-8", "/EHsc", "/MD", "/O2", "/W3",
        "/D", "WIN32", "/D", "_WINDOWS", "/D", "NDEBUG",
        $inc,
        "/Fo`"$obj`"",
        "`"$cpp`""
    )
    $clCmd = "cl " + ($clArgs -join " ")
    Write-Host "    $clCmd" -ForegroundColor DarkGray
    cmd /c "$clCmd 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "编译失败" }

    Write-Host "  [2/2] 链接 $dll ..." -ForegroundColor Yellow
    $libs = @(
        "libufun.lib", "libnxopenuicpp.lib", "libnxopencpp.lib",
        "libugopenint.lib", "libnxopenuicpp.lib",
        "kernel32.lib", "user32.lib", "gdi32.lib",
        "winspool.lib", "comdlg32.lib", "advapi32.lib",
        "shell32.lib", "ole32.lib", "oleaut32.lib",
        "uuid.lib", "odbc32.lib", "odbccp32.lib"
    )
    $libPathArg = "/LIBPATH:`"$nxLib`""
    $libArgs = ($libs | ForEach-Object { "`"$_`"" }) -join " "
    $linkCmd = "link /DLL /NOLOGO /SUBSYSTEM:WINDOWS /MACHINE:X64 $libPathArg `"$obj`" $libArgs /OUT:`"$dll`""
    Write-Host "    $linkCmd" -ForegroundColor DarkGray
    cmd /c "$linkCmd 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "链接失败" }

    # 清理
    if (Test-Path $obj) { Remove-Item $obj }
    if (Test-Path "$project.exp") { Remove-Item "$project.exp" }
    if (Test-Path "$project.lib") { Remove-Item "$project.lib" }

    Write-Host "========== 编译成功: $dll ==========" -ForegroundColor Green
    Write-Host "  在 NX 中 Ctrl+U 加载此 dll 即可使用" -ForegroundColor Green
}
finally {
    Pop-Location
}
