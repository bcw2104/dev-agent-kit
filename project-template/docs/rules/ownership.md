# 소유권

모든 에이전트가 따른다. 자기 소유 영역만 수정하고, 다른 영역 변경은 리포트의 "요청 사항"으로 넘긴다.

에이전트는 **자기 소유 영역만 수정**한다 (security-reviewer·planning-researcher·planning-spec은 키트의 가드 훅이 소유 영역 밖 Edit/Write를 막는다. 나머지 역할은 이 규칙으로 지킨다). 다른 영역 변경이 필요하면 직접 고치지 않고 "요청 사항"으로 PM에게 반환한다. 표에 없는 파일이 필요하면 PM이 담당을 정하고 진행판에 기록한다.

| 영역 | 소유자 |
|---|---|
| `docs/research/` | planning-researcher |
| `docs/security/` (위협 모델, 점검 이력) | security-reviewer (그 밖의 파일은 읽기만 한다) |
| `docs/prd/`, `docs/screens/` | planning-spec |
| `docs/api/` | be-api |
| `docs/db/`, `backend/src/main/resources/db/migration/` | dba |
| `docs/adr/{NNNN}-{주제}.md` | PM이 위임할 때 번호·파일 이름을 지정한 담당 (0단계 ADR은 PM). 규칙은 `docs/rules/handoff.md`의 "ADR" |
| 프로젝트 루트 `README.md` (프로젝트 소개, 실행 방법) | PM |
| `docs/rules/` (부서별 규칙), `.claude/office.json` (agent-office 부서 배치) | PM (이 운영 규칙의 일부라 바꾸려면 CEO 승인) |
| `docs/handoff/{feature}/README.md` (진행판) | PM |
| `docs/handoff/{feature}/{NN}-{에이전트}.md` | 그 리포트를 쓴 에이전트 (모든 에이전트가 자기 리포트를 쓴다) |
| `backend/build.gradle`, `settings.gradle`, Gradle Wrapper(`gradlew`, `gradlew.bat`, `gradle/`), 백엔드 `.gitignore` | be-api (테스트 의존성 `testImplementation`·`testRuntimeOnly`는 be-reviewer가 직접 추가) |
| `backend/src/main/resources/application*.yml` | be-api |
| `backend/.../{App}Application.java`, `backend/.../global/` (공통 응답·예외·설정·보안·BaseTimeEntity·멱등성) | be-api |
| `backend/.../domain/{domain}/controller/`, `dto/`, `application/` | be-api |
| `backend/.../domain/{domain}/entity/`, `repository/`(`query/` 포함), `mapper/`, `service/`, `exception/` | be-domain |
| `backend/src/main/resources/mapper/` (MyBatis XML) | be-domain |
| `backend/src/test/` (test 리소스 포함) | be-reviewer |
| `frontend/` 설정·진입점 (`package.json`, lockfile, `vite.config.ts`, `tsconfig*`, ESLint, `index.html`, `src/main.ts(x)`, `.env.development`, `.env.example`, 프론트 `.gitignore`), `frontend/public/` | fe-feature (테스트 도구 devDependencies는 fe-reviewer가 직접 추가) |
| `frontend/src/app/`, `features/`, `shared/api/`, `shared/hooks/`, `shared/lib/`, `mocks/` | fe-feature |
| `frontend/src/shared/ui/` (`layout/` 포함), `shared/styles/`, 디자인 토큰 | fe-design-system (예외: 0단계 0-3에 fe-feature가 `shared/styles/global.css` **빈 파일만** 만들어 `main.ts(x)`에서 import한다. 그 뒤 내용과 파일은 fe-design-system 소유) |
| `frontend/**/*.test.ts(x)`, `frontend/src/test/`, `frontend/vitest.config.ts` | fe-reviewer |
| `e2e/` (자체 `package.json`, `playwright.config.ts`, 시드·테스트 계정 포함) | qa |
| `docker-compose*.yml`, 루트 `.env.example`, 루트 `.gitignore`, `backend/Dockerfile`·`.dockerignore`, `frontend/Dockerfile`·`.dockerignore`, `.github/workflows/`, `infra/`, 리버스 프록시 설정 | infra |

- **백엔드가 Python이면** 위 표의 `backend/` 행 대신 `python-conventions` 1장의 경로·소유자를 쓴다 (담당 이름은 같다: be-api, be-domain, be-reviewer, dba).
- 리뷰어가 작성한 테스트는 QA가 시나리오 누락 관점에서 점검한다 (자기 채점 방지).
- 조회 방식(JPA / QueryDSL / MyBatis)은 spring-conventions 4장 기준으로 고른다. MyBatis XML, QueryDSL, 복잡한 JPA 쿼리는 be-domain이 작성하고 dba가 성능을 리뷰한다.
- 보안 헤더: CSP·HSTS·캐시 헤더는 infra(리버스 프록시)만 설정한다. be-api는 CORS, 쿠키 속성, CSRF, 인증·인가를 맡고 CSP를 설정하지 않는다.
