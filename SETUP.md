# Dev Agent Kit 세팅 가이드

> **Claude Code 세션용 문서.** 사용자가 "SETUP.md 읽고 세팅해줘"라고 요청하면 아래 단계를 순서대로 수행하고, 단계마다 결과를 짧게 보고한다. 실패한 단계는 건너뛰지 말고 원인과 사용자가 할 일을 알린다.

## 키트 구성

```
dev-agent-kit/
├── SETUP.md                 # 이 문서
├── README.md                # 사람용 요약
├── .gitattributes           # .sh 파일을 LF로 유지 (Windows 클론 대비)
├── install.sh               # 처음 설치: sync.sh 실행 + 자동 동기화 훅 등록
├── hooks/guard.js           # 가드 훅: 키트 에이전트의 git 쓰기·소유 영역 밖 수정 차단 (sync.sh가 등록)
├── sync.sh                  # ~/.claude ↔ 저장소 양방향 동기화 (세션 시작·종료 때 자동 실행)
├── init-project.sh          # 프로젝트에 CLAUDE.md와 docs/ 적용
├── local/                   # (git 제외) 이 PC에만 쓰는 설정: 외부 플러그인 지시(overlay/), 권한·env(permissions.json)
├── tests/                   # sync_test.sh(동기화), harness_test.sh(참조 정합성), guard_test.sh(가드 훅)
├── global/                  # 사용자 범위(~/.claude)에 설치되는 것
│   ├── agents/              # 에이전트 12개
│   ├── skills/              # spring-conventions, frontend-conventions, python-conventions
│   └── settings/            # 권한 규칙 permissions.json (ask: 확인 창, allow: 확인 없이 실행, remove: 지울 규칙)
└── project-template/        # 프로젝트마다 복사되는 것
    ├── CLAUDE.md            # PM용 운영 규칙. docs/rules/를 @로 불러온다 (키트 에이전트는 CLAUDE.md를 받지 않고 필요한 docs/rules 파일만 읽는다)
    ├── .claude/office.json  # agent-office 부서 배치 (기획·백엔드·DBA·프론트엔드·QA·인프라·보안)
    └── docs/                # research, prd, screens, api, db, adr, handoff(에이전트 리포트), rules(에이전트가 읽는 규칙: basics, ownership, handoff, stack, review, frontend, qa), templates
```

설치 범위 원칙:
- **에이전트와 컨벤션 스킬** → 사용자 범위. 이 PC의 모든 프로젝트에서 같은 조직을 쓴다.
- **CLAUDE.md와 docs/** → 프로젝트 범위. 기술 스택과 명령어가 프로젝트마다 다르기 때문이다.

## 0. 사전 확인

다음을 실행해 버전을 확인한다.
```bash
claude --version
node -v      # 18 이상 (install.sh가 settings.json 병합에 사용)
git --version
```
없는 도구가 있으면 설치 방법(macOS는 Homebrew, Windows는 winget 기준)을 안내하고 사용자가 설치할 때까지 기다린다.

**Windows라면 아래 "Windows에서 세팅하기"를 먼저 확인한다.** 이후 모든 셸 명령은 Git Bash에서 실행한다.

## 1. 에이전트와 스킬 설치

키트 폴더에서 실행한다.
```bash
chmod +x install.sh init-project.sh
./install.sh
```
- 에이전트는 `~/.claude/agents/`, 스킬은 `~/.claude/skills/`에 복사된다.
- 이 PC에 이미 있던 파일 중 저장소와 내용이 다른 것은 `~/.claude/backup-dev-company-{시각}/`에 백업한 뒤 저장소 내용으로 바꾼다. 저장소에 없는 이 PC만의 에이전트·스킬은 저장소에 올라가 다른 PC에도 퍼진다.
- `global/settings/permissions.json`의 규칙이 `~/.claude/settings.json`의 `permissions`에 병합된다 (사용자가 직접 넣은 규칙은 유지, 바뀌면 병합 전 백업).
  - `ask` (실행 직전 확인 창): `terraform apply`·`destroy` 같은 IaC 적용 명령, 배포를 일으키는 `gh workflow run`·`gh run rerun`·`docker push` 등. ask 규칙은 auto 모드에서도 적용된다
  - `allow` (확인 없이 실행): `git add`, `git commit`, `git push`. push만으로는 배포가 일어나지 않도록 CD를 수동 실행으로만 만드는 규칙(infra)이 있어서 push는 확인하지 않는다
  - `remove`: 예전 키트가 넣었지만 이제 빼는 규칙. 동기화 때 ask·allow·deny에서 지운다 (예: 예전의 `git push` 확인 규칙)
- `~/.claude/settings.json`의 `hooks.PreToolUse`에 가드 훅(`hooks/guard.js`)이 등록된다. 키트 서브에이전트가 커밋·푸시·브랜치 전환 등 git 쓰기 명령을 실행하거나, 읽기 위주 역할(security-reviewer, planning-researcher, planning-spec)이 소유 영역 밖 파일을 Edit/Write로 고치면 막는다. 메인 세션(PM)과 키트 밖 에이전트에는 적용되지 않는다. Bash로 파일을 쓰는 것은 막지 못하는 보조 장치다.
- `~/.claude/settings.json`의 `hooks`에 자동 동기화 훅이 등록된다 (아래 "PC 간 동기화"). 원하지 않으면 `./install.sh --no-hooks`.
- 키트 폴더는 **자기 GitHub 저장소**를 `git clone`한 폴더여야 하고, 이 PC에서 그 저장소로 push할 수 있어야 한다 (SSH 키 등록). 공개된 키트를 쓰려면 먼저 포크(fork)한 뒤 그 포크를 clone한다.
- 외부 플러그인·스킬은 키트에 들어 있지 않다. 쓰고 싶으면 각자 설치하고, 에이전트에 덧붙일 지시는 키트 폴더의 `local/`(git에 올라가지 않음)에 둔다 (아래 "로컬 전용 설정").

## 2. 설치 확인

- `ls ~/.claude/agents ~/.claude/skills`로 파일 12개와 스킬 3개를 확인한다.
- `~/.claude/settings.json`의 `permissions.ask`에 `Bash(terraform apply *)`, `Bash(docker push *)`와 같은 내용의 `PowerShell(...)` 규칙이, `permissions.allow`에 `Bash(git commit *)`, `Bash(git push *)`가 들어갔는지 확인한다.
- `~/.claude/settings.json`의 `hooks.SessionStart`, `hooks.SessionEnd`에 `dev-company-kit sync` 명령이, `hooks.PreToolUse`에 `dev-company-kit guard` 명령이 하나씩 있는지 확인한다.
- `./sync.sh`를 한 번 실행해 `커밋 0, 받음 0, 삭제 0`처럼 오류 없이 끝나는지 확인한다.
- 사용자에게 Claude Code를 재시작한 뒤 `/agents`에서 에이전트 12개가 보이는지 확인을 요청한다.

## 3. 프로젝트에 적용

새 프로젝트(또는 기존 프로젝트)마다 실행한다.
```bash
./init-project.sh <프로젝트 경로>
```
- `CLAUDE.md`, `.claude/office.json`, `docs/` 폴더가 생긴다. `office.json`은 agent-office 뷰어가 에이전트를 부서별 방에 앉히고 각자 관련 규칙을 보여 주는 설정이다 (뷰어를 안 써도 해롭지 않다). 기존 `office.json`은 덮어쓰지 않는다. 기존 `CLAUDE.md`가 있으면 덮어쓰지 않고 `CLAUDE.dev-company.md`로 저장되므로 두 파일을 병합한다.
- 그 다음 그 프로젝트에서 Claude Code를 열고 **"0단계(초기 세팅)부터 시작해"**라고 요청한다. PM(메인 세션)이 `CLAUDE.md`의 **8. 기술 스택과 프로젝트 결정**을 기본값으로 채워 확인을 받고, 골격·테스트 기반·E2E 환경을 만든 뒤 **9. 명령어**를 실제 명령으로 고친다.
- 기존 프로젝트에 적용하면 8장의 확정값을 실제 구성에 맞게 채우고, 저장소 구조가 다르면 3장 소유권 표의 경로도 맞춘다.
- 프로젝트에만 필요한 에이전트는 그 프로젝트의 `.claude/agents/`에 둔다 (CLAUDE.md 1장 "프로젝트 전용 에이전트", 템플릿은 `docs/templates/agent.md`). 공통 에이전트와 같은 이름이면 그 프로젝트에서는 프로젝트 쪽이 우선한다.
- 프론트가 있는 프로젝트라면 Baseline 목표(기본 Widely available)가 맞는지 사용자에게 확인한다.
- 통합 테스트(Testcontainers)와 E2E에는 Docker가 필요하다 (macOS는 Docker Desktop 또는 OrbStack, Windows는 Docker Desktop).

### 프로젝트에서 안 쓰는 플러그인 끄기 (토큰 절감)
켜진 플러그인은 쓰지 않아도 스킬 목록·에이전트 목록·MCP 도구 이름이 매 세션 컨텍스트에 들어간다. 그 프로젝트에서 안 쓰는 플러그인은 **프로젝트의 `.claude/settings.json`**에서 끈다. 데스크톱 앱 설정이나 `/plugin`에서 끄면 다른 프로젝트에서도 꺼진다.

```json
{
  "enabledPlugins": {
    "<플러그인>@<마켓플레이스>": false,
    "<계정 동기화 플러그인>@synced": false
  }
}
```
- 키 이름은 `claude plugin list --json`의 `id`를 그대로 쓴다. claude.ai 계정에서 동기화된 플러그인은 `<이름>@synced`다.
- 우선순위는 `settings.local.json` > 프로젝트 `settings.json` > 사용자 설정이라, 여기서 `false`로 두면 그 프로젝트에서만 꺼진다. 새 세션부터 적용된다.
- 보안 훅처럼 모든 프로젝트에 필요한 플러그인은 끄지 않는다.
- 꺼 둔 플러그인이 필요해지면 그 키를 `true`로 바꾸거나 지워서 다시 켜고 **새 세션**에서 쓴다. 한 번 쓰고 말 일이면 끝난 뒤 다시 `false`로 돌린다.

## Windows에서 세팅하기

Windows 네이티브(Git Bash)에서 세팅한다. WSL 안에서 설치하면 WSL의 `~/.claude`에 들어가 Windows용 Claude Code에서 보이지 않으므로 쓰지 않는다.

1. 사전 도구 설치 (PowerShell 또는 터미널에서 사용자가 실행)
   ```powershell
   winget install Git.Git OpenJS.NodeJS.LTS
   ```
   설치 후 터미널을 다시 연다. Claude Code는 Git Bash가 있어야 Bash 도구를 쓴다.
2. 키트 받기: Git으로 받으면 `.gitattributes`가 `.sh` 파일을 LF로 유지한다. zip 등으로 복사해서 `$'\r': command not found` 오류가 나면 Git Bash에서 줄바꿈을 고친다.
   ```bash
   sed -i 's/\r$//' install.sh init-project.sh
   ```
3. 1단계부터 **Git Bash에서** 그대로 진행한다. `~`는 `C:\Users\<이름>`이고 설치 위치는 `C:\Users\<이름>\.claude`다. `chmod`는 Windows에서 효과가 없지만 오류도 나지 않는다.
4. 비용 확인 규칙 점검: Windows용 Claude Code는 Git Bash와 함께 PowerShell 도구도 쓸 수 있어서(claude.ai 계정은 기본 활성화), 키트는 `Bash(...)` 규칙마다 같은 `PowerShell(...)` 규칙을 함께 넣는다. 설치 후 Claude Code에서 `docker push dev-agent-kit/ask-test` 실행을 요청해 **확인 창이 뜨는지** 본다. 확인 창에서는 거부한다. Bash와 PowerShell 양쪽에서 확인하려면 각각 "Bash로", "PowerShell로" 실행을 요청한다.
5. 자동 동기화 훅 점검: 훅 명령은 `bash "<키트 경로>/sync.sh" --hook` 형식이다. Claude Code를 재시작한 뒤 `~/.claude/agents`의 파일 하나에 빈 줄을 추가하고 세션을 닫았다 열어서 저장소에 `sync:` 커밋이 생기는지 본다. 생기지 않으면 Git Bash의 `bash`가 PATH에 있는지 확인한다.
6. `node`가 Git Bash에서 안 잡히면(`command not found`) 터미널을 다시 열거나 Node 설치 경로를 PATH에 추가한 뒤 `./install.sh`를 다시 실행한다.

## 4. PC 간 동기화

GitHub 저장소가 기준이다. install.sh가 등록한 훅이 `sync.sh`를 자동으로 실행한다.

| 시점 | 하는 일 |
|---|---|
| 세션 시작 (`SessionStart`, startup) | 이 PC의 변경을 로컬에 commit → 저장소에서 pull → `~/.claude`에 반영 |
| 세션 종료 (`SessionEnd`) | 세션 중에 고친 에이전트·스킬을 로컬에 commit |
| 직접 실행 `./sync.sh --push` | push 대기 커밋을 확인한 뒤 원격에 올린다 |

- **push는 확인한 뒤에만 한다.** 저장소가 공개일 수 있어서, 훅은 로컬에 커밋만 하고 `push 대기 커밋 N개`를 알린다. 키트 폴더에서 `git log -p @{u}..HEAD`로 올라갈 내용을 보고(`~/.claude/agents`의 모든 파일이 대상이다) `./sync.sh --push`로 올린다. 다른 PC는 push된 뒤의 다음 세션에 받는다.
- 자동 동기화 커밋은 `dev-company-sync` 이름으로 남고 PC의 git 이메일을 쓰지 않는다. 키트 폴더에서 직접 커밋할 때는 각자 git 설정의 이메일이 공개된다.
- 비공개 저장소라 확인 없이 자동으로 올리려면 셸 설정(`~/.zshrc` 등)에 `export DEV_COMPANY_SYNC_AUTOPUSH=1`을 둔다.

- **어디서 고쳐도 된다.** `~/.claude/agents`, `~/.claude/skills`를 직접 고치거나(`/agents` 포함) 키트의 `global/`을 고쳐도 다음 동기화 때 저장소로 올라간다. 추가와 삭제도 전달된다.
- 에이전트·스킬·문서를 고친 뒤에는 `bash tests/harness_test.sh`(가드 훅을 고쳤으면 `bash tests/guard_test.sh`도)로 이름·절 참조가 깨지지 않았는지 확인한다.
- 동기화 대상은 `~/.claude/agents`, `~/.claude/skills`, 권한 규칙(`permissions.json`)이다. `SETUP.md`, 스크립트, `project-template/`은 자동 커밋하지 않으니 고친 뒤 직접 commit·push한다 (pull은 자동).
- 훅은 변경이 있거나 문제가 있을 때만 `[dev-company sync] ...` 한 줄을 출력한다. 수동으로 바로 맞추려면 `./sync.sh`를 실행한다.
- **오프라인**이면 로컬에 커밋해 두고 다음 `./sync.sh --push` 때 올린다.
- **충돌**(두 PC에서 같은 파일의 같은 부분을 고침)이면 동기화를 멈추고 `~/.claude`는 건드리지 않는다. 키트 폴더에서 `git pull --rebase`로 충돌을 해결하고 `git rebase --continue` 후 `./sync.sh`를 실행한다. 해결 전까지 세션을 열 때마다 안내가 나온다.
- 덮어쓰기 전에 이 PC에서 바뀐 내용이 있으면 `~/.claude/backup-dev-company-{시각}/`에 백업한다.
- 동기화 기준점은 `~/.claude/.dev-company-sync/manifest`에 저장된다. 지우면 다음 동기화를 "처음 동기화"로 처리한다 (저장소 내용 우선).
- 키트 폴더를 옮기면 `./install.sh`를 다시 실행해 훅 경로를 갱신한다.

## 로컬 전용 설정 (`local/`, git에 올라가지 않음)

외부 플러그인·스킬에 관한 지시는 공개 저장소에 두지 않고 키트 폴더의 `local/`에 둔다. 이 폴더는 `.gitignore`에 있어 push되지 않고, PC마다 따로 둔다.

| 경로 | 쓰임 |
|---|---|
| `local/overlay/<키트 경로>` | 그 키트 파일 끝에 덧붙일 내용. 예: `local/overlay/global/agents/be-api.md`는 `~/.claude/agents/be-api.md`에, `local/overlay/project-template/docs/rules/basics.md`는 `init-project.sh`가 만드는 프로젝트의 `docs/rules/basics.md`에 붙는다 |
| `local/permissions.json` | 이 PC에만 넣을 권한 규칙·env. 형식은 `global/settings/permissions.json`과 같다 |

- sync가 `~/.claude`에 설치할 때 `<!-- local-overlay -->` 블록으로 덧붙이고, 저장소로 올릴 때는 그 블록을 떼고 올린다. 블록 안 내용은 `~/.claude`에서 고치지 말고 `local/overlay/`에서 고친다 (다음 동기화 때 덮어쓴다).
- 다른 PC에도 같은 설정을 쓰려면 `local/` 폴더를 직접 복사한다.

