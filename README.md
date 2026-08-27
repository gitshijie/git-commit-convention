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
./scripts/install-hooks.sh
```

### Windows

三种方式任选其一，效果相同：

```
:: 方式 1：文件管理器里双击（最省事）
scripts\install-hooks.bat
```

```powershell
# 方式 2：PowerShell
.\scripts\install-hooks.ps1

# 若提示"禁止运行脚本"（执行策略限制）：
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```

```bash
# 方式 3：Git Bash 里直接跑 sh 版本
./scripts/install-hooks.sh
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
  4) 卸载
  q) 退出
```

### 非交互用法

| 操作 | Linux / macOS | Windows |
| --- | --- | --- |
| 装到当前仓库 | `./scripts/install-hooks.sh --project` | `.\scripts\install-hooks.ps1 -Project` |
| 装到指定仓库 | `./scripts/install-hooks.sh --project /path/to/repo` | `.\scripts\install-hooks.ps1 -Project -Path D:\work\repo` |
| 全局安装 | `./scripts/install-hooks.sh --global` | `.\scripts\install-hooks.ps1 -Global` |
| 查看状态 | `./scripts/install-hooks.sh --status` | `.\scripts\install-hooks.ps1 -Status` |
| 卸载 | `./scripts/install-hooks.sh --uninstall` | `.\scripts\install-hooks.ps1 -Uninstall` |

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
| [`.gitattributes`](.gitattributes) | 强制钩子为 LF 换行（**Windows 关键防护**，勿删） |
| [`scripts/install-hooks.sh`](scripts/install-hooks.sh) | 安装脚本（Linux / macOS / Git Bash） |
| [`scripts/install-hooks.ps1`](scripts/install-hooks.ps1) | 安装脚本（Windows PowerShell） |
| [`scripts/install-hooks.bat`](scripts/install-hooks.bat) | Windows 双击入口，转发给 `.ps1` |

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
./scripts/install-hooks.sh --uninstall      # Linux / macOS
.\scripts\install-hooks.ps1 -Uninstall      # Windows
```

会清掉本规范写入的 `core.hooksPath` 和 `commit.template`；若全局安装时覆盖过
别人的 `core.hooksPath`，卸载时会自动恢复原值（安装时备份在
`commit-convention.previousHooksPath`）。

---

## License

MIT
