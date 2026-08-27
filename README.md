# Git 提交信息规范（commit-msg hook）

一套开箱即用的 Git 提交信息校验钩子，基于 [Conventional Commits](https://www.conventionalcommits.org/)。
克隆下来执行一次安装脚本，之后每次 `git commit` 都会自动校验提交信息格式，不合规直接拒绝。

支持 **Windows / Linux / macOS**，可选择**仅某个项目生效**或**全局所有项目生效**。

```
$ git commit -m "修改了一些东西"

提交信息不符合规范，已中止提交：

  x Header 缺少 "<type>: " 前缀

你的提交信息：
  | 修改了一些东西

正确格式：
  <type>(<scope>): <subject>
  ...
```

---

## 快速开始

```bash
git clone <本仓库地址>
cd git-commit-convention
```

然后按平台执行安装脚本。

### Linux / macOS

```bash
./githook-setup/install-hooks.sh
```

### Windows

三种方式任选其一，效果相同：

```
:: 方式 1：文件管理器里双击（最省事）
githook-setup\install-hooks.bat
```

```powershell
# 方式 2：PowerShell
.\githook-setup\install-hooks.ps1

# 若提示"禁止运行脚本"（执行策略限制）：
powershell -ExecutionPolicy Bypass -File .\githook-setup\install-hooks.ps1
```

```bash
# 方式 3：Git Bash 里直接跑 sh 版本
./githook-setup/install-hooks.sh
```

运行后会出现菜单：

```
请选择安装范围：

  1) 仅当前仓库生效  (推荐)
     只影响一个仓库，不干扰你的其他项目。每个仓库需各装一次。

  2) 全局生效
     当前用户的【所有】仓库都会校验，无需逐个安装。
     代价：会停用各仓库 .git/hooks/ 下的其他钩子

  3) 查看当前状态
  4) 卸载（全局 + 指定的一个仓库）
  q) 退出
```

### 非交互用法

| 操作 | Linux / macOS | Windows |
| --- | --- | --- |
| 装到当前仓库 | `./githook-setup/install-hooks.sh --project` | `.\githook-setup\install-hooks.ps1 -Project` |
| 装到指定仓库 | `./githook-setup/install-hooks.sh --project /path/to/repo` | `.\githook-setup\install-hooks.ps1 -Project -Path D:\work\repo` |
| 全局安装 | `./githook-setup/install-hooks.sh --global` | `.\githook-setup\install-hooks.ps1 -Global` |
| 查看状态 | `./githook-setup/install-hooks.sh --status` | `.\githook-setup\install-hooks.ps1 -Status` |
| 查看指定仓库状态 | `./githook-setup/install-hooks.sh --status /path/to/repo` | `.\githook-setup\install-hooks.ps1 -Status -Path D:\work\repo` |
| 卸载 | `./githook-setup/install-hooks.sh --uninstall` | `.\githook-setup\install-hooks.ps1 -Uninstall` |
| 卸载指定仓库 | `./githook-setup/install-hooks.sh --uninstall /path/to/repo` | `.\githook-setup\install-hooks.ps1 -Uninstall -Path D:\work\repo` |

安装完验证一下（应当被拒绝）：

```bash
git commit --allow-empty -m "wip"
```

---

## 两种安装范围怎么选

| | 项目级 | 全局 |
| --- | --- | --- |
| 生效范围 | 指定的那一个仓库 | 当前用户的所有仓库 |
| 每个新仓库 | 需要各装一次 | 自动生效 |
| 对已有钩子的影响 | 仅该仓库 | 所有仓库 |
| 本目录能否删除/移动 | 不能 | 不能 |
| 适合 | 团队协作、只想规范某几个项目 | 个人电脑、想统一自己所有提交 |

**推荐项目级。** 全局模式方便，但有一个必须知道的副作用，见下。

### 两种范围分别改了哪些文件

安装脚本**不复制任何文件**，只写两条 git 配置。区别仅在于**写进哪个配置文件**：

| | 项目级 | 全局 |
| --- | --- | --- |
| 写入的文件 | `<你的仓库>/.git/config` | `~/.gitconfig`（Windows: `C:\Users\<你>\.gitconfig`） |
| 等价命令 | `git config core.hooksPath ...` | `git config --global core.hooksPath ...` |
| 该文件是否受版本控制 | **否**，`.git/` 不进仓库，队友 clone 后仍需各自安装 | 否，属于你的个人环境 |

两种范围写入的内容完全一样，都是这两条：

```ini
[core]
	hooksPath = /abs/path/to/git-commit-convention/.githooks
[commit]
	template = /abs/path/to/git-commit-convention/.gitmessage
```

`.githooks/` 和 `.gitmessage` 始终留在本规范仓库里，两种范围都是**指过去**，
不做拷贝——所以改规则库即时生效，但本目录也因此不能删除或移动。

优先级：git 配置的生效顺序是 system → global → local，**local 覆盖 global**。
所以某个仓库若同时装了两种范围，实际生效的是项目级那条；也正因如此，
想让某个仓库从全局模式豁免，只需在它里面写一条 local 配置指回 `.git/hooks`。

### 全局模式的副作用

两种模式都是靠 `git config core.hooksPath` 指向本仓库的 `.githooks/` 目录实现的。
而 **`core.hooksPath` 一旦设置，git 就完全不再读取各仓库 `.git/hooks/` 下的钩子**。
全局设置意味着你所有仓库里 husky、pre-commit、lefthook 装的钩子统统失效——
而且是**静默失效**，不报任何错。

本规范做了一层缓解：`commit-msg` 钩子会**主动转发调用**仓库自己的
`.git/hooks/commit-msg`（若存在），原钩子拒绝则整体拒绝。所以 husky 的
commit-msg 校验（commitlint 等）仍然有效。

但 **`pre-commit` / `pre-push` 等其他类型的钩子无法挽救**——它们根本不会被 git
调用，本规范也没有对应文件去转发。如果你的项目依赖 pre-commit 跑 lint / 测试，
请用项目级安装。

单个仓库想从全局模式里豁免：

```bash
cd 该仓库
git config core.hooksPath .git/hooks
```

### 本目录不能删除或移动

`core.hooksPath` 记录的是**绝对路径**。把本仓库删掉或换个位置，所有装过的仓库
执行 `git commit` 时都会报 `cannot run ...: No such file or directory`。

建议放在一个稳定位置，比如 `~/tools/git-commit-convention`（Windows:
`D:\tools\git-commit-convention`），而不是 `~/Downloads` 或临时目录。

真移动了的话，重新跑一次安装脚本即可（它会写入新路径）。

---

## 提交格式

```
<type>(<scope>): <subject>

[可选的正文描述]

[可选的脚注（如关联 Issue）]
```

### Header（第一行，必填）

| 字段 | 必选 | 说明 |
| --- | --- | --- |
| `type` | 是 | 从下表中选择 |
| `scope` | 否 | 变更范围，如模块名、组件名 |
| `subject` | 是 | 简短描述，**不超过 50 字符**，首字母小写，结尾不加句号；英文用现在时动词开头（`add` 而非 `added`） |

> 50 的上限按**字符**算，不是字节——一个汉字算 1 个，中文可以写到 50 字。

### type 取值

| 类型 | 含义 | 示例场景 |
| --- | --- | --- |
| `feat` | 新功能或优化 | 新增用户注册模块 |
| `fix` | 修复 Bug 或问题 | 修复登录接口返回 500 错误的问题 |
| `docs` | 文档更新 | 更新 README 中的 API 说明 |
| `style` | 代码格式调整（不影响逻辑） | 调整缩进、删除多余空格 |
| `refactor` | 代码重构（无功能变更） | 重构用户模块，提升可读性 |
| `test` | 测试相关变更 | 新增单元测试用例 |
| `chore` | 构建或工具链变更 | 升级依赖库版本 |
| `ci` | 持续集成配置变更 | 修改 CI 流水线配置 |
| `perf` | 性能优化 | 优化查询逻辑，响应时间减少 30% |
| `revert` | 回退提交 | 撤销上一次关于支付逻辑的修改 |
| `build` | 构建系统 / 依赖变更 | 调整 Makefile、升级构建工具 |

### 正文与脚注

- **正文**：详细描述变更原因、实现方案、测试场景。与 Header 之间**必须空一行**。
- **脚注**：关联 Issue。`Closes #123` 会自动关闭 Issue，`Refs #123` 只做关联。

### 示例

新增功能：

```
feat(user-module): 添加用户注册功能

- 实现注册接口及前端表单
- 增加密码加密逻辑

Closes #101
```

修复 Bug：

```
fix(login-api): 修复验证码失效问题

- 验证码超时时间从 5 分钟延长至 15 分钟
- 修复缓存键冲突导致的失效

Refs #205
```

---

## 校验规则清单

钩子会**拒绝**以下情况：

- 缺少 `<type>: ` 前缀
- `type` 不在允许列表中
- 冒号后没有空格
- `scope` 括号为空 `feat(): xxx`（不需要 scope 就省略括号）
- `scope` 含非法字符（只允许字母、数字和 `_ . / , -`）
- `subject` 为空
- `subject` 超过 50 字符
- `subject` 以英文大写字母开头
- `subject` 结尾带 `.` 或 `。`
- Header 与正文之间没有空行

**自动放行**：`Merge ...`、`Revert "..."`、`fixup!` / `squash!` / `amend!` 开头的
提交——这些是 git 自己生成的，改不了也不该改。

---

## 自定义规则

### 方式一：改规则库（影响所有用本规范的人）

规则集中在 [`.githooks/lib/commit-msg-rules.sh`](.githooks/lib/commit-msg-rules.sh)
顶部：

```sh
COMMIT_TYPES='feat|fix|docs|style|refactor|test|chore|ci|perf|revert|build'
COMMIT_SUBJECT_MAX=50
COMMIT_REQUIRE_BLANK_LINE=1
COMMIT_REQUIRE_LOWERCASE=1
```

改完即时生效，不用重跑安装脚本（`core.hooksPath` 是一次性配置）。

### 方式二：单个仓库覆盖（不改代码）

在需要特殊规则的仓库里执行：

```bash
git config commit-convention.types "feat|fix|docs|hotfix"
git config commit-convention.subjectMax 72
git config commit-convention.requireBlankLine false
git config commit-convention.requireLowercase false
```

这样别的仓库不受影响，也不会在本规范仓库里留下改动。

---

## 紧急绕过

```bash
git commit --no-verify
```

`--no-verify` 会跳过所有本地钩子。本地钩子的定位是**提前告知**，不是硬约束——
真要强制，需要在服务端（GitLab / Gitea 的 `pre-receive`，或 GitHub 的
branch protection + CI）再加一道，那样才无法绕过。

---

## 文件清单

| 文件 | 作用 |
| --- | --- |
| [`.githooks/commit-msg`](.githooks/commit-msg) | 钩子本体，`git commit` 时被 git 调用 |
| [`.githooks/lib/commit-msg-rules.sh`](.githooks/lib/commit-msg-rules.sh) | 校验规则，单一事实来源 |
| [`.gitmessage`](.gitmessage) | 提交模板，`git commit`（不带 `-m`）时自动带出 |
| [`.gitattributes`](.gitattributes) | 强制钩子为 LF、Windows 脚本为 CRLF（**Windows 关键防护**，勿删） |
| [`githook-setup/install-hooks.sh`](githook-setup/install-hooks.sh) | 安装脚本（Linux / macOS / Git Bash） |
| [`githook-setup/install-hooks.ps1`](githook-setup/install-hooks.ps1) | 安装脚本（Windows PowerShell） |
| [`githook-setup/install-hooks.bat`](githook-setup/install-hooks.bat) | Windows 双击入口，转发给 `.ps1` |

---

## 原理与常见问题

### 为什么必须手动装一次，不能 clone 就生效？

Git 出于安全考虑**不把 `.git/hooks/` 纳入版本控制**——否则 clone 任意仓库就等于
执行陌生人的脚本。所以钩子只能存在受版本控制的普通目录（这里是 `.githooks/`），
再由使用者主动执行一条 `git config core.hooksPath` 指过去。这一步是不可省的，
任何 hook 分发方案（husky 也一样）都绕不开。

安装脚本做的就两件事：

```bash
git config core.hooksPath <本仓库>/.githooks
git config commit.template <本仓库>/.gitmessage
```

### 钩子装了但没生效？（Windows 最常见）

**首先怀疑换行符。** Windows 上 `core.autocrlf=true` 是默认值，checkout 时会把
文本文件转成 CRLF。钩子一旦变成 CRLF，shebang 就成了 `#!/bin/sh\r`，sh 报
`bad interpreter: No such file or directory`。

实测两种情况的后果：

| 情况 | 现象 | 后果 |
| --- | --- | --- |
| `commit-msg` 是 CRLF | `/bin/sh^M: bad interpreter`，退出码 126 | 钩子没跑，但 git 视为失败，**提交被拦**（提示很难懂） |
| 只有 `lib/` 是 CRLF | 钩子主动检出并报错 | **提交被拦**，提示清晰 |

本仓库有三重防护：

1. `.gitattributes` 用 `eol=lf` 强制 `.githooks/**` 和 `*.sh` 无论什么平台都保持
   LF——这是根本性防护，**不要删除这个文件**
2. `commit-msg` 在加载规则库**之前**先检查其换行符，是 CRLF 就直接报错退出，
   并打印修复步骤；加载后还会再验证关键函数是否真的就位（双保险）
3. 安装脚本会读取两个钩子文件的字节判断是否 CRLF，是则**拒绝安装**并给出修复步骤

> 换句话说，CRLF 只会让你**提交不上去**，不会让不合规的提交**溜过去**。
> 这是刻意的设计取向：宁可挡住，也不放过。

如果钩子已经变成 CRLF：

```bash
git config core.autocrlf input
git rm --cached -r .
git reset --hard
```

### 双击 .bat 报一屏「意外的标记」「运算符是为将来使用而保留的」？

这是**编码**问题，不是语法问题。`install-hooks.ps1` 开头必须保留 **UTF-8 BOM**
（`EF BB BF` 三个字节）。

Windows 10/11 内置的是 **Windows PowerShell 5.1**，它读取**没有 BOM** 的 `.ps1`
时不按 UTF-8 解析，而是按系统 ANSI 代码页（简体中文机器上是 936/GBK）。脚本里的
中文是 UTF-8 编码，一个汉字 3 字节，被 GBK 按 2 字节一组消化后字节就错位了，
紧跟在中文后面的 `"` 或 `)` 会被当成某个汉字的尾字节吃掉——字符串没了结尾，
于是从那一行开始整个文件语法崩溃，报出一堆指向合法代码的荒谬错误。

本仓库的 `.ps1` 自带 BOM，正常 clone 不会有这个问题。会踩到通常是因为：

- 用编辑器打开另存过，编码选成了「UTF-8」（不带 BOM）或「ANSI」
- 某些工具链在传输/打包过程中剥掉了 BOM

修复：把 `install-hooks.ps1` 重新保存为 **UTF-8 with BOM**（VS Code 右下角点
编码 → Save with Encoding → UTF-8 with BOM），或者直接重新 clone。

`install-hooks.bat` 会在调用前先检查 BOM，缺失时给一句明确提示，不会再让你面对
那一屏乱码报错。

另外两条相关的编码约定，改动时请保持：

- `.githooks/` 下的 sh 脚本**不能有 BOM**——`sh` 会把 BOM 当成命令的一部分
- `install-hooks.bat` **只用 ASCII**——`.bat` 按当前控制台代码页解析，
  写中文在 GBK 终端上必然是乱码。所有中文输出都由 `.ps1` 负责

### 报 `sh.exe :` + `NativeCommandError` / `RemoteException`？

形如：

```
sh.exe :
所在位置 ...\install-hooks.ps1:223 字符: 9
+         & $shPath $hookForSh $tmpForSh 2>&1 | Out-Null
    + CategoryInfo          : NotSpecified: (:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
```

`sh.exe` 后面空空如也，指着一行看起来毫无问题的代码。这是 **Windows PowerShell
5.1 独有的行为**，跟 sh.exe 本身没关系：

脚本设了 `$ErrorActionPreference = 'Stop'`（为了让真正的错误立刻停下）。而 5.1
在外部命令的 stderr 被**重定向**时（`2>&1` 或 `2>$null`），会把 stderr 的**每一行**
包成 `ErrorRecord`（`NativeCommandError`）写进错误流——于是 `Stop` 让脚本当场中止。
哪怕命令本身完全正常，哪怕那行 stderr 只是个**空行**。

安装脚本自检时会故意拿一条违规信息去调钩子，钩子按设计拒绝并往 stderr 打整篇
规范说明——正常流程，却正好踩中这个雷。`pwsh` 7 没有这个行为，所以装了 pwsh 的
机器测不出来，只在用系统自带 5.1 时爆。

现在所有外部命令都走统一的 `Invoke-Native` 包装：函数内把 `ErrorActionPreference`
降为 `Continue`（局部赋值，不影响外层），把 stdout / stderr 一并收下再按对象类型
分开，只根据**退出码**判断成败。如果你要改这个脚本，注意别在 `Invoke-Native`
之外直接写 `& 外部命令 ... 2>&1`。

### Windows 需要装什么？

需要 **Git for Windows**（https://git-scm.com/download/win）。它自带 MSYS2 的
`sh.exe`，git 调用钩子时用的就是它——所以 `.githooks/` 下的 sh 脚本在 Windows
上可以直接跑，**不需要为 Windows 重写钩子**。

只装 GitHub Desktop 或 IDE 内置的精简版 git 可能没有 `sh.exe`，安装脚本会检测
并报错。

### GUI 客户端里提交，钩子生效吗？

SourceTree / TortoiseGit / VS Code 多数会走 git 命令行，因此生效。但个别 GUI
自带 git，或默认加了 `--no-verify`。**装完请用命令行 `git commit` 验证一次。**

### 已经装了 husky，会冲突吗？

- **项目级安装**：会。该仓库的 `.git/hooks/` 被 `core.hooksPath` 顶掉，但本钩子
  会转发调用原来的 `commit-msg`，commitlint 之类仍有效；`pre-commit` 会失效。
- **全局安装**：同上，且影响所有仓库。

依赖 husky `pre-commit` 的项目，建议不要装全局模式，或给那个仓库单独豁免。

### 要求的 git 版本？

`core.hooksPath` 需要 **git ≥ 2.9**（2016 年），安装脚本会检查。

### 怎么卸载？

```bash
./githook-setup/install-hooks.sh --uninstall      # Linux / macOS
.\githook-setup\install-hooks.ps1 -Uninstall      # Windows
```

**卸载的作用范围要留意：** 它会清理

1. **全局配置**（`~/.gitconfig`）里本规范写入的 `core.hooksPath` / `commit.template`；
2. **一个仓库**的 `.git/config` —— 就是**你当前所在的那个仓库**。

它不会去扫盘找出你装过的所有仓库。要卸载别的仓库，指定路径：

```bash
./githook-setup/install-hooks.sh --uninstall /path/to/your/project
.\githook-setup\install-hooks.ps1 -Uninstall -Path D:\work\myrepo
```

如果输出「没有找到本规范的安装记录」，通常不是没装，而是**你没站在装过的那个
仓库里**（很常见的情形：在本规范仓库目录下执行卸载，但钩子其实装在你的业务
项目上）。此时脚本会列出它实际检查了哪两个位置，照着指定路径重试即可。

忘了装在哪些仓库：

```bash
# Linux / macOS
grep -rl 'hooksPath.*git-commit-convention' ~/ --include=config 2>/dev/null

# Windows PowerShell（按需改搜索目录）
Get-ChildItem D:\work -Recurse -Force -Filter config -File |
  Select-String 'hooksPath.*git-commit-convention' | Select-Object Path
```

若全局安装时覆盖过别人的 `core.hooksPath`，卸载会自动恢复原值（安装时备份在
`commit-convention.previousHooksPath`）。

也可以手工卸载，就两条配置：

```bash
git config --unset core.hooksPath        # 项目级，需在目标仓库内执行
git config --unset commit.template
git config --global --unset core.hooksPath   # 全局
git config --global --unset commit.template
```

### Git Bash 装的，能用 PowerShell 卸载吗？（反过来也一样）

可以。但要知道这里有个坑，早期版本会踩到：

同一个目录，两边写进配置里的**路径写法不一样**。Git Bash / MINGW64 里
`pwd` 给出的是 MSYS 形式 `/c/Users/jerry/Desktop/git-commit-convention`，
PowerShell 给出的是原生形式 `C:/Users/jerry/Desktop/git-commit-convention`。
指的是同一处，但字符串不相等。

如果卸载时拿 `core.hooksPath` 的值去做**字面比较**，就会认不出对方装的那份，
报「没有找到本规范的安装记录」——明明装着。

现在两个脚本都做了路径归一化（统一斜杠、`C:/x` 与 `/c/x` 互转、忽略盘符大小写、
去掉重复和末尾斜杠），并且同时匹配两种写法，所以：

- Git Bash 装的，PowerShell 能卸；
- PowerShell 装的，Git Bash 能卸；
- 用旧版本装过的历史记录，也照样能被认出来清掉。

安装时写进配置的一律是**原生形式**（`C:/...`），这样 PowerShell、GUI 客户端、
cmd 都能直接用；Git Bash 自己读文件仍走 MSYS 形式。

---

## License

MIT
