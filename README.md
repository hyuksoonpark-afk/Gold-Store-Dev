# 금거래소 매장관리 앱

제품 조회·판매·주문·시세 관리와 마스터 정보(업체, 분류, 할인율, 직원, 휴무일)를 다루는 매장 관리 앱입니다.

## 현재 단계
- **로그인·사용자·매장 관리: Supabase 사용** (이 배포본은 `APP_CONFIG.MODE = 'supabase'`)
- **마스터 데이터(업체, 분류, 시세, 할인율, 휴무일): Supabase 사용** (2-1단계 완료)
- **제품·사진: Supabase 사용** (2-2단계 완료, 직원에게는 매입원가가 DB에서 차단됨)
- **판매·판매 현황·장바구니: Supabase 사용** (2-3단계 완료, 재고 증감은 서버 함수로 처리)
- **주문: 아직 브라우저 저장소** → 2-4단계에서 Supabase로 교체 예정

## 폴더 구성
| 경로 | 설명 |
|---|---|
| `index.html` | 앱 전체 (Netlify가 그대로 배포) |
| `netlify.toml` | 배포 설정 (빌드 없음) |
| `supabase/schema.sql` | 테이블·권한 정책(RLS)·서버 함수 |
| `supabase/seed_admin.sql` | 최초 Administrator 계정 연결 |
| `supabase/step1_auth.sql` | 1단계 보조 함수 (schema.sql을 이미 실행했다면 추가 실행) |
| `supabase/step2_sales.sql` | 2-3단계: 판매 등록·취소·수정 함수, 직원용 판매 뷰, 기간 합계 함수 |
| `supabase/step2_products.sql` | 2-2단계: 직원용 제품 뷰 교체, 사진 저장소(버킷·권한) 생성 |
| `supabase/step_unique_login.sql` | 이미 실행한 DB에서 아이디를 **매장별로 유일**하게 바꾸는 SQL |
| `supabase/functions/admin-users/index.ts` | 계정 생성·비밀번호 초기화 Edge Function |
| `templates/금거래소_데이터이관_템플릿.xlsx` | 기존 매장 자료 이관용 엑셀 템플릿 |
| `docs/마진계산_규칙_계산기.xlsx` | 마진 계산 규칙 |

## 설정 위치 (index.html 맨 위 APP_CONFIG)
| 항목 | 설명 |
|---|---|
| `SUPABASE_URL` / `SUPABASE_KEY` | 프로젝트 주소와 **Publishable Key**(공개 가능) |
| `MODE` | `'supabase'` = Supabase 로그인, `'local'` = 브라우저 저장(체험용) |
| `AUTH_DOMAIN` | 로그인 계정의 내부 이메일 도메인(현재 `goldstore-dev.netlify.app`). 로그인 ID는 `매장번호.아이디@AUTH_DOMAIN` 으로 변환됩니다. Edge Function의 Secrets `AUTH_DOMAIN`과 같은 값이어야 합니다 |

- **Secret key / service_role 키는 이 저장소에 절대 올리지 마세요.** (Edge Function은 Supabase가 자동 제공하는 값을 씁니다.)

## 아이디 규칙
사용자 아이디는 **같은 매장 안에서만 중복되지 않으면** 됩니다(다른 매장과 같아도 됨). 로그인은 매장번호와 아이디를 함께 입력합니다.

## 1단계 설치 순서
1. Supabase SQL Editor: `schema.sql` 실행 (이미 실행했다면 `step1_auth.sql`, `step_unique_login.sql`을 순서대로 실행)
2. Authentication: 관리자 사용자 생성(이메일 `000.admin@도메인`) → `seed_admin.sql` 실행, 외부 회원가입 끄기
3. Edge Functions: `admin-users` 배포, Secrets에 `AUTH_DOMAIN` 등록
4. `index.html`의 `AUTH_DOMAIN`은 이미 설정되어 있음(Secrets 값과 동일해야 함) → GitHub에 올리면 Netlify가 자동 배포
5. 로그인 → 직원 계정 생성 → 그 계정으로 로그인·비밀번호 변경 확인
