#!/usr/bin/env bash
# =====================================================================
#  SillyTavern · Termux 部署器
#  在 Android 手机上把酒馆装好，并生成一个 `st` 管理面板。
#
#  用法:
#    curl -fsSL <raw>/install.sh | bash      # 装完即用
#    bash -c "$(curl -fsSL <raw>/install.sh)" # 想装扩展时用这个（有 TTY）
#
#  许可: Apache-2.0
# =====================================================================

set -uo pipefail

# ---------------------------------------------------------------- 配置
readonly TAVERN_VERSION="1.18.0"
readonly TAVERN_DIR="$HOME/SillyTavern"
readonly PANEL_PATH="$HOME/st.sh"
readonly LOG_DIR="$HOME/.st-logs"

readonly SRC_TAVERN_CN="https://gitee.com/mirrors/sillytavern.git"
readonly SRC_TAVERN_INTL="https://github.com/SillyTavern/SillyTavern.git"
readonly SRC_HELPER_CN="https://gitlab.com/novi028/JS-Slash-Runner.git"
readonly SRC_HELPER_INTL="https://github.com/N0VI028/JS-Slash-Runner.git"
readonly NPM_MIRROR="https://registry.npmmirror.com"
readonly NPM_UPSTREAM="https://registry.npmjs.org"
readonly TUNA="https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"

readonly EXT_ROOT="$TAVERN_DIR/public/scripts/extensions/third-party"

# ---------------------------------------------------------------- 输出
if [ -t 1 ]; then
  C_DIM=$'\033[2m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_HI=$'\033[36m'; C_OFF=$'\033[0m'
else
  C_DIM=''; C_OK=''; C_WARN=''; C_ERR=''; C_HI=''; C_OFF=''
fi

step() { printf '%s==>%s %s\n' "$C_HI" "$C_OFF" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s  !!%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s err%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }
hint() { printf '%s      %s%s\n' "$C_DIM" "$*" "$C_OFF"; }

rule() { printf '%s%s%s\n' "$C_DIM" "--------------------------------------------------------------------" "$C_OFF"; }

# ------------------------------------------------------------ 前置检查
# Termux 稳定版是 v0.118.3。注意别写成 apt-android-N 那种名字 —— 那只存在于
# 0.119.0-beta 预发布里，稳定版全是 +github-debug_<架构> 命名。
readonly TERMUX_APK_URL="https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3+github-debug_universal.apk"

require_termux() {
  [ -d /data/data/com.termux ] && return 0
  cat >&2 <<EOF
err 这个脚本只能在 Termux 里跑。

装 Termux，二选一：

  F-Droid（推荐，不用装 F-Droid 客户端）
    https://f-droid.org/packages/com.termux/
    拉到「版本」列表，点最新版旁边的 Download APK

  GitHub 直接下（113MB，全架构通用，什么手机都能装）
    $TERMUX_APK_URL
    手机是 arm64 的话可以换 ..._arm64-v8a.apk，只有 35MB

  千万别用 Google Play 里那个旧版，跑不起来。

装好重新执行本脚本。
EOF
  exit 1
}

# Termux 的 apt 源文件位置随版本变过，两处都认
apt_source_file() {
  local d="$PREFIX/etc/apt/sources.list.d/termux-main.list"
  local f="$PREFIX/etc/apt/sources.list"
  if [ -f "$d" ]; then printf '%s' "$d"
  elif [ -f "$f" ]; then printf '%s' "$f"
  else mkdir -p "$PREFIX/etc/apt"; printf '%s' "$f"
  fi
}

# 国内源加速。不靠探测（探测抖一下就误判），直接写源再拿 apt update 验真，
# 不行就回滚备份。Termux 直连官方源在国内经常慢到没法用。
setup_apt_mirror() {
  local src; src=$(apt_source_file)
  # 命令替换里的报错只杀子 shell，父进程会照常往下走 —— 那样这里就成了
  # 静默空操作，换源没换还装作换好了。宁可当场死。
  [ -n "$src" ] || die "定位不到 Termux 的 apt 源文件（PREFIX 异常）"

  if grep -q "tuna.tsinghua.edu.cn" "$src" 2>/dev/null; then
    ok "apt 已走国内镜像"
    return 0
  fi

  step "把 apt 源换成国内镜像"
  local bak="${src}.bak.$$"
  cp "$src" "$bak" 2>/dev/null || true
  sed -i 's@^\(deb .*stable main\)$@#\1@' "$src" 2>/dev/null || true
  printf 'deb %s stable main\n' "$TUNA" >> "$src"

  if apt update >/dev/null 2>&1; then
    ok "镜像可用，留着用"
    rm -f "$bak"
  else
    warn "镜像连不上，恢复原来的源"
    [ -f "$bak" ] && mv "$bak" "$src"
  fi
}

ensure_packages() {
  local missing=()
  local c
  for c in git node curl; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [ ${#missing[@]} -eq 0 ] && { ok "基础依赖齐全"; return 0; }

  step "装基础依赖: ${missing[*]}"
  pkg install -y git nodejs-lts curl nano || die "依赖装不上，检查网络后重试"
  ok "依赖就绪"
}

# ---------------------------------------------------------------- git
# Termux 上升级库文件时常见新旧包混装，git 会突然报
#   cannot locate symbol "SSL_set_quic_tls_transport_params" ...
# 这时候只能整体对齐版本。注意不能用 pkg upgrade —— pkg 自己是个 bash 封装、
# 内部要调 curl，curl 已经崩了它就一起崩；apt 走 libapt，不依赖 curl。
repair_toolchain() {
  warn "检测到 Termux 包版本错位（CANNOT LINK），正在整体对齐，第一次会比较久"
  apt update >/dev/null 2>&1 || true
  apt full-upgrade -y >/dev/null 2>&1 || true
}

# clone 一个仓库，国内源失败自动切国际源
# $1 项目名  $2 国内源  $3 国际源  $4 目标目录
clone_with_fallback() {
  local label="$1" cn="$2" intl="$3" dest="$4"
  local log="$LOG_DIR/clone-$$.log"

  if [ -e "$dest" ] && [ ! -d "$dest/.git" ]; then
    warn "$dest 已存在但不是 git 仓库，清掉重来"
    rm -rf "$dest"
  fi

  step "拉取 $label"
  if git clone --depth 1 "$cn" "$dest" >"$log" 2>&1; then
    ok "$label ← 国内源"
    return 0
  fi

  if grep -q 'CANNOT LINK' "$log" 2>/dev/null; then
    repair_toolchain
    step "再次尝试 $label"
    if git clone --depth 1 "$cn" "$dest" >"$log" 2>&1; then
      ok "$label ← 国内源（修复后）"
      return 0
    fi
  fi

  warn "国内源不行，换国际源"
  if git clone --depth 1 "$intl" "$dest" >"$log" 2>&1; then
    ok "$label ← 国际源"
    return 0
  fi

  printf '%s\n' "$C_ERR" >&2
  tail -n 15 "$log" >&2 || true
  return 1
}

# --depth 1 的克隆不含 tag，得显式把目标 tag 拉下来才能 checkout。
# $1 版本  $2 远端（remote 名或 URL）
checkout_version() {
  git fetch --depth 1 "$2" "refs/tags/$1:refs/tags/$1" >/dev/null 2>&1 || return 1
  git checkout "$1" >/dev/null 2>&1 || return 1
  return 0
}

# --------------------------------------------------------------- 安装
install_tavern() {
  clone_with_fallback "酒馆本体" "$SRC_TAVERN_CN" "$SRC_TAVERN_INTL" "$TAVERN_DIR" \
    || die "酒馆代码拉不下来，检查网络后重跑"

  cd "$TAVERN_DIR" || die "进不去 $TAVERN_DIR"

  # 镜像站同步有延迟，可能还没有目标 tag。缺了就整个换成官方源重来
  # （此刻还没装任何数据，删掉重来是安全的）
  if ! checkout_version "$TAVERN_VERSION" "$(git remote get-url origin)"; then
    warn "当前源没有 v$TAVERN_VERSION，多半是镜像还没同步，改用 GitHub 官方源"
    rm -rf "$TAVERN_DIR"
    clone_with_fallback "酒馆本体" "$SRC_TAVERN_INTL" "$SRC_TAVERN_INTL" "$TAVERN_DIR" \
      || die "官方源也拉不下来"
    cd "$TAVERN_DIR" || die "进不去 $TAVERN_DIR"
    checkout_version "$TAVERN_VERSION" "$SRC_TAVERN_INTL" \
      || die "切不到 v$TAVERN_VERSION"
  fi

  ok "已锁定 v$TAVERN_VERSION"
}

install_npm_deps() {
  step "装 npm 依赖（这一步最慢，等着就行）"
  cd "$TAVERN_DIR" || die "进不去 $TAVERN_DIR"
  [ -d node_modules ] && { ok "依赖已存在，跳过"; return 0; }

  if curl -sfI --max-time 5 "$NPM_MIRROR" >/dev/null 2>&1; then
    npm config set registry "$NPM_MIRROR"
  else
    npm config set registry "$NPM_UPSTREAM"
  fi

  npm install --no-audit --no-fund && { ok "依赖装好了"; return 0; }

  warn "镜像失败，换 npm 官方源再试"
  npm config set registry "$NPM_UPSTREAM"
  npm install --no-audit --no-fund || die "npm install 失败，看上面的报错"
  ok "依赖装好了"
}

install_extension() {
  local dest="$EXT_ROOT/JS-Slash-Runner"
  [ -d "$TAVERN_DIR" ] || { warn "酒馆还没装"; return 1; }

  if [ -d "$dest/.git" ]; then
    step "更新酒馆助手"
    git -C "$dest" pull --ff-only >/dev/null 2>&1 && ok "已更新" || warn "更新失败，忽略"
    return 0
  fi

  mkdir -p "$EXT_ROOT"
  clone_with_fallback "酒馆助手" "$SRC_HELPER_CN" "$SRC_HELPER_INTL" "$dest" \
    || { warn "酒馆助手没装上，不影响本体使用"; return 1; }
  hint "装完记得去酒馆「扩展」面板勾上它"
}

ask_extensions() {
  printf '\n'
  rule
  printf '  酒馆本体已就位。要不要顺手装「酒馆助手」(Tavern Helper)？\n'
  printf '    %s[1]%s 装        %s[2]%s 不用，就这样\n' "$C_OK" "$C_OFF" "$C_OK" "$C_OFF"
  printf '  选 [1-2]: '
  local a; read -r a || a=""
  case "${a:-}" in
    1) install_extension ;;
    *) ok "行，先不装" ;;
  esac
}

# ------------------------------------------------------------- 面板生成
# 面板直接内联成 heredoc 写盘。这么做是为了 `curl | bash` 装完也有面板，
# 不需要第二次联网。引号 heredoc，里面的 $VAR 不会被外层展开。
write_panel() {
  step "生成管理面板 $PANEL_PATH"
  cat > "$PANEL_PATH" <<'ST_PANEL_EOF'
#!/usr/bin/env bash
# SillyTavern 管理面板
set -uo pipefail

TAVERN_DIR="$HOME/SillyTavern"
SRV_LOG="$HOME/.st-logs/server.log"
SNAP_DIR="$HOME/.st-snapshots"
OFFICIAL_SRC="https://github.com/SillyTavern/SillyTavern.git"
EXT_ROOT="$TAVERN_DIR/public/scripts/extensions/third-party"
NPM_MIRROR="https://registry.npmmirror.com"
NPM_UPSTREAM="https://registry.npmjs.org"

if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_HI=$'\033[36m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_HI=''; C_OFF=''
fi
say()  { printf '%s\n' "$*"; }
good() { printf '%s  ok%s %s\n' "$C_OK" "$C_OFF" "$*"; }
bad()  { printf '%s err%s %s\n' "$C_ERR" "$C_OFF" "$*"; }
note() { printf '%s  !!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
ask()  { printf '  %s ' "$*"; }

hold() { printf '\n'; read -r -p "  ── 回车继续 ──" _ || true; }

# 抹掉当前行（CJK 是双宽字符，光 \r 回不到行首，得配 ESC[K 擦）
clear_line() { [ -t 1 ] && printf '\r\033[K'; return 0; }

# 只认酒馆自己的 node 进程。绝不 pkill node —— 手机上还有别的 node 在跑。
tavern_pids() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f 'node server\.js' 2>/dev/null
  else
    ps -ef 2>/dev/null | awk '/[n]ode server\.js/ {print $2}'
  fi
}
is_up() { [ -n "$(tavern_pids)" ]; }

probe() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:8000/ 2>/dev/null
}

# 取一个远端能给出的最高正式版
newest_tag() {
  git ls-remote --tags --refs "$1" 2>/dev/null \
    | awk -F'refs/tags/' 'NF>1 {print $2}' \
    | grep -E '^[0-9]+(\.[0-9]+){2}$' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

# $1 比 $2 新？
is_newer() {
  [ "$1" != "$2" ] || return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ]
}

grab_tag() {
  git fetch --depth 1 "$2" "refs/tags/$1:refs/tags/$1" >/dev/null 2>&1 || return 1
  git checkout "$1" >/dev/null 2>&1 || return 1
  return 0
}

# ------------------------------------------------------------------ 启停
start_tavern() {
  if is_up; then
    note "已经在跑了，PID $(tavern_pids | tr '\n' ' ')"
    return 0
  fi
  [ -f "$TAVERN_DIR/start.sh" ] || { bad "找不到 $TAVERN_DIR/start.sh"; return 1; }

  mkdir -p "$(dirname "$SRV_LOG")"
  : > "$SRV_LOG"
  ( cd "$TAVERN_DIR" && nohup bash start.sh >>"$SRV_LOG" 2>&1 </dev/null & )

  printf '  等端口起来'
  local i code
  for i in $(seq 1 60); do
    code=$(probe)
    if [ -n "$code" ] && [ "$code" != "000" ]; then
      printf '\n'; good "起来了 → http://127.0.0.1:8000"
      return 0
    fi
    if ! is_up; then
      printf '\n'; bad "进程挂了，日志尾巴："
      tail -n 20 "$SRV_LOG" 2>/dev/null | sed 's/^/      /'
      return 1
    fi
    printf '.'
    sleep 1
  done
  printf '\n'
  note "一分钟还没就绪，可能还在初始化。看日志: tail -f $SRV_LOG"
}

stop_tavern() {
  local pids; pids=$(tavern_pids)
  [ -n "$pids" ] || { note "本来就没在跑"; return 0; }
  kill $pids 2>/dev/null
  local i
  for i in $(seq 1 10); do
    is_up || { good "已停止"; return 0; }
    sleep 1
  done
  kill -9 $pids 2>/dev/null
  note "强杀了"
}

show_status() {
  if is_up; then good "运行中  PID $(tavern_pids | tr '\n' ' ')"
  else note "没在运行"; fi
  say "  端口探测   $(probe)"
  say "  安装位置   $TAVERN_DIR"
  [ -d "$TAVERN_DIR/.git" ] && say "  当前版本   $(git -C "$TAVERN_DIR" describe --tags 2>/dev/null || echo '?')"
  say "  数据目录   $TAVERN_DIR/data"
  local n; n=$(ls -1 "$SNAP_DIR"/*.tar.gz 2>/dev/null | wc -l)
  say "  备份份数   $n"
}

show_log() {
  [ -f "$SRV_LOG" ] || { note "还没有日志"; return 0; }
  say "  最近 30 行（跟实时用 tail -f $SRV_LOG）"
  printf '%s\n' "  ------------------------------------------------"
  tail -n 30 "$SRV_LOG" | sed 's/^/  /'
}

# ------------------------------------------------------------------ 更新
update_tavern() {
  [ -d "$TAVERN_DIR/.git" ] || { bad "没找到酒馆"; return 1; }
  cd "$TAVERN_DIR" || return 1

  local from; from=$(git remote get-url origin 2>/dev/null || echo "$OFFICIAL_SRC")
  printf '  查版本...'
  local target; target=$(newest_tag "$from")
  clear_line
  [ -n "$target" ] || { bad "查不到，网络问题？"; return 1; }

  # 国内镜像同步慢，顺手问下官方源有没有更新的
  local pull_from="$from"
  if [ "$from" != "$OFFICIAL_SRC" ]; then
    local latest; latest=$(newest_tag "$OFFICIAL_SRC")
    if [ -n "$latest" ] && is_newer "$latest" "$target"; then
      note "当前源最高 $target（镜像没跟上），官方已有 $latest"
      ask "改从官方源拉 $latest？会慢一点 [y/N]:"
      local y; read -r y || y=""
      case "${y:-}" in
        y|Y) pull_from="$OFFICIAL_SRC"; target="$latest" ;;
      esac
    fi
  fi

  local now; now=$(git describe --tags 2>/dev/null || echo '?')
  ask "确认从 $now 更新到 $target？会先停服 [y/N]:"
  local a; read -r a || a=""
  case "${a:-}" in y|Y) ;; *) return 0 ;; esac

  stop_tavern >/dev/null 2>&1 || true
  if ! grab_tag "$target" "$pull_from"; then
    bad "拉取或切换失败（本地改过文件？先 git -C $TAVERN_DIR stash）"
    return 1
  fi

  npm config set registry "$NPM_MIRROR"
  npm install --no-audit --no-fund || {
    npm config set registry "$NPM_UPSTREAM"
    npm install --no-audit --no-fund
  }
  good "已更新到 $target"
}

toggle_extension() {
  [ -d "$TAVERN_DIR" ] || { bad "没找到酒馆"; return 1; }
  local dest="$EXT_ROOT/JS-Slash-Runner"
  mkdir -p "$EXT_ROOT"
  if [ -d "$dest/.git" ]; then
    printf '  拉最新... '
    git -C "$dest" pull --ff-only >/dev/null 2>&1 && good "酒馆助手已更新" || bad "更新失败"
    return 0
  fi
  printf '  克隆酒馆助手... '
  if git clone --depth 1 https://gitlab.com/novi028/JS-Slash-Runner.git "$dest" >/dev/null 2>&1 \
  || git clone --depth 1 https://github.com/N0VI028/JS-Slash-Runner.git "$dest" >/dev/null 2>&1; then
    good "装好了"
  else
    bad "没装上"
    return 1
  fi
}

# ------------------------------------------------------------------ 数据
snapshot() {
  mkdir -p "$SNAP_DIR"
  local stamp out; stamp=$(date +%Y%m%d-%H%M%S); out="$SNAP_DIR/$stamp.tar.gz"
  local targets=()
  [ -d "$TAVERN_DIR/data" ] && targets+=(data)
  [ -f "$TAVERN_DIR/config.yaml" ] && targets+=(config.yaml)
  [ ${#targets[@]} -gt 0 ] || { bad "找不到 data 目录，没什么可备份的"; return 1; }

  if tar -czf "$out" -C "$TAVERN_DIR" "${targets[@]}"; then
    good "打包好了 → $out"
    note "config.yaml 里是你的 API Key，别随便传人"
  else
    bad "打包失败"
    return 1
  fi
}

rollback() {
  [ -d "$SNAP_DIR" ] || { note "一份备份都没有"; return 0; }
  local snaps=() f
  while IFS= read -r f; do [ -n "$f" ] && snaps+=("$f"); done \
    < <(ls -1t "$SNAP_DIR"/*.tar.gz 2>/dev/null)
  [ ${#snaps[@]} -gt 0 ] || { note "一份备份都没有"; return 0; }

  say "  已有备份："
  local i=1
  for f in "${snaps[@]}"; do say "    [$i] $(basename "$f")"; i=$((i+1)); done

  ask "选一份恢复 [1-${#snaps[@]}]，0 取消:"
  local n; read -r n || n=""
  case "${n:-}" in ''|0) return 0 ;; esac
  case "$n" in *[!0-9]*) bad "这不是数字"; return 1 ;; esac
  local idx=$((n-1))
  { [ "$idx" -ge 0 ] && [ "$idx" -lt "${#snaps[@]}" ]; } || { bad "超出范围"; return 1; }

  ask "恢复会盖掉现在的数据。先把现在这份也存一下？[Y/n]:"
  local b; read -r b || b=""
  case "${b:-}" in n|N) ;; *) snapshot ;; esac

  stop_tavern >/dev/null 2>&1 || true
  tar -xzf "${snaps[$idx]}" -C "$TAVERN_DIR" && good "恢复完了" || { bad "恢复失败"; return 1; }
}

remove_tavern() {
  ask "真的卸载酒馆？[y/N]:"
  local a; read -r a || a=""
  case "${a:-}" in y|Y) ;; *) return 0 ;; esac
  ask "先存一份数据？[Y/n]:"
  local b; read -r b || b=""
  case "${b:-}" in n|N) ;; *) snapshot ;; esac
  stop_tavern >/dev/null 2>&1 || true
  rm -rf "$TAVERN_DIR"
  good "酒馆已删除。Termux 环境还在，重跑 install.sh 可以装回来"
}

# ------------------------------------------------------------------ 界面
draw_menu() {
  local state; is_up && state="${C_OK}运行中${C_OFF}" || state="${C_WARN}已停止${C_OFF}"
  printf '\n'
  printf '%s┌────────────────────────────────────────────┐%s\n' "$C_HI" "$C_OFF"
  printf '%s│%s  酒馆控制台                     %s\n' "$C_HI" "$C_OFF" "$state"
  printf '%s├────────────────────────────────────────────┤%s\n' "$C_HI" "$C_OFF"
  printf '%s│%s  %s[1]%s 启动        %s[2]%s 停止      %s[3]%s 重启\n' "$C_HI" "$C_OFF" "$C_OK" "$C_OFF" "$C_OK" "$C_OFF" "$C_OK" "$C_OFF"
  printf '%s│%s  %s[4]%s 状态        %s[5]%s 日志\n' "$C_HI" "$C_OFF" "$C_OK" "$C_OFF" "$C_OK" "$C_OFF"
  printf '%s├────────────────────────────────────────────┤%s\n' "$C_HI" "$C_OFF"
  printf '%s│%s  %s[6]%s 更新版本    %s[7]%s 酒馆助手\n' "$C_HI" "$C_OFF" "$C_OK" "$C_OFF" "$C_OK" "$C_OFF"
  printf '%s│%s  %s[8]%s 备份数据    %s[9]%s 恢复数据\n' "$C_HI" "$C_OFF" "$C_OK" "$C_OFF" "$C_OK" "$C_OFF"
  printf '%s├────────────────────────────────────────────┤%s\n' "$C_HI" "$C_OFF"
  printf '%s│%s  %s[10]%s 卸载酒馆   %s[0]%s 退出\n' "$C_HI" "$C_OFF" "$C_ERR" "$C_OFF" "$C_OK" "$C_OFF"
  printf '%s└────────────────────────────────────────────┘%s\n' "$C_HI" "$C_OFF"
}

main_loop() {
  while true; do
    draw_menu
    ask "选择 [0-10]:"
    local c; read -r c || c="0"
    case "${c:-}" in
      1)  start_tavern;    hold ;;
      2)  stop_tavern;     hold ;;
      3)  stop_tavern; start_tavern; hold ;;
      4)  show_status;     hold ;;
      5)  show_log;        hold ;;
      6)  update_tavern;   hold ;;
      7)  toggle_extension; hold ;;
      8)  snapshot;        hold ;;
      9)  rollback;        hold ;;
      10) remove_tavern;   hold ;;
      0)  printf '  回头见\n'; exit 0 ;;
      *)  note "没有这个选项" ;;
    esac
  done
}

if [ ! -d "$TAVERN_DIR" ]; then
  bad "还没装酒馆，先跑一遍 install.sh"
  exit 1
fi
if [ ! -t 0 ]; then
  note "当前不是交互终端，面板要交互才能用。请重开 Termux 后输入 st"
  exit 0
fi
main_loop
ST_PANEL_EOF

  chmod +x "$PANEL_PATH"
  ok "面板已就位"

  # 注入 st 别名
  local rc="$HOME/.bashrc"
  touch "$rc"
  if ! grep -qF "alias st=" "$rc" 2>/dev/null; then
    {
      printf '\n# SillyTavern 管理面板（由 install.sh 写入）\n'
      printf "alias st='bash \$HOME/st.sh'\n"
    } >> "$rc"
    ok "已写入别名 st → 重开 Termux 生效"
  else
    ok "别名 st 已存在"
  fi
}

# --------------------------------------------------------------- 主流程
main() {
  printf '\n%sSillyTavern for Termux%s  ·  部署器\n' "$C_HI" "$C_OFF"
  printf '%sApache-2.0 · 免费使用%s\n\n' "$C_DIM" "$C_OFF"

  require_termux
  mkdir -p "$LOG_DIR"

  if [ -d "$TAVERN_DIR/.git" ]; then
    ok "酒馆已装好，直接进面板"
  else
    setup_apt_mirror
    ensure_packages
    install_tavern
    install_npm_deps

    if [ -t 0 ]; then
      ask_extensions
    else
      warn "管道安装没有交互终端，跳过扩展选择"
      hint "想要的话，装完在面板里选 [7]"
    fi
  fi

  write_panel

  printf '\n'
  rule
  printf '  %s装好了%s\n' "$C_OK" "$C_OFF"
  rule
  printf '  管理面板   st       %s(当前窗口: bash ~/st.sh)%s\n' "$C_DIM" "$C_OFF"
  printf '  浏览器     http://127.0.0.1:8000\n'
  printf '  数据在     %s/data\n' "$TAVERN_DIR"
  printf '\n'
  printf '  %s玩的时候 Termux 要留在后台：挂小窗 / 省电策略设成无限制 / 长按卡片锁定%s\n' "$C_DIM" "$C_OFF"
  printf '\n'

  if [ -t 0 ]; then
    bash "$PANEL_PATH"
  else
    printf '  重开 Termux，输入 st 进面板\n'
  fi
}

main "$@"
