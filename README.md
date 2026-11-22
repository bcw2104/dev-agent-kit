# Dev Agent Kit

AI 에이전트로 구성한 1인 개발회사 세팅 키트.

## 새 PC에서 세팅하기

1. 이 저장소를 포크한 뒤 원하는 위치에 clone한다 (예: `git clone <내 포크 주소> ~/dev-agent-kit`)
2. 그 폴더에서 Claude Code를 실행하고 이렇게 요청한다:
   > SETUP.md 읽고 세팅해줘
3. 새 프로젝트를 시작할 때마다:
   > ./init-project.sh 로 ~/projects/my-app 에 적용해줘
4. 그 프로젝트에서 Claude Code를 열고:
   > 0단계(초기 세팅)부터 시작해

   기술 결정 확인 → 백엔드·프론트 골격, 테스트 기반, E2E 환경까지 만든 뒤 기능 개발(1~7단계)로 넘어간다.

직접 하려면 `./install.sh` 후 `./init-project.sh <경로>`.

## PC 간 동기화

설치하면 Claude Code 세션 시작·종료 때 에이전트·스킬이 이 저장소를 거쳐 동기화된다. 받는 것은 자동이고, 올리는 것(push)은 내용을 확인한 뒤 `./sync.sh --push`로 한다. 이 키트를 쓰려면 저장소를 포크해서 자기 포크로 동기화한다. 어느 PC에서 고쳐도(`~/.claude`든 키트 폴더든) push한 뒤 다른 PC의 다음 세션에 반영된다. 바로 맞추려면 `./sync.sh`. 자세한 내용은 SETUP.md "4. PC 간 동기화".

Windows는 Git Bash에서 같은 방법으로 세팅한다. 주의할 점은 SETUP.md의 "Windows에서 세팅하기" 참고.

## 공통 에이전트와 프로젝트 전용 에이전트

- **공통**: 이 키트의 12개. `~/.claude/agents/`에 설치되고 모든 PC·프로젝트가 같이 쓴다 (자동 동기화).
- **프로젝트 전용**: 그 프로젝트의 `.claude/agents/`에 두고 프로젝트 저장소에 커밋한다. 공통에 없는 역할을 추가하거나, 같은 이름으로 공통 에이전트를 그 프로젝트에서만 교체한다.
- 프로젝트 전용 에이전트를 `~/.claude/agents/`에 두면 동기화로 모든 PC·프로젝트에 퍼지므로 두지 않는다. 만드는 방법은 프로젝트 `CLAUDE.md` 1장.

## 조직

프로젝트에 적용하면 `.claude/office.json`에 아래 부서 배치가 들어가 agent-office 뷰어에서 부서별 방으로 보인다.

| 부서 | 에이전트 |
|---|---|
| 개발 PM | 메인 세션 |
| 기획 | planning-researcher, planning-spec |
| 백엔드 | be-domain, be-api, be-reviewer |
| 프론트엔드 | fe-design-system, fe-feature, fe-reviewer |
| QA / 인프라 / DBA | qa, infra, dba |
| 보안 | security-reviewer (코드는 고치지 않고 담당별로 수정 요청) |

모델: 에이전트 12개 모두 `model: opus` (Max 플랜 기준). 별칭이라 새 모델이 나오면 최신 버전을 자동으로 쓴다.
사용 한도에 자주 걸리면 가장 자주·길게 도는 `fe-feature`부터, 다음으로 `qa`를 `model: sonnet`으로 내린다.

운영 규칙과 작업 흐름은 `project-template/CLAUDE.md` 참고.

## 라이선스

MIT
