#!/usr/bin/env bash
# 프로젝트에 개발회사 운영 규칙(CLAUDE.md)과 인수인계 문서 폴더(docs/)를 적용한다.
# 기존 파일은 덮어쓰지 않는다.
# 사용법: ./init-project.sh <프로젝트 경로>
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$KIT_DIR/project-template"
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "사용법: ./init-project.sh <프로젝트 경로>"; exit 1
fi
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

# 로컬 전용 덧붙임(local/overlay/project-template, git 제외)이 있으면 복사한 파일 끝에 블록으로 붙인다
add_overlay() {  # $1 = 템플릿 기준 상대 경로, $2 = 복사한 파일
  local ov="$KIT_DIR/local/overlay/project-template/$1"
  [ -f "$ov" ] || return 0
  { printf '\n%s\n' '<!-- local-overlay: 이 블록은 키트의 local/overlay에서 온다 -->'; cat "$ov"; printf '%s\n' '<!-- /local-overlay -->'; } >> "$2"
}

if [ -e "$TARGET/CLAUDE.md" ]; then
  cp "$TEMPLATE/CLAUDE.md" "$TARGET/CLAUDE.dev-company.md"
  echo "! CLAUDE.md가 이미 있어 CLAUDE.dev-company.md로 저장했다. 두 파일을 병합해야 한다."
else
  cp "$TEMPLATE/CLAUDE.md" "$TARGET/CLAUDE.md"; add_overlay CLAUDE.md "$TARGET/CLAUDE.md"
  echo "+ CLAUDE.md"
fi

# agent-office 부서 배치 (.claude/office.json). 이미 있으면 덮어쓰지 않는다
mkdir -p "$TARGET/.claude"
if [ -e "$TARGET/.claude/office.json" ]; then
  echo "! .claude/office.json이 이미 있어 그대로 두었다 (키트 부서 배치: $TEMPLATE/.claude/office.json)"
else
  cp "$TEMPLATE/.claude/office.json" "$TARGET/.claude/office.json"
  echo "+ .claude/office.json"
fi

for d in "$TEMPLATE"/docs/*/; do
  name="$(basename "$d")"
  mkdir -p "$TARGET/docs/$name"
  # 템플릿 파일(.gitkeep 제외)은 없을 때만 복사한다
  for f in "$d"*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    if [ ! -e "$TARGET/docs/$name/$base" ]; then
      cp "$f" "$TARGET/docs/$name/$base"; add_overlay "docs/$name/$base" "$TARGET/docs/$name/$base"
      echo "+ docs/$name/$base"
    fi
  done
  [ -e "$TARGET/docs/$name/.gitkeep" ] || [ -n "$(ls -A "$TARGET/docs/$name")" ] || touch "$TARGET/docs/$name/.gitkeep"
  echo "+ docs/$name/"
done

echo
echo "다음 할 일: 이 프로젝트에서 Claude Code를 열고 '0단계(초기 세팅)부터 시작해'라고 요청한다 (CLAUDE.md 2장, 8장, 9장)."
