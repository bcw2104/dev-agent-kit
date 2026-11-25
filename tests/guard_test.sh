#!/usr/bin/env bash
# hooks/guard.js 검사: 키트 서브에이전트의 금지 동작은 막고, 메인 세션·허용된 동작은 통과시키는지 본다.
# 사용법: bash tests/guard_test.sh   (node 필요)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$ROOT/hooks/guard.js" <<'EOF'
const { execFileSync } = require("child_process");
const guard = process.argv[2];
const run = (input, projectDir = "") => {
  const env = { ...process.env, CLAUDE_PROJECT_DIR: projectDir };
  const out = execFileSync("node", [guard], { input: JSON.stringify(input), env }).toString();
  return out ? JSON.parse(out).hookSpecificOutput.permissionDecision : "pass";
};
const bash = (agent, command) => ({ agent_type: agent, tool_name: "Bash", tool_input: { command }, cwd: "/p" });
const write = (agent, file_path) => ({ agent_type: agent, tool_name: "Write", tool_input: { file_path }, cwd: "/p" });
const cases = [
  ["구현 담당 git commit", bash("be-api", "git add backend/src && git commit -m x"), "pass"],
  ["구현 담당 git -C 경로 push", bash("infra", "git -C /p push origin main"), "pass"],
  ["리뷰어 테스트 커밋", bash("be-reviewer", "git commit -m test"), "pass"],
  ["qa git commit", bash("qa", "git commit -m x"), "deny"],
  ["security-reviewer git push", bash("security-reviewer", "git push"), "deny"],
  ["planning-spec git -C 경로 commit", bash("planning-spec", "git -C /p commit -m x"), "deny"],
  ["구현 담당 git push --force", bash("be-api", "git push --force"), "deny"],
  ["구현 담당 git push -f", bash("fe-feature", "git push origin main -f"), "deny"],
  ["구현 담당 git push -uf 묶음 옵션", bash("dba", "git push -uf origin main"), "deny"],
  ["구현 담당 --force-with-lease", bash("infra", "git -C /p push --force-with-lease"), "deny"],
  ["구현 담당 +refspec push", bash("be-domain", "git push origin +main"), "deny"],
  ["구현 담당 일반 push 옵션", bash("be-api", "git push -u origin feat/x --follow-tags"), "pass"],
  ["구현 담당 git merge", bash("be-api", "git merge main"), "deny"],
  ["구현 담당 git rebase", bash("fe-feature", "git rebase main"), "deny"],
  ["구현 담당 git reset", bash("dba", "git reset --hard HEAD~1"), "deny"],
  ["구현 담당 gh pr create", bash("be-api", "gh pr create --fill"), "deny"],
  ["서브에이전트 브랜치 전환", bash("fe-feature", "git switch -c feat"), "deny"],
  ["구현 담당 브랜치 생성", bash("be-api", "git branch feat-x"), "deny"],
  ["구현 담당 브랜치 삭제", bash("be-api", "git branch -D feat-x"), "deny"],
  ["구현 담당 태그 생성", bash("infra", "git tag v1.0"), "deny"],
  ["구현 담당 다른 브랜치로 push", bash("be-api", "git push origin HEAD:main"), "deny"],
  ["구현 담당 원격 브랜치 삭제", bash("be-api", "git push origin :feat-x"), "deny"],
  ["구현 담당 push --tags", bash("infra", "git push --tags"), "deny"],
  ["브랜치 목록 조회", bash("be-reviewer", "git branch -a | grep feat"), "pass"],
  ["현재 브랜치 조회", bash("be-api", "git branch --show-current"), "pass"],
  ["태그 목록 조회", bash("infra", "git tag -l 'v*'"), "pass"],
  ["https 원격으로 push", bash("be-api", "git push https://github.com/o/r.git"), "pass"],
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
  ["따옴표 안의 git push (커밋하지 않는 역할)", bash("qa", 'bash -c "git push"'), "deny"],
  ["$( ) 안의 git commit (커밋하지 않는 역할)", bash("security-reviewer", "x=$(git commit -m y)"), "deny"],
  ["따옴표 안의 force push", bash("be-api", 'bash -c "git push -f"'), "deny"],
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
// 프로젝트 폴더 판단: docs/rules/basics.md가 없는 프로젝트는 건드리지 않고, 있으면 키트 규칙대로 막는다
const fs = require("fs"), os = require("os"), path = require("path");
const plain = fs.mkdtempSync(path.join(os.tmpdir(), "guard-plain-"));
const kit = fs.mkdtempSync(path.join(os.tmpdir(), "guard-kit-"));
fs.mkdirSync(path.join(kit, "docs", "rules"), { recursive: true });
fs.writeFileSync(path.join(kit, "docs", "rules", "basics.md"), "x");
process.on("exit", () => { fs.rmSync(plain, { recursive: true, force: true }); fs.rmSync(kit, { recursive: true, force: true }); });
cases.push(
  ["키트 아닌 프로젝트의 infra push", bash("infra", "git push --force"), "pass", plain],
  ["키트 아닌 프로젝트의 qa commit", bash("qa", "git commit -m x"), "pass", plain],
  ["키트 프로젝트의 qa commit", bash("qa", "git commit -m x"), "deny", kit],
  ["키트 프로젝트의 be-api commit", bash("be-api", "git commit -m x"), "pass", kit],
  ["키트 프로젝트의 be-api switch", bash("be-api", "git switch -c x"), "deny", kit],
);
let failed = 0;
for (const [name, input, want, projectDir] of cases) {
  const got = run(input, projectDir);
  if (got === want) console.log(`ok - ${name}`); else { console.log(`FAIL: ${name}: ${got} (기대 ${want})`); failed++; }
}
const bad = execFileSync("node", [guard], { input: "not json" }).toString();
if (bad) { console.log("FAIL: 잘못된 입력에서 막음"); failed++; } else console.log("ok - 잘못된 입력은 통과 (세션을 깨지 않음)");
process.exit(failed ? 1 : 0);
EOF
