#!/usr/bin/env bash
# sync.sh 회귀 테스트: 임시 원격 저장소 하나와 PC 두 대(클론 + CLAUDE_CONFIG_DIR)를 만들어 동기화를 돌려 본다.
# 사용법: bash tests/sync_test.sh   (git, node 필요. 실제 ~/.claude 는 건드리지 않는다)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1   # 사용자 git 설정(서명, 훅 등) 영향 제거
G=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)

fail() { echo "FAIL: $*"; exit 1; }
ok()   { echo "ok - $*"; }

# 원격 저장소와 최소 키트
"${G[@]}" init -q --bare "$T/remote.git"
mkdir -p "$T/seed/global/agents" "$T/seed/global/settings" "$T/seed/hooks"
cp "$ROOT/sync.sh" "$T/seed/"
cp "$ROOT/hooks/guard.js" "$T/seed/hooks/"
cp "$ROOT/global/settings/permissions.json" "$T/seed/global/settings/"
echo v1 > "$T/seed/global/agents/x.md"
"${G[@]}" -C "$T/seed" init -q
"${G[@]}" -C "$T/seed" add -A
"${G[@]}" -C "$T/seed" commit -qm seed
"${G[@]}" -C "$T/seed" push -q "$T/remote.git" HEAD:main
for pc in a b; do "${G[@]}" clone -q "$T/remote.git" "$T/kit-$pc"; mkdir -p "$T/claude-$pc"; done

sync_pc() { CLAUDE_CONFIG_DIR="$T/claude-$1" bash "$T/kit-$1/sync.sh" --push >/dev/null; }   # 확인을 마친 동기화

# 1. 처음 동기화하는 PC: 로컬 내용이 다르면 백업 후 저장소 내용으로 맞춘다
mkdir -p "$T/claude-b/agents"; echo b-old > "$T/claude-b/agents/x.md"
sync_pc a; sync_pc b
[ "$(cat "$T/claude-a/agents/x.md")" = v1 ] || fail "A가 x.md를 받지 못함"
[ "$(cat "$T/claude-b/agents/x.md")" = v1 ] || fail "B의 x.md가 저장소 내용으로 바뀌지 않음"
grep -rqx b-old "$T/claude-b"/backup-dev-company-*/agents/x.md || fail "B의 기존 x.md가 백업되지 않음"
ok "첫 동기화: 저장소 우선 + 백업"

# 2. A에서 고치면 B에 반영된다
echo v2 > "$T/claude-a/agents/x.md"; sync_pc a; sync_pc b
[ "$(cat "$T/claude-b/agents/x.md")" = v2 ] || fail "A의 수정이 B에 반영되지 않음"
ok "수정 전파"

# 3. A에서 지우면 B에서도 지워진다
rm "$T/claude-a/agents/x.md"; sync_pc a; sync_pc b
[ ! -e "$T/claude-b/agents/x.md" ] || fail "A의 삭제가 B에 반영되지 않음"
ok "삭제 전파"

# 4. 앱이 관리하는 skills/synced 는 올리지도, 지우지도 않는다 (예전 manifest 에 남아 있어도)
mkdir -p "$T/claude-a/skills/synced/acct/s"; echo app > "$T/claude-a/skills/synced/acct/s/SKILL.md"
printf -- '-\tskills/synced/acct/s/SKILL.md\n' >> "$T/claude-a/.dev-company-sync/manifest"
sync_pc a
[ -e "$T/claude-a/skills/synced/acct/s/SKILL.md" ] || fail "skills/synced 파일이 지워짐"
"${G[@]}" -C "$T/kit-a" ls-files | grep -q 'skills/synced' && fail "skills/synced 가 저장소에 올라감"
ok "skills/synced 제외"

# 4-1. 외부 설치 스킬(aws-* 등)은 올리지 않고, 예전 manifest 에 남아 있어도 로컬에서 지우지 않는다
mkdir -p "$T/claude-a/skills/aws-x"; echo ext > "$T/claude-a/skills/aws-x/SKILL.md"
printf -- '-\tskills/aws-x/SKILL.md\n' >> "$T/claude-a/.dev-company-sync/manifest"
mkdir -p "$T/claude-a/skills/spring-conventions"; echo own > "$T/claude-a/skills/spring-conventions/SKILL.md"
sync_pc a
[ -e "$T/claude-a/skills/aws-x/SKILL.md" ] || fail "외부 스킬이 로컬에서 지워짐"
"${G[@]}" -C "$T/kit-a" ls-files | grep -q 'skills/aws-x' && fail "외부 스킬이 저장소에 올라감"
"${G[@]}" -C "$T/kit-a" ls-files | grep -q 'skills/spring-conventions/SKILL.md' || fail "자체 스킬이 올라가지 않음"
ok "외부 스킬 제외, 자체 스킬 동기화"

# 4-2. --push 없이는 로컬에 커밋만 하고 원격에 올리지 않는다 (공개 저장소 대비). 훅은 대기 중임을 알린다
echo pending > "$T/claude-a/agents/p.md"
OUT="$(CLAUDE_CONFIG_DIR="$T/claude-a" bash "$T/kit-a/sync.sh" --hook)"
"${G[@]}" -C "$T/kit-a" log --oneline -1 -- global/agents/p.md | grep -q . || fail "로컬 커밋이 안 됨"
"${G[@]}" --git-dir="$T/remote.git" log --oneline main -- global/agents/p.md | grep -q . && fail "--push 없이 원격에 올라감"
echo "$OUT" | grep -q "push 대기 커밋 1개" || fail "훅이 push 대기를 알리지 않음: $OUT"
sync_pc a
"${G[@]}" --git-dir="$T/remote.git" log --oneline main -- global/agents/p.md | grep -q . || fail "--push로 올라가지 않음"
ok "push는 확인(--push) 후에만"

# 4-3. 자동 커밋 작성자는 PC의 전역 git 이메일과 상관없이 dev-company-sync@localhost 로 고정된다
printf '[user]\n\tname = pc-user\n\temail = pc@company.example\n' > "$T/gitconfig-pc"
echo e > "$T/claude-a/agents/e.md"
GIT_CONFIG_GLOBAL="$T/gitconfig-pc" sync_pc a
AUTHOR="$("${G[@]}" -C "$T/kit-a" log -1 --format='%an <%ae>|%cn <%ce>' -- global/agents/e.md)"
[ "$AUTHOR" = "dev-company-sync <dev-company-sync@localhost>|dev-company-sync <dev-company-sync@localhost>" ] \
  || fail "자동 커밋 신원이 고정되지 않음: $AUTHOR"
ok "자동 커밋 작성자 고정"

# 4-3. local/overlay: ~/.claude에는 블록으로 붙고, 이 PC에서 고친 내용을 올릴 때는 블록을 떼고 올린다
mkdir -p "$T/claude-a/agents" "$T/kit-a/local/overlay/global/agents"
echo base > "$T/claude-a/agents/o.md"; sync_pc a
echo "LOCAL-ONLY" > "$T/kit-a/local/overlay/global/agents/o.md"; sync_pc a
grep -q LOCAL-ONLY "$T/claude-a/agents/o.md" || fail "덧붙임이 ~/.claude에 안 붙음"
grep -q LOCAL-ONLY "$T/kit-a/global/agents/o.md" && fail "덧붙임이 저장소 파일에 들어감"
sed -i.bak 's/^base$/edited/' "$T/claude-a/agents/o.md"; rm -f "$T/claude-a/agents/o.md.bak"; sync_pc a
[ "$(cat "$T/kit-a/global/agents/o.md")" = edited ] || fail "로컬 수정을 올릴 때 블록을 떼지 못함: $(cat "$T/kit-a/global/agents/o.md")"
grep -q LOCAL-ONLY "$T/claude-a/agents/o.md" || fail "수정 뒤 덧붙임이 사라짐"
"${G[@]}" --git-dir="$T/remote.git" show main:global/agents/o.md | grep -q LOCAL-ONLY && fail "덧붙임이 원격에 올라감"
sync_pc b; grep -q LOCAL-ONLY "$T/claude-b/agents/o.md" && fail "local이 없는 PC에 덧붙임이 감"
[ "$(cat "$T/claude-b/agents/o.md")" = edited ] || fail "다른 PC가 수정을 받지 못함"
ok "local/overlay 덧붙임 (설치 때만, 원격 제외)"

# 5. 사용자가 직접 넣은 deny 규칙은 remove 목록에 있어도 지우지 않는다
echo '{"permissions":{"deny":["Bash(git push *)"]}}' > "$T/claude-b/settings.json"
sync_pc b
node -e 'const s=require(process.argv[1]); if(!s.permissions.deny.includes("Bash(git push *)")) process.exit(1)' "$T/claude-b/settings.json" \
  || fail "deny 규칙이 지워짐"
ok "deny 규칙 보존"

# 6. 가드 훅이 PreToolUse에 한 번만 등록되고, 사용자가 둔 다른 훅은 남는다
node -e '
  const fs=require("fs"), p=process.argv[1]; const s=JSON.parse(fs.readFileSync(p));
  s.hooks.PreToolUse.push({matcher:"Bash",hooks:[{type:"command",command:"echo mine"}]});
  fs.writeFileSync(p, JSON.stringify(s));' "$T/claude-b/settings.json"
sync_pc b; sync_pc b
node -e '
  const s=require(process.argv[1]); const cmds=(s.hooks.PreToolUse||[]).flatMap(e=>e.hooks.map(h=>h.command));
  const g=cmds.filter(c=>c.includes("dev-company-kit guard"));
  if (g.length!==1 || !g[0].includes(process.argv[2]) || !cmds.includes("echo mine")) process.exit(1)' "$T/claude-b/settings.json" "$T/kit-b/hooks/guard.js" \
  || fail "가드 훅 등록이 잘못됨 (중복, 경로, 사용자 훅 유실 중 하나)"
ok "가드 훅 등록"

echo "all passed"
