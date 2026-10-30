-- 이미 schema.sql 을 실행한 DB에서 "아이디 유일 범위"를 전체 → 매장별로 바꾸는 SQL (1회 실행)
-- 같은 매장 안에서는 아이디가 중복될 수 없고, 다른 매장에는 같은 아이디를 쓸 수 있습니다.
alter table profiles drop constraint if exists profiles_login_id_key;
alter table profiles add constraint profiles_store_login_uk unique (store_code, login_id);
