---
name: sl-api-lookup
description: FEGate SL API 함수, 구조체, 상수를 쓰기 전에 fegate_api 헤더에서 정확한 선언과 설명(HELP_FUN, HELP_STRUCT, #define)을 찾고 사용 예제 경로를 보여 줌. SL 코드 작성·수정·리뷰, "이 함수 있어?", 시그니처 확인, 없는 함수 대신 쓸 실제 함수 찾기에 사용.
---

# sl-api-lookup

헤더 전체를 읽지 않고 필요한 선언 블록만 뽑음. 헤더 38개는 4만 줄이 넘어서 통째로 읽으면 컨텍스트를 낭비함.

## 실행

이 스킬 폴더의 `scripts/Find-SlApi.ps1` 을 실행함.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "<이 스킬 폴더>/scripts/Find-SlApi.ps1" -Name "dbNode::First" -Root "<SL 프로젝트 루트>"
```

| 매개변수 | 뜻 |
|---|---|
| `-Name` | 찾을 이름. `dbNode::First`, `First`(메서드 이름만), `xut*`(와일드카드), `stPair`, `DB_NODE` 모두 됨 |
| `-Root` | `fegate_api/` 가 있는 폴더. 생략하면 현재 폴더에서 위로 올라가며 찾음 |
| `-Max` | 보여 줄 블록 수. 기본 5 |
| `-NoExample` | 예제 경로 찾기를 건너뜀 |

이름 대소문자를 구분함. SL 이 대소문자를 구분하기 때문임.

## 출력 읽기

- 찾으면 헤더 경로와 줄 번호, `HELP_FUN` 블록 원문, 그 이름을 쓰는 예제 .sl 경로를 보여 줌.
- `@in`, `@out` 은 인자, `@return` 은 반환값의 뜻임. `ref` 가 붙은 인자는 함수가 값을 써 넣음.
- 못 찾으면 `없음` 과 비슷한 실제 이름을 보여 줌. 그 목록 밖의 이름을 쓰지 않음. 목록에서 고른 이름도 다시 조회해 선언을 확인함.

## 스크립트를 쓸 수 없을 때

`fegate_api/*.h` 에서 이름을 검색하고, 찾은 줄 앞뒤 30줄만 읽음. 헤더 파일 전체를 읽지 않음.
