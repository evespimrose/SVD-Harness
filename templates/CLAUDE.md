# CLAUDE.md

FEGate SL 스크립트 프로젝트용 지시임. Claude Code 가 세션마다 이 파일 전체를 읽음. 그래서 짧게 유지함. 상세 절차는 SVD-Harness 의 규칙(`~/.claude/rules/svd-harness/`)과 스킬(`sl-api-lookup`, `sl-report-fail`)에 있음.

## 이 프로젝트

이 절에 프로젝트 목적과 주요 폴더를 적음. 비어 있으면 Claude 가 구조를 매번 다시 찾음.

## 폴더

- `fegate_api/`: FEGate API 헤더(.h). 함수 존재와 시그니처의 정본임. 고치지 않음.
- `fegate_api_exam/`: API 사용 예제(.sl 과 같은 이름의 .py). 호출 패턴 참고용임. 정본이 아님.

## SL 언어 요점 (C 와 다른 점)

- 포인터, 형 변환, `->` 가 없음. 참조 전달은 `ref` 로 함.
- 추가 키워드: `bool string set map vec3 ref foreach_db`.
- 지원 안 함: `goto typedef const unsigned auto register static extern sizeof union`.
- 전처리기는 `#include` 만 있음.
- 사용자 코드도 `namespace` 와 `enum` 을 선언할 수 있음. 다른 파일의 함수는 `#include` 로 가져옴.
- `array`(1차원, `int x[]`)와 `matrix`(2차원, `string t[][]`)는 다른 타입임. 함수도 다름(`ary*`, `mat*`).
- 메모리는 자동으로 관리됨.
- API 는 내부 Index 를 받음. 화면에 보이는 Label 이 아님. Label 은 `dbNode::Search(label)` 같은 `Search` 함수로 Index 로 바꿈.
- DB 항목 순회는 `foreach_db(i, dbNode)` 또는 `First()`, `Next()`, `End()`, `GetAll()` 을 씀.
- `message()` 는 헤더에 없는 언어 내장 출력 함수임.

## 반드시 할 것

1. API 함수, 구조체, 상수를 쓰기 전에 `sl-api-lookup` 스킬로 헤더 선언을 찾음.
2. 인자 개수, 타입, `ref` 인자, `@return` 의 뜻을 확인한 뒤 씀.
3. `sl-report-fail` 스킬의 함정 원장(`failures.md`)을 확인함.

## 하지 말 것

- 헤더에 없는 함수를 쓰거나 비슷한 이름을 지어내지 않음. 예: `xutFileOpen` 은 없음. 실제 함수는 `xuFileOpenWindow` 임.
- 헤더 파일이나 큰 API 문서를 통째로 읽지 않음.
- `fegate_api/` 를 고치지 않음.
- 예제 코드를 검토 없이 복사하지 않음. 예제에도 버그가 있음.
- Label 을 Index 자리에 넘기지 않음.
- 데이터가 든 행렬에 `matResize` 를 쓰지 않음. 내용이 지워짐.
- FEGate 에서 실행하지 않은 코드를 "동작한다"고 보고하지 않음.

## UI 와 기능 분리

- 기능 함수(계산, DB 조회와 수정, 파일 처리)는 UI API(`xu*`, `xut*`, `xud*`, `ui*`)를 부르지 않음.
- UI 콜백(`bt_*` 등)은 위젯 값을 읽고, 기능 함수를 부르고, 결과를 표시함. 계산을 직접 하지 않음.
- 기능 함수는 값을 인자로 받고 결과를 반환값이나 `ref` 인자로 돌려줌. 위젯 핸들을 인자로 받지 않음.

## 완료 보고

- 바꾼 파일 목록, 실행한 확인 명령과 결과, FEGate 에서 사람이 확인할 항목을 적음.
- 응답은 한국어로 씀. 코드 식별자는 원문 그대로 씀.
