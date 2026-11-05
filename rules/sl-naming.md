---
paths:
  - "**/*.sl"
---

# SL 이름 규칙

SL 코드를 읽거나 쓸 때 적용함. 기준은 이 하네스를 만들 때 센 실제 자료임. `fegate_api/` 헤더 38개(HELP_FUN 선언 1,678개)와 `fegate_api_exam/` 예제 .sl 542개임.

## API 가 쓰는 이름

읽을 때 알아 둘 형태임. 이 형태로 API 와 사용자 코드를 구분함.

| 대상 | 형태 | 예 |
|---|---|---|
| 네임스페이스 | 소문자 분류 접두사 + PascalCase | `dbNode`, `dbElem`, `uiStep`, `xlTool`, `utDisp` |
| 네임스페이스 함수 | PascalCase | `dbNode::First`, `dbElem::GetAll`, `dbElem::Search` |
| 자유 함수 | 소문자 계열 접두사 + PascalCase | `aryAdd`, `strFindFirstOf`, `xuFileOpenWindow`, `msgLog` |
| 구조체 | `st` + PascalCase | `stPair`, `stNumSys` |
| 상수 | 대문자와 밑줄 | `DB_NODE`, `ELEM_ROD` |
| 매개변수 | 소문자 한 단어 또는 snake_case | `index`, `label`, `entity_type`, `bdry_nodes` |

선언 1,678개 중 1,291개가 `네임스페이스::함수` 형태임. 헤더 매개변수의 고유 이름 522개 중 snake_case 가 134개, camelCase 가 19개이고 나머지는 한 단어임.

자유 함수 계열 접두사:

| 접두사 | 영역 |
|---|---|
| `ary`, `mat`, `set`, `map` | 배열, 행렬, 집합, 맵 |
| `str`, `token` | 문자열 |
| `fi` | 파일 시스템(경로, 파일 목록) |
| `fd` | 파일 핸들(열기, 읽기, 쓰기) |
| `msg` | 로그와 상태 표시줄 메시지 |
| `bit` | 비트 연산 |
| `xu`, `xut`, `xud` | UI 위젯 |
| `ui` | UI 시작과 실행 |

`message()` 는 헤더에 없는 언어 내장 출력 함수임.

## 새로 쓰는 코드의 이름

| 대상 | 규칙 | 예 | 근거 |
|---|---|---|---|
| 사용자 함수 | snake_case | `create_gui`, `count_free_nodes` | 예제 사용자 함수 대부분이 snake_case(`create_gui` 111회, `define_step` 27회) |
| 지역 변수 | snake_case | `n_elem`, `node_indices` | 예제 지역 변수 고유 이름 569개 중 snake_case 197개, camelCase 97개 |
| 버튼 콜백 | `bt_` 접두사 | `bt_apply` | 예제의 `bt_clicked`, `bt_activate` |
| 위젯 핸들 변수 | `_wg` 접미사 | `apply_wg` | 예제의 `Check1_wg`, `Combo1_wg` |
| 사용자 구조체 | `st` + PascalCase | `stFrameInfo` | API 구조체와 같은 형태 |

## 금지

- 사용자 함수에 API 형태 이름(계열 접두사 + PascalCase, 예: `strTrimAll`)을 쓰지 않음. API 와 구분되지 않고 `sl-api-check` 훅이 없는 API 로 판단함.
- API 함수나 `fegate_api/structs.h` 구조체와 같은 이름을 쓰지 않음.
- 한 파일 안에서 snake_case 와 camelCase 를 섞지 않음. 기존 파일을 고칠 때는 그 파일의 방식을 따름.
