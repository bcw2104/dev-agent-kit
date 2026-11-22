---
name: python-conventions
description: Python 백엔드(FastAPI + SQLAlchemy 2 async + Alembic + PostgreSQL, uv, pytest) 코드 규칙. 폴더 구조와 담당별 소유권, 공통 응답·예외(프론트 규칙과 같은 ApiResponse 형식), 인증·CSRF, DB·트랜잭션, 시간·금액, 동시성, 외부 연동, 테스트, 완료 기준. 프로젝트 `docs/rules/stack.md`의 백엔드 스택이 Python일 때 be-api, be-domain, be-reviewer, dba가 backend/ 작업 전에 불러온다.
---

# Python 백엔드 규칙

기준 버전은 프로젝트 ADR과 `backend/pyproject.toml`·`uv.lock`에 고정한 값이다. 이 문서와 프로젝트 `docs/rules/stack.md`·ADR이 다르면 프로젝트 쪽이 우선한다. 프로젝트 전용 규칙 스킬이 있으면(`docs/rules/stack.md`에 적힘) 함께 불러온다.

## 1. 폴더 구조와 소유권

`{app}`은 패키지 이름(프로젝트 이름의 snake_case)이다.
```
backend/
├── pyproject.toml, uv.lock, .python-version   # be-api (테스트 의존성 그룹 `test`는 be-reviewer)
├── alembic.ini, migrations/env.py             # be-api
├── migrations/versions/                       # dba
├── src/{app}/
│   ├── api_main.py        # be-api: FastAPI 앱 진입점 (uvicorn {app}.api_main:app)
│   ├── worker_main.py     # be-api: 백그라운드 워커 진입점 (있을 때만)
│   ├── cli.py             # be-api: 배치·운영 명령 진입점 (있을 때만)
│   ├── common/            # be-api: config, db 세션, 시간, ApiResponse, 에러 코드, 로깅, 보안 유틸
│   ├── auth/              # be-api: 계정, 세션, CSRF, 로그인 라우터 (계정 규칙·해시 저장은 domain/user의 service)
│   ├── api/{domain}/      # be-api: router.py, schemas.py (요청·응답 Pydantic 모델)
│   ├── usecases/          # be-api: 여러 도메인을 조합하는 유스케이스, 트랜잭션 경계, 외부 API 연동 조합
│   └── domain/{domain}/   # be-domain
│       ├── models.py      #   SQLAlchemy ORM 모델 (dba 스키마와 일치)
│       ├── repository.py  #   조회·저장 (조회 전용 결과는 dataclass/Pydantic으로)
│       ├── service.py     #   단일 도메인 비즈니스 로직
│       ├── errors.py      #   도메인 ErrorCode
│       └── (그 밖의 순수 로직 모듈: calc.py, rules.py 등)
└── tests/                 # be-reviewer (conftest.py, 픽스처, 가짜 외부 어댑터 포함)
```
- 의존 방향: `api/` → `usecases/` 또는 `domain/*/service.py` → `repository.py`·`models.py` → `common/`. `common/`은 도메인을 import하지 않는다. 도메인끼리 서로 import하지 않고, 조합은 `usecases/`에서 한다.
- `api/` 라우터에는 로직을 두지 않는다. 검증·변환·서비스(유스케이스) 호출만 한다.
- 외부 시스템 호출은 해당 도메인의 어댑터 모듈(`domain/{domain}/client.py`) 한 곳에서만 하고, 테스트용 가짜 구현으로 바꿀 수 있게 Protocol 인터페이스 뒤에 둔다.

## 2. 언어·도구
- `uv`로 실행한다: `uv run ...`, 의존성 추가는 `uv add`. pip를 직접 쓰지 않는다. 시스템 Python을 쓰지 않는다(`.python-version`).
- 모든 공개 함수에 타입 힌트. `uv run ruff check`, `uv run ruff format --check`, `uv run mypy src`가 통과해야 한다.
- 설정은 `pydantic-settings`로 `common/config.py` 한 곳에서 읽는다(저장소 루트 `../.env`). 코드에서 `os.environ`을 직접 읽지 않는다.
- 로깅은 표준 `logging` + 구조화(JSON) 포맷. `print` 금지. 비밀번호·토큰·세션 ID·API 키·개인정보는 로그에 남기지 않는다.
- 비동기 코드에서 블로킹 호출(`requests`, `time.sleep`, 무거운 CPU 연산)을 하지 않는다. HTTP는 `httpx.AsyncClient`, 무거운 연산은 `asyncio.to_thread` 또는 별도 프로세스.

## 3. API 공통 응답·예외 (frontend-conventions와 같은 형식)
```python
class ApiResponse(CamelModel, Generic[T]):
    success: bool
    data: T | None
    error: ErrorBody | None
class ErrorBody(CamelModel):  code: str; message: str; field_errors: list[FieldError]
class FieldError(CamelModel): field: str; reason: str
class PageResponse(CamelModel, Generic[T]):       content, page(0부터), size, total_elements, total_pages
class CursorPageResponse(CamelModel, Generic[T]): content, next_cursor (None이면 마지막)
```
- `CamelModel`: `alias_generator=to_camel`, `populate_by_name=True`. JSON은 camelCase, Python은 snake_case. 라우터는 `response_model`과 `response_model_by_alias=True`(기본)를 쓴다.
- 에러 코드: `ErrorCode` enum(값에 http_status, code, message). 공통은 `common/errors.py`의 `CommonErrorCode`(`INVALID_INPUT`, `UNAUTHORIZED`, `FORBIDDEN`, `CSRF_INVALID`, `NOT_FOUND`, `CONFLICT`, `INTERNAL_ERROR`), 도메인은 `domain/{domain}/errors.py`의 `{DOMAIN}_{NNN}`. **코드와 HTTP 상태는 `docs/api/{feature}.yaml`에 정의된 것만 쓴다.** 명세에 없는 코드가 필요하면 "결정 필요"로 올린다.
- 예외는 `BusinessError(code: ErrorCode)` 하나로 통일한다. 도메인별 예외 클래스를 만들지 않는다.
- 예외 핸들러(`common/exception_handlers.py`)가 모든 실패를 그 HTTP 상태 + `ApiResponse` 실패 형식으로 바꾼다:
  - `BusinessError` → 해당 코드의 상태
  - `RequestValidationError` → 400 `INVALID_INPUT` + `fieldErrors`
  - Starlette `HTTPException`(404, 405, 413 등) → 그 상태, 코드는 `HTTP_{status}` 또는 공통 코드
  - SQLAlchemy `IntegrityError`(유니크 위반) → 409 `CONFLICT`. 업무상 의미가 있으면 서비스에서 잡아 도메인 코드로 바꿔 던진다
  - SQLAlchemy `StaleDataError`(낙관적 락) → 409 `CONFLICT`
  - 그 외 `Exception` → 500 `INTERNAL_ERROR`. 내부 메시지·스택트레이스를 응답에 넣지 않는다
- 라우터 접두사 `/api`, 앱에 root_path·context path를 두지 않는다. 헬스체크 `GET /api/health` → `ApiResponse.ok`.
- OpenAPI 스키마 이름 = Pydantic 모델 이름 = 프론트 타입 이름. FastAPI가 만든 `/openapi.json`을 `docs/api/{feature}.yaml`과 대조한다(명세가 기준).
- 시각 필드는 aware UTC `datetime`, 직렬화 결과가 `Z`로 끝나게 한다(공통 직렬화기 한 곳).
- try/except로 예외를 삼키지 않는다. 잡았으면 로그를 남기고 `BusinessError`로 바꾸거나 다시 던진다.

## 4. 인증·CSRF
- 인증 방식은 ADR을 따른다. 기본은 서버 세션: DB 세션 테이블 + 쿠키(`HttpOnly`, `Secure`(로컬 http는 설정으로 끔), `SameSite=Lax`, path `/`). 로그인 때 세션 ID를 새로 발급(세션 고정 방지), 로그아웃 때 DB에서 삭제, 만료는 슬라이딩. 세션 ID는 `secrets.token_urlsafe(32)` 이상, DB에는 해시로 저장한다.
- 비밀번호는 argon2(`argon2-cffi`) 해시로만 저장한다.
- CSRF: 더블 서브밋. `XSRF-TOKEN` 쿠키(JS가 읽을 수 있음, path `/`)와 `X-XSRF-TOKEN` 헤더가 일치해야 POST·PUT·PATCH·DELETE를 처리한다(상수 시간 비교). 실패는 403 `CSRF_INVALID`, 미인증은 401 `UNAUTHORIZED`. `GET /api/auth/me`가 토큰 쿠키를 내려주고 비로그인이면 `data: null`.
- 인증 확인은 의존성(`Depends(current_user)`) 하나로 한다. 기본은 인증 필요이고, 공개 경로(`/api/health`, 로그인, `/api/auth/me` 등)는 명시적으로만 연다. 같은 출처 구성이라 CORS를 열지 않는다. CSP 등 HTML 보안 헤더는 infra(리버스 프록시) 담당이다.
- 인가: 데이터를 조회·변경할 때 소유자 조건을 쿼리에 넣는다(조회 후 비교로 끝내지 않는다).

## 5. DB (PostgreSQL, SQLAlchemy 2 async + asyncpg, Alembic)
- 엔진·세션은 `common/db.py`의 `async_sessionmaker` 하나. 요청마다 세션 하나(`Depends(get_session)`).
- **트랜잭션 경계는 서비스·유스케이스 함수**(`async with session.begin():`). 라우터·repository에서 commit하지 않는다. 트랜잭션 안에서 외부 HTTP 호출을 하지 않는다.
- ORM 모델은 SQLAlchemy 2 스타일(`Mapped[...]`, `mapped_column`). dba 마이그레이션과 정확히 일치시킨다. 모델을 바꿨다고 `alembic revision --autogenerate`로 마이그레이션을 직접 만들지 않는다(dba 담당. dba는 autogenerate 결과를 참고만 하고 손으로 검토한다).
- 공통 컬럼 `created_at`, `updated_at`(`timestamptz`, 기본값 `now()`, 갱신 시 애플리케이션에서 UTC로 설정)은 `common/`의 믹스인 하나로 쓴다.
- N+1 금지: 관계는 `lazy="raise"`를 기본으로 하고 조회마다 `selectinload`/`joinedload`를 명시한다.
- 목록 조회는 `PageResponse`(offset, 총개수 쿼리 별도) 또는 `CursorPageResponse`(정렬 키 기반). 선택적 검색 조건은 `select()`에 조건을 조립한다.
- 대량 적재는 ORM 단건 add가 아니라 `insert().values([...])`(필요하면 `on_conflict_do_nothing`) 배치나 `COPY`로 한다.
- 문자열로 SQL을 이어 붙이지 않는다. `text()`는 바인드 파라미터만 쓴다.

## 6. 시간·숫자
- 시간은 항상 timezone-aware UTC(`datetime.now(UTC)`). naive datetime 금지. DB 타입은 `timestamptz`.
- 금액·수량·비율처럼 정확해야 하는 값은 `Decimal`, DB는 `numeric(p, s)`(정밀도 명시). float로 계산하지 않는다. 반올림 규칙은 한 함수에 모은다.

## 6-1. 동시성
- 동시 요청·중복 클릭·재시도로 깨지는 지점(잔액·수량 차감, 중복 생성, 상태 전이, 카운트 증감)을 기능마다 찾는다.
- 대응: 유니크 제약(중복 생성), 원자적 UPDATE(`update(...).values(cnt=Model.cnt + 1)`), 비관적 락(`with_for_update()`), 낙관적 락(`version_id_col`), 되돌릴 수 없는 외부 호출은 `Idempotency-Key`(키 선점은 별도 트랜잭션). 읽고-계산하고-쓰기와 애플리케이션 메모리 락(`asyncio.Lock`)으로 공유 DB 상태를 지키지 않는다(프로세스가 여러 개면 무용).
- 백그라운드 워커가 여러 개 뜨면 안 되는 작업은 DB advisory lock으로 하나만 돌게 한다.
- 리포트에 `경합 지점 | 깨지는 상황 | 대응 방식` 표를 적는다.

## 7. 외부 연동
- 외부 API 클라이언트는 타임아웃을 명시하고, 재시도는 멱등한 요청에만 지수 백오프로 한다. 되돌릴 수 없는 요청(결제, 주문 생성 등)은 결과를 모르면 다시 보내지 말고 조회로 확정한다.
- 외부 응답은 Pydantic으로 검증한 뒤 도메인 값으로 바꾼다.
- 비밀값(API 키)은 설정에서만 읽고, DB·로그·응답에 남기지 않는다.

## 8. 테스트 (be-reviewer)
- pytest + pytest-asyncio(`asyncio_mode = "auto"`), httpx `AsyncClient` + `ASGITransport`로 API 호출. 커버리지는 pytest-cov.
- DB: testcontainers PostgreSQL(프로젝트와 같은 메이저 버전) 세션 범위 컨테이너 하나에 Alembic 전체 마이그레이션을 적용한다. 테스트마다 트랜잭션 롤백 또는 테이블 정리로 격리한다(동시성 테스트는 롤백 격리를 쓰지 않고 커밋 후 정리).
- 외부 HTTP는 respx로 막는다. 테스트에서 실제 외부 서비스를 부르지 않는다(필요하면 `@pytest.mark.external`로 표시하고 기본 실행에서 뺀다).
- **SmokeTest**(`tests/test_smoke.py`, 0단계에 만든다): 새 DB에 전체 마이그레이션 → ORM 메타데이터와 실제 스키마 비교(차이 없음) → `GET /api/health` 200. 구현 담당과 dba가 이 테스트를 실행해 스키마를 확인한다.
- 보안 기본 테스트: 토큰 없이 POST → 403 `CSRF_INVALID`, 쿠키를 받은 뒤 토큰을 담은 미인증 POST → 401, 둘 다 ApiResponse 형식.
- 동시성: 경합 지점마다 `asyncio.gather`로 동시 요청을 보내 최종 상태(음수 없음, 1건만 생성, 전이 1회)를 검증한다.
- 테스트 이름은 한글 허용: `test_재고가_부족하면_주문을_거부한다`.

## 9. 완료 기준
- 구현 담당(be-api, be-domain): `cd backend && uv run ruff check && uv run ruff format --check && uv run mypy src && uv run pytest tests/test_smoke.py` 통과. 테스트 코드는 쓰지 않는다. 서버를 직접 오래 띄우지 않는다.
- 리뷰어(be-reviewer): `uv run pytest` 전체 통과(기존 테스트 포함), 경합 지점마다 동시성 테스트, 커버한 인수 조건 기록.
- dba: `uv run pytest tests/test_smoke.py`로 새 DB에 전체 마이그레이션이 적용되는지 확인.
