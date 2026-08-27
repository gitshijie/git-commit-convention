<#
.SYNOPSIS
    安装 Git 提交信息规范钩子（Windows / PowerShell）

.DESCRIPTION
    与 scripts/install-hooks.sh 功能等价，支持项目级与全局两种安装范围。

    钩子脚本本身不需要为 Windows 重写：Git for Windows 自带 MSYS2 的 sh.exe，
    git 调用钩子时用的是它，而不是 cmd/PowerShell。本脚本负责 Windows 特有的
    检查（CRLF 换行、sh.exe 是否存在）与配置写入。

.PARAMETER Project
    安装到仓库（默认当前仓库，可配合 -Path 指定）

.PARAMETER Path
    -Project 的目标仓库路径

.PARAMETER Global
    全局安装，当前用户的所有仓库生效

.PARAMETER Status
    查看当前安装状态

.PARAMETER Uninstall
    卸载

.EXAMPLE
    .\scripts\install-hooks.ps1                          # 交互式选择
    .\scripts\install-hooks.ps1 -Project
    .\scripts\install-hooks.ps1 -Project -Path D:\work\myrepo
    .\scripts\install-hooks.ps1 -Global
    .\scripts\install-hooks.ps1 -Status
    .\scripts\install-hooks.ps1 -Uninstall

    # 若提示执行策略限制：
    powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Project')]
    [switch]$Project,

    [Parameter(ParameterSetName = 'Project')]
    [string]$Path,

    [Parameter(ParameterSetName = 'Global')]
    [switch]$Global,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,

    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# $PSNativeCommandUseErrorActionPreference（PowerShell 7.3+）若为 $true，外部命令
# 退出码非 0 会直接抛异常。它目前默认 $false，但可以由实验特性或用户 profile 打开。
# 而本脚本里有两处【正常且期望】非 0 退出码：
#   1. git config --get <不存在的键> 正常返回 1
#   2. 自检时故意用违规信息调钩子，期望它返回非 0
# 不显式关掉的话，在开了该开关的机器上脚本会在这些地方崩掉。
# PowerShell 5.1 没有这个变量，赋值无副作用。
$PSNativeCommandUseErrorActionPreference = $false

function Write-Ok    ($m) { Write-Host "[OK]   $m" -ForegroundColor Green }
function Write-Warn2 ($m) { Write-Host "[??]   $m" -ForegroundColor Yellow }
function Write-Err2  ($m) { Write-Host "[!!]   $m" -ForegroundColor Red }
function Write-Info2 ($m) { Write-Host "       $m" }
function Die         ($m) { Write-Err2 $m; exit 1 }

# git config 读取包装：键不存在时返回空串而不是报错
function Get-GitCfg {
    param([string[]]$GitArgs)
    $out = & git @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    if ($null -eq $out) { return '' }
    return ([string]$out).Trim()
}

# ---------------------------------------------------------------- 路径
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot   = (Resolve-Path (Join-Path $scriptDir '..')).Path
$hooksDir  = Join-Path $pkgRoot '.githooks'
$template  = Join-Path $pkgRoot '.gitmessage'

# 写进 git config 的路径统一用正斜杠：反斜杠在 config 文件里是转义字符，
# "D:\work\githooks" 会被读成 "D:workgithooks"（\w \g 被吞掉）。
$hooksDirGit = $hooksDir -replace '\\', '/'
$templateGit = $template -replace '\\', '/'

# ---------------------------------------------------------------- 前置检查
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Die "找不到 git。请安装 Git for Windows: https://git-scm.com/download/win"
}

$verRaw = (& git --version) -join ' '
if ($verRaw -match 'git version (\d+)\.(\d+)') {
    $gMajor = [int]$Matches[1]; $gMinor = [int]$Matches[2]
    if ($gMajor -lt 2 -or ($gMajor -eq 2 -and $gMinor -lt 9)) {
        Die "core.hooksPath 需要 git >= 2.9，当前 $verRaw"
    }
} else {
    Write-Warn2 "无法解析 git 版本: $verRaw"
}

$hookFile = Join-Path $hooksDir 'commit-msg'
$libFile  = Join-Path $hooksDir 'lib\commit-msg-rules.sh'
if (-not (Test-Path $hookFile)) { Die "找不到钩子: $hookFile" }
if (-not (Test-Path $libFile))  { Die "找不到规则库: $libFile" }

# ---------------------------------------------------------------- sh.exe
function Find-Sh {
    $cands = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        $cands += (Join-Path $base 'Git\bin\sh.exe')
        $cands += (Join-Path $base 'Git\usr\bin\sh.exe')
        $cands += (Join-Path $base 'Programs\Git\bin\sh.exe')
    }

    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }

    $cmd = Get-Command sh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 从 git.exe 的位置反推（自定义安装路径）
    $gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitCmd) { $gitCmd = Get-Command git -ErrorAction SilentlyContinue }
    if ($gitCmd) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCmd.Source)
        foreach ($sub in @('bin\sh.exe', 'usr\bin\sh.exe')) {
            $c = Join-Path $gitRoot $sub
            if (Test-Path $c) { return $c }
        }
    }
    return $null
}

$shPath = Find-Sh
if (-not $shPath) {
    Die @"
找不到 sh.exe —— 钩子无法执行。
请安装 Git for Windows (https://git-scm.com/download/win)，
不要只用 GitHub Desktop / IDE 内置的精简版 git。
"@
}

# ---------------------------------------------------------------- CRLF 检查
# Windows 上 core.autocrlf=true 是默认值，checkout 会把钩子转成 CRLF，
# shebang 变成 "#!/bin/sh\r"，sh 报 bad interpreter —— 钩子静默不生效，提交照过。
function Test-IsCRLF ($p) {
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $n = [Math]::Min($bytes.Length - 1, 500)
    for ($i = 0; $i -lt $n; $i++) {
        if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) { return $true }
    }
    return $false
}

foreach ($f in @($hookFile, $libFile)) {
    if (Test-IsCRLF $f) {
        Write-Err2 "$f 是 CRLF 换行 —— shebang 会解析失败，钩子将静默不生效"
        Write-Info2 "修复："
        Write-Info2 "  git config --global core.autocrlf input"
        Write-Info2 "  cd `"$pkgRoot`" ; git rm --cached -r . ; git reset --hard"
        exit 1
    }
}

# ---------------------------------------------------------------- 自检
function Invoke-SelfTest {
    $tmp = [System.IO.Path]::GetTempFileName()
    $hookForSh = $hookFile -replace '\\', '/'
    $tmpForSh  = $tmp      -replace '\\', '/'
    try {
        $env:COMMIT_CONVENTION_NO_CHAIN = '1'

        # 必须用 LF 写入：PowerShell 的 Set-Content 默认 CRLF，会干扰校验
        [System.IO.File]::WriteAllText($tmp, "这是一条不合规的提交信息`n")
        & $shPath $hookForSh $tmpForSh 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Die "自检失败：不合规的提交信息未被拦截" }

        [System.IO.File]::WriteAllText($tmp, "feat(core): 添加初始化流程`n")
        & $shPath $hookForSh $tmpForSh 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "自检失败：合规的提交信息被误拦截" }

        Write-Ok "钩子自检通过（违规拦截 / 合规放行）"
    } finally {
        Remove-Item Env:\COMMIT_CONVENTION_NO_CHAIN -ErrorAction SilentlyContinue
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- 状态
function Show-Status {
    Write-Host ""
    Write-Host "当前安装状态" -ForegroundColor White
    Write-Host ""

    $g = Get-GitCfg @('config', '--global', '--get', 'core.hooksPath')
    if ($g) {
        if ($g -eq $hooksDirGit) { Write-Ok "全局: 已安装本规范 ($g)" }
        else { Write-Warn2 "全局: core.hooksPath 指向别处 ($g)" }
    } else {
        Write-Info2 "全局: 未设置 core.hooksPath"
    }

    $gt = Get-GitCfg @('config', '--global', '--get', 'commit.template')
    if ($gt) { Write-Info2 "全局: commit.template = $gt" }

    $root = Get-GitCfg @('rev-parse', '--show-toplevel')
    if ($root) {
        $l = Get-GitCfg @('config', '--local', '--get', 'core.hooksPath')
        if ($l) {
            if ($l -eq $hooksDirGit) { Write-Ok "当前仓库 ($root): 已安装本规范" }
            else { Write-Warn2 "当前仓库 ($root): core.hooksPath 指向别处 ($l)" }
        } else {
            Write-Info2 "当前仓库 ($root): 未设置 core.hooksPath（若全局已装则走全局）"
        }
    } else {
        Write-Info2 "当前目录不是 git 仓库"
    }
    Write-Host ""
}

# ---------------------------------------------------------------- 安装
function Install-Project ($target) {
    if (-not $target) { $target = '.' }
    if (-not (Test-Path $target)) { Die "目录不存在: $target" }

    $root = Get-GitCfg @('-C', $target, 'rev-parse', '--show-toplevel')
    if (-not $root) { Die "不是 git 仓库: $target" }

    $gd = Get-GitCfg @('-C', $root, 'rev-parse', '--git-dir')
    if ($gd -and -not [System.IO.Path]::IsPathRooted($gd)) { $gd = Join-Path $root $gd }
    if ($gd -and (Test-Path (Join-Path $gd 'hooks\commit-msg'))) {
        Write-Warn2 "该仓库已有 .git/hooks/commit-msg"
        Write-Info2 "设置 core.hooksPath 后 git 不再读取 .git/hooks/，"
        Write-Info2 "但本钩子会主动转发调用它，原有校验仍然生效。"
    }

    & git -C $root config core.hooksPath $hooksDirGit
    if (Test-Path $template) { & git -C $root config commit.template $templateGit }

    Write-Ok "已安装到仓库: $root"
    Write-Info2 "core.hooksPath  = $(Get-GitCfg @('-C', $root, 'config', '--get', 'core.hooksPath'))"
    if (Test-Path $template) {
        Write-Info2 "commit.template = $(Get-GitCfg @('-C', $root, 'config', '--get', 'commit.template'))"
    }
}

function Install-Global {
    $cur = Get-GitCfg @('config', '--global', '--get', 'core.hooksPath')
    if ($cur -and $cur -ne $hooksDirGit) {
        Write-Warn2 "全局 core.hooksPath 当前指向: $cur"
        Write-Info2 "继续将覆盖它。原值已备份到 commit-convention.previousHooksPath"
        & git config --global commit-convention.previousHooksPath $cur
    }

    & git config --global core.hooksPath $hooksDirGit
    if (Test-Path $template) { & git config --global commit.template $templateGit }

    Write-Ok "已全局安装（当前用户的所有仓库）"
    Write-Info2 "core.hooksPath  = $(Get-GitCfg @('config', '--global', '--get', 'core.hooksPath'))"
    if (Test-Path $template) {
        Write-Info2 "commit.template = $(Get-GitCfg @('config', '--global', '--get', 'commit.template'))"
    }
    Write-Host ""
    Write-Warn2 "全局模式注意："
    Write-Info2 "1. git 设置 core.hooksPath 后【不再读取】各仓库 .git/hooks/。"
    Write-Info2 "   本钩子会主动转发调用原有 commit-msg，husky 等仍能工作；"
    Write-Info2 "   但其他类型的钩子（pre-commit / pre-push 等）会失效。"
    Write-Info2 "2. 本规范目录【不能删除或移动】，否则所有仓库提交都会报错。"
    Write-Info2 "   当前路径: $pkgRoot"
    Write-Info2 "3. 某个仓库想豁免: cd 该仓库 ; git config core.hooksPath .git/hooks"
}

function Uninstall-Hooks {
    $did = $false

    if ((Get-GitCfg @('config', '--global', '--get', 'core.hooksPath')) -eq $hooksDirGit) {
        & git config --global --unset core.hooksPath
        $prev = Get-GitCfg @('config', '--global', '--get', 'commit-convention.previousHooksPath')
        if ($prev) {
            & git config --global core.hooksPath $prev
            & git config --global --unset commit-convention.previousHooksPath
            Write-Ok "已卸载全局安装，并恢复原 core.hooksPath: $prev"
        } else {
            Write-Ok "已卸载全局安装"
        }
        $did = $true
    }
    if ((Get-GitCfg @('config', '--global', '--get', 'commit.template')) -eq $templateGit) {
        & git config --global --unset commit.template
        $did = $true
    }

    if (Get-GitCfg @('rev-parse', '--git-dir')) {
        if ((Get-GitCfg @('config', '--local', '--get', 'core.hooksPath')) -eq $hooksDirGit) {
            & git config --local --unset core.hooksPath
            Write-Ok "已卸载当前仓库的安装"
            $did = $true
        }
        if ((Get-GitCfg @('config', '--local', '--get', 'commit.template')) -eq $templateGit) {
            & git config --local --unset commit.template
            $did = $true
        }
    }

    if (-not $did) { Write-Info2 "没有找到本规范的安装记录" }
}

# ---------------------------------------------------------------- 交互菜单
function Invoke-Interactive {
    $repoRoot = Get-GitCfg @('rev-parse', '--show-toplevel')

    Write-Host ""
    Write-Host "Git 提交信息规范 —— 安装" -ForegroundColor White
    Write-Host ""
    Write-Host "请选择安装范围："
    Write-Host ""
    Write-Host "  1) 仅当前仓库生效  (推荐)" -ForegroundColor Cyan
    Write-Host "     只影响一个仓库，不干扰你的其他项目。每个仓库需各装一次。"
    if ($repoRoot) {
        Write-Host "     当前仓库: $repoRoot"
    } else {
        Write-Host "     当前目录不是 git 仓库，选 1 需要另外指定路径" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  2) 全局生效" -ForegroundColor Cyan
    Write-Host "     当前用户的【所有】仓库都会校验，无需逐个安装。"
    Write-Host "     代价：会停用各仓库 .git/hooks/ 下的其他钩子" -ForegroundColor Yellow
    Write-Host "     （本钩子会转发 commit-msg，但 pre-commit 等会失效）" -ForegroundColor Yellow
    Write-Host "     且本目录不能删除或移动。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  3) 查看当前状态" -ForegroundColor Cyan
    Write-Host "  4) 卸载" -ForegroundColor Cyan
    Write-Host "  q) 退出" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "请输入选项 [1]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }

    switch ($choice.Trim()) {
        '1' {
            if ($repoRoot) { Install-Project $repoRoot }
            else {
                $p = Read-Host "请输入目标仓库路径"
                if ([string]::IsNullOrWhiteSpace($p)) { Die "路径为空" }
                Install-Project $p.Trim('"').Trim()
            }
        }
        '2' {
            Write-Host ""
            $yn = Read-Host "全局安装会影响你所有的 git 仓库，确认？[y/N]"
            if ($yn -match '^\s*(y|yes)\s*$') { Install-Global }
            else { Write-Info2 "已取消"; exit 0 }
        }
        '3' { Show-Status; exit 0 }
        '4' { Uninstall-Hooks; exit 0 }
        'q' { Write-Info2 "已退出"; exit 0 }
        'Q' { Write-Info2 "已退出"; exit 0 }
        default { Die "无效选项: $choice" }
    }
}

# ---------------------------------------------------------------- 主流程
switch ($PSCmdlet.ParameterSetName) {
    'Status'    { Show-Status; exit 0 }
    'Uninstall' { Uninstall-Hooks; exit 0 }
    'Project'   { Invoke-SelfTest; Install-Project $Path }
    'Global'    { Invoke-SelfTest; Install-Global }
    default     { Invoke-SelfTest; Invoke-Interactive }
}

Write-Host ""
Write-Ok "安装完成"
Write-Info2 "规范说明见 README.md"
Write-Info2 "验证: git commit --allow-empty -m `"wip`"   （应被拒绝）"
Write-Host ""
Write-Host "提示：SourceTree / TortoiseGit / VS Code 多数会走 git 命令行，钩子生效；" -ForegroundColor Yellow
Write-Host "      但个别 GUI 自带 git 或默认加了 --no-verify。" -ForegroundColor Yellow
Write-Host "      装完请用命令行 git commit 验证一次。" -ForegroundColor Yellow
