-- 1단계(로그인 전환) 추가 SQL — schema.sql 실행 후 SQL Editor에서 1회 실행
-- 본인 계정의 '임시 비밀번호 변경 필요' 표시만 해제하는 함수 (다른 컬럼은 변경 불가)
create or replace function clear_must_change() returns void
language sql security definer set search_path = public as $$
  update profiles set must_change = false where id = auth.uid()
$$;
revoke all on function clear_must_change() from public, anon;
grant execute on function clear_must_change() to authenticated;
