#!/usr/bin/env bash
# hooks/guard.js 검사: 키트 서브에이전트의 금지 동작은 막고, 메인 세션·허용된 동작은 통과시키는지 본다.
# 사용법: bash tests/guard_test.sh   (node 필요)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$ROOT/hooks/guard.js" <<'EOF'
const { execFileSync } = require("child_process");
const guard = process.argv[2];
const run = (input) => {
  const out = execFileSync("node", [guard], { input: JSON.stringify(input) }).toString();
  return out ? JSON.parse(out).hookSpecificOutput.permissionDecision : "pass";
};
const bash = (agent, command) => ({ agent_type: agent, tool_name: "Bash", tool_input: { command }, cwd: "/p" });
const write = (agent, file_path) => ({ agent_type: agent, tool_name: "Write", tool_input: { file_path }, cwd: "/p" });
const cases = [
  ["서브에이전트 git commit", bash("be-api", "git add . && git commit -m x"), "deny"],
  ["서브에이전트 git -C 경로 push", bash("infra", "git -C /p push origin main"), "deny"],
  ["서브에이전트 브랜치 전환", bash("fe-feature", "git switch -c feat"), "deny"],
  ["서브에이전트 git 조회", bash("be-reviewer", "git diff HEAD~1 && git log --oneline"), "pass"],
  ["git이 아닌 명령의 commit 단어", bash("qa", "echo 'commit message'"), "pass"],
  ["메인 세션 git push", { tool_name: "Bash", tool_input: { command: "git push" }, cwd: "/p" }, "pass"],
  ["키트 밖 에이전트 git commit", bash("general-purpose", "git commit -m x"), "pass"],
  ["security-reviewer 위협 모델 수정", write("security-reviewer", "/p/docs/security/threat-model.md"), "pass"],
  ["security-reviewer 리포트 작성", write("security-reviewer", "/p/docs/handoff/auth/09-security-reviewer.md"), "pass"],
  ["security-reviewer 코드 수정", write("security-reviewer", "/p/backend/src/main/App.java"), "deny"],
  ["planning-spec PRD 작성", write("planning-spec", "/p/docs/prd/auth.md"), "pass"],
  ["planning-spec API 명세 수정", write("planning-spec", "/p/docs/api/auth.yaml"), "deny"],
  ["구현 담당 코드 수정", write("be-api", "/p/backend/src/main/App.java"), "pass"],
  ["따옴표 안의 git push", bash("be-api", 'bash -c "git push"'), "deny"],
  ["$( ) 안의 git commit", bash("be-domain", "x=$(git commit -m y)"), "deny"],
  ["gh pr create", bash("infra", "gh pr create --fill"), "deny"],
  ["gh pr merge", bash("infra", "gh pr merge 3 --squash"), "deny"],
  ["gh pr view (조회)", bash("infra", "gh pr view 3"), "pass"],
  ["git stash list (조회)", bash("qa", "git stash list"), "pass"],
  ["git stash (쓰기)", bash("qa", "git stash"), "deny"],
  ["하위 폴더에서 허용 경로 쓰기", { ...write("security-reviewer", "/p/docs/security/t.md"), cwd: "/p/backend" }, "pass"],
  ["상대 경로로 허용 경로 쓰기", write("security-reviewer", "docs/handoff/auth/10-security-reviewer.md"), "pass"],
  ["Windows 경로로 허용 경로 쓰기", write("planning-spec", "C:\\p\\docs\\prd\\auth.md"), "pass"],
  ["하위 폴더에서 소유 밖 쓰기", { ...write("security-reviewer", "/p/backend/src/App.java"), cwd: "/p/backend" }, "deny"],
];
let failed = 0;
for (const [name, input, want] of cases) {
  const got = run(input);
  if (got === want) console.log(`ok - ${name}`); else { console.log(`FAIL: ${name}: ${got} (기대 ${want})`); failed++; }
}
const bad = execFileSync("node", [guard], { input: "not json" }).toString();
if (bad) { console.log("FAIL: 잘못된 입력에서 막음"); failed++; } else console.log("ok - 잘못된 입력은 통과 (세션을 깨지 않음)");
process.exit(failed ? 1 : 0);
EOF
