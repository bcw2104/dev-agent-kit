#!/usr/bin/env bash
# 하네스 정합성 검사: 에이전트·스킬·문서가 서로 가리키는 이름과 절이 실제로 있는지 본다.
# 사용법: bash tests/harness_test.sh   (node 필요. 파일을 고치지 않는다)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$ROOT" <<'EOF'
const fs = require("fs"), path = require("path");
const root = process.argv[2];
const read = (p) => fs.readFileSync(path.join(root, p), "utf8");
const ls = (d) => fs.readdirSync(path.join(root, d));
const walk = (d) => ls(d).flatMap((f) => {
  const p = path.join(d, f);
  return fs.statSync(path.join(root, p)).isDirectory() ? walk(p) : p.endsWith(".md") ? [p] : [];
});
const errors = [];
const fail = (msg) => errors.push(msg);

const docs = [...walk("global"), ...walk("project-template"), "SETUP.md", "README.md"];
const skills = ls("global/skills").filter((d) => fs.existsSync(path.join(root, "global/skills", d, "SKILL.md")));
const agents = ls("global/agents").filter((f) => f.endsWith(".md"));

// 1. 에이전트 frontmatter: 이름이 파일명과 같고, 필수 키가 있고, skills가 실제 스킬이다
for (const f of agents) {
  const m = read(`global/agents/${f}`).match(/^---\n([\s\S]*?)\n---/);
  if (!m) { fail(`${f}: frontmatter 없음`); continue; }
  const fm = Object.fromEntries(m[1].split("\n").map((l) => l.split(/:\s(.*)/s).slice(0, 2)));
  if (fm.name !== f.replace(/\.md$/, "")) fail(`${f}: name(${fm.name})이 파일 이름과 다름`);
  for (const k of ["description", "tools", "model"]) if (!fm[k]) fail(`${f}: ${k} 없음`);
  for (const s of (fm.skills || "").split(",").map((x) => x.trim()).filter(Boolean))
    if (!skills.includes(s)) fail(`${f}: skills의 ${s}가 global/skills에 없음`);
}

// 1-1. 키트 에이전트는 CLAUDE.md를 받지 않는다(omitClaudeMd). 대신 "먼저 읽을 규칙"의 docs/rules 파일이 템플릿에 있어야 하고,
//      본문이 CLAUDE.md를 근거로 삼으면 안 된다 (받지 않는 파일이라 그 규칙을 모른다)
const readLists = {};
for (const f of agents) {
  const t = read(`global/agents/${f}`);
  if (!/^omitClaudeMd: true$/m.test(t.split(/\n---/)[0])) fail(`${f}: frontmatter에 omitClaudeMd: true 없음`);
  const sec = (t.match(/## 먼저 읽을 규칙\n([^\n]*)/) || [, ""])[1];
  const list = [...sec.matchAll(/`(docs\/rules\/[a-z0-9-]+\.md)`/g)].map((m) => m[1]);
  if (!list.includes("docs/rules/basics.md")) fail(`${f}: "먼저 읽을 규칙"에 docs/rules/basics.md 없음`);
  for (const p of list) if (!fs.existsSync(path.join(root, "project-template", p))) fail(`${f}: ${p}가 템플릿에 없음`);
  readLists[f.replace(/\.md$/, "")] = list;
  const body = t.replace(/이 에이전트는 CLAUDE\.md를 받지 않는다/g, "");
  for (const [m] of body.matchAll(/CLAUDE\.md[^\n]{0,20}/g)) fail(`${f}: 받지 않는 CLAUDE.md를 참조함: ${m}`);
}
// 1-1b. 가드 훅이 에이전트에게 보내는 메시지도 CLAUDE.md를 근거로 삼지 않는다
for (const [m] of read("hooks/guard.js").matchAll(/CLAUDE\.md[^\n]{0,20}/g)) fail(`hooks/guard.js: 에이전트가 받지 않는 CLAUDE.md를 가리킴: ${m}`);
// 1-2. CLAUDE.md의 @ 불러오기 대상이 있다 (PM은 이것으로 docs/rules를 모두 받는다)
const claudeMd = read("project-template/CLAUDE.md");
for (const [, p] of claudeMd.matchAll(/^@(\S+)$/gm)) if (!fs.existsSync(path.join(root, "project-template", p))) fail(`CLAUDE.md: @${p} 파일이 없음`);
for (const p of ls("project-template/docs/rules")) if (!claudeMd.includes(`@docs/rules/${p}`)) fail(`CLAUDE.md가 docs/rules/${p}를 불러오지 않음 (PM이 모름)`);

// 2. sync.sh의 KIT_SKILLS와 global/skills가 같다 (빠지면 그 스킬은 동기화되지 않는다)
const kit = (read("sync.sh").match(/^KIT_SKILLS="([^"]*)"/m) || [, ""])[1].split(/\s+/).filter(Boolean);
for (const s of skills) if (!kit.includes(s)) fail(`sync.sh KIT_SKILLS에 ${s} 없음`);
for (const s of kit) if (!skills.includes(s)) fail(`sync.sh KIT_SKILLS의 ${s}가 global/skills에 없음`);

// 2-1. 가드 훅의 키트 에이전트 목록이 global/agents와 같다 (빠지면 그 에이전트는 가드를 받지 않는다)
const guardSrc = read("hooks/guard.js");
const guarded = [...((guardSrc.match(/KIT_AGENTS = new Set\(\[([\s\S]*?)\]\)/) || [, ""])[1]).matchAll(/"([a-z0-9-]+)"/g)].map((m) => m[1]);
const names = agents.map((f) => f.replace(/\.md$/, ""));
for (const a of names) if (!guarded.includes(a)) fail(`hooks/guard.js KIT_AGENTS에 ${a} 없음`);
for (const a of guarded) if (!names.includes(a)) fail(`hooks/guard.js KIT_AGENTS의 ${a}가 global/agents에 없음`);

// 3. 공개 저장소에는 외부 플러그인 스킬(plugin:skill) 이름을 두지 않는다. 그런 지시는 local/overlay(git 제외)에 둔다
for (const f of docs) for (const [, s] of read(f).matchAll(/`([a-z0-9-]+:[a-z0-9-]+)`/g))
  if (!["dev:mock", "update:xxx"].includes(s)) fail(`${f}: 외부 플러그인 스킬 ${s}가 저장소에 있음 (local/overlay로 옮긴다)`);
// 3-1. local/overlay가 있으면 덧붙일 대상 파일이 저장소에 있어야 한다 (없으면 조용히 무시돼 지시가 사라진다)
const ovRoot = path.join(root, "local/overlay");
const walkAbs = (d) => fs.readdirSync(d).flatMap((f) => { const p = path.join(d, f); return fs.statSync(p).isDirectory() ? walkAbs(p) : [p]; });
if (fs.existsSync(ovRoot)) for (const p of walkAbs(ovRoot)) {
  const rel = path.relative(ovRoot, p);
  if (!fs.existsSync(path.join(root, rel))) fail(`local/overlay/${rel}: 덧붙일 대상 ${rel}이 저장소에 없음`);
}

// 4. "{스택}-conventions N장/N-N" 참조가 그 스킬의 절 번호로 있다
const heads = {};
for (const s of skills) heads[s] = new Set([...read(`global/skills/${s}/SKILL.md`).matchAll(/^#+\s*(\d+(?:-\d+)?)[.\s]/gm)].map((m) => m[1]));
for (const f of docs) for (const [, s, n] of read(f).matchAll(/([a-z]+-conventions)[^\n]{0,4}?"?\s?(\d+(?:-\d+)?)(?:장|[ .의)\]"])/g))
  if (heads[s] && !heads[s].has(n)) fail(`${f}: ${s} ${n}장이 없음`);

// 5. CLAUDE.md의 "N장"과 따옴표로 가리킨 절 제목이 있다
const claude = read("project-template/CLAUDE.md");
const chapters = new Set([...claude.matchAll(/^## (\d+)\./gm)].map((m) => m[1]));
for (const f of docs) {
  const t = read(f);
  for (const [, n] of t.matchAll(/CLAUDE\.md[^\n]{0,3}?(\d+)장/g)) if (!chapters.has(n)) fail(`${f}: CLAUDE.md ${n}장이 없음`);
  for (const [, q] of t.matchAll(/CLAUDE\.md[^"\n]{0,12}"([^"]+)"/g)) if (!claude.includes(q.replace(/^\d+\. /, ""))) fail(`${f}: CLAUDE.md "${q}" 절이 없음`);
}

// 6. 문서가 가리키는 docs/templates/ 파일이 있다
for (const f of docs) for (const [, p] of read(f).matchAll(/`?(docs\/templates\/[a-z0-9-]+\.md)`?/g))
  if (!fs.existsSync(path.join(root, "project-template", p))) fail(`${f}: ${p} 없음`);

// 7. SETUP.md "N. 제목" 참조가 SETUP.md 절로 있다
const setup = read("SETUP.md");
const setupHeads = new Set([...setup.matchAll(/^## (.+)$/gm)].map((m) => m[1].trim()));
for (const f of docs) for (const [, q] of read(f).matchAll(/SETUP\.md[^"\n]{0,6}"(\d+\. [^"]+)"/g))
  if (![...setupHeads].some((h) => h.startsWith(q))) fail(`${f}: SETUP.md "${q}" 절이 없음`);

// 7-1. 템플릿 .claude/office.json(agent-office 부서 배치): 키트 에이전트가 정확히 한 부서에 있고, docs가 가리키는 파일#제목이 있다
try {
  const office = JSON.parse(read("project-template/.claude/office.json"));
  const seated = (office.teams || []).flatMap((t) => t.agents || []);
  for (const a of names) if (seated.filter((x) => x === a).length !== 1) fail(`office.json: ${a}가 부서 ${seated.filter((x) => x === a).length}곳에 있음 (1곳이어야 함)`);
  for (const a of seated) if (!names.includes(a)) fail(`office.json: 부서의 ${a}가 global/agents에 없음`);
  for (const [key, refs] of Object.entries(office.docs || {})) {
    if (key.startsWith("agent:") && !names.includes(key.slice(6))) fail(`office.json: docs의 ${key} 에이전트가 없음`);
    // 패널에 보이는 규칙은 그 에이전트가 실제로 읽는 규칙이어야 한다
    if (key.startsWith("agent:") && readLists[key.slice(6)])
      for (const ref of refs) if (ref.startsWith("docs/rules/") && !readLists[key.slice(6)].includes(ref)) fail(`office.json: ${key}가 읽지 않는 ${ref}를 보여 줌`);
    for (const ref of refs) {
      const [rel, heading] = ref.split("#");
      const p = path.join(root, "project-template", rel);
      if (!fs.existsSync(p) || !fs.statSync(p).isFile()) { fail(`office.json: ${ref} 파일이 템플릿에 없음`); continue; }
      if (heading && !fs.readFileSync(p, "utf8").split("\n").some((l) => /^#{1,6}\s/.test(l) && l.replace(/^#+\s*/, "").trim() === heading.trim()))
        fail(`office.json: ${ref} 제목이 없음 (agent-office는 제목이 정확히 같아야 그 절을 보여 준다)`);
    }
  }
} catch (e) { fail(`office.json: ${e.message}`); }

// 8. permissions.json은 올바른 JSON이고, 같은 규칙이 ask와 allow에 함께 있지 않다
try {
  const p = JSON.parse(read("global/settings/permissions.json"));
  for (const r of p.ask || []) if ((p.allow || []).includes(r)) fail(`permissions.json: ${r}가 ask와 allow에 모두 있음`);
} catch (e) { fail(`permissions.json: ${e.message}`); }

if (errors.length) { console.log(errors.map((e) => "FAIL: " + e).join("\n")); process.exit(1); }
console.log(`ok - 에이전트 ${agents.length}개, 스킬 ${skills.length}개, 문서 ${docs.length}개 정합성 확인`);
EOF
