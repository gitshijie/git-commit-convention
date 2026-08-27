#!/bin/sh
#
# 安装 Git 提交信息规范钩子（Linux / macOS / Git Bash）
#
# 用法:
#   ./githook-setup/install-hooks.sh                 交互式选择安装范围
#   ./githook-setup/install-hooks.sh --project       仅当前仓库生效
#   ./githook-setup/install-hooks.sh --project /path 指定仓库生效
#   ./githook-setup/install-hooks.sh --global        所有仓库生效（当前用户）
#   ./githook-setup/install-hooks.sh --uninstall     卸载（全局 + 当前仓库）
#   ./githook-setup/install-hooks.sh --uninstall /p  卸载（全局 + 指定仓库）
#   ./githook-setup/install-hooks.sh --status [/p]   查看安装状态
#
# 兼容 POSIX sh，不依赖 bash。

set -eu

# ---------------------------------------------------------------- 基础
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# 本脚本自己读文件用的路径（POSIX 形式，Git Bash 下形如 /c/Users/...）
HOOKS_DIR_LOCAL="$PKG_ROOT/.githooks"
TEMPLATE_LOCAL="$PKG_ROOT/.gitmessage"

case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
	*)                    IS_WINDOWS=0 ;;
esac

# Windows 下把 MSYS 路径转成原生形式：/c/Users/x -> C:/Users/x
#
# 必须转，否则 Git Bash 装、PowerShell 卸（或反过来）会互相认不出来：
# MINGW64 的 pwd 给出 "/c/Users/...", install-hooks.ps1 写入的是 "C:/Users/..."，
# 指的是同一个目录，但字符串不同，比较就失败 —— 表现为"没有找到安装记录"。
# 统一成原生形式后两个脚本写进 git config 的值完全一致。
to_native_path() {
	[ "$IS_WINDOWS" = 1 ] || { printf '%s' "$1"; return 0; }
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
	elif ( CDPATH= cd -- "$1" >/dev/null 2>&1 ); then
		( CDPATH= cd -- "$1" && pwd -W 2>/dev/null ) || printf '%s' "$1"
	else
		printf '%s' "$1"
	fi
}

# 写进 git config 的路径
PKG_ROOT_NATIVE=$(to_native_path "$PKG_ROOT")
HOOKS_DIR="$PKG_ROOT_NATIVE/.githooks"
TEMPLATE="$PKG_ROOT_NATIVE/.gitmessage"

# 归一化路径，仅用于比较：统一斜杠、盘符小写、去掉重复与末尾斜杠
norm_path() {
	_np=$(printf '%s' "$1" | tr '\\' '/')
	case "$_np" in
		[A-Za-z]:/*)
			_nd=$(printf '%s' "$_np" | cut -c1 | tr 'A-Z' 'a-z')
			_np="/$_nd$(printf '%s' "$_np" | cut -c3-)"
			;;
	esac
	printf '%s' "$_np" | sed -e 's://*:/:g' -e 's:/$::'
}

# 两个路径是否指向同一位置。Windows 下大小写不敏感。
# 除了当前写法，还要认出历史上装进去的另一种写法，否则老用户卸不掉。
same_path() {
	_sa=$(norm_path "$1")
	_sb=$(norm_path "$2")
	[ "$_sa" = "$_sb" ] && return 0
	if [ "$IS_WINDOWS" = 1 ]; then
		_sa=$(printf '%s' "$_sa" | tr 'A-Z' 'a-z')
		_sb=$(printf '%s' "$_sb" | tr 'A-Z' 'a-z')
		[ "$_sa" = "$_sb" ] && return 0
	fi
	return 1
}

# 某个 git config 值是否就是本规范的钩子目录 / 提交模板
is_our_hooks()    { same_path "$1" "$HOOKS_DIR" || same_path "$1" "$HOOKS_DIR_LOCAL"; }
is_our_template() { same_path "$1" "$TEMPLATE"  || same_path "$1" "$TEMPLATE_LOCAL"; }

if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
	RED=$(printf '\033[31m'); GRN=$(printf '\033[32m'); YEL=$(printf '\033[33m')
	CYA=$(printf '\033[36m'); BLD=$(printf '\033[1m'); RST=$(printf '\033[0m')
else
	RED=''; GRN=''; YEL=''; CYA=''; BLD=''; RST=''
fi

ok()   { printf '%s[OK]%s   %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '%s[??]%s   %s\n' "$YEL" "$RST" "$1"; }
err()  { printf '%s[!!]%s   %s\n' "$RED" "$RST" "$1" >&2; }
info() { printf '         %s\n' "$1"; }
die()  { err "$1"; exit 1; }

# ---------------------------------------------------------------- 前置检查
command -v git >/dev/null 2>&1 || die "找不到 git"

GIT_VER=$(git --version | sed -n 's/^git version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
GIT_MAJOR=$(printf '%s' "$GIT_VER" | cut -d' ' -f1)
GIT_MINOR=$(printf '%s' "$GIT_VER" | cut -d' ' -f2)
[ -n "$GIT_MAJOR" ] || die "无法解析 git 版本: $(git --version)"

if [ "$GIT_MAJOR" -lt 2 ] || { [ "$GIT_MAJOR" -eq 2 ] && [ "$GIT_MINOR" -lt 9 ]; }; then
	die "core.hooksPath 需要 git >= 2.9，当前 $(git --version)"
fi

[ -f "$HOOKS_DIR_LOCAL/commit-msg" ] || die "找不到钩子: $HOOKS_DIR_LOCAL/commit-msg"
[ -f "$HOOKS_DIR_LOCAL/lib/commit-msg-rules.sh" ] || die "找不到规则库: $HOOKS_DIR_LOCAL/lib/commit-msg-rules.sh"

# 换行符检查：CRLF 会让 shebang 失效，钩子静默不生效
check_crlf() {
	if head -1 "$1" | LC_ALL=C grep -q "$(printf '\r')"; then
		err "$1 是 CRLF 换行 —— shebang 会解析失败，钩子将静默不生效"
		info "修复:"
		info "  git config --global core.autocrlf input"
		info "  cd '$PKG_ROOT' && git rm --cached -r . && git reset --hard"
		exit 1
	fi
}

# 只有要【安装】时才卡 CRLF。卸载和查状态不执行钩子，
# 若在这里就退出，用户反而没法把一个已损坏的安装清理掉。
case "${1:-}" in
	--uninstall|--status|-h|--help) ;;
	*)
		check_crlf "$HOOKS_DIR_LOCAL/commit-msg"
		check_crlf "$HOOKS_DIR_LOCAL/lib/commit-msg-rules.sh"
		;;
esac

chmod +x "$HOOKS_DIR_LOCAL/commit-msg" 2>/dev/null || true

# ---------------------------------------------------------------- 自检
selftest() {
	_tmp=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/cc-$$")
	printf '这是一条不合规的提交信息\n' > "$_tmp"
	if COMMIT_CONVENTION_NO_CHAIN=1 "$HOOKS_DIR_LOCAL/commit-msg" "$_tmp" >/dev/null 2>&1; then
		rm -f "$_tmp"; die "自检失败：不合规的提交信息未被拦截"
	fi
	printf 'feat(core): 添加初始化流程\n' > "$_tmp"
	if ! COMMIT_CONVENTION_NO_CHAIN=1 "$HOOKS_DIR_LOCAL/commit-msg" "$_tmp" >/dev/null 2>&1; then
		rm -f "$_tmp"; die "自检失败：合规的提交信息被误拦截"
	fi
	rm -f "$_tmp"
	ok "钩子自检通过（违规拦截 / 合规放行）"
}

# ---------------------------------------------------------------- 状态
show_status() {
	# $1 可选：要查看的仓库路径。留空则用当前目录所在仓库。
	_target=${1:-}
	printf '\n%s当前安装状态%s\n\n' "$BLD" "$RST"

	_g=$(git config --global --get core.hooksPath 2>/dev/null || true)
	if [ -n "$_g" ]; then
		if is_our_hooks "$_g"; then
			ok "全局: 已安装本规范 ($_g)"
		else
			warn "全局: core.hooksPath 指向别处 ($_g)"
		fi
	else
		info "全局: 未设置 core.hooksPath"
	fi

	_gt=$(git config --global --get commit.template 2>/dev/null || true)
	[ -n "$_gt" ] && info "全局: commit.template = $_gt"

	if [ -n "$_target" ]; then
		[ -d "$_target" ] || die "目录不存在: $_target"
		_root=$(git -C "$_target" rev-parse --show-toplevel 2>/dev/null || true)
		[ -n "$_root" ] || die "不是 git 仓库: $_target"
	else
		_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
	fi

	if [ -n "$_root" ]; then
		_l=$(git -C "$_root" config --local --get core.hooksPath 2>/dev/null || true)
		if [ -n "$_l" ]; then
			if is_our_hooks "$_l"; then
				ok "仓库 ($_root): 已安装本规范"
			else
				warn "仓库 ($_root): core.hooksPath 指向别处 ($_l)"
			fi
		else
			info "仓库 ($_root): 未设置 core.hooksPath（若全局已装则走全局）"
		fi
	else
		info "当前目录不是 git 仓库（可用 --status PATH 指定仓库）"
	fi
	printf '\n'
	info "注: 项目级只查【这一个】仓库。别的仓库请用 --status PATH 查看。"
	printf '\n'
}

# ---------------------------------------------------------------- 安装
install_project() {
	_target=${1:-.}
	[ -d "$_target" ] || die "目录不存在: $_target"

	_root=$(git -C "$_target" rev-parse --show-toplevel 2>/dev/null || true)
	[ -n "$_root" ] || die "不是 git 仓库: $_target"

	# 若该仓库 .git/hooks 下已有 commit-msg，提醒它会被顶掉
	_gd=$(git -C "$_root" rev-parse --git-dir 2>/dev/null)
	case "$_gd" in /*) ;; *) _gd="$_root/$_gd" ;; esac
	if [ -x "$_gd/hooks/commit-msg" ]; then
		warn "该仓库已有 .git/hooks/commit-msg"
		info "设置 core.hooksPath 后 git 不再读取 .git/hooks/，"
		info "但本钩子会主动转发调用它，原有校验仍然生效。"
	fi

	git -C "$_root" config core.hooksPath "$HOOKS_DIR"
	[ -f "$TEMPLATE_LOCAL" ] && git -C "$_root" config commit.template "$TEMPLATE"

	ok "已安装到仓库: $_root"
	info "core.hooksPath  = $(git -C "$_root" config --get core.hooksPath)"
	[ -f "$TEMPLATE_LOCAL" ] && info "commit.template = $(git -C "$_root" config --get commit.template)"
}

install_global() {
	_cur=$(git config --global --get core.hooksPath 2>/dev/null || true)
	if [ -n "$_cur" ] && ! is_our_hooks "$_cur"; then
		warn "全局 core.hooksPath 当前指向: $_cur"
		info "继续将覆盖它。原值已备份到 git config commit-convention.previousHooksPath"
		git config --global commit-convention.previousHooksPath "$_cur"
	fi

	git config --global core.hooksPath "$HOOKS_DIR"
	[ -f "$TEMPLATE_LOCAL" ] && git config --global commit.template "$TEMPLATE"

	ok "已全局安装（当前用户的所有仓库）"
	info "core.hooksPath  = $(git config --global --get core.hooksPath)"
	[ -f "$TEMPLATE_LOCAL" ] && info "commit.template = $(git config --global --get commit.template)"
	printf '\n'
	warn "全局模式注意："
	info "1. git 设置 core.hooksPath 后【不再读取】各仓库 .git/hooks/。"
	info "   本钩子会主动转发调用原有 commit-msg，husky 等工具仍能工作；"
	info "   但其他类型的钩子（pre-commit / pre-push 等）会失效。"
	info "2. 本规范仓库【不能删除或移动】，否则所有仓库提交都会报错。"
	info "   当前路径: $PKG_ROOT"
	info "3. 某个仓库想豁免: cd 该仓库 && git config core.hooksPath .git/hooks"
}

uninstall() {
	# $1 可选：要卸载的仓库路径。留空则用当前目录所在仓库。
	_target=${1:-}
	_did=0

	# ---- 全局 ----
	if is_our_hooks "$(git config --global --get core.hooksPath 2>/dev/null || true)"; then
		git config --global --unset core.hooksPath
		_prev=$(git config --global --get commit-convention.previousHooksPath 2>/dev/null || true)
		if [ -n "$_prev" ]; then
			git config --global core.hooksPath "$_prev"
			git config --global --unset commit-convention.previousHooksPath
			ok "已卸载【全局】安装，并恢复原 core.hooksPath: $_prev"
		else
			ok "已卸载【全局】安装（~/.gitconfig）"
		fi
		_did=1
	fi
	if is_our_template "$(git config --global --get commit.template 2>/dev/null || true)"; then
		git config --global --unset commit.template
		_did=1
	fi

	# ---- 项目级 ----
	_root=''
	if [ -n "$_target" ]; then
		[ -d "$_target" ] || die "目录不存在: $_target"
		_root=$(git -C "$_target" rev-parse --show-toplevel 2>/dev/null || true)
		[ -n "$_root" ] || die "不是 git 仓库: $_target"
	else
		_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
	fi

	if [ -n "$_root" ]; then
		if is_our_hooks "$(git -C "$_root" config --local --get core.hooksPath 2>/dev/null || true)"; then
			git -C "$_root" config --local --unset core.hooksPath
			ok "已卸载【项目级】安装: $_root"
			_did=1
		fi
		if is_our_template "$(git -C "$_root" config --local --get commit.template 2>/dev/null || true)"; then
			git -C "$_root" config --local --unset commit.template
			_did=1
		fi
	fi

	if [ "$_did" = 1 ]; then
		return 0
	fi

	# 没找到——把实际读到的值打出来，用户一眼能看出是"没装"还是"装的是另一份拷贝"
	warn "没有找到本规范的安装记录"
	printf '\n'
	info "本规范的钩子目录: $HOOKS_DIR"
	printf '\n'
	info "已检查的位置及实际读到的值："

	_gv=$(git config --global --get core.hooksPath 2>/dev/null || true)
	info "  1. 全局 ~/.gitconfig"
	info "     core.hooksPath = ${_gv:-（未设置）}"

	if [ -n "$_root" ]; then
		_lv=$(git -C "$_root" config --local --get core.hooksPath 2>/dev/null || true)
		info "  2. 仓库 $_root"
		info "     core.hooksPath = ${_lv:-（未设置）}"
	else
		info "  2. 当前目录不在任何 git 仓库内，项目级无从检查"
	fi
	printf '\n'
	info "若上面某个值确实指向一个 .githooks 目录，只是路径跟本份不同，"
	info "说明你当初是用【另一份拷贝】安装的。可以直接手工清掉："
	info "  git config --unset core.hooksPath            # 在目标仓库内执行"
	info "  git config --global --unset core.hooksPath   # 全局"
	printf '\n'
	info "本命令【只检查当前目录所在的那一个仓库】。"
	info "如果你把钩子装在别的项目里，请指定它的路径："
	info "  $0 --uninstall /path/to/your/project"
	info "或先 cd 到那个项目再执行本命令。"
	printf '\n'
	info "忘了装在哪些仓库？可以这样找（按需调整搜索目录）："
	info "  grep -rl 'hooksPath' ~/ --include=config 2>/dev/null"
	return 1
}

# ---------------------------------------------------------------- 交互菜单
interactive() {
	_in_repo=no
	_repo_root=''
	if git rev-parse --show-toplevel >/dev/null 2>&1; then
		_in_repo=yes
		_repo_root=$(git rev-parse --show-toplevel)
	fi

	cat <<EOF

${BLD}Git 提交信息规范 —— 安装${RST}

请选择安装范围：

  ${CYA}1)${RST} 仅当前仓库生效  ${YEL}(推荐)${RST}
     只影响一个仓库，不干扰你的其他项目。
     每个仓库需各装一次。
EOF
	if [ "$_in_repo" = yes ]; then
		printf '     当前仓库: %s\n' "$_repo_root"
	else
		printf '     %s当前目录不是 git 仓库，选 1 需要另外指定路径%s\n' "$YEL" "$RST"
	fi

	cat <<EOF

  ${CYA}2)${RST} 全局生效
     当前用户的【所有】仓库都会校验，无需逐个安装。
     ${YEL}代价：会停用各仓库 .git/hooks/ 下的其他钩子${RST}
     ${YEL}（本钩子会转发 commit-msg，但 pre-commit 等会失效）${RST}
     ${YEL}且本目录不能删除或移动。${RST}

  ${CYA}3)${RST} 查看当前状态
  ${CYA}4)${RST} 卸载（全局 + 指定的一个仓库）
  ${CYA}q)${RST} 退出

EOF
	printf '请输入选项 [1]: '
	read -r _choice || _choice=q
	[ -z "$_choice" ] && _choice=1

	case "$_choice" in
		1)
			if [ "$_in_repo" = yes ]; then
				install_project "$_repo_root"
			else
				printf '请输入目标仓库路径: '
				read -r _p || die "已取消"
				[ -n "$_p" ] || die "路径为空"
				install_project "$_p"
			fi
			;;
		2)
			printf '\n%s全局安装会影响你所有的 git 仓库，确认？[y/N]: %s' "$YEL" "$RST"
			read -r _yn || _yn=n
			case "$_yn" in
				y|Y|yes|YES) install_global ;;
				*) info "已取消"; exit 0 ;;
			esac
			;;
		3) show_status; exit 0 ;;
		4)
			# 卸载只能针对一个仓库，这里明确问清楚，避免"卸载了却没生效"
			printf '\n要卸载的仓库路径（直接回车 = %s）: ' \
				"${_repo_root:-当前目录，但当前不在仓库内}"
			read -r _p || _p=''
			uninstall "$_p" || exit $?
			exit 0
			;;
		q|Q) info "已退出"; exit 0 ;;
		*) die "无效选项: $_choice" ;;
	esac
}

# ---------------------------------------------------------------- 主流程
usage() {
	cat <<EOF
用法: $0 [选项]

  (无选项)            交互式选择安装范围
  --project [PATH]    安装到指定仓库（默认当前仓库）
  --global            全局安装（当前用户所有仓库）
  --status  [PATH]    查看安装状态（默认当前仓库）
  --uninstall [PATH]  卸载：清理全局配置 + 指定仓库（默认当前仓库）
  -h, --help          显示本帮助

说明: 卸载会同时检查全局配置和【一个】仓库的配置，
      要卸载别的仓库需用 PATH 指定，或先 cd 过去。
EOF
}

case "${1:-}" in
	--project)  selftest; install_project "${2:-.}" ;;
	--global)   selftest; install_global ;;
	--status)   show_status "${2:-}"; exit 0 ;;
	--uninstall) uninstall "${2:-}" || exit $?; exit 0 ;;
	-h|--help)  usage; exit 0 ;;
	'')         selftest; interactive ;;
	*)          err "未知选项: $1"; usage; exit 1 ;;
esac

printf '\n'
ok "安装完成"
info "规范说明见 README.md"
info "验证: git commit --allow-empty -m \"wip\"   （应被拒绝）"
