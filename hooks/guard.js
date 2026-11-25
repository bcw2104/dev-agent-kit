#!/usr/bin/env node
// Dev Agent Kit 가드 훅 (PreToolUse). sync.sh가 ~/.claude/settings.json에 등록한다.
// 키트 서브에이전트가 docs/rules의 금지 규칙을 어기는 도구 호출을 막는다. 메인 세션(PM)과 키트 밖 에이전트는 건드리지 않는다.
// - 모든 키트 에이전트: 브랜치·태그 생성, 전환·머지·rebase·reset, 현재 브랜치가 아닌 곳으로 푸시, force push·PR 생성 등 금지 (docs/rules/basics.md "Git")
// - 커밋하지 않는 역할(COMMIT_AGENTS 밖): 커밋·푸시도 금지. 구현 담당·리뷰어는 PM 지시로 커밋·푸시한다
// - 읽기 위주 역할: 소유 영역 밖 파일을 Edit/Write로 고치지 못한다 (docs/rules/ownership.md)
// shortcut: 쓰기 범위는 Edit/Write 도구만 검사한다. Bash 리다이렉트(>)로 쓰는 것은 못 막는다. 전체 소유권 표는 프로젝트마다 바뀌어 고정하지 않았다.
"use strict";

const fs = require("fs");
const path = require("path");

const KIT_AGENTS = new Set([
  "planning-researcher", "planning-spec", "be-api", "be-domain", "be-reviewer", "dba",
  "fe-feature", "fe-design-system", "fe-reviewer", "qa", "infra", "security-reviewer",
]);

// PM 지시로 커밋·푸시하는 역할. 그 밖의 키트 에이전트(security-reviewer, planning-*, qa)는 커밋·푸시하지 않는다
const COMMIT_AGENTS = new Set([
  "be-api", "be-domain", "dba", "fe-feature", "fe-design-system", "infra", "be-reviewer", "fe-reviewer",
]);

// 역할별로 Edit/Write를 허용하는 경로 (프로젝트 루트 기준). 여기 없는 에이전트는 쓰기 범위를 검사하지 않는다
const WRITE_SCOPE = {
  "security-reviewer": ["docs/security/", "docs/handoff/"],
  "planning-researcher": ["docs/research/", "docs/handoff/"],
  "planning-spec": ["docs/prd/", "docs/screens/", "docs/handoff/"],
};

// git 다음에 오는 전역 옵션(-C 경로, -c 키=값 등)을 건너뛰고 하위 명령을 본다. 따옴표·$( 안의 명령도 잡는다 (bash -c "git push")
const GIT = String.raw`(?:^|[\s;&|(\`"'])git(?:\s+-[Cc]\s+\S+|\s+--?[\w-]+(?:=\S+)?)*\s+`;
// 모든 키트 에이전트에게 금지: 브랜치·히스토리를 바꾸는 명령
const GIT_BRANCH = new RegExp(GIT + String.raw`(?:merge|rebase|switch|checkout|reset|cherry-pick|revert|am|pull|stash(?!\s+(?:list|show)\b))\b`);
// 모든 키트 에이전트에게 금지: 브랜치·태그 생성·삭제·이름 변경. 목록 조회(git branch, -a, --list, git tag -l)는 허용
const GIT_REF = new RegExp(GIT + String.raw`(?:branch|tag)\b(?![^;&|\n]*\s(?:-l|--list|--show-current)\b)(?=[^;&|\n]*\s(?:[^-\s;&|]|-[dDmMcCf]\b|--(?:delete|move|copy|force)\b))`);
// 모든 키트 에이전트에게 금지: 현재 브랜치가 아닌 곳으로 푸시 (src:dst refspec, :삭제, --all·--mirror·--tags·--delete)
// shortcut: scp 형식 원격 주소(git@host:repo)도 refspec으로 보고 막는다. 에이전트는 origin 이름으로 푸시하므로 그대로 둔다
const GIT_PUSH_OTHER = new RegExp(GIT + String.raw`push\b[^;&|\n]*?\s(?:[^\s:]*:[^\s/]\S*|--all|--mirror|--tags|--delete|-d)(?=\s|$)`);
// 커밋하지 않는 역할에게 금지
const GIT_COMMIT = new RegExp(GIT + String.raw`(?:commit|push)\b`);
// 모든 키트 에이전트에게 금지: force push (--force, --force-with-lease, -f, -uf 같은 묶음 옵션, +refspec)
const GIT_FORCE = new RegExp(GIT + String.raw`push\b[^;&|\n]*?\s(?:--force|-[a-zA-Z]*f|\+\S)`);
// PR 생성·머지도 저장소 상태를 바꾼다
const GH_WRITE = /(?:^|[\s;&|(`"'])gh\s+pr\s+(?:create|merge)\b/;

function decide(input) {
  const agent = input.agent_type;
  if (!agent || !KIT_AGENTS.has(agent)) return null;
  // 키트 규칙(docs/rules/basics.md)을 쓰지 않는 프로젝트는 건드리지 않는다. 그 프로젝트에도 qa·infra 같은 같은 이름의 담당이 있을 수 있다
  if (!usesKitRules(process.env.CLAUDE_PROJECT_DIR)) return null;
  const tool = input.tool_name;
  const ti = input.tool_input || {};

  if (tool === "Bash" || tool === "PowerShell") {
    const cmd = ti.command || "";
    if (GIT_BRANCH.test(cmd) || GIT_REF.test(cmd) || GIT_PUSH_OTHER.test(cmd) || GH_WRITE.test(cmd)) {
      return `${agent}는 브랜치·태그 생성·전환, 머지, rebase, reset, cherry-pick, revert, stash, pull, 현재 브랜치가 아닌 곳으로 푸시, PR 생성·머지를 하지 않는다. 브랜치는 PM이 관리하고, 담당은 PM이 만들어 둔 현재 브랜치에만 커밋·푸시한다 (docs/rules/basics.md "Git"). 필요하면 리포트의 "요청 사항"에 적는다.`;
    }
    if (GIT_FORCE.test(cmd)) {
      return `${agent}는 force push(--force, -f, --force-with-lease, +refspec)를 하지 않는다 (docs/rules/basics.md "Git"). 푸시가 거부되면 멈추고 리포트의 "요청 사항"에 적는다.`;
    }
    if (!COMMIT_AGENTS.has(agent) && GIT_COMMIT.test(cmd)) {
      return `${agent}는 리포트·문서만 쓰는 역할이라 커밋·푸시하지 않는다 (docs/rules/basics.md "Git"). 커밋은 PM이 지시할 때 그 변경을 만든 담당이 한다. 필요하면 리포트의 "요청 사항"에 적는다.`;
    }
  }

  const scope = WRITE_SCOPE[agent];
  const file = ti.file_path || ti.notebook_path;
  if (scope && file && /^(Edit|Write|MultiEdit|NotebookEdit)$/.test(tool)) {
    const rel = toRel(file, input.cwd || process.cwd());
    // 하위 폴더에서 작업 중이어도 맞게: 경로 어딘가에 허용 폴더가 있으면 통과 (예: cwd=backend/, 파일=../docs/security/x)
    const norm = "/" + file.replace(/\\/g, "/").replace(/^\.\//, "");
    if (!scope.some((p) => norm.includes("/" + p))) {
      return `${agent}는 ${scope.join(", ")} 밖의 파일을 고치지 않는다 (docs/rules/ownership.md). ${rel} 변경이 필요하면 리포트의 "요청 사항"으로 담당에게 넘긴다.`;
    }
  }
  return null;
}

// 프로젝트 경로를 모르면(환경변수 없음) 키트 프로젝트로 보고 막는다
function usesKitRules(projectDir) {
  if (!projectDir || !fs.existsSync(projectDir)) return true;
  return fs.existsSync(path.join(projectDir, "docs", "rules", "basics.md"));
}

function toRel(file, cwd) {
  const norm = (p) => p.replace(/\\/g, "/");
  const f = norm(file), c = norm(cwd).replace(/\/$/, "");
  return f.startsWith(c + "/") ? f.slice(c.length + 1) : f.replace(/^\.\//, "");
}

module.exports = { decide };

if (require.main === module) {
  let raw = "";
  process.stdin.on("data", (d) => (raw += d));
  process.stdin.on("end", () => {
    let input;
    try { input = JSON.parse(raw); } catch { process.exit(0); } // 입력을 못 읽으면 막지 않는다 (세션을 깨지 않게)
    const reason = decide(input);
    if (reason) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason },
      }));
    }
    process.exit(0);
  });
}
