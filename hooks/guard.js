#!/usr/bin/env node
// Dev Agent Kit 가드 훅 (PreToolUse). sync.sh가 ~/.claude/settings.json에 등록한다.
// 키트 서브에이전트가 docs/rules의 금지 규칙을 어기는 도구 호출을 막는다. 메인 세션(PM)과 키트 밖 에이전트는 건드리지 않는다.
// - 모든 키트 에이전트: 커밋·푸시·브랜치 전환·머지 등 git 상태를 바꾸는 명령 금지 (docs/rules/basics.md)
// - 읽기 위주 역할: 소유 영역 밖 파일을 Edit/Write로 고치지 못한다 (docs/rules/ownership.md)
// shortcut: 쓰기 범위는 Edit/Write 도구만 검사한다. Bash 리다이렉트(>)로 쓰는 것은 못 막는다. 전체 소유권 표는 프로젝트마다 바뀌어 고정하지 않았다.
"use strict";

const KIT_AGENTS = new Set([
  "planning-researcher", "planning-spec", "be-api", "be-domain", "be-reviewer", "dba",
  "fe-feature", "fe-design-system", "fe-reviewer", "qa", "infra", "security-reviewer",
]);

// 역할별로 Edit/Write를 허용하는 경로 (프로젝트 루트 기준). 여기 없는 에이전트는 쓰기 범위를 검사하지 않는다
const WRITE_SCOPE = {
  "security-reviewer": ["docs/security/", "docs/handoff/"],
  "planning-researcher": ["docs/research/", "docs/handoff/"],
  "planning-spec": ["docs/prd/", "docs/screens/", "docs/handoff/"],
};

// git 다음에 오는 전역 옵션(-C 경로, -c 키=값 등)을 건너뛰고 하위 명령을 본다. 따옴표·$( 안의 명령도 잡는다 (bash -c "git push")
const GIT_WRITE = /(?:^|[\s;&|(`"'])git(?:\s+-[Cc]\s+\S+|\s+--?[\w-]+(?:=\S+)?)*\s+(?:commit|push|merge|rebase|switch|checkout|reset|cherry-pick|revert|am|pull|stash(?!\s+(?:list|show)\b))\b/;
// PR 생성·머지도 저장소 상태를 바꾼다
const GH_WRITE = /(?:^|[\s;&|(`"'])gh\s+pr\s+(?:create|merge)\b/;

function decide(input) {
  const agent = input.agent_type;
  if (!agent || !KIT_AGENTS.has(agent)) return null;
  const tool = input.tool_name;
  const ti = input.tool_input || {};

  if ((tool === "Bash" || tool === "PowerShell") && (GIT_WRITE.test(ti.command || "") || GH_WRITE.test(ti.command || ""))) {
    return `${agent}는 git 상태를 바꾸는 명령(커밋·푸시·브랜치·머지·PR 생성 등)을 실행하지 않는다. 커밋은 PM이 한다 (docs/rules/basics.md). 필요하면 리포트의 "요청 사항"에 적는다.`;
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
