#!/bin/sh
#
# 安装 Git 提交信息规范钩子（Linux / macOS / Git Bash）
#
# 用法:
#   ./scripts/install-hooks.sh                 交互式选择安装范围
#   ./scripts/install-hooks.sh --project       仅当前仓库生效
#   ./scripts/install-hooks.sh --project /path 指定仓库生效
#   ./scripts/install-hooks.sh --global        所有仓库生效（当前用户）
#   ./scripts/install-hooks.sh --uninstall     卸载
#   ./scripts/install-hooks.sh --status        查看当前安装状态
#
# 兼容 POSIX sh，不依赖 bash。

set -eu

# ---------------------------------------------------------------- 基础
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
HOOKS_DIR="$PKG_ROOT/.githooks"
TEMPLATE="$PKG_ROOT/.gitmessage"

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

[ -f "$HOOKS_DIR/commit-msg" ] || die "找不到钩子: $HOOKS_DIR/commit-msg"
[ -f "$HOOKS_DIR/lib/commit-msg-rules.sh" ] || die "找不到规则库: $HOOKS_DIR/lib/commit-msg-rules.sh"

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
check_crlf "$HOOKS_DIR/commit-msg"
check_crlf "$HOOKS_DIR/lib/commit-msg-rules.sh"

chmod +x "$HOOKS_DIR/commit-msg" 2>/dev/null || true

# ---------------------------------------------------------------- 自检
selftest() {
	_tmp=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/cc-$$")
	printf '这是一条不合规的提交信息\n' > "$_tmp"
	if COMMIT_CONVENTION_NO_CHAIN=1 "$HOOKS_DIR/commit-msg" "$_tmp" >/dev/null 2>&1; then
		rm -f "$_tmp"; die "自检失败：不合规的提交信息未被拦截"
	fi
	printf 'feat(core): 添加初始化流程\n' > "$_tmp"
	if ! COMMIT_CONVENTION_NO_CHAIN=1 "$HOOKS_DIR/commit-msg" "$_tmp" >/dev/null 2>&1; then
		rm -f "$_tmp"; die "自检失败：合规的提交信息被误拦截"
	fi
	rm -f "$_tmp"
	ok "钩子自检通过（违规拦截 / 合规放行）"
}

# ---------------------------------------------------------------- 状态
show_status() {
	printf '\n%s当前安装状态%s\n\n' "$BLD" "$RST"

	_g=$(git config --global --get core.hooksPath 2>/dev/null || true)
	if [ -n "$_g" ]; then
		if [ "$_g" = "$HOOKS_DIR" ]; then
			ok "全局: 已安装本规范 ($_g)"
		else
			warn "全局: core.hooksPath 指向别处 ($_g)"
		fi
	else
		info "全局: 未设置 core.hooksPath"
	fi

	_gt=$(git config --global --get commit.template 2>/dev/null || true)
	[ -n "$_gt" ] && info "全局: commit.template = $_gt"

	if git rev-parse --git-dir >/dev/null 2>&1; then
		_root=$(git rev-parse --show-toplevel 2>/dev/null || echo '(裸仓库)')
		_l=$(git config --local --get core.hooksPath 2>/dev/null || true)
		if [ -n "$_l" ]; then
			if [ "$_l" = "$HOOKS_DIR" ]; then
				ok "当前仓库 ($_root): 已安装本规范"
			else
				warn "当前仓库 ($_root): core.hooksPath 指向别处 ($_l)"
			fi
		else
			info "当前仓库 ($_root): 未设置 core.hooksPath（若全局已装则走全局）"
		fi
	else
		info "当前目录不是 git 仓库"
	fi
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
	[ -f "$TEMPLATE" ] && git -C "$_root" config commit.template "$TEMPLATE"

	ok "已安装到仓库: $_root"
	info "core.hooksPath  = $(git -C "$_root" config --get core.hooksPath)"
	[ -f "$TEMPLATE" ] && info "commit.template = $(git -C "$_root" config --get commit.template)"
}

install_global() {
	_cur=$(git config --global --get core.hooksPath 2>/dev/null || true)
	if [ -n "$_cur" ] && [ "$_cur" != "$HOOKS_DIR" ]; then
		warn "全局 core.hooksPath 当前指向: $_cur"
		info "继续将覆盖它。原值已备份到 git config commit-convention.previousHooksPath"
		git config --global commit-convention.previousHooksPath "$_cur"
	fi

	git config --global core.hooksPath "$HOOKS_DIR"
	[ -f "$TEMPLATE" ] && git config --global commit.template "$TEMPLATE"

	ok "已全局安装（当前用户的所有仓库）"
	info "core.hooksPath  = $(git config --global --get core.hooksPath)"
	[ -f "$TEMPLATE" ] && info "commit.template = $(git config --global --get commit.template)"
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
	_did=0
	if [ "$(git config --global --get core.hooksPath 2>/dev/null || true)" = "$HOOKS_DIR" ]; then
		git config --global --unset core.hooksPath
		_prev=$(git config --global --get commit-convention.previousHooksPath 2>/dev/null || true)
		if [ -n "$_prev" ]; then
			git config --global core.hooksPath "$_prev"
			git config --global --unset commit-convention.previousHooksPath
			ok "已卸载全局安装，并恢复原 core.hooksPath: $_prev"
		else
			ok "已卸载全局安装"
		fi
		_did=1
	fi
	if [ "$(git config --global --get commit.template 2>/dev/null || true)" = "$TEMPLATE" ]; then
		git config --global --unset commit.template
		_did=1
	fi

	if git rev-parse --git-dir >/dev/null 2>&1; then
		if [ "$(git config --local --get core.hooksPath 2>/dev/null || true)" = "$HOOKS_DIR" ]; then
			git config --local --unset core.hooksPath
			ok "已卸载当前仓库的安装"
			_did=1
		fi
		if [ "$(git config --local --get commit.template 2>/dev/null || true)" = "$TEMPLATE" ]; then
			git config --local --unset commit.template
			_did=1
		fi
	fi

	[ "$_did" = 1 ] || info "没有找到本规范的安装记录"
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
  ${CYA}4)${RST} 卸载
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
		4) uninstall; exit 0 ;;
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
  --status            查看当前安装状态
  --uninstall         卸载
  -h, --help          显示本帮助
EOF
}

case "${1:-}" in
	--project)  selftest; install_project "${2:-.}" ;;
	--global)   selftest; install_global ;;
	--status)   show_status; exit 0 ;;
	--uninstall) uninstall; exit 0 ;;
	-h|--help)  usage; exit 0 ;;
	'')         selftest; interactive ;;
	*)          err "未知选项: $1"; usage; exit 1 ;;
esac

printf '\n'
ok "安装完成"
info "规范说明见 README.md"
info "验证: git commit --allow-empty -m \"wip\"   （应被拒绝）"
