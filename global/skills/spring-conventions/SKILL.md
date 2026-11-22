---
name: spring-conventions
description: Spring Boot + JPA/QueryDSL/MyBatis + MySQL 백엔드 코드를 작성·수정·리뷰할 때 사용. 패키지 구조, 공통 응답/예외, JPA·QueryDSL·MyBatis 사용 기준, 트랜잭션, 동시성, N+1 방지, 테스트, 역할별 완료 기준을 정의한다.
---

# Spring Backend Conventions

이 프로젝트의 백엔드 코드는 아래 규칙을 따른다. 규칙과 기존 코드가 충돌하면 기존 코드 스타일을 우선 확인하고, 불일치는 작업 결과에 보고한다. 버전·DB·인증 방식은 `docs/rules/stack.md`을 따른다.

**기준 버전: Spring Boot 4.1.x** (Spring Framework 7, Spring Security 7, Hibernate 7, Jackson 3, Testcontainers 2). 3.x 시절 자료와 다른 점:
- 스타터가 기술별로 나뉘었다 (예: Flyway는 Flyway 스타터가 있어야 자동 설정된다, 테스트 슬라이스도 기술별 test 스타터). **정확한 의존성 이름은 Spring Initializr(start.spring.io)에서 확정한 버전으로 생성한 결과를 기준**으로 하고, 기억에 의존해 적지 않는다.
- 테스트 슬라이스 애너테이션(`@DataJpaTest`, `@WebMvcTest`, `@AutoConfigureTestDatabase` 등)의 패키지가 바뀌었다. import는 실제 클래스패스에서 확인한다.
- `@MockBean`은 없다. `@MockitoBean`을 쓴다.
- Jackson 3의 패키지는 `tools.jackson.*`이다 (애너테이션 `com.fasterxml.jackson.annotation`은 그대로).
- Testcontainers 2는 모듈 artifact 이름과 컨테이너 클래스 패키지가 바뀌었다 (예: MySQL 모듈). 생성된 BOM 기준으로 쓴다.

## 1. 패키지 구조 (도메인 기준)

```
backend/src/main/java/com/{company}/{app}
├── {App}Application.java       # be-api
├── global/                     # be-api 소유
│   ├── config/                 # JPA Auditing, Security, Web 설정
│   ├── entity/                 # BaseTimeEntity
│   ├── exception/              # ErrorCode(인터페이스), CommonErrorCode, BusinessException, GlobalExceptionHandler
│   ├── idempotency/            # Idempotency-Key 공통 처리 (필요해지면 만든다. 엔티티·저장소 포함)
│   ├── security/               # SecurityConfig, EntryPoint·AccessDeniedHandler, UserDetailsService 어댑터 (8장)
│   └── response/               # ApiResponse, ErrorResponse, PageResponse
└── domain/
    └── {domain}/               # 예: member, post, order (기능 이름이 아니라 도메인 이름)
        ├── controller/         # be-api
        ├── application/        # be-api: 여러 도메인을 조합하는 유스케이스
        ├── dto/                # be-api: request/, response/
        ├── service/            # be-domain: 단일 도메인 서비스
        ├── entity/             # be-domain
        ├── repository/         # be-domain: JPA Repository, QueryDSL 커스텀 Repository(…Custom, …Impl)
        │   └── query/          # be-domain: 조회 전용 DTO (JPA·QueryDSL 프로젝션, MyBatis 결과)
        ├── mapper/             # be-domain: MyBatis Mapper 인터페이스 (필요할 때만)
        └── exception/          # be-domain: {Domain}ErrorCode
backend/src/main/resources
├── application.yml, application-{profile}.yml   # be-api
├── db/migration/               # dba: Flyway (Spring Boot 기본 위치)
└── mapper/{domain}/*.xml       # be-domain: MyBatis XML
```

- 레이어 기준(controller/, service/ 최상위) 구조를 새로 만들지 않는다.
- **도메인 간 호출은 Application 계층에서만** 한다. Service는 다른 도메인의 Service·Repository를 호출하지 않는다.
- 여러 도메인을 조합하는 유스케이스는 **주 도메인**(상태가 바뀌는 쪽)의 `application/`에 둔다. 예: 주문하면서 재고를 차감하면 `domain/order/application/`.

## 2. 레이어 책임

| 레이어 | 하는 일 | 하지 않는 일 |
|---|---|---|
| Controller | 요청 검증(@Valid), Application·Service 호출, 응답 래핑 | 비즈니스 로직, Entity 반환 |
| Application | 여러 도메인 서비스 조합, 트랜잭션 경계, 외부 연동, 재시도 | 단일 도메인 규칙 구현 |
| Service | 단일 도메인 비즈니스 로직 | HTTP 관련 처리, 다른 도메인 호출 |
| Repository/Mapper | 데이터 접근 | 비즈니스 판단 |
| Entity | 상태와 도메인 행위 | 표현 계층 관심사 |

- Controller는 Entity를 절대 반환하지 않는다. 항상 Response DTO.
- DTO는 Java `record`를 기본으로 한다. Entity → DTO 변환은 `XxxResponse.from(entity)` 정적 팩토리.
- **Response DTO의 시각 필드는 `OffsetDateTime`**이다: `entity.getCreatedAt().atOffset(ZoneOffset.UTC)`. `LocalDateTime`을 그대로 내보내면 JSON에 오프셋이 빠져(`2026-11-19T01:00:00`) 브라우저가 로컬 시간으로 잘못 읽는다. 요청 DTO의 시각도 `OffsetDateTime`으로 받아 UTC로 바꿔 저장한다.
- 단일 도메인만 쓰는 API는 Controller가 Service를 바로 호출해도 된다.

## 3. 공통 응답 / 예외

```java
public record ApiResponse<T>(boolean success, T data, ErrorResponse error) {
    public static <T> ApiResponse<T> ok(T data) { return new ApiResponse<>(true, data, null); }
    public static ApiResponse<Void> fail(ErrorCode code) { return fail(code, List.of()); }
    public static ApiResponse<Void> fail(ErrorCode code, List<FieldError> fieldErrors) {
        return new ApiResponse<>(false, null, ErrorResponse.of(code, fieldErrors));
    }
}
public record ErrorResponse(String code, String message, List<FieldError> fieldErrors) { ... }
public record FieldError(String field, String reason) {}

public interface ErrorCode { HttpStatus status(); String code(); String message(); }
public enum CommonErrorCode implements ErrorCode { INVALID_INPUT, UNAUTHORIZED, FORBIDDEN, NOT_FOUND, CONFLICT, INTERNAL_ERROR ... }  // global, be-api
public enum OrderErrorCode implements ErrorCode { ORDER_001, ... }                                                              // domain/order/exception, be-domain
```

- 예외는 `BusinessException(ErrorCode)` 하나로 통일한다. 도메인별 예외 클래스를 만들지 않는다.
- 에러 코드 형식은 `{DOMAIN}_{NNN}` (예: `ORDER_001`). **코드와 HTTP 상태는 API 명세(`docs/api/{feature}.yaml`)에 정의된 것을 쓴다.** 명세에 없는 코드가 필요하면 "결정 필요"로 올린다.
- **실패 응답은 ErrorCode의 HTTP 상태 코드**로 보내고, 본문은 `ApiResponse.fail(...)` 형식이다. 성공은 2xx + `success: true`.
- `GlobalExceptionHandler`는 **`ResponseEntityExceptionHandler`를 상속**한 `@RestControllerAdvice`다. Spring MVC 표준 예외(잘못된 JSON, 파라미터·헤더 누락, 타입 불일치, 404, 405, 406, 413, 415 등)는 부모가 알맞은 상태 코드로 처리하므로 하나씩 나열하지 않는다. `handleExceptionInternal`을 오버라이드해 모든 응답을 `ApiResponse.fail` 형식으로 감싸고, 검증 실패(`MethodArgumentNotValidException`, `HandlerMethodValidationException`)는 `fieldErrors`를 채운다.
- 그 위에 직접 처리하는 예외 (catch-all보다 구체적인 것이 먼저 잡히도록 각각 `@ExceptionHandler`로 둔다):
  - `BusinessException` → 해당 ErrorCode의 상태
  - `ConstraintViolationException` → 400 + `fieldErrors`
  - `AuthenticationException` → 401, `AccessDeniedException` → 403 (컨트롤러 안의 로그인 실패, `@PreAuthorize` 거부가 500이 되지 않게)
  - `OptimisticLockingFailureException` → 409 (`CommonErrorCode.CONFLICT`)
  - `DataIntegrityViolationException` → 409. 단, 업무상 의미가 있는 유니크 위반은 서비스에서 도메인 ErrorCode로 바꿔서 던진다 (6-1)
  - 그 외 `Exception` → 500. 내부 메시지와 스택트레이스를 응답에 넣지 않는다
- **Spring Security 필터에서 나는 예외는 `@RestControllerAdvice`를 거치지 않는다.** 같은 형식으로 응답하도록 `global/config`에 `AuthenticationEntryPoint`(401, `UNAUTHORIZED`)와 `AccessDeniedHandler`(403)를 등록한다. `AccessDeniedHandler`는 CSRF 실패(`CsrfException`)를 `CSRF_INVALID` 코드로 구분해 응답한다 (프론트가 토큰을 다시 받고 재시도하는 근거).
- try-catch로 예외를 삼키지 않는다. 잡았다면 로그를 남기고 BusinessException으로 변환한다.

## 4. JPA / QueryDSL / MyBatis 사용 기준

위에서부터 고른다. 아래 것을 쓸 이유가 없으면 위의 것을 쓴다.

| 방식 | 쓰는 곳 | 쓰지 않는 곳 |
|---|---|---|
| **Spring Data JPA** (메서드 이름 쿼리, 간단한 `@Query`) | 단건 조회, 조건이 고정된 단순 조회, 생성·수정·삭제, 도메인 로직이 있는 쓰기, 원자적 UPDATE(`@Modifying @Query`, 6-1). **기본값** | 조건이 선택적으로 붙는 검색 |
| **QueryDSL** | 검색 조건이 선택적으로 붙는 목록·검색 조회, 엔티티 연관을 따라가는 조인 조회, 조회 전용 DTO 프로젝션. **조회 전용** | 쓰기(벌크 update·delete 포함), 통계·리포트 SQL |
| **MyBatis** | 통계·리포트처럼 SQL을 직접 다듬어야 하는 조회, 윈도 함수 등 DB 특화 기능, 대량 배치 | 단순 CRUD, 엔티티로 충분한 조회 |

- 같은 테이블 **쓰기**를 여러 방식에서 섞지 않는다. 쓰기는 JPA로만 한다 (영속성 컨텍스트 불일치 방지). 조회는 테이블이 같아도 방식이 달라도 된다.
- 조회 결과는 Entity가 아닌 조회 전용 DTO(`repository/query/`)로 받는다 (Entity를 그대로 쓰면 N+1·변경 감지 위험).
- MyBatis XML에서 `${}` 사용 금지 (정렬 컬럼 등 불가피한 경우 화이트리스트 검증 후 사용). 항상 `#{}`.
- MyBatis 설정(`mybatis.mapper-locations: classpath:mapper/**/*.xml`, `map-underscore-to-camel-case: true`)은 be-api가 application.yml에 둔다.

### 4-1. QueryDSL 규칙
- **버전**: Spring Boot 4(Hibernate 7)에서는 원조 `com.querydsl` 5.x 대신 활발히 관리되는 **OpenFeign 포크 `io.github.openfeign.querydsl`**을 쓴다. Hibernate 7 호환 버전과 APT 설정은 0단계에서 be-api가 실제 컴파일로 확인해 `build.gradle`에 고정하고 리포트에 적는다 (PM이 ADR에 옮긴다).
- **Q타입**: 애노테이션 프로세서(APT)로 빌드 때 생성한다. `build/` 아래에 생기므로 커밋하지 않고, 손으로 고치지 않는다.
- **설정**: `JPAQueryFactory` 빈은 be-api가 `global/config/QuerydslConfig`에 둔다.
- **구조** (be-domain, 도메인별):
  ```
  repository/
  ├── OrderRepository.java              # extends JpaRepository<Order, Long>, OrderRepositoryCustom
  ├── OrderRepositoryCustom.java        # QueryDSL 조회 메서드 선언
  ├── OrderRepositoryImpl.java          # 구현 (이름은 반드시 {Repository}Impl. Spring Data가 이 접미사로 찾는다)
  └── query/OrderSummaryDto.java        # 조회 전용 DTO
  ```
- **동적 조건**: 조건마다 `BooleanExpression`을 돌려주는 private 메서드를 만들고, 값이 없으면 `null`을 돌려준다. `where(a(), b(), c())`는 `null`을 무시한다. 조건 문자열을 직접 이어 붙이지 않는다.
- **프로젝션**: DTO는 `Projections.constructor(...)`로 채운다. DTO에 `@QueryProjection`을 붙여 QueryDSL에 묶지 않는다 (DTO가 다른 계층에서도 쓰이므로).
- **페이징**: 내용은 `offset/limit` + `fetch()`, 개수는 따로 `select(count)` 쿼리로 구하고 `PageableExecutionUtils.getPage(...)`로 필요할 때만 개수 쿼리를 실행한다. 지원이 끊긴 `fetchResults()`, `fetchCount()`를 쓰지 않는다. 결과는 공통 `PageResponse`로 바꾼다 (7장).
- **조인**: N+1 규칙(7장)을 그대로 따른다. 컬렉션 `fetchJoin()` + 페이징 금지.
- **문자열 템플릿 주의**: `Expressions.stringTemplate`·`numberTemplate`에 사용자 입력을 이어 붙이지 않는다. 값은 항상 파라미터(`{0}`)로 넘긴다 (인젝션 방지).
- **dba 리뷰용**: 동적 조건이 있는 쿼리는 조건 조합별로 실제 실행 SQL이 달라지므로, 대표 조합(조건 없음, 자주 쓰는 조합)의 SQL을 리포트에 적는다.

## 5. Entity 규칙

- `@Setter` 금지. 상태 변경은 의미 있는 메서드로 (`member.changeNickname(...)`).
- `@NoArgsConstructor(access = AccessLevel.PROTECTED)` + 정적 팩토리 또는 @Builder(생성자에만).
- 연관관계는 모두 `fetch = FetchType.LAZY`. `@ManyToOne` 기본 EAGER를 반드시 바꾼다.
- 공통 시간 컬럼은 `global/entity/BaseTimeEntity`(@MappedSuperclass, createdAt/updatedAt, Auditing) 상속. Auditing 설정(`@EnableJpaAuditing`)은 be-api가 `global/config/`에 둔다.
- 시간 필드는 UTC 기준 `LocalDateTime`으로 다루고 DB 컬럼은 `DATETIME(6)`이다. API로 내보낼 때는 `OffsetDateTime`(UTC)으로 바꾼다 (2장).
- JVM 기본 타임존은 `main()`이 아니라 `build.gradle`의 `bootRun`·`test` 태스크 `jvmArgs '-Duser.timezone=UTC'`, 운영 Dockerfile의 `-Duser.timezone=UTC`(infra)로 준다. `spring.jpa.properties.hibernate.jdbc.time_zone: UTC`도 둔다. IDE에서 실행해도 시간이 어긋나지 않도록 Auditing에는 UTC 기준 `DateTimeProvider`를 등록한다.
- enum 컬럼은 `@Enumerated(EnumType.STRING)` + DB는 `VARCHAR`. `validate`가 실패하면 컬럼 정의(길이)를 dba 문서와 대조한다.
- 스키마는 DBA가 Flyway 마이그레이션으로 관리한다. `ddl-auto`는 `validate`.

## 6. 트랜잭션

- Service 클래스에 `@Transactional(readOnly = true)`, 쓰기 메서드에만 `@Transactional`. 트랜잭션 안에서 외부 API 호출 등 오래 걸리는 작업을 하지 않는다.

## 6-1. 동시성 (레이스 컨디션)

**모든 쓰기 기능은 "같은 요청이 동시에 두 번 들어오면?"을 검토한다.** 서버는 여러 대, 요청은 여러 스레드로 동시에 처리된다고 가정한다.

- **경합 지점 예시**: 재고·잔액·포인트·쿠폰 수량 차감, 좌석·예약 선점, 중복 가입·중복 신청·중복 결제, 상태 전이(결제대기→결제완료), 조회수·좋아요 수 같은 카운트
- **금지 패턴**
  - 확인 후 실행(check-then-act): `if (!exists(email)) save(...)`, `if (stock >= qty) stock -= qty`를 잠금 없이 실행
  - 읽고-수정하고-쓰기: 엔티티를 읽어 값을 바꾸고 변경 감지로 저장하는 방식으로 공유 값을 증감 (lost update 발생)
  - `synchronized`, JVM 내부 락: 서버가 여러 대면 소용없다
- **대응 방식** (위에서부터 우선 검토)
  1. **DB 유니크 제약**: 중복 가입·중복 신청은 UNIQUE 제약으로 막는다. 사전 조회는 친절한 메시지용일 뿐 방어 수단이 아니다
     - `save()`는 INSERT를 커밋 시점까지 미룰 수 있어 서비스 안에서 위반을 못 잡는다. 위반을 도메인 에러로 바꾸려면 `saveAndFlush()`를 쓰고 `DataIntegrityViolationException`을 잡아 `BusinessException`으로 바꿔 던진다 (잡은 뒤 같은 트랜잭션에서 다른 작업을 계속하지 않는다)
  2. **원자적 UPDATE**: `UPDATE product SET stock = stock - :qty WHERE id = :id AND stock >= :qty` 후 영향받은 행 수가 0이면 실패 처리. 카운트도 `SET cnt = cnt + 1`
     - JPA에서는 `@Modifying(flushAutomatically = true, clearAutomatically = true) @Query`로 작성한다. `clearAutomatically`만 쓰면 아직 반영되지 않은 다른 엔티티 변경이 사라진다
     - `clearAutomatically`는 영속성 컨텍스트를 비우므로 **그 전에 조회한 모든 엔티티가 준영속이 된다.** 이후 그 엔티티를 바꿔도 저장되지 않는다. 원자적 UPDATE를 유스케이스의 마지막 쓰기로 두거나, 실행 후 바꿀 엔티티를 다시 조회한다
  3. **조건부 상태 전이**: `UPDATE orders SET status = 'PAID' WHERE id = :id AND status = 'PENDING'`처럼 이전 상태를 조건에 넣고 영향 행 수로 성공 여부를 판단한다
  4. **낙관적 락** (`@Version`): 충돌이 드문 수정(게시글·프로필 편집). 충돌하면 409로 "다시 시도" 응답하는 것이 기본이다. 자동 재시도가 필요하면 **Application 계층에서 트랜잭션 바깥에서** 새 트랜잭션으로 최대 3회 재시도한다 (같은 트랜잭션 안의 재시도는 소용없다)
  5. **비관적 락** (`@Lock(PESSIMISTIC_WRITE)`, `SELECT ... FOR UPDATE`): 충돌이 잦고 복잡한 검증이 필요한 경우. 잠금 순서를 항상 같게(예: id 오름차순) 해서 데드락을 막고 트랜잭션은 짧게 유지한다
     - 잠금 대기 시간은 DB 설정(`innodb_lock_wait_timeout`)으로 정한다. MySQL에서는 JPA의 `jakarta.persistence.lock.timeout` 힌트가 반영되지 않는다(NOWAIT만 가능). 힌트만 넣고 설정했다고 보고하지 않는다
  6. **멱등성 키**: 업무 키·유니크 제약으로 중복을 막을 수 없는 요청에만 쓴다. 결제, 외부 시스템 호출처럼 되돌릴 수 없는 부수 효과가 있는 요청이 대상이다. 가입·신청처럼 유니크 제약으로 막을 수 있는 생성 요청에는 쓰지 않는다. 같은 키의 두 번째 요청에는 첫 요청의 결과를 돌려준다 (API 명세에 정의)
     - **키 선점과 저장된 응답 조회는 업무 트랜잭션과 다른 트랜잭션**(업무 트랜잭션 시작 전, 또는 `REQUIRES_NEW`)에서 한다. 업무 트랜잭션 안에서 유니크 위반을 잡고 저장된 응답을 돌려주면, 그 트랜잭션이 이미 롤백 전용이라 커밋 때 `UnexpectedRollbackException`(500)이 난다
     - 흐름: ① 키 선점(처리 중, 만료 시각 기록, 별도 트랜잭션) → ② 업무 처리(업무 트랜잭션) → ③ 결과 저장(완료, 별도 트랜잭션). 같은 키가 처리 중이면 409, 완료면 저장된 응답을 돌려준다. 업무가 실패하면 키를 지워 재시도를 허용한다
     - ②와 ③ 사이에 서버가 죽으면 키가 "처리 중"으로 남는다. 만료 시각(예: 10분)이 지난 처리 중 키는 실패로 보고 다시 선점할 수 있게 한다. 결제처럼 실제 처리 여부를 확인해야 하면 외부 시스템 조회로 결과를 맞춘다
  - Redis 분산 락 등 새 인프라가 필요한 방식은 비용이 드므로 "결정 필요"로 올린다
- **MySQL 참고**: 기본 격리 수준(REPEATABLE READ)의 일반 SELECT는 스냅샷을 읽을 뿐 잠그지 않는다. 읽은 값으로 쓰기 판단을 하면 위 방식 중 하나가 필요하다

## 7. N+1 / 성능

- 목록 조회에서 연관 엔티티를 쓰면 반드시 다음 중 하나를 적용한다:
  - `fetch join` 또는 `@EntityGraph` (단일 컬렉션까지)
  - `spring.jpa.properties.hibernate.default_batch_fetch_size: 100` (be-api가 application.yml에 둔다)
- 컬렉션 fetch join + 페이징 조합 금지 (메모리 페이징 발생).
- 목록 API는 항상 페이징한다. `page`는 0부터 시작한다. 응답은 공통 `PageResponse<T>`(`content`, `page`, `size`, `totalElements`, `totalPages`) 또는 커서 방식이면 `CursorPageResponse<T>`(`content`, `nextCursor`, 마지막이면 `nextCursor: null`)로 보낸다. Spring Data `Page`를 그대로 직렬화하지 않는다.
- 조회 조건/정렬 컬럼에 인덱스가 있는지 `docs/db/{feature}.md`로 확인하고, 없으면 작업 결과에 dba 요청 사항으로 포함한다.

## 8. 검증 / 보안 / 로깅

- Request DTO에 Bean Validation(@NotBlank, @Size 등). 비즈니스 검증은 Service에서.
- 비밀번호, 토큰, 개인정보는 로그에 남기지 않는다. 응답에도 화면에 필요한 개인정보만 담고, 필요하면 마스킹한다.
- CSP 등 HTML 보안 헤더는 리버스 프록시(infra)가 설정한다. 백엔드는 CORS, 쿠키 속성, CSRF, 인증·인가를 맡는다.
- **CSRF (SPA 방식)**: Spring Security 7의 `http.csrf(csrf -> csrf.spa())`를 쓴다. JS가 읽을 수 있는 `XSRF-TOKEN` 쿠키를 내려주고 `X-XSRF-TOKEN` 헤더의 원본 토큰을 받는다. 직접 `CookieCsrfTokenRepository`를 조립하지 않는다 (기본 생성자는 HttpOnly이고 기본 요청 핸들러는 마스킹된 토큰을 기대해 SPA에서 403이 난다). 서블릿 context-path를 `/api`로 두지 말고 컨트롤러를 `/api/**`로 매핑한다 (context-path를 쓰면 쿠키 path가 `/api`가 되어 페이지 JS가 못 읽는다).
- **CSRF 토큰은 로그인·로그아웃 때 바뀐다.** 그래서 프론트는 앱 시작과 로그아웃 뒤에 `GET /api/auth/me`를 호출해 새 토큰 쿠키를 받는다 (frontend-conventions 3장). `GET /api/auth/me`는 `permitAll`이고 비로그인이면 `data: null`로 200을 준다.
- 인가: 기본은 인증 필요, 공개 경로(`/api/health`, `/api/auth/me`, 로그인·가입 등)만 `permitAll`. 다른 사용자의 데이터 접근은 Service에서 소유자를 확인한다.

### 8-1. 로그인 구현 (JSON API)
- 담당: 보안 설정, `PasswordEncoder` 빈, `UserDetailsService` 어댑터(`global/security/`), 로그인·로그아웃·me 컨트롤러는 be-api. 회원 조회·가입 규칙·비밀번호 해시 저장은 be-domain의 회원 서비스.
- 컨트롤러에서 직접 로그인할 때는 다음 순서를 모두 지킨다. 하나라도 빠지면 다음 요청이 401이 되거나 세션 고정 공격에 열린다:
  1. `AuthenticationManager.authenticate(UsernamePasswordAuthenticationToken.unauthenticated(...))`
  2. 새 `SecurityContext`를 만들어 인증 정보를 넣고 `SecurityContextHolderStrategy`에 설정
  3. `SecurityContextRepository.saveContext(context, request, response)` (Spring Security 6부터 자동 저장되지 않는다)
  4. `SessionAuthenticationStrategy.onAuthentication(...)` (세션 ID 변경, CSRF 토큰 교체)
- 비밀번호가 틀리면 `AuthenticationException`이 난다 → 401 (3장). 응답에 "아이디가 없음"과 "비밀번호 틀림"을 구분하지 않는다.
- 로그아웃은 Spring Security의 `logout()` 설정을 쓰고, 성공 응답도 `ApiResponse` 형식으로 준다.

## 9. 테스트 (be-reviewer)

- 통합 테스트는 **Testcontainers로 프로젝트와 같은 버전의 MySQL**을 띄운다. H2 등 내장 DB를 쓰지 않는다.
  - 컨테이너는 **`@TestConfiguration` 클래스에 `@Bean @ServiceConnection` MySQL 컨테이너로 정의**하고 모든 통합 테스트가 `@Import`한다. 테스트 클래스의 static `@Container` 필드로 두면 클래스가 끝날 때 컨테이너가 멈추는데 캐시된 스프링 컨텍스트는 재사용되어 다음 클래스에서 연결이 끊긴다
  - 컨테이너 빈은 **스프링 컨텍스트마다 하나씩** 뜬다. 컨텍스트 조합을 줄인다: 통합 테스트는 공통 베이스 클래스 하나를 쓰고, 테스트마다 다른 `@MockitoBean` 조합을 만들지 않는다. 그래도 컨테이너가 많이 떠서 느리거나 메모리가 부족하면 싱글턴 컨테이너(static 초기화 블록에서 한 번만 start)로 바꾸고 리포트에 적는다
  - `@DataJpaTest`, `@MybatisTest`는 `@SpringBootTest` 베이스 클래스를 상속할 수 없으므로 같은 `@TestConfiguration`을 `@Import`하고 `@AutoConfigureTestDatabase(replace = Replace.NONE)`을 붙인다. 붙이지 않으면 내장 DB로 바꾸려 해서 실패한다. 슬라이스 테스트는 일반 설정 클래스를 읽지 않으므로 JPA Auditing 설정과 `QuerydslConfig`(QueryDSL 커스텀 Repository를 쓸 때)도 `@Import`한다 (Auditing이 빠지면 `created_at`이 NULL이 되어 제약 위반, QuerydslConfig가 빠지면 `JPAQueryFactory` 빈이 없어 실패)
  - 테스트 프로필 설정은 be-reviewer가 `src/test/resources/application-test.yml`에만 둔다 (main 쪽에 같은 이름 파일을 두지 않는다. 같은 이름이면 test 쪽 파일이 main 파일을 통째로 가린다)
  - Flyway 마이그레이션이 테스트 DB에도 그대로 적용되게 한다 (스키마 검증 겸용)
- **SmokeTest** (0단계에 be-reviewer가 만든다): 새 컨테이너 DB에 전체 마이그레이션 적용 + `ddl-auto: validate`로 컨텍스트 기동 + `/api/health` 200. 구현 담당과 dba는 이 테스트를 실행해 스키마·엔티티 일치를 확인한다 (`./gradlew test --tests '*SmokeTest'`)
- Service: 단위 테스트(Mockito) 또는 통합 테스트로 핵심 로직 검증.
- Repository/Mapper 커스텀 쿼리: `@DataJpaTest`(QueryDSL 포함) / `@MybatisTest`로 쿼리 검증. QueryDSL 동적 조건은 조건이 없을 때, 하나씩 있을 때, 모두 있을 때를 나눠 검증한다.
- Controller: `@WebMvcTest`로 요청 검증, 응답 형식, 에러 코드와 HTTP 상태.
- **인가·CSRF**: "다른 사용자 데이터 접근 거부"와 CSRF는 Service를 mock하는 `@WebMvcTest`로는 의미가 없다. 실제 보안 설정이 적용되는 통합 테스트로 검증한다. 상태를 바꾸는 요청 하나 이상은 `with(csrf())` 없이 실제 흐름(GET으로 `XSRF-TOKEN` 쿠키 받기 → 헤더에 담아 POST)으로 검증한다.
- 응답의 시각 필드가 `Z`(UTC 오프셋)로 끝나는지 검증한다.
- **동시성 테스트**: `ExecutorService` + `CountDownLatch`로 동시 요청 N개를 보내고 최종 값(재고 음수 없음, 중복 1건, 상태 전이 1회)을 검증한다.
  - 테스트 메서드·클래스에 `@Transactional`을 붙이지 않는다. 붙이면 픽스처가 커밋되지 않아 다른 스레드가 보지 못한다
  - 픽스처는 커밋하고, 테스트가 끝나면 직접 정리한다 (`@AfterEach`에서 삭제 또는 테이블 비우기)
- Docker가 없어 Testcontainers를 띄울 수 없으면 테스트 실패로 보지 말고 "차단됨"으로 보고한다.
- 테스트 이름은 한글 허용: `회원가입_시_중복_이메일이면_예외()`.

## 10. 공통화 / 단순화 원칙

- 같은 로직이 3번 반복되면 공통화한다. 2번까지는 중복을 허용한다 (섣부른 추상화 방지).
- 구현체가 하나뿐인 Service에 인터페이스(XxxService + XxxServiceImpl)를 만들지 않는다.

## 완료 기준 (Definition of Done)

작업 종료 전 자기 역할의 항목을 모두 확인하고 결과를 보고한다.

**구현 담당 (be-domain, be-api)** — 테스트는 쓰지 않는다 (be-reviewer 담당)
- [ ] `./gradlew build -x test` 성공
- [ ] 엔티티·마이그레이션을 바꿨으면 `./gradlew test --tests '*SmokeTest'` 통과 (Docker 필요. 테스트를 쓰는 게 아니라 기존 테스트를 실행한다. 서버를 직접 띄우지 않는다)
- [ ] 리뷰 반려로 재작업했으면 리뷰에 적힌 실패 테스트를 `./gradlew test --tests '...'`로 실행해 통과 확인 (테스트 코드는 고치지 않는다)
- [ ] Entity 직접 반환, @Setter, EAGER 연관관계 없음
- [ ] 목록 조회 N+1 확인 완료
- [ ] 쓰기 기능의 레이스 컨디션 검토 완료 (경합 지점과 대응 방식, 또는 해당 없음과 이유)
- [ ] 새 ErrorCode·API가 있으면 변경 내역에 명시

**리뷰어 (be-reviewer)**
- [ ] `./gradlew test` 전체 통과 (기존 테스트 포함)
- [ ] 동시성 검토 표의 경합 지점마다 동시성 테스트 작성
- [ ] 커버한 인수 조건 번호 기록
