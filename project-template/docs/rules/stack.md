# 기술 스택과 명령어

이 프로젝트의 기술 결정과 실행 명령이다. 기술 작업을 하는 에이전트와 PM이 따른다.

## 프로젝트 결정
0단계에서 PM이 기본값을 검토해 "확정값"을 채우고 CEO 승인을 받는다. 확정값이 비어 있으면 기본값을 따른다.
- **승인되면 표를 확정값만 남겨 정리한다** (이 문서는 모든 세션과 에이전트가 매번 읽는다): 쓰지 않는 스택의 행(Python을 택하면 Spring 백엔드 행, 그 반대도 마찬가지)과 기본값 설명을 지우고, 다른 행의 스택 전용 값(DB, 시간, 테스트 도구 등)도 확정한 스택 기준으로 바꿔 적는다. 결정 근거는 `docs/adr/0001-project-setup.md`에 남긴다.

| 항목 | 기본값 | 확정값 |
|---|---|---|
| 저장소 구조 | 모노레포: `backend/`, `frontend/`, `e2e/`, `infra/`, `docs/` | |
| 백엔드 (Spring, 기본) | Java 21, **Spring Boot 4.1.x**(패치 버전까지 고정. Spring Framework 7, Spring Security 7, Hibernate 7, Jackson 3), Gradle, JPA, **QueryDSL**(Hibernate 7을 지원하는 OpenFeign 포크 `io.github.openfeign.querydsl`, 버전은 0단계에서 컴파일로 확인해 고정), MyBatis, Flyway(Boot 4의 Flyway 스타터 + `flyway-mysql`). 프로젝트는 Spring Initializr로 생성하고 실제 의존성 이름을 ADR에 기록한다 | |
| 백엔드 (Python을 택할 때) | Python 3.13, **uv**, FastAPI + Pydantic v2, SQLAlchemy 2(async) + Alembic, pytest. 규칙은 스킬 `python-conventions`. 이때 DB는 PostgreSQL 17이 기본이고 시간은 `timestamptz`(UTC), 서버 세션 테이블은 dba가 Alembic으로 만든다. 아래 Spring 전용 항목(Spring Session, Flyway, JUnit 등)은 python-conventions의 같은 주제로 바꿔 읽는다 | |
| DB | **MySQL 8.4 LTS** (MariaDB를 쓰면 버전과 문법 차이를 기록) | |
| 문자셋 | `utf8mb4` / `utf8mb4_0900_ai_ci` (MariaDB는 `utf8mb4_unicode_ci`) | |
| 시간 | DB는 `DATETIME(6)`, 모두 UTC로 저장(JVM·JDBC·DB). 엔티티는 `LocalDateTime`(UTC), **API 응답은 `OffsetDateTime`(UTC, 끝이 `Z`)**, 화면에서 로컬 시간으로 변환 | |
| 인증 | HttpOnly·Secure·SameSite=Lax 쿠키. 서버 세션(Spring Session JDBC, 세션 테이블은 dba가 마이그레이션) 또는 쿠키에 담은 JWT 중 ADR로 결정. 로그인 상태는 프론트가 `GET /api/auth/me`(비로그인이면 `data: null`)로 확인 | |
| CSRF | 쿠키 `XSRF-TOKEN` + 헤더 `X-XSRF-TOKEN` (Spring은 `csrf.spa()`). 세부는 백엔드 규칙 스킬과 frontend-conventions 4장 | |
| 프론트-백엔드 연결 | 같은 출처: 개발은 Vite proxy `/api`, 운영은 리버스 프록시. 백엔드는 context-path 없이 컨트롤러를 `/api/**`로 매핑. 헬스체크 `/api/health` | |
| 페이징 | `page`는 0부터, 응답은 `PageResponse`(offset) 또는 `CursorPageResponse`(`nextCursor`) | |
| 프론트 | React(기본) 또는 Vue 3, TypeScript, Vite, TanStack Query, Zustand/Pinia, React Hook Form + Zod | |
| 스타일 | CSS Modules + CSS 변수 디자인 토큰 (Tailwind를 쓰면 fe-feature가 0단계에서 설치) | |
| 웹 Baseline 목표 | **Baseline Widely available** (브라우저 간 호환된 지 30개월 이상 된 기능). 더 최신 기능은 CEO 승인 후 이 값을 바꾼다. 승인 전에는 폴백이 있는 점진적 향상으로만 쓴다 | |
| 테스트 | JUnit 5, Mockito, Testcontainers(MySQL), Vitest, Testing Library, MSW, Playwright, axe | |
| 배포 대상 | 첫 배포 전에 infra가 제안하고 CEO가 결정 | |
| Infra (클라우드 사용 시) | 배포 대상과 함께 infra가 IaC 도구, 환경별 계정·프로필(`{프로젝트}-dev` / `{프로젝트}-prod`), 리전을 제안하고 ADR로 정한다 | |

- 클라우드 CLI·플러그인은 클라우드를 쓰기 시작할 때 설치한다. infra가 설치 필요를 보고하면 PM은 CEO에게 설치를 요청한다.
- **백엔드 규칙 스킬 고르기** (be-api·be-domain·be-reviewer·dba·security-reviewer·infra가 작업 전에 한다): 위 표의 백엔드가 Spring이면 `spring-conventions`, Python이면 `python-conventions`를 Skill 도구로 불러오고, 프로젝트 전용 규칙 스킬(아래)이 있으면 함께 불러온다. 에이전트 본문의 Spring 전용 지시는 그 에이전트의 "Python 스택일 때" 대응표, 표에 없으면 python-conventions의 같은 주제를 따른다. 백엔드 스택이 비었거나 애매하면 작업하지 말고 "결정 필요"로 반환한다. 프론트는 `frontend-conventions`.
- 프로젝트 전용 규칙 스킬(`.claude/skills/`): 없음 (있으면 이름을 적는다. 백엔드 담당은 공통 규칙 스킬과 함께 불러온다)
- 통합 테스트와 E2E는 Docker가 필요하다 (Testcontainers 또는 Python testcontainers, docker-compose).

## 명령어
<!-- 0단계 0-6에서 PM이 실제 명령으로 고친다 -->
```bash
# 로컬 환경 (PM이 백그라운드로 띄운다)
docker compose up -d                          # DB
cd backend && ./gradlew bootRun               # 백엔드 (local 프로필 기본, ../.env 읽음, Flyway 자동 적용)
cd frontend && npm run dev                    # 프론트 (/api는 백엔드로 프록시, mock 꺼짐)
cd frontend && npm run dev:mock               # 백엔드 없이 MSW mock으로 개발할 때

# 구현 담당 확인 (테스트 코드는 쓰지 않고 기존 SmokeTest만 실행, Docker 필요)
cd backend && ./gradlew build -x test && ./gradlew test --tests '*SmokeTest'
cd frontend && npm run build && npm run lint

# 리뷰어 테스트 (Docker 필요)
cd backend && ./gradlew test
cd frontend && npm run test

# QA
cd e2e && npm run seed                            # 테스트 계정·데이터 (auth 기능 이후)
cd e2e && npx playwright test                     # webServer가 필요한 서버를 띄운다
cd frontend && npm run build && npm run preview   # 성능 측정 대상 (qa는 webServer로 띄운다)
```
