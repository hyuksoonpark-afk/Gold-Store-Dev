-- =====================================================================
-- 최초 Administrator 계정 연결 (schema.sql 실행 후 1회)
-- 1) Supabase 대시보드 > Authentication > Users > Add user > Create new user
--      이메일: 000.admin@소유한도메인   (매장번호.아이디@도메인 형식)
--      비밀번호: 임시 비밀번호 지정, "Auto Confirm User" 체크
-- 2) 만들어진 사용자의 UID(uuid)를 복사해 아래 'ADMIN-UID-HERE' 를 바꾼 뒤 실행
-- =====================================================================

insert into stores (store_code, store_name, biz_no) values ('000', '본사', '-')
  on conflict (store_code) do nothing;

insert into profiles (id, store_code, login_id, full_name, grp, must_change)
values ('ADMIN-UID-HERE', '000', 'admin', '시스템관리자', 'A', true);

-- (선택) 테스트 매장 1개와 기본 설정
-- insert into stores (store_code, store_name, biz_no) values ('S01', '경주금거래소', '123-45-67890');
-- insert into store_config (store_code) values ('S01');
