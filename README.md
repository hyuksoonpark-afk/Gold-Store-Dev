# 금거래소 매장관리 앱

제품 조회·판매·주문·시세 관리와 마스터 정보(업체, 분류, 할인율, 직원, 휴무일)를 다루는 매장 관리 앱입니다.
현재 `index.html` 하나로 동작하며, 데이터는 브라우저 저장소를 사용하는 프로토타입 단계입니다.

## 폴더 구성
| 경로 | 설명 |
|---|---|
| `index.html` | 앱 전체 (Netlify가 그대로 배포) |
| `netlify.toml` | 배포 설정 (빌드 없음) |
| `supabase/schema.sql` | 테이블·권한 정책(RLS)·서버 함수 (Supabase SQL Editor에서 실행) |
| `supabase/seed_admin.sql` | 최초 Administrator 계정 연결 |
| `templates/금거래소_데이터이관_템플릿.xlsx` | 기존 매장 자료 이관용 엑셀 템플릿 |
| `docs/마진계산_규칙_계산기.xlsx` | 마진 계산 규칙 정리와 계산기 |

## Supabase 연결 정보
`index.html` 맨 위 `APP_CONFIG`에 프로젝트 주소와 **Publishable Key**가 들어 있습니다.
- Publishable Key는 공개되어도 되는 키입니다. 단, 모든 테이블에 RLS(행 단위 보안)가 켜져 있어야 안전합니다(`schema.sql`에 포함).
- **Secret key / service_role 키는 이 저장소에 절대 올리지 마세요.**

## 설치 순서
1. Supabase: `supabase/schema.sql` 실행 → Authentication에서 관리자 사용자 생성 → `supabase/seed_admin.sql` 실행
2. GitHub: 이 폴더의 내용을 저장소에 업로드
3. Netlify: GitHub 저장소를 가져와 배포 (빌드 명령 없음, 게시 폴더 `.`)
4. 앱에 Administrator로 로그인 → 데이터 이관 메뉴 → "연결 확인"

## 다음 개발 단계
프로토타입의 저장소(localStorage)를 Supabase 호출로 교체하고, 로그인을 Supabase Auth로 바꿉니다.
