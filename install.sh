#!/usr/bin/env bash
# Dev Agent Kit 설치 스크립트
# - 에이전트·스킬·비용 확인 규칙을 사용자 범위(~/.claude)에 설치한다 (sync.sh로 처리).
# - Claude Code 세션 시작·종료 때 sync.sh가 자동 실행되도록 훅을 등록한다.
#   그러면 어느 PC에서 에이전트를 고쳐도 저장소를 거쳐 다른 PC에 반영된다.
# - 내용이 다른 기존 파일은 ~/.claude/backup-dev-company-{시각}/ 에 백업한다.
# 사용법:
#   ./install.sh                 설치 + 자동 동기화 훅 등록
#   ./install.sh --no-hooks      자동 동기화 훅 없이 설치 (수동으로 ./sync.sh 실행)
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
WITH_HOOKS=true
for a in "$@"; do
  case "$a" in
    --no-hooks) WITH_HOOKS=false ;;
    *) echo "알 수 없는 옵션: $a (--no-hooks)"; exit 1 ;;
  esac
done

echo "== Dev Agent Kit 설치: $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR"

if ! command -v node >/dev/null 2>&1; then
  echo "   ! node가 없다. node 18 이상을 설치한 뒤 다시 실행한다"; exit 1
fi

echo "-- 에이전트·스킬·비용 확인 규칙 동기화"
bash "$KIT_DIR/sync.sh"

if $WITH_HOOKS; then
  echo "-- 자동 동기화 훅 (settings.json hooks: SessionStart, SessionEnd)"
  SETTINGS="$CLAUDE_DIR/settings.json"
  TS="$(date +%Y%m%d-%H%M%S)"
  [ -f "$SETTINGS" ] && { mkdir -p "$CLAUDE_DIR/backup-dev-company-$TS"; cp "$SETTINGS" "$CLAUDE_DIR/backup-dev-company-$TS/settings.json"; }
  node -e '
    const fs = require("fs");
    const [settingsPath, kitDir] = process.argv.slice(1);
    let s = {};
    if (fs.existsSync(settingsPath)) {
      const raw = fs.readFileSync(settingsPath, "utf8").trim();
      s = raw ? JSON.parse(raw) : {};
    }
    const MARK = "dev-company-kit sync";
    const command = `bash "${kitDir}/sync.sh" --hook # ${MARK}`;
    const entry = (matcher) => ({ ...(matcher ? { matcher } : {}), hooks: [{ type: "command", command, timeout: 30 }] });
    s.hooks = s.hooks || {};
    for (const [event, matcher] of [["SessionStart", "startup"], ["SessionEnd", null]]) {
      // 이전에 등록한 키트 훅은 지우고 현재 키트 경로로 다시 등록한다 (키트 폴더를 옮겨도 안전)
      const kept = (s.hooks[event] || [])
        .map(e => ({ ...e, hooks: (e.hooks || []).filter(h => !String(h.command || "").includes(MARK)) }))
        .filter(e => e.hooks.length);
      s.hooks[event] = kept.concat(entry(matcher));
    }
    fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + "\n");
  ' "$SETTINGS" "$KIT_DIR"
  echo "   + 세션 시작 시 pull·반영, 세션 종료 시 변경을 로컬 commit (push는 확인 후 ./sync.sh --push)"
fi

echo
echo "== 완료"
$WITH_HOOKS || echo "- 자동 동기화 없음: 에이전트를 고친 뒤 ./sync.sh 를 직접 실행한다"
echo "- 프로젝트 적용: ./init-project.sh <프로젝트 경로>"
echo "- Claude Code를 재시작하면 /agents 에 에이전트가 표시된다"
