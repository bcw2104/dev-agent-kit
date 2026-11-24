# 프론트엔드 부서 규칙

웹 화면을 만드는 담당(fe-design-system, fe-feature, fe-reviewer, qa, be-api, infra)이 따른다.

## 웹 플랫폼 기준
- **Baseline 목표**는 `docs/rules/stack.md` 표의 "웹 Baseline 목표" 행을 따른다.
- 우선순위:
  - **어떤 웹 API/HTML/CSS 기능을 쓸지** → Baseline 목표 안의 네이티브 기능 우선 (설치된 웹 플랫폼 가이드 스킬이 있으면 그것으로 확인)
  - **폴더 구조, 상태관리, API 클라이언트, 네이밍** → `frontend-conventions`
  - 예: `shared/ui`의 Modal은 frontend-conventions 위치에 두되, 구현은 네이티브 `<dialog>`로 한다.
- 커스텀 JS로 구현하기 전에 같은 일을 하는 네이티브 기능(dialog, popover, details, container queries, 폼 검증 등)이 Baseline 목표 안에 있는지 먼저 확인한다.

## 화면 확인은 스크립트로 (토큰 절감)
- 화면을 열어 보는 확인(시각 확인·연동 확인·스크린숏)은 **Playwright 스크립트**로 한다: 스크립트가 화면을 열고 스크린숏을 파일로 저장하고, 확인 결과(요소 존재·문구·가로 넘침·콘솔 오류 수 등)를 **몇 줄로 출력**한다. 스크립트는 작업 폴더 밖(scratchpad)이나 `e2e/`(qa 소유) 기존 도우미를 쓴다.
- Playwright **MCP의 접근성 트리·페이지 스냅샷·스크린숏 반환은 쓰지 않는다**(결과가 커서 토큰을 많이 쓴다). 화면을 사람처럼 하나씩 조작하며 원인을 찾아야 할 때만 예외로 쓰고, 그때도 필요한 영역만 본다. 예외를 썼으면 리포트에 이유를 한 줄 적는다.
- 스크린숏은 `e2e/screenshots/…`에 저장하고 리포트에 경로를 적는다(PM이 파일로 직접 본다).
