---
name: frontend-conventions
description: React 또는 Vue + TypeScript 프론트엔드 코드를 작성·수정·리뷰할 때 사용. 폴더 구조, 컴포넌트 분리, 상태관리, 폼, API 클라이언트·인증·에러 처리, 중복 요청 방지, 타입 규칙, 역할별 완료 기준을 정의한다.
---

# Frontend Conventions

기본은 React + TypeScript + Vite. Vue 프로젝트는 각 항목의 [Vue] 표기를 따른다. 기존 코드와 충돌하면 기존 스타일을 확인하고 불일치를 보고한다. 인증 방식·연결 방식은 `docs/rules/stack.md`을 따른다.

**어떤 웹 API, HTML, CSS 기능을 쓸지는 프로젝트 `docs/rules/frontend.md`의 웹 플랫폼 기준을 따른다.** 이 스킬은 구조, 상태관리, API 클라이언트, 네이밍을 다룬다. Baseline 목표는 프로젝트 `docs/rules/stack.md`를 따른다.

## 1. 폴더 구조 (도메인 기준)

```
frontend/
├── package.json, lockfile, vite.config.ts, tsconfig*.json, eslint 설정, index.html, .env.development   # fe-feature
├── vitest.config.ts                                           # fe-reviewer
├── public/mockServiceWorker.js                                # fe-feature (MSW)
└── src/
    ├── main.tsx        # fe-feature: 진입점 (MSW 조건부 시작 포함)
    ├── app/            # fe-feature: 라우터, 전역 Provider(QueryClient 등), 라우트별 레이아웃 배치
    ├── shared/
    │   ├── api/        # fe-feature: http 클라이언트, ApiError, 공통 타입(ApiResponse, PageResponse)
    │   ├── ui/         # fe-design-system: Button, Input, Modal 등 범용 컴포넌트
    │   │   └── layout/ # fe-design-system: AppShell, Header 등 레이아웃 컴포넌트
    │   ├── styles/     # fe-design-system: 디자인 토큰, 전역 스타일
    │   ├── hooks/      # fe-feature: useSubmitLock 등 공통 훅 [Vue] composables/
    │   └── lib/        # fe-feature: 순수 유틸 (format, date)
    ├── features/
    │   └── {domain}/   # fe-feature: 예: auth, post, order (기능 이름이 아니라 도메인 이름)
    │       ├── api/    # 해당 도메인 API 함수 + query 훅
    │       ├── components/
    │       ├── hooks/
    │       ├── types.ts
    │       └── index.ts  # 외부 공개 API만 export
    ├── mocks/          # fe-feature: MSW handlers (개발 mock과 테스트가 함께 쓴다)
    └── test/           # fe-reviewer: 테스트 setup, 렌더 헬퍼
```

- feature 간 import는 `features/{x}/index.ts`를 통해서만 한다. 내부 파일 직접 import 금지.
- `shared`는 `features`를 import하지 않는다 (의존 방향: features → shared).
- E2E는 `frontend/` 밖의 최상위 `e2e/`에 있다 (qa 소유). Vitest가 E2E 파일을 집지 않는다.
- 앱 빌드용 tsconfig(Vite 템플릿의 `tsconfig.app.json`)는 `**/*.test.ts(x)`와 `src/test/`를 제외한다. 테스트 파일 타입 검사는 Vitest 쪽이 맡는다 (그래야 테스트 파일 때문에 `npm run build`가 깨지지 않는다).

## 2. 컴포넌트 규칙

- [Vue] `<script setup lang="ts">` + Composition API만 사용.
- 한 파일 150줄을 넘으면 분리를 검토한다.
- 분리 기준:
  - **화면(페이지) 컴포넌트**: 데이터 조회, 상태 조합, 하위 컴포넌트 배치
  - **표현 컴포넌트**: props만 받아 렌더링. API 호출/전역 상태 접근 금지
- 이벤트 핸들러 이름: props는 `onXxx`, 내부 함수는 `handleXxx`. [Vue] emit은 `update:xxx`, `xxx` 동사형.

## 3. 상태 관리와 폼

| 종류 | 도구 |
|---|---|
| 서버 상태 (API 데이터) | TanStack Query (React/Vue 공통) |
| 로그인 상태 | TanStack Query의 `useMe()` (`GET /api/auth/me`) — 전역 스토어에 복사하지 않는다 |
| 전역 클라이언트 상태 (테마, 사이드바 열림 등) | Zustand / [Vue] Pinia |
| 폼 상태와 검증 | React Hook Form + Zod / [Vue] VeeValidate + Zod |
| 지역 UI 상태 | useState / [Vue] ref |

- 서버에서 받은 데이터를 전역 스토어에 복사하지 않는다. 캐시는 Query가 담당한다.
- 파생 가능한 값은 상태로 두지 않고 계산한다 (useMemo / [Vue] computed는 비용이 클 때만).
- Query key는 도메인별 팩토리로 관리한다:
  ```ts
  export const postKeys = {
    all: ['post'] as const,
    list: (params: PostListParams) => [...postKeys.all, 'list', params] as const,
    detail: (id: number) => [...postKeys.all, 'detail', id] as const,
  };
  ```
- mutation 성공 시 관련 key를 `invalidateQueries`로 무효화한다.
- **로그인 상태와 CSRF 토큰**: 앱 시작 시 `useMe()`(`GET /api/auth/me`, 비로그인이면 `data: null`)를 먼저 불러온다. 이 요청이 `XSRF-TOKEN` 쿠키도 받아 온다. 로그인·로그아웃 성공 뒤에는 서버가 CSRF 토큰을 바꾸므로 `me` 쿼리를 다시 불러온다(`refetchQueries`). 사용자 정보를 Zustand 등에 따로 복사하지 않는다.
- **폼**: 검증 규칙은 Zod 스키마 하나로 정의하고 에러 메시지는 화면 기획서 문구를 쓴다. 입력 보조와 접근성을 위해 네이티브 속성(`type`, `autocomplete`, `inputmode`, `required`, `maxLength`)도 함께 단다. 브라우저 기본 검증 말풍선과 메시지가 겹치지 않게 `<form noValidate>`로 둔다.
- 서버가 400과 함께 보낸 `fieldErrors`는 해당 필드 에러로 표시한다 (`setError`).

## 4. API 클라이언트·인증·에러

- axios 인스턴스는 `shared/api/http.ts` 하나만 만든다.
  - `baseURL: '/api'` (같은 출처. 개발은 Vite proxy가 백엔드로 넘긴다)
  - **쿠키 인증**: `withCredentials: true`. 토큰을 JS에서 읽거나 저장하지 않는다 (localStorage·sessionStorage 금지)
  - **CSRF**: 상태를 바꾸는 요청에 `XSRF-TOKEN` 쿠키 값을 `X-XSRF-TOKEN` 헤더로 보낸다 (axios 기본 `xsrfCookieName`/`xsrfHeaderName`과 같고, 같은 출처라 자동으로 붙는다)
  - **CSRF 실패 재시도**: 403 + `CSRF_INVALID`를 받으면 `GET /api/auth/me`로 토큰을 다시 받고 **1회만** 재시도한다 (재시도 표시 플래그로 무한 반복을 막는다)
  - **성공 응답 인터셉터**: `ApiResponse<T>`를 풀어 `data`만 반환한다
  - **에러 응답 인터셉터**: 백엔드는 실패를 4xx/5xx 상태 코드로 보낸다.
    - `error.response`가 있고 본문에 `error`가 있으면 → `ApiError(status, code, message, fieldErrors)`
    - `error.response`는 있는데 본문 형식이 다르면(프록시 오류 등) → `ApiError(status, 'HTTP_' + status)`
    - `error.response`가 없을 때만(연결 실패, 타임아웃, 취소) → `ApiError(0, 'NETWORK_ERROR')`
  - **401**: 로그인 화면으로 보낸다 (ADR에서 토큰 갱신 방식을 정했다면 그 절차를 한 번 시도한 뒤). 단, `GET /api/auth/me`·로그인 요청의 401과 공개 라우트에서는 이동하지 않는다 (무한 이동 방지)
  - **403** (`CSRF_INVALID` 제외): 권한 없음 화면·안내로 처리한다
- 백엔드 응답 타입과 맞춘다:
  ```ts
  export interface ApiResponse<T> { success: boolean; data: T; error: ErrorBody | null }
  export interface ErrorBody { code: string; message: string; fieldErrors: { field: string; reason: string }[] }
  export interface PageResponse<T> { content: T[]; page: number; size: number; totalElements: number; totalPages: number }  // page는 0부터
  export interface CursorPageResponse<T> { content: T[]; nextCursor: string | null }                                      // null이면 마지막
  ```
- 화면에 보여주는 페이지 번호는 1부터, API로 보내는 `page`는 0부터다. 변환은 한 곳(`shared/api` 또는 Pagination 사용부)에서만 한다.
- 컴포넌트에서 axios/fetch를 직접 호출하지 않는다. 항상 `features/{x}/api`의 함수나 query 훅을 통한다.
- 요청/응답 타입은 `docs/api/{feature}.yaml`(OpenAPI)과 일치시킨다. 타입 이름은 명세의 스키마 이름과 같게 짓는다.
- 에러 메시지 표시는 공통 처리(토스트 등)를 기본으로 하고, 화면별 처리(필드 에러, 409 안내)가 필요할 때만 개별 처리한다.
- **MSW mock**: `src/mocks/`의 handlers는 API 명세 응답 형식을 따른다(시각은 `Z`로 끝나는 UTC). `main.tsx`에서 `import.meta.env.DEV && import.meta.env.VITE_API_MOCKING === 'true'`일 때만 동적 import로 시작한다. 기본값은 꺼짐이다: `.env.development`에 `VITE_API_MOCKING=false`, mock으로 개발할 때는 `npm run dev:mock`(`VITE_API_MOCKING=true vite`) 스크립트를 쓴다. 프로덕션 번들에 msw 코드가 들어가지 않고 Service Worker가 등록되지 않아야 한다 (`public/mockServiceWorker.js` 파일이 dist에 복사되는 것은 등록되지 않으면 무해하다). `msw` 패키지는 fe-feature가 devDependency로 설치한다.

## 4-1. 중복 요청 방지

**데이터를 바꾸는 모든 요청(생성·수정·삭제·결제)은 더블 클릭, 연타, Enter 반복, 뒤로 가기 재제출로 두 번 나가지 않게 한다.** 프론트 방지는 사용자 경험을 위한 1차 방어이고, 최종 방어는 백엔드(유니크 제약, 멱등성 키)다. 둘 다 한다.

- **동기 잠금(`useRef`)으로 막는다.** `mutation.isPending`이나 `disabled`는 다음 렌더 이후에 반영되므로, 같은 렌더에서 들어온 두 번째 클릭을 막지 못한다. 공통 훅 `shared/hooks/useSubmitLock`을 쓴다:
  ```ts
  export function useSubmitLock() {
    const locked = useRef(false);
    return useCallback(async <T>(run: () => Promise<T>): Promise<T | undefined> => {
      if (locked.current) return undefined;   // 진행 중이면 무시
      locked.current = true;
      try { return await run(); } finally { locked.current = false; }
    }, []);
  }
  // 사용: const withLock = useSubmitLock();
  //       const onSubmit = form.handleSubmit((v) => withLock(() => mutation.mutateAsync(v)));
  ```
  [Vue] 컴포넌트 밖에 두지 않는 `let locked = false` 또는 `ref`를 같은 방식으로 감싼 composable.
- **화면에도 표시한다**: 요청 중에는 제출 버튼을 `shared/ui` Button의 `loading` prop으로 비활성화하고 로딩을 보여준다.
- 폼은 버튼 `onClick`이 아니라 `<form onSubmit>`으로 처리한다 (Enter 제출도 같은 잠금을 거친다).
- **재시도를 조심한다**
  - 멱등하지 않은 mutation에는 `retry`를 설정하지 않는다 (TanStack Query mutation 기본값은 재시도 0)
  - API 명세에 `Idempotency-Key` 헤더가 있으면, 사용자 의도 1번당 키 1개를 만든다(`crypto.randomUUID()`, HTTPS 또는 localhost에서만 동작). 네트워크 오류로 다시 보낼 때는 같은 키를 쓰고, 성공한 뒤에만 새 키를 만든다
- **폼이 아닌 동작**
  - 좋아요·북마크 같은 토글: 진행 중에는 추가 클릭을 무시하거나, 낙관적 업데이트 후 마지막 상태만 서버에 보낸다
  - 검색어 입력처럼 연속 입력으로 조회하는 경우: 300ms 내외 debounce. 오래된 요청은 Query가 주는 `signal`을 axios에 넘겨 취소한다
- **완료 후**
  - 생성·결제 완료 후 이동은 `replace`로 해서 뒤로 가기로 폼에 돌아와 다시 제출하지 않게 한다
  - 백엔드의 409 Conflict(이미 처리된 요청, 동시 수정 충돌)는 에러로 끝내지 말고 안내 문구를 보여준 뒤 최신 데이터를 다시 조회한다

## 5. TypeScript 규칙

- `strict: true`. `any` 금지, 불가피하면 `unknown` 후 타입 가드.
- 객체 형태는 `interface`, 유니온/유틸 조합은 `type`.
- API 요청/응답 타입은 `features/{x}/types.ts`에 정의하고, 명세 스키마·백엔드 DTO 이름과 맞춘다 (`PostResponse`, `PostCreateRequest`).
- enum 대신 `as const` 객체 + 유니온 타입을 사용한다.
- 날짜는 API의 ISO-8601 문자열(UTC, 끝이 `Z`)을 받아 화면에서 로컬 시간으로 바꾼다 (`shared/lib/date`). 오프셋이 없는 문자열이 오면 백엔드 버그이므로 보정하지 말고 보고한다.

## 6. 스타일

- 스타일 방식은 `docs/rules/stack.md`의 스타일 행을 따른다 (기본: CSS Modules + CSS 변수 토큰). 혼용하지 않는다. 도구 설치·설정은 fe-feature가 0단계에서 한다.
- 색상, 간격, 폰트 크기는 디자인 토큰(CSS 변수 또는 Tailwind 설정)으로만 사용. 하드코딩 금지.
- 접근성과 네이티브 요소 사용 기준은 프로젝트 `docs/rules/frontend.md`를 따른다.
- popover로 만든 툴팁·드롭다운의 **위치 계산**은 JS로 해도 된다 (anchor positioning이 아직 Baseline 목표 밖이므로). 클릭으로 여닫기, Esc 닫기, 바깥 클릭 닫기는 popover 네이티브 동작을 쓴다. 마우스를 올리거나 포커스할 때 여는 툴팁은 네이티브 동작이 없으므로 그 열기 처리도 JS로 해도 된다.

## 7. 성능

- 라우트 단위 lazy loading (`React.lazy` / [Vue] `defineAsyncComponent`, 라우터 동적 import).
- 메모이제이션(memo, useCallback)은 측정된 문제가 있을 때만 적용한다. 기본으로 남발하지 않는다.
- 이미지, 리소스 우선순위 등 웹 성능 세부 기법은 설치된 웹 플랫폼 가이드 스킬이 있으면 그것을 따른다.

## 8. 네이밍

- 컴포넌트 파일: `PascalCase.tsx` / [Vue] `PascalCase.vue`
- 훅: `useCamelCase.ts`, 유틸: `camelCase.ts`
- boolean: `is/has/can` 접두사
- 상수: `UPPER_SNAKE_CASE`

## 9. 공통화 / 단순화 원칙

- 같은 UI 패턴이 3번 반복되면 `shared/ui`로 올린다 (fe-design-system에 요청). 2번까지는 중복 허용.
- 특정 기능에서만 쓰는 컴포넌트는 `shared`로 올리지 않는다.
- props가 7개를 넘으면 컴포넌트 책임이 큰 것이므로 분리나 composition(children/slot)을 검토한다.

## 10. 테스트 (fe-reviewer)

- Vitest + Testing Library, 환경은 jsdom. `src/test/setup.ts`에서 MSW `setupServer(...handlers)`를 `src/mocks/` handlers로 띄우고, 테스트마다 `server.use(...)`로 덮어쓴다.
- 렌더 헬퍼(`src/test/render.tsx`)는 테스트마다 새 QueryClient(`retry: false`)와 Router를 감싼다.
- 요소는 role/label로 찾는다. 구현 세부(클래스명, 내부 상태)를 검사하지 않는다.
- http 클라이언트: 403 `CSRF_INVALID` 응답 뒤 `me`를 다시 불러 **한 번만** 재시도하는지, `me`·로그인의 401에서 로그인 화면으로 이동하지 않는지 검증한다.
- **중복 요청 테스트**: **같은 틱에** 이벤트를 두 번 보낸다. `await user.click()`을 두 번 하면 사이에 리렌더가 끼어 버튼이 이미 비활성이 되므로, 잠금이 없고 `isPending`만 있는 구현도 통과해 버린다.
  ```ts
  fireEvent.click(submitButton); fireEvent.click(submitButton);   // 폼이면 fireEvent.submit(form) 두 번
  await waitFor(() => expect(handlerCalls).toBe(1));
  ```
  - **폼이 아닌 버튼**(로그아웃, 토글 등)은 `fireEvent.click` 두 번으로도 부족하다. 첫 클릭 직후 React가 동기로 다시 그려 버튼이 비활성이 되면, 잠금이 없는 구현도 통과한다. 두 클릭을 **한 `act` 안에서** 보낸다. 잠금을 빼면 이 테스트가 실패하는지 한 번 확인한다.
  ```ts
  act(() => { button.click(); button.click(); });
  await waitFor(() => expect(handlerCalls).toBe(1));
  ```
- **CSS로 숨긴 글자는 jsdom이 못 잡는다.** jsdom은 CSS를 적용하지 않아 `visibility: hidden`·`display: none`으로 사라진 문구도 이름·텍스트 검사를 통과한다. 상태에 따라 문구를 숨기거나 바꾸는 공통 컴포넌트(로딩 버튼 등)는 실제 브라우저 e2e에서 `toHaveAccessibleName`·axe로 확인하도록 qa에 넘긴다.
- 날짜 표시 테스트는 handler가 `Z`로 끝나는 시각을 줄 때 로컬 시간으로 바뀌는지 확인한다.

## 완료 기준 (Definition of Done)

작업 종료 전 자기 역할의 항목을 모두 확인하고 결과를 보고한다.

**구현 담당 (fe-feature, fe-design-system)** — 테스트는 쓰지 않는다 (fe-reviewer 담당)
- [ ] `npm run build` 성공 (타입 에러 0)
- [ ] `npm run lint` 에러 0
- [ ] 컴포넌트에서 직접 API 호출, `any`, index key 없음
- [ ] 로딩 / 에러 / 빈 상태 UI 처리 완료
- [ ] 데이터를 바꾸는 요청의 중복 요청 방지 완료 (4-1)
- [ ] 리뷰 반려로 재작업했으면 리뷰에 적힌 실패 테스트를 `npm run test -- <파일>`로 실행해 통과 확인 (테스트 코드는 고치지 않는다)

**리뷰어 (fe-reviewer)**
- [ ] `npm run test` 전체 통과 (기존 테스트 포함)
- [ ] fe-feature 리포트의 중복 요청 방지 목록마다 테스트 작성
- [ ] 커버한 인수 조건 번호 기록

<!-- local-overlay: 이 블록은 키트의 local/overlay에서 온다. 여기서 고치지 말고 그 파일을 고친다 -->
## 이 PC에서 쓰는 웹 플랫폼 가이드 스킬
- 웹 API·HTML·CSS 기능 선택, 접근성, 네이티브 요소, 웹 성능 세부 기법은 `modern-web-guidance` 스킬로 확인한다 (forms, performance, accessibility, html, css 지침).
<!-- /local-overlay -->
