# 프론트엔드 부서 규칙

웹 화면을 만드는 담당(fe-design-system, fe-feature, fe-reviewer, qa, be-api, infra)이 따른다.

## 웹 플랫폼 기준
- **Baseline 목표**는 `docs/rules/stack.md` 표의 "웹 Baseline 목표" 행을 따른다.
- 우선순위:
  - **어떤 웹 API/HTML/CSS 기능을 쓸지** → Baseline 목표 안의 네이티브 기능 우선 (설치된 웹 플랫폼 가이드 스킬이 있으면 그것으로 확인)
  - **폴더 구조, 상태관리, API 클라이언트, 네이밍** → `frontend-conventions`
  - 예: `shared/ui`의 Modal은 frontend-conventions 위치에 두되, 구현은 네이티브 `<dialog>`로 한다.
- 커스텀 JS로 구현하기 전에 같은 일을 하는 네이티브 기능(dialog, popover, details, container queries, 폼 검증 등)이 Baseline 목표 안에 있는지 먼저 확인한다.
