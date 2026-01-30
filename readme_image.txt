```markdown
# 젤리패밀리 (JellyFamily) — 디자인 리소스 가이드 (README)

이 문서는 `image_4.png`에 포함된 디자인 리소스를 개발 프로젝트에 적용하기 위해 분할하고 활용하는 방법을 설명합니다. Codex 또는 개발자는 이 가이드를 따라 이미지를 개별 에셋으로 추출하여 사용하시기 바랍니다.

## 원본 이미지

모든 리소스는 아래 이미지에서 추출합니다.

[image_4.png]

---

## 1. 이미지 분할 및 파일명 가이드

`image_4.png`를 다음 세 구역으로 나누어 개별 파일로 저장합니다.

### 1.1 앱 아이콘 (App Icon)

* **위치:** 원본 이미지의 왼쪽 큰 정사각형 영역.
* **설명:** 앱 설치 시 홈 화면 및 앱 목록에 표시되는 아이콘입니다. 가족 캐릭터와 '용돈+성장'을 상징하는 코인/새싹이 포함되어 있습니다.
* **권장 파일명:**
    * Android: `ic_launcher.png` (각 해상도별 디렉토리에 배치)
    * iOS: `AppIcon` (에셋 카탈로그 사용)

### 1.2 스플래시 화면 (Splash Screen)

* **위치:** 원본 이미지의 오른쪽 상단 가로형 영역.
* **설명:** 앱 실행 시 처음 나타나는 로딩 화면입니다. 앱 로고("젤리패밀리")와 슬로건("우리 가족 용돈 챌린지"), 그리고 젤리 가족의 활동 모습이 담겨 있습니다.
* **권장 파일명:** `splash_bg.png` 또는 `splash_screen.png`
* **참고:** 다양한 기기 화면 비율에 맞춰 배경이 잘리거나 늘어날 수 있음을 고려하여 배치해야 합니다.

### 1.3 UI 아이콘 (UI Icons)

* **위치:** 원본 이미지의 오른쪽 하단 영역.
* **설명:** 앱 내에서 사용되는 각종 아이콘 모음입니다. 각 아이콘을 개별 PNG 파일(투명 배경)로 분할하여 사용합니다.

#### [cite_start]젤리 타입 (Jelly Types) [cite: 10]

DB의 `public.jelly_type` enum과 매핑됩니다.

| 아이콘 이미지 | 설명 | 권장 파일명 | DB Enum 값 |
| :---: | :--- | :--- | :--- |
| (노란 곰) | 기본 젤리 | `jelly_normal.png` | `'NORMAL'` |
| (무지개 별) | 스페셜 젤리 | `jelly_special.png` | `'SPECIAL'` |
| (날개 상자) | 보너스 젤리 | `jelly_bonus.png` | `'BONUS'` |

#### [cite_start]챌린지 타입 (Challenge Types) [cite: 11]

DB의 `public.challenge_type` enum과 매핑됩니다.

| 아이콘 이미지 | 설명 | 권장 파일명 | DB Enum 값 |
| :---: | :--- | :--- | :--- |
| (책과 안경) | 독서 | `ic_challenge_reading.png` | `'BOOK_READING'` |
| (숫자와 연필) | 연산 | `ic_challenge_arithmetic.png` | `'ARITHMETIC'` |
| (붓과 한자) | 한자 쓰기 | `ic_challenge_hanja.png` | `'HANJA_WRITING'` |

#### 상태 및 기타 (Status & Others)

주요 기능 및 상태를 나타내는 아이콘입니다.

| 아이콘 이미지 | 설명 | 권장 파일명 | 관련 기능/상태 |
| :---: | :--- | :--- | :--- |
| (알람시계) | [cite_start]젤리 지급 가능 시간 (06:00~08:00) 표시 [cite: 2, 58] | `ic_time_grant.png` | 부모 지급 화면 |
| (손 내민 젤리)| [cite_start]용돈 요청 중 상태 표시 [cite: 12] | `ic_status_requested.png`| `allowance_status` = `'REQUESTED'` |
| (지갑과 체크)| [cite_start]정산 완료 (0원) 상태 표시 [cite: 2, 12] | `ic_status_settled.png` | `allowance_status` = `'SETTLED'` |

---

## 2. 디렉토리 구조 예시 (Flutter 기준)

추출한 이미지들을 프로젝트 내에서 다음과 같이 관리하는 것을 권장합니다.


```

/assets
/images
/icon
ic_launcher.png
/splash
splash_screen.png
/ui
/jelly
jelly_normal.png
jelly_special.png
jelly_bonus.png
/challenge
ic_challenge_reading.png
ic_challenge_arithmetic.png
ic_challenge_hanja.png
/status
ic_time_grant.png
ic_status_requested.png
ic_status_settled.png

```

## 3. 주의사항

* **해상도:** 모바일 앱 특성상 다양한 화면 밀도(DPI)에 대응하기 위해, 추출한 원본 이미지를 기준으로 2x, 3x 등의 고해상도 버전을 추가로 생성해야 할 수 있습니다.
* **투명도:** UI 아이콘들은 배경이 투명한 PNG 형식으로 저장되어야 다양한 배경색 위에서도 자연스럽게 표시됩니다.

```