#requires -Version 5
<#
.SYNOPSIS
  一键把「从零到能编译出 NX 插件 dll」所需的整条环境检查好并自动装齐。
  面向完全不懂编程、只会用 NX 的用户：跑一次，缺什么自动装什么，最后用模板
  真编译一个 dll 来证明环境就绪——之后跑用例不会再被环境问题卡住。

.DESCRIPTION
  按编译链顺序逐项检查 + 自动安装（用 winget）：
    winget → Git → Python(+pip+mcp) → VS2022 C++ 工具集(+Windows SDK) → NX SDK(UGOPEN，只检测)
  最后拿 templates 里的样例真跑一次 build.ps1，编出 dll 才算通过。
  编译产物保留在知识库根下 _env_selftest\（dll+dlx 同目录），可直接在 NX 里
  Ctrl+U 试加载作为第一次全链路验证；重跑本脚本会先清空该目录再重编。
  自动安装会弹 Windows 权限确认(UAC)，点"是"即可。NX 是付费软件、装不了——
  但你既然在用 NX，它通常已经装好，脚本只做检测并提示。

.EXAMPLE
  pwsh -File templates/setup-nx-dev-env.ps1            # 检查 + 自动安装 + 编译自测
  pwsh -File templates/setup-nx-dev-env.ps1 -CheckOnly # 只检查、不安装
#>
param([switch]$CheckOnly, [switch]$SkipVision)

$ErrorActionPreference = 'Continue'
$report = New-Object System.Collections.Generic.List[object]
function Note($name,$status,$detail){ $report.Add([pscustomobject]@{n=$name;s=$status;d=$detail}) }
function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
}
function Has($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }

Say "`n=== NX 二次开发 · 一键环境准备 ===`n" Cyan
Say "会按顺序检查编译一个 NX 插件需要的所有东西，缺的自动装。安装时弹权限确认点『是』。`n" DarkGray

# ---------- 0) winget（后面所有自动安装都靠它）----------
$winget = Has 'winget'
if ($winget) { Note 'winget 安装器' OK '可用' }
else {
    Note 'winget 安装器' FAIL '未找到——无法自动安装。请在 Microsoft Store 安装『应用安装程序 / App Installer』后重跑本脚本。'
}

function Winget-Install($id,$override){
    if ($CheckOnly) { return $false }
    if (-not $winget) { return $false }
    Say "  → 正在安装 $id （可能较大，请耐心等待，并在弹窗点『是』）…" Yellow
    $a = @('install','--id',$id,'-e','--source','winget',
           '--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
    if ($override) { $a += @('--override',$override) }
    & winget @a 2>&1 | Out-Null
    Refresh-Path
    return $true
}

# ---------- 1) Git（克隆知识库用）----------
if (Has 'git') { Note 'Git' OK (git --version) }
else {
    Winget-Install 'Git.Git' | Out-Null
    if (Has 'git') { Note 'Git' FIXED '已自动安装' }
    else { Note 'Git' FAIL '未装成——手动装：https://git-scm.com' }
}

# ---------- 2) Python 3.10+ / pip / mcp（视觉 MCP 用）----------
function PyOK {
    if (-not (Has 'python')) { return $false }
    try { $v=[version](python -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null); return ($v -ge [version]'3.10') } catch { return $false }
}
if (-not $SkipVision) {
    if (PyOK) { Note 'Python 3.10+' OK (python --version) }
    else {
        Winget-Install 'Python.Python.3.12' | Out-Null
        if (PyOK) { Note 'Python 3.10+' FIXED '已自动安装' } else { Note 'Python 3.10+' FAIL '未装成——手动装：https://www.python.org （勾 Add to PATH）' }
    }
    if (PyOK) {
        python -m pip install --quiet --upgrade pip 2>&1 | Out-Null
        $hasMcp = $false; try { python -c "import mcp" 2>$null; $hasMcp = ($LASTEXITCODE -eq 0) } catch {}
        if ($hasMcp) { Note 'mcp 库(视觉)' OK '已安装' }
        elseif ($CheckOnly) { Note 'mcp 库(视觉)' WARN '未安装（跑安装模式会自动 pip install mcp）' }
        else {
            python -m pip install --quiet mcp 2>&1 | Out-Null
            $ok=$false; try { python -c "import mcp" 2>$null; $ok=($LASTEXITCODE -eq 0) } catch {}
            Note 'mcp 库(视觉)' ($(if($ok){'FIXED'}else{'FAIL'})) $(if($ok){'已 pip 安装'}else{'pip install mcp 失败，联网后重试'})
        }
    }
}

# ---------- 3) Visual Studio 2022 C++ 工具集（cl/link/vcvars64；之前漏检的就是它）----------
function Find-VcVars {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $root = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($root) { $vc = Join-Path $root 'VC\Auxiliary\Build\vcvars64.bat'; if (Test-Path $vc) { return $vc } }
    }
    $g = Get-ChildItem 'C:\Program Files*\Microsoft Visual Studio\*\*\VC\Auxiliary\Build\vcvars64.bat' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { return $g.FullName }
    return $null
}
$vcvars = Find-VcVars
if ($vcvars) { Note 'VS C++ 工具集' OK $vcvars }
else {
    # 装免费的「VS 生成工具」+ C++ 工作负载（含 Windows SDK），足够命令行编译
    Winget-Install 'Microsoft.VisualStudio.2022.BuildTools' `
        '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' | Out-Null
    $vcvars = Find-VcVars
    if ($vcvars) { Note 'VS C++ 工具集' FIXED "已自动安装 VS 生成工具：$vcvars" }
    else { Note 'VS C++ 工具集' FAIL '未装成——用 VS Installer 勾选「使用 C++ 的桌面开发」工作负载（大文件、需管理员）。' }
}

# ---------- 4) NX SDK (UGOPEN)：只检测，装不了（你已装 NX 通常就有）----------
function Find-UgOpen {
    if ($env:UGII_ROOT_DIR) { $c = Join-Path (Split-Path $env:UGII_ROOT_DIR -Parent) 'UGOPEN'; if (Test-Path (Join-Path $c 'uf.h')) { return $c } }
    $c = Get-ChildItem 'C:\Program Files\Siemens\NX*\UGOPEN\uf.h' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return (Split-Path $c.FullName -Parent) }
    return $null
}
$ugopen = Find-UgOpen
if ($ugopen) { Note 'NX SDK (UGOPEN)' OK $ugopen }
else { Note 'NX SDK (UGOPEN)' FAIL '没找到 NX 的 UGOPEN。你装 NX 时它就在 NX 安装目录下；请确认 NX 已装，或设环境变量 UGII_ROOT_DIR 指向 NX 的 UGII 目录（付费软件，脚本装不了）。' }

# ---------- 5) 终极验证：拿样例真编译一个 dll（产物保留，供 NX 里 Ctrl+U 试加载）----------
$compiled = $false; $artifact = $null
$tpl = $PSScriptRoot   # 本脚本就在 templates 目录里，样例 nx_demo.* + build.ps1 同目录
if ($vcvars -and $ugopen -and (Test-Path (Join-Path $tpl 'build.ps1')) -and (Get-ChildItem $tpl -Filter *.cpp -ErrorAction SilentlyContinue)) {
    Say "`n正在用样例做编译自测（这一步过了，说明你之后跑用例不会被环境卡住）…" Cyan
    # 产物目录放在知识库根下，固定好找；每次重跑先清空（已 gitignore，不会误提交）
    $work = Join-Path (Split-Path $tpl -Parent) '_env_selftest'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        Copy-Item (Join-Path $tpl 'build.ps1') $work
        # 注意: Get-ChildItem 的 -Include 不带 -Recurse/通配路径时返回空(PS 经典坑), 用 Where-Object 过滤
        Get-ChildItem $tpl -File | Where-Object { $_.Extension -in '.cpp','.hpp','.dlx' } | Copy-Item -Destination $work -Force
        & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $work 'build.ps1') 2>&1 | Out-Null
        $dll = Get-ChildItem $work -Filter *.dll -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dll) {
            $compiled = $true; $artifact = $dll.FullName
            Note '编译自测' OK "成功编出 $($dll.Name)，产物已保留：$($dll.FullName)"
        }
        else {
            Note '编译自测' FAIL '没编出 dll——看上面哪项未通过；VS 刚装完可能需要新开终端让 PATH 生效后重跑。'
            Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue   # 失败无产物可留，清掉
        }
    } catch {
        Note '编译自测' FAIL "编译出错：$($_.Exception.Message)"
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Note '编译自测' WARN '前置未齐（VS 或 NX SDK 缺），补齐后重跑本脚本再自测。'
}

# ---------- 汇总 ----------
Say ""
$ic=@{OK='  ✓';FIXED=' 🔧';WARN=' ⚠';FAIL=' ✗'}; $cl=@{OK='Green';FIXED='Green';WARN='Yellow';FAIL='Red'}
foreach($r in $report){ Say ("{0} {1,-16}{2}" -f $ic[$r.s],$r.n,$r.d) $cl[$r.s] }
$fails = @($report | Where-Object s -eq 'FAIL')
Say ""
if ($compiled) {
    Say "✅ 环境就绪：已成功编译出测试 dll。你可以放心去跑用例了。" Green
    Say "   测试产物已保留（dll+dlx 同目录同名）：$artifact" Green
    Say "   现在就可以到 NX 里按 Ctrl+U 选这个 dll 试加载，弹出对话框即全链路 OK。" Green
    exit 0
}
if ($fails.Count -eq 0) { Say "基本就绪（有告警，多为可选项）。装完 VS 后若首次自测未过，新开一个终端重跑本脚本即可。" Yellow; exit 0 }
Say "还差 $($fails.Count) 项（见上面 ✗）。照提示处理后重跑本脚本；VS/Python 刚装完请新开终端再跑。" Red
exit 1
