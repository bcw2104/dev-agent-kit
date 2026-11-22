# 리뷰 판정 기준

be-reviewer, fe-reviewer, dba(쿼리 리뷰), security-reviewer가 따른다. QA 판정은 `docs/rules/qa.md`.

## 리뷰 심각도 (be-reviewer, fe-reviewer, dba 쿼리 리뷰, security-reviewer 공통)
| 심각도 | 기준 | 처리 |
|---|---|---|
| **Blocker** | 명세·인수 조건과 다른 동작, 데이터 손상·유실 가능성, 보안 취약점(권한 체크 누락, 인젝션, 민감정보 노출), 레이스 컨디션·중복 요청 대응 누락, 빌드·테스트 실패, 소유권 위반, 핵심 흐름을 키보드로 수행 불가 | 반드시 수정 |
| **Major** | 동작은 맞지만 고쳐야 하는 문제: N+1·인덱스를 못 타는 쿼리, 에러 처리 누락, 컨벤션 중대 위반(Entity 반환, `any` 등), 접근성 위반(label 누락, 명도 대비 부족) | 이번 기능에서 수정. PM이 미루기로 하면 사유를 진행판에 기록하고 재리뷰 대상에서 뺀다 |
| **Minor** | 가독성, 네이밍, 작은 중복 | 구현 담당 판단. 기록만 한다 |

- **APPROVED**: Blocker 0건, Major 0건(PM이 미루기로 기록한 것 제외), 리뷰어가 맡은 테스트 전부 통과. 그 외는 CHANGES_REQUESTED. (dba 쿼리 리뷰는 테스트 조건 없이 Blocker·Major 기준만 적용한다)
- 리뷰 항목마다 고칠 담당을 적는다: `(담당: be-domain | be-api | dba | fe-feature | fe-design-system | infra)`.
- 보안 문제의 심각도 예시는 security-reviewer 지침의 "판정"을 따른다 (악용 가능 = Blocker).
