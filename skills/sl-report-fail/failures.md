# SL 함정 원장

시그니처만 봐서는 알 수 없는 실수를 모은 목록임. SL 코드를 쓰기 전에 읽고, 새 함정을 찾으면 `sl-report-fail` 스킬 절차로 추가함.

심각도:

- `API`: 없는 함수나 틀린 시그니처. 컴파일이 실패함.
- `BEHAVIOR`: 컴파일은 되지만 결과가 틀림. 가장 찾기 어려움.
- `INTENT`: API 는 맞지만 목적에 맞지 않게 씀.

---

## F-001 · API · 없는 파일 대화상자 함수

- **증상**: `function 'xutFileOpen()' is not defined`, `xutFileSave()` 도 같음.
- **원인**: 함수 이름을 추측함. 헤더에 없음.
- **올바른 방법**: `bool xuFileOpenWindow(string title, string filterName, string filter, ref string fileName)` 와 `xuFileSaveWindow` 를 씀. 둘 다 `bool` 을 돌려주고, 고른 경로를 `ref` 인자에 씀.
- **근거**: `fegate_api/api_ui_handle.h` 의 선언, `fegate_api_exam/ui/xu/xuFileOpenWindow.sl`.

## F-002 · BEHAVIOR · array 함수를 matrix 에 씀 (반대도 같음)

- **증상**: `passing argument 1 of 'aryClear()' makes 'ary<void>' from 'mat<string>'`.
- **원인**: `array`(1차원)와 `matrix`(2차원)는 다른 타입임.
- **올바른 방법**: matrix 에는 `matResize`, `matRowSize`, `matColSize`, `matEraseRow`, `matFill` 을 씀. array 에는 `aryAdd`, `aryClear`, `arySize`, `aryEmpty` 를 씀. 섞지 않음.
- **근거**: `fegate_api/api_base_array.h` 의 두 함수 계열 선언.

## F-003 · BEHAVIOR · matResize 가 기존 데이터를 모두 지움

- **증상**: 행을 하나씩 늘리며 `matResize` 로 행렬을 만들면 마지막 행만 남고 앞 행은 0 이 됨.
- **원인**: `matResize` 는 내용을 보존하지 않음. 다시 할당하고 0 으로 채움.
- **올바른 방법**: 행을 먼저 array 에 모으고, 최종 크기를 계산해 `matResize(table, rows, cols)` 를 한 번만 부른 뒤 칸을 채움. 반복문 안에서 `matResize` 를 부르지 않음.
- **근거**: `fegate_api_exam/base/container/matrix/print.sl`. 값이 든 3x3 행렬에 `matResize(m, 2, 2)` 를 부르면 출력이 모두 `0.000` 임.

## F-004 · BEHAVIOR · 예제에도 버그가 있음

- **증상**: 예제를 그대로 복사하면 예제의 결함도 따라옴.
- **원인**: 예제는 참고 자료이고 검수된 코드가 아님. 예: `fegate_api_exam/db/DB_Query_Elem_01.sl` 은 `dbElem::GetNodes(indices[i], ...)` 자리에 반복 변수 `i` 를 넘김.
- **올바른 방법**: 예제는 API 모양과 호출 순서만 참고함. 반복 변수, 인덱스, `ref` 인자는 목적에 맞는지 다시 확인함.
- **근거**: `fegate_api_exam/db/DB_Query_Elem_01.sl` 의 `dbElem::GetNodes(i, n_indices)`.

## F-005 · BEHAVIOR · xutEntity 는 Index 가 아니라 Label 을 돌려줌

- **증상**: `xutEntity(label, DB_ELEM, ref data)` 로 고른 값을 `dbElem::Type` 같은 함수에 바로 넘기면 다른 요소의 정보가 나옴.
- **원인**: `xutEntity` 는 화면에 보이는 Label 을 `ref` 인자에 씀. `dbXxx::` 함수는 내부 Index 를 받음.
- **올바른 방법**: UI 경계에서 한 번 바꿈. `int idx = dbElem::Search(picked_label);` 는 Index 를 돌려주고, 없으면 `-1` 을 돌려줌. 절점은 `dbNode::Search` 를 씀. Label 은 표시와 이름 짓기에만 씀.
- **근거**: `fegate_api/api_ui_handle.h` 의 `xutEntity`, `fegate_api/api_db_elem.h` 의 `dbElem::Search`.

## F-006 · INTENT · tokenStr 는 빈 토큰을 만들지 않음

- **증상**: `tokenStr(tokens, line, " ")` 뒤에 빈 토큰을 거르는 반복문을 추가함. 실행되지 않는 코드가 됨.
- **원인**: `tokenStr` 는 연속된 구분자를 하나로 취급함.
- **올바른 방법**: `tokens` 를 그대로 씀.
- **근거**: FEGate 실행 결과. `"  FR        X      BEND    SHEAR"` 를 공백으로 나누면 토큰 4개(`FR`, `X`, `BEND`, `SHEAR`)가 나옴.

<!-- 새 항목은 이 줄 위에 추가함. 번호는 이어서 매김. -->
