#!/usr/bin/env bash
# Dev Agent Kit 양방향 동기화
# - 이 PC의 ~/.claude/agents, ~/.claude/skills 변경을 키트 저장소(global/)로 올리고 commit/push한다.
# - 저장소의 최신 내용을 pull해서 ~/.claude에 반영한다. 다른 PC에서 지운 파일은 여기서도 지운다.
# - 권한 규칙(global/settings/permissions.json: ask·allow·remove)과 env 를 settings.json에 병합한다.
# install.sh가 Claude Code 세션 시작(SessionStart)과 종료(SessionEnd) 훅으로 등록한다.
# 저장소가 공개일 수 있으므로 push는 확인한 뒤에만 한다: 평소에는 로컬에 커밋만 하고 "push 대기"를 알린다.
# 사용법:
#   ./sync.sh          수동 실행 (진행 내용과 push 대기 커밋을 출력)
#   ./sync.sh --push   push 대기 커밋을 확인했으면 원격에 올린다
#   ./sync.sh --hook   훅에서 실행 (변경이나 문제가 있을 때만 한 줄 출력)
# 확인 없이 자동 push하려면(비공개 저장소 등) 환경변수 DEV_COMPANY_SYNC_AUTOPUSH=1
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC="$KIT_DIR/global"
DIRS="agents skills"
STATE="$CLAUDE_DIR/.dev-company-sync"
MANIFEST="$STATE/manifest"
LOCK="$STATE/lock"
HOOK=false; PUSH=false
for a in "$@"; do
  case "$a" in
    --hook) HOOK=true ;;
    --push) PUSH=true ;;
  esac
done
[ "${DEV_COMPANY_SYNC_AUTOPUSH:-}" = "1" ] && PUSH=true

# 훅에서는 비밀번호·passphrase 입력을 기다리지 않고, 네트워크가 느리면 빨리 포기한다
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=8}"

log()  { $HOOK || echo "$@"; }
note() { echo "[dev-company sync] $*"; }
g()    { git -C "$KIT_DIR" "$@"; }

mkdir -p "$STATE"
# 세션 여러 개가 동시에 시작해도 한 번만 돈다. 2분 넘은 잠금은 비정상 종료로 보고 지운다
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backup-dev-company-$TS"
SENT=0; RECEIVED=0; REMOVED=0; BACKED_UP=0; PENDING=0

hash_of() { if [ -f "$1" ]; then git hash-object --no-filters "$1"; else echo "-"; fi; }
# 로컬 전용 덧붙임(local/overlay, git 제외): ~/.claude에 설치할 때 블록으로 붙이고, 저장소로 올릴 때 뗀다
OVERLAY="$KIT_DIR/local/overlay/global"
OV_BEGIN='<!-- local-overlay: 이 블록은 키트의 local/overlay에서 온다. 여기서 고치지 말고 그 파일을 고친다 -->'
OV_END='<!-- /local-overlay -->'
compose() {  # $1 = 상대 경로. 저장소 파일 + 덧붙임 블록을 출력한다
  cat "$SRC/$1"
  [ -f "$OVERLAY/$1" ] && { printf '\n%s\n' "$OV_BEGIN"; cat "$OVERLAY/$1"; printf '%s\n' "$OV_END"; }
  return 0
}
strip_overlay() {  # stdin에서 덧붙임 블록과 그 앞에 붙인 빈 줄 하나를 지운다
  awk -v b="$OV_BEGIN" -v e="$OV_END" '
    $0 == b { if (have && prev != "") print prev; have = 0; skip = 1; next }
    skip    { if ($0 == e) skip = 0; next }
            { if (have) print prev; prev = $0; have = 1 }
    END     { if (have) print prev }'
}
# 저장소 쪽 해시는 ~/.claude에 실제로 설치될 내용(덧붙임 포함) 기준
src_hash() { if [ -f "$SRC/$1" ]; then compose "$1" | git hash-object --stdin; else echo "-"; fi; }
base_of() { [ -f "$MANIFEST" ] && awk -F'\t' -v p="$1" '$2==p {print $1; exit}' "$MANIFEST"; }
# 스킬은 키트 자체 스킬만 동기화한다. 플러그인·외부에서 설치한 스킬(skills/synced 포함)은 공개 저장소에 올리지 않고 로컬에서 지우지도 않는다
# 새 자체 스킬을 만들면 여기에 이름을 추가한다
KIT_SKILLS="spring-conventions frontend-conventions python-conventions"
kit_only() { grep -E "^(agents/|skills/($(echo $KIT_SKILLS | tr ' ' '|'))/)" || true; }
list_files() {  # $1 아래 agents/, skills/의 파일을 상대 경로로 나열
  local d
  for d in $DIRS; do
    [ -d "$1/$d" ] && (cd "$1" && find "$d" -type f ! -name .DS_Store ! -name Thumbs.db ! -name desktop.ini)
  done | kit_only
}
# 예전 manifest 에 남은 외부 스킬 경로도 빼야 3단계에서 로컬 파일을 지우지 않는다
manifest_paths() { [ -f "$MANIFEST" ] && cut -f2 "$MANIFEST" | kit_only; }
backup_local() {
  mkdir -p "$BACKUP_DIR/$(dirname "$1")"
  cp "$CLAUDE_DIR/$1" "$BACKUP_DIR/$1"
  BACKED_UP=$((BACKED_UP + 1))
}

if ! g rev-parse --git-dir >/dev/null 2>&1; then
  note "키트 폴더가 Git 저장소가 아니라 동기화하지 않았다: $KIT_DIR"; exit 0
fi

# ---- 1. 이 PC의 변경을 저장소로 모은다 ----
FIRST_RUN=false
[ -f "$MANIFEST" ] || FIRST_RUN=true
while IFS= read -r p; do
  [ -n "$p" ] || continue
  L="$(hash_of "$CLAUDE_DIR/$p")"
  R="$(src_hash "$p")"
  if $FIRST_RUN; then
    # 처음 동기화하는 PC: 저장소에 없는 파일만 올린다. 내용이 다르면 저장소 쪽이 이긴다(3단계에서 백업 후 덮어씀)
    [ "$R" = "-" ] && [ "$L" != "-" ] || continue
  else
    B="$(base_of "$p")"; B="${B:--}"
    [ "$L" != "$B" ] || continue          # 지난 동기화 이후 이 PC에서 바뀌지 않음
  fi
  if [ "$L" = "-" ]; then
    rm -f "$SRC/$p"; log "  - (이 PC에서 삭제) $p"
  else
    mkdir -p "$(dirname "$SRC/$p")"; strip_overlay < "$CLAUDE_DIR/$p" > "$SRC/$p"; log "  ↑ $p"
  fi
done < <( { list_files "$CLAUDE_DIR"; manifest_paths; } | sort -u )

g add -A -- global
if ! g diff --cached --quiet -- global; then
  SENT=$(g diff --cached --name-only -- global | wc -l | tr -d ' ')
  # 자동 커밋은 PC의 git 설정(회사 이메일 등)과 상관없이 항상 고정 신원으로 남긴다
  g -c user.name=dev-company-sync -c user.email=dev-company-sync@localhost commit -q -m "sync: 에이전트·스킬 변경 반영" -- global \
    || { note "변경을 커밋하지 못해 동기화를 멈췄다. 키트 폴더에서 git status를 확인한다: $KIT_DIR"; exit 0; }
fi

# ---- 2. 저장소와 주고받는다 ----
OFFLINE=false
if g rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  BEFORE="$(g rev-parse HEAD)"
  GIT_DIR_ABS="$(g rev-parse --absolute-git-dir)"
  if ! g pull -q --rebase --autostash >/dev/null 2>&1; then
    if [ -d "$GIT_DIR_ABS/rebase-merge" ] || [ -d "$GIT_DIR_ABS/rebase-apply" ]; then
      g rebase --abort 2>/dev/null
      note "다른 PC의 변경과 같은 파일이 충돌해 동기화를 멈췄다. 이 PC의 변경은 로컬 커밋으로 남아 있다. 키트 폴더에서 git pull --rebase로 직접 해결한다: $KIT_DIR"
      exit 0
    fi
    OFFLINE=true
  fi
  if ! $OFFLINE; then
    [ "$BEFORE" != "$(g rev-parse HEAD)" ] && log "  ↓ 저장소에서 새 변경을 받았다"
    AHEAD="$(g rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    if [ "$AHEAD" -gt 0 ]; then
      if $PUSH; then
        g push -q 2>/dev/null || OFFLINE=true
      else
        PENDING="$AHEAD"   # 공개 저장소에 올라가기 전에 사람이 확인한다
        $HOOK || g log --oneline '@{u}..HEAD'
      fi
    fi
  fi
else
  log "  (원격 저장소가 연결되어 있지 않아 이 PC 안에서만 반영한다)"
fi

# ---- 3. 저장소 내용을 ~/.claude에 반영한다 ----
while IFS= read -r p; do
  [ -n "$p" ] || continue
  R="$(src_hash "$p")"
  L="$(hash_of "$CLAUDE_DIR/$p")"
  [ "$R" != "$L" ] || continue
  B="$(base_of "$p")"; B="${B:--}"
  # 마지막 동기화 이후 이 PC에서 바뀐 내용을 덮어쓰게 되면 먼저 백업한다
  [ "$L" != "-" ] && [ "$L" != "$B" ] && backup_local "$p"
  if [ "$R" = "-" ]; then
    rm -f "$CLAUDE_DIR/$p"; REMOVED=$((REMOVED + 1)); log "  - $p"
  else
    mkdir -p "$(dirname "$CLAUDE_DIR/$p")"; compose "$p" > "$CLAUDE_DIR/$p"; RECEIVED=$((RECEIVED + 1)); log "  ↓ $p"
  fi
done < <( { list_files "$SRC"; manifest_paths; } | sort -u )
[ -d "$CLAUDE_DIR/skills" ] && find "$CLAUDE_DIR/skills" -mindepth 1 -type d -empty -delete 2>/dev/null

# 다음 동기화의 기준점: 지금 저장소(=이 PC) 상태
TMP="$MANIFEST.tmp"; : > "$TMP"
while IFS= read -r p; do
  [ -n "$p" ] && printf '%s\t%s\n' "$(src_hash "$p")" "$p" >> "$TMP"
done < <(list_files "$SRC" | sort)
mv "$TMP" "$MANIFEST"

# ---- 4. 권한 규칙 병합 (ask: 확인 창, allow: 확인 없이 실행, remove: 이전 키트가 넣었던 규칙 제거) ----
RULES="$SRC/settings/permissions.json"
SETTINGS="$CLAUDE_DIR/settings.json"
ADDED=0
if [ -f "$RULES" ] && command -v node >/dev/null 2>&1; then
  ADDED="$(node -e '
    const fs = require("fs");
    const [settingsPath, rulesPath, backupPath, guardPath, localPath] = process.argv.slice(1);
    let s = {};
    if (fs.existsSync(settingsPath)) {
      const raw = fs.readFileSync(settingsPath, "utf8").trim();
      s = raw ? JSON.parse(raw) : {};
    }
    const rules = JSON.parse(fs.readFileSync(rulesPath, "utf8"));
    // 이 PC 전용 규칙(local/permissions.json, git 제외)을 함께 병합한다
    if (localPath && fs.existsSync(localPath)) {
      const extra = JSON.parse(fs.readFileSync(localPath, "utf8"));
      for (const k of ["ask", "allow", "remove"]) rules[k] = (rules[k] || []).concat(extra[k] || []);
      rules.env = { ...(rules.env || {}), ...(extra.env || {}) };
    }
    const p = s.permissions = s.permissions || {};
    let changed = 0;
    // 1) 제거: remove 목록의 규칙을 ask·allow에서 지운다. deny는 사용자가 직접 건 안전장치라 건드리지 않는다.
    //    단, 키트가 그 목록(ask·allow)에 원하는 규칙은 지우지 않는다 (예: git push는 ask에서만 빼고 allow에는 둔다)
    const remove = new Set(rules.remove || []);
    for (const k of ["ask", "allow"]) {
      if (!Array.isArray(p[k])) continue;
      const want = new Set(rules[k] || []);
      const kept = p[k].filter(r => !remove.has(r) || want.has(r));
      changed += p[k].length - kept.length;
      p[k] = kept;
    }
    // 2) 추가: 빠진 ask·allow 규칙을 더한다 (사용자가 직접 넣은 규칙은 그대로 둔다)
    for (const k of ["ask", "allow"]) {
      const want = rules[k] || [];
      const cur = p[k] || [];
      const add = want.filter(r => !cur.includes(r));
      if (add.length) { p[k] = cur.concat(add); changed += add.length; }
    }
    // 3) env: 키트·local이 관리하는 환경변수를 맞춘다. 다른 env 키는 건드리지 않는다
    if (rules.env && typeof rules.env === "object") {
      const e = s.env = s.env || {};
      for (const [k, v] of Object.entries(rules.env)) {
        if (e[k] !== v) { e[k] = v; changed++; }
      }
    }
    // 4) 가드 훅: 키트 서브에이전트의 git 쓰기·소유 영역 밖 수정을 막는 PreToolUse 훅을 현재 키트 경로로 등록한다
    if (guardPath && fs.existsSync(guardPath)) {
      const MARK = "dev-company-kit guard";
      const command = `node "${guardPath}" # ${MARK}`;
      const h = s.hooks = s.hooks || {};
      const cur = h.PreToolUse || [];
      if (!cur.some(e => (e.hooks || []).some(x => x.command === command))) {
        // 예전 경로로 등록된 가드는 지우고 다시 넣는다 (키트 폴더를 옮겨도 안전)
        const kept = cur.map(e => ({ ...e, hooks: (e.hooks || []).filter(x => !String(x.command || "").includes(MARK)) })).filter(e => e.hooks.length);
        h.PreToolUse = kept.concat({ matcher: "Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit", hooks: [{ type: "command", command, timeout: 10 }] });
        changed++;
      }
    }
    if (changed) {
      if (fs.existsSync(settingsPath)) {
        fs.mkdirSync(require("path").dirname(backupPath), { recursive: true });
        fs.copyFileSync(settingsPath, backupPath);
      }
      fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + "\n");
    }
    console.log(changed);
  ' "$SETTINGS" "$RULES" "$BACKUP_DIR/settings.json" "$KIT_DIR/hooks/guard.js" "$KIT_DIR/local/permissions.json" 2>/dev/null)" || { note "settings.json 병합 실패 (JSON 형식 확인 필요)"; ADDED=0; }
  [ "${ADDED:-0}" -gt 0 ] && log "  ~ 권한 규칙·env·가드 훅 ${ADDED}건 변경"
fi

# ---- 결과 ----
SUMMARY="커밋 ${SENT}, 받음 ${RECEIVED}, 삭제 ${REMOVED}"
[ "${ADDED:-0}" -gt 0 ] && SUMMARY="$SUMMARY, 권한 규칙 ${ADDED}건 변경"
$OFFLINE && SUMMARY="$SUMMARY (원격 저장소에 연결하지 못함: 다음 동기화 때 다시 시도)"
[ "$PENDING" -gt 0 ] && SUMMARY="$SUMMARY, push 대기 커밋 ${PENDING}개 (키트 폴더에서 git log -p @{u}..HEAD 로 확인한 뒤 ./sync.sh --push)"
[ "$BACKED_UP" -gt 0 ] && SUMMARY="$SUMMARY, 덮어쓰기 전 백업: $BACKUP_DIR"
if $HOOK; then
  { [ "$SENT$RECEIVED$REMOVED" != "000" ] || $OFFLINE || [ "$BACKED_UP" -gt 0 ] || [ "$PENDING" -gt 0 ]; } && note "$SUMMARY"
else
  note "$SUMMARY"
fi
exit 0
