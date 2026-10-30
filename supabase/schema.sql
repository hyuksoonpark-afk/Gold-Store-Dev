-- =====================================================================
-- 금거래소 매장관리 앱 · Supabase(PostgreSQL) 스키마 초안
-- 프로토타입(localStorage)의 데이터 구조와 업무 규칙을 옮긴 것입니다.
-- 실행 순서: ① 이 파일(schema.sql) → ② seed_admin.sql (최초 Administrator 계정 연결)
-- 실행 전 Supabase SQL Editor에서 검토하고, 개발용 프로젝트에서 먼저 실행하세요.
-- 로그인: 매장번호 + 아이디 → 내부 이메일(예: S01.mgr@소유한도메인)로 Supabase Auth에 매핑
-- 사용자 생성·비밀번호 초기화는 service role 키를 쓰는 Edge Function(admin-users)에서만 수행
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- 1. 기본 테이블 ----------
create table stores (
  store_code  text primary key,
  store_name  text not null,
  biz_no      text
);

create table profiles (                      -- auth.users 1:1 (사용자 정보·권한)
  id          uuid primary key references auth.users(id) on delete cascade,
  store_code  text not null references stores(store_code),
  login_id    text not null,                 -- 아이디는 같은 매장 안에서만 유일 (아래 unique 참고)
  full_name   text not null,
  tel         text,
  grp         char(1) not null check (grp in ('A','M','S','U')),   -- A/M/S(Sub)/U
  expires_on  date not null default '2099-12-31',
  must_change boolean not null default false,                       -- 임시 비밀번호 → 변경 강제
  active      boolean not null default true,
  unique (store_code, login_id)
);

create table categories (
  store_code text references stores(store_code),
  cat_code   text, cat_name text not null,
  primary key (store_code, cat_code)
);

create table vendors (
  store_code  text references stores(store_code),
  vendor_code text, vendor_name text not null, tel text,
  status text not null default '활성' check (status in ('활성','비활성')),
  memo   text,
  primary key (store_code, vendor_code)
);

create table rates (                         -- 시세 이력 (원/돈, VAT 포함 판매시세)
  store_code text references stores(store_code),
  rate_date  date, round_no int,
  gold int not null, silver int not null, platinum int not null,
  primary key (store_code, rate_date, round_no)
);

create table store_config (                  -- 할인율 설정
  store_code   text primary key references stores(store_code),
  disc_pct     numeric(5,2) not null default 10,    -- 기준시세·단가제: 할인가 = 정상가 ÷ (1+할인율)
  card_pct     numeric(5,2) not null default 3,     -- 카드가 = 정상가 × (1+카드 가산율)
  disc_pub_pct numeric(5,2) not null default 2.5,   -- 공시가제: 할인가 = 정상가 × (1−할인율)
  card_pub_pct numeric(5,2) not null default 3
);

create table holidays (
  store_code text references stores(store_code),
  hday date, name text not null,
  type text not null default '공휴일' check (type in ('공휴일','매장휴무')),
  primary key (store_code, hday)
);

create table products (
  store_code   text references stores(store_code),
  product_code text,                                   -- YYMM + 일련번호 3자리 (자동 생성)
  model_name   text not null,
  cat_code     text not null,
  vendor_code  text not null,
  in_date      date not null,
  material     text not null check (material in ('24','18','14','PT','Ag')),
  color text, purity text, size text,
  total_wt_g   numeric(8,3) not null,
  pure_wt_g    numeric(8,3) not null default 0,         -- 순금(은·백금) 중량
  wt18_g       numeric(8,3) not null default 0,
  wt14_g       numeric(8,3) not null default 0,
  base_labor   int not null default 0,
  stone_labor  int not null default 0,
  vat_flag     smallint not null default 0 check (vat_flag in (0,1)),   -- 0 미포함, 1 포함
  policy       char(1) not null default 'S' check (policy in ('S','U','P')), -- 기준시세/단가제/공시가제
  cost_rate    int,                                     -- S: 매입원가 기준시세(원/돈, 결제일 기준)
  sale_mult    numeric(6,2),                            -- U: 판매 배수
  direct_cost  int,                                     -- U·P: 제품 매입원가
  qty          int not null default 0 check (qty >= 0),
  created_by   uuid references profiles(id), created_at timestamptz default now(),
  primary key (store_code, product_code),
  foreign key (store_code, cat_code)    references categories(store_code, cat_code),
  foreign key (store_code, vendor_code) references vendors(store_code, vendor_code),
  check (policy <> 'S' or coalesce(cost_rate, 0) > 0),
  check (policy <> 'U' or (coalesce(direct_cost, 0) > 0 and coalesce(sale_mult, 0) > 0)),
  check (policy <> 'P' or coalesce(direct_cost, 0) > 0)
);

create table product_photos (                -- 사진 파일은 Storage 버킷 product-photos에 보관
  id bigint generated always as identity primary key,
  store_code text not null, product_code text not null,
  storage_path text not null, sort_no smallint not null default 1 check (sort_no between 1 and 3),
  foreign key (store_code, product_code) references products(store_code, product_code) on delete cascade
);

create table sales (
  sale_id uuid primary key default gen_random_uuid(),
  store_code text not null, product_code text not null,
  qty int not null check (qty > 0),
  price_type text not null check (price_type in ('base','disc','card')),
  amount bigint not null check (amount >= 0),           -- 최종 판매금액(흥정 반영)
  cost   bigint,                                        -- 판매 시점 매입원가 합계(마진용)
  sale_date date not null default current_date,
  created_by uuid not null references profiles(id),
  is_edited boolean not null default false,
  is_canceled boolean not null default false, canceled_at timestamptz,
  foreign key (store_code, product_code) references products(store_code, product_code)
);

create table orders (
  order_id uuid primary key default gen_random_uuid(),
  store_code text not null, product_code text not null,
  status text not null default '주문' check (status in ('주문','업체의뢰','출고대기','출고완료','주문취소')),
  order_date date not null default current_date, due_date date,
  customer_name text, customer_tel text, qty int not null check (qty > 0),
  note text, deposit_note text,                         -- 비고(특별 주문) / 비고(계약금 내역)
  from_spec jsonb not null, to_spec jsonb not null,     -- 재질·순도·사이즈·색상·중량·업체
  base_price bigint, disc_price bigint, card_price bigint,  -- 예정가
  snapshot jsonb,                                       -- 등록 시점 시세·할인율·공시가(수정 시 이 값으로 재계산)
  created_by uuid not null references profiles(id), created_at timestamptz default now(),
  foreign key (store_code, product_code) references products(store_code, product_code)
);

create table order_history (
  id bigint generated always as identity primary key,
  order_id uuid not null references orders(order_id) on delete cascade,
  edited_at timestamptz not null default now(),
  edited_by uuid not null references profiles(id),
  changes jsonb not null                                -- [{"field":"수량","from":"1","to":"2"}, ...]
);

create table cart_items (                                -- 사용자별 장바구니
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  store_code text not null, product_code text not null,
  kind text not null check (kind in ('sale','order')),
  price_type text not null, qty int not null check (qty > 0), amount bigint not null,
  spec jsonb, checked boolean not null default true
);

create table role_permissions (                          -- 기능별 권한표 (이관 기능을 Manager에게 열 때 값만 변경)
  grp char(1) not null, feature text not null, allowed boolean not null default false,
  primary key (grp, feature)
);
insert into role_permissions values ('A','data_import',true),('M','data_import',false),('S','data_import',false),('U','data_import',false);

create table migration_logs (
  id bigint generated always as identity primary key,
  store_code text not null, done_by uuid references profiles(id),
  mode text not null check (mode in ('skip','over')), file_name text,
  result jsonb, done_at timestamptz not null default now()
);

create index on products (store_code, in_date desc);
create index on sales (store_code, sale_date desc);
create index on orders (store_code, status, due_date);

-- ---------- 2. 권한 도우미 함수 ----------
create function my_store() returns text language sql stable security definer set search_path = public
as $$ select store_code from profiles where id = auth.uid() and active and expires_on >= current_date $$;
create function my_grp() returns char language sql stable security definer set search_path = public
as $$ select grp from profiles where id = auth.uid() and active and expires_on >= current_date $$;
create function can_do(f text) returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select allowed from role_permissions where grp = my_grp() and feature = f), false) $$;

-- ---------- 3. RLS ----------
do $$ declare t text; begin
  foreach t in array array['stores','profiles','categories','vendors','rates','store_config','holidays','products',
    'product_photos','sales','orders','order_history','cart_items','role_permissions','migration_logs']
  loop execute format('alter table %I enable row level security', t); end loop;
end $$;

-- 매장 단위 마스터: 같은 매장 사용자 조회 / M·S 쓰기 / Administrator 전체
do $$ declare t text; begin
  foreach t in array array['categories','vendors','rates','store_config','holidays'] loop
    execute format($f$create policy %1$s_sel on %1$I for select using (my_grp()='A' or store_code = my_store())$f$, t);
    execute format($f$create policy %1$s_w on %1$I for all
      using (my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()))
      with check (my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()))$f$, t);
  end loop;
end $$;

create policy stores_sel on stores for select using (my_grp()='A' or store_code = my_store());
create policy stores_w   on stores for all using (my_grp()='A') with check (my_grp()='A');

create policy prof_sel on profiles for select
  using (id = auth.uid() or my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()));
-- profiles의 추가·변경·삭제는 Edge Function(service role)에서만 수행 (정책 없음 = 직접 변경 불가)

-- 제품 원본(매입원가 포함)은 A·M·S만 직접 조회. 직원(U)은 아래 products_staff 뷰와 product_prices() 사용
create policy prod_sel on products for select
  using (my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()));
create policy prod_w on products for all
  using (my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()))
  with check (my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()));

create policy photo_sel on product_photos for select using (my_grp()='A' or store_code = my_store());
create policy photo_w   on product_photos for all
  using (my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()))
  with check (my_grp()='A' or (my_grp() in ('M','S') and store_code = my_store()));

-- 판매: 같은 매장 조회 / 직접 등록·수정은 RPC 사용(재고 정합성) / 정책은 조회만 열어 둠
create policy sales_sel on sales for select using (my_grp()='A' or store_code = my_store());

-- 주문: 같은 매장 조회·등록. 수정은 상태가 '주문'이고 (M·S 또는 본인 등록)일 때만
create policy ord_sel on orders for select using (my_grp()='A' or store_code = my_store());
create policy ord_ins on orders for insert with check (store_code = my_store() and created_by = auth.uid());
create policy ord_upd on orders for update
  using (store_code = my_store() and status = '주문' and (my_grp() in ('M','S') or created_by = auth.uid()))
  with check (store_code = my_store());
-- 상태 변경(주문→업체의뢰→…)은 update_order_status() RPC로 처리

create policy hist_sel on order_history for select
  using (exists (select 1 from orders o where o.order_id = order_history.order_id and (my_grp()='A' or o.store_code = my_store())));
create policy cart_own on cart_items for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy perm_sel on role_permissions for select using (true);
create policy mig_sel  on migration_logs for select using (my_grp()='A' or (can_do('data_import') and store_code = my_store()));

-- ---------- 4. 직원용 제품 뷰 (매입원가·마진·입고일 제외) ----------
create view products_staff with (security_invoker = false) as
  select store_code, product_code, model_name, cat_code, vendor_code, material, color, purity, size,
         total_wt_g, pure_wt_g, wt18_g, wt14_g, base_labor + stone_labor as labor_sum, policy, qty
  from products where store_code = my_store();
grant select on products_staff to authenticated;

-- ---------- 5. 가격 계산 (서버 계산: 직원이 매입원가를 보지 않고도 판매가를 받음) ----------
create function product_prices(p_store text, p_code text, p_pub numeric default null)
returns table(base numeric, disc numeric, card numeric)
language plpgsql stable security definer set search_path = public as $$
declare pr products%rowtype; r rates%rowtype; c store_config%rowtype;
        conv numeric; perdon numeric; vf numeric; tag numeric; b numeric; d numeric; k numeric;
begin
  if my_grp() is null or (p_store is distinct from my_store() and my_grp() <> 'A') then raise exception 'forbidden'; end if;
  select * into pr from products where store_code = p_store and product_code = p_code;
  if not found then raise exception '제품 없음'; end if;
  select * into r  from rates where store_code = p_store order by rate_date desc, round_no desc limit 1;
  select * into c  from store_config where store_code = p_store;
  conv   := case when pr.material in ('24','PT','Ag') then pr.pure_wt_g
                 else pr.pure_wt_g + pr.wt18_g*0.825 + pr.wt14_g*0.6435 end;
  perdon := case pr.material when 'PT' then r.platinum when 'Ag' then r.silver else r.gold end;
  vf  := case when pr.vat_flag = 0 then 1.1 else 1 end;
  tag := ceil((pr.base_labor + pr.stone_labor) * 2.5 * vf / 100) * 100;                -- 세공비
  b := case pr.policy when 'U' then pr.direct_cost * vf * pr.sale_mult
                      when 'P' then coalesce(p_pub, 0)
                      else perdon / 3.75 * conv + tag end;
  b := round(b / 1000) * 1000;                                                         -- 천원 단위(백원에서 반올림)
  if pr.policy = 'P' then d := c.disc_pub_pct; k := c.card_pub_pct; else d := c.disc_pct; k := c.card_pct; end if;
  return query select b,
    round((case when pr.policy = 'P' then b * (1 - d/100) else b / (1 + d/100) end) / 1000) * 1000,
    round(b * (1 + k/100) / 1000) * 1000;
end $$;

-- ---------- 6. 판매 등록·취소·상태 변경 RPC (재고 정합성은 DB에서 보장) ----------
create function register_sale(p_code text, p_qty int, p_type text, p_amount bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare s text := my_store(); pr products%rowtype; id uuid; unit_cost numeric;
begin
  if coalesce(my_grp()::text, '') not in ('M','S','U') then raise exception 'forbidden'; end if;
  select * into pr from products where store_code = s and product_code = p_code for update;
  if not found or pr.qty < p_qty then raise exception '재고 부족'; end if;
  unit_cost := case pr.policy when 'S' then (pr.cost_rate / 3.75) *
                 (case when pr.material in ('24','PT','Ag') then pr.pure_wt_g else pr.pure_wt_g + pr.wt18_g*0.825 + pr.wt14_g*0.6435 end)
                 + pr.base_labor + pr.stone_labor
               else pr.direct_cost end;
  update products set qty = qty - p_qty where store_code = s and product_code = p_code;
  insert into sales(store_code, product_code, qty, price_type, amount, cost, created_by)
    values (s, p_code, p_qty, p_type, p_amount, round(unit_cost * p_qty), auth.uid()) returning sale_id into id;
  return id;
end $$;

create function cancel_sale(p_sale uuid) returns void language plpgsql security definer set search_path = public as $$
declare sl sales%rowtype;
begin
  select * into sl from sales where sale_id = p_sale for update;
  if not found or sl.is_canceled or sl.store_code is distinct from my_store() then raise exception '취소할 수 없는 판매'; end if;
  if coalesce(my_grp()::text, '') not in ('M','S') and sl.created_by <> auth.uid() then raise exception '권한 없음'; end if;
  update products set qty = qty + sl.qty where store_code = sl.store_code and product_code = sl.product_code;
  update sales set is_canceled = true, canceled_at = now() where sale_id = p_sale;
end $$;

create function update_order_status(p_order uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_status not in ('주문','업체의뢰','출고대기','출고완료','주문취소') then raise exception '잘못된 상태'; end if;
  update orders set status = p_status where order_id = p_order and store_code = my_store();
end $$;

-- ---------- 6-1. 로그인 보조 (1단계) ----------
create or replace function clear_must_change() returns void
language sql security definer set search_path = public as $$
  update profiles set must_change = false where id = auth.uid()
$$;
revoke all on function clear_must_change() from public, anon;
grant execute on function clear_must_change() to authenticated;

-- ---------- 7. 함수·뷰 실행 권한 (로그인한 사용자만) ----------
revoke all on function product_prices(text,text,numeric), register_sale(text,int,text,bigint), cancel_sale(uuid), update_order_status(uuid,text) from public, anon;
grant execute on function product_prices(text,text,numeric), register_sale(text,int,text,bigint), cancel_sale(uuid), update_order_status(uuid,text) to authenticated;
revoke all on products_staff from anon;

-- ---------- 8. Storage (사진) ----------
-- 대시보드에서 버킷 product-photos 를 비공개로 생성하고, 경로 규칙: {store_code}/{product_code}/{n}.jpg
-- Storage 정책 예: 경로의 첫 폴더(store_code)가 my_store() 와 같은 사용자만 읽기, M·S만 업로드.
