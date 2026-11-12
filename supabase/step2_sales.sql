-- 2-3단계(판매·장바구니) SQL — SQL Editor에서 1회 실행 (step2_products.sql 실행 후)

-- 1) 판매 테이블 보강: 등록자 이름, 등록 시각
alter table sales add column if not exists created_by_name text;
alter table sales add column if not exists created_at timestamptz not null default now();

-- 2) 매입원가(cost)가 들어 있는 판매 원본은 Administrator·Manager·S만 조회.
--    직원(User)은 원가 열이 빠진 sales_staff 뷰만 읽습니다.
drop policy if exists sales_sel on sales;
create policy sales_sel on sales for select
  using (my_grp() = 'A' or (my_grp() in ('M','S') and store_code = my_store()));

create or replace view sales_staff with (security_invoker = false) as
  select sale_id, store_code, product_code, qty, price_type, amount, sale_date, created_at,
         created_by, created_by_name, is_edited, is_canceled, canceled_at
  from sales where store_code = my_store();
grant select on sales_staff to authenticated;
revoke all on sales_staff from anon;

-- 3) 판매 등록 (재고 차감과 판매 기록을 한 번에, 날짜는 한국 시간 기준)
create or replace function register_sale(p_code text, p_qty int, p_type text, p_amount bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare s text := my_store(); pr products%rowtype; sid uuid; unit_cost numeric; nm text;
begin
  if coalesce(my_grp()::text, '') not in ('M','S','U') then raise exception '권한이 없습니다'; end if;
  if p_qty is null or p_qty <= 0 then raise exception '수량을 확인하세요'; end if;
  if p_type not in ('base','disc','card') then raise exception '가격 구분이 올바르지 않습니다'; end if;
  if p_amount is null or p_amount < 0 then raise exception '판매금액을 확인하세요'; end if;
  select * into pr from products where store_code = s and product_code = p_code for update;
  if not found then raise exception '제품을 찾을 수 없습니다'; end if;
  if pr.qty < p_qty then raise exception '재고 부족 (재고 %개)', pr.qty; end if;
  unit_cost := case pr.policy
    when 'S' then (pr.cost_rate / 3.75) *
         (case when pr.material in ('24','PT','Ag') then pr.pure_wt_g
               else pr.pure_wt_g + pr.wt18_g * 0.825 + pr.wt14_g * 0.6435 end)
         + pr.base_labor + pr.stone_labor
    else pr.direct_cost end;
  select full_name into nm from profiles where id = auth.uid();
  update products set qty = qty - p_qty where store_code = s and product_code = p_code;
  insert into sales(store_code, product_code, qty, price_type, amount, cost, sale_date, created_by, created_by_name)
    values (s, p_code, p_qty, p_type, p_amount, round(unit_cost * p_qty),
            (now() at time zone 'Asia/Seoul')::date, auth.uid(), nm)
    returning sale_id into sid;
  return sid;
end $$;

-- 4) 판매 취소 (재고 복구). Manager·S는 모든 건, User는 본인이 당일 등록한 건만
create or replace function cancel_sale(p_sale uuid) returns void
language plpgsql security definer set search_path = public as $$
declare sl sales%rowtype;
begin
  select * into sl from sales where sale_id = p_sale for update;
  if not found or sl.is_canceled or sl.store_code is distinct from my_store() then
    raise exception '취소할 수 없는 판매입니다'; end if;
  if coalesce(my_grp()::text, '') not in ('M','S')
     and (sl.created_by <> auth.uid() or sl.sale_date <> (now() at time zone 'Asia/Seoul')::date) then
    raise exception '본인이 당일 등록한 판매만 취소할 수 있습니다'; end if;
  update products set qty = qty + sl.qty where store_code = sl.store_code and product_code = sl.product_code;
  update sales set is_canceled = true, canceled_at = now() where sale_id = p_sale;
end $$;

-- 5) 판매 수정 (수량·가격 구분·최종 판매금액, 수량 변경분은 재고에 반영)
create or replace function update_sale(p_sale uuid, p_qty int, p_type text, p_amount bigint) returns void
language plpgsql security definer set search_path = public as $$
declare sl sales%rowtype; pr products%rowtype; unit_cost numeric;
begin
  if p_qty is null or p_qty <= 0 then raise exception '수량을 확인하세요'; end if;
  if p_type not in ('base','disc','card') then raise exception '가격 구분이 올바르지 않습니다'; end if;
  if p_amount is null or p_amount < 0 then raise exception '판매금액을 확인하세요'; end if;
  select * into sl from sales where sale_id = p_sale for update;
  if not found or sl.is_canceled or sl.store_code is distinct from my_store() then
    raise exception '수정할 수 없는 판매입니다'; end if;
  if coalesce(my_grp()::text, '') not in ('M','S')
     and (sl.created_by <> auth.uid() or sl.sale_date <> (now() at time zone 'Asia/Seoul')::date) then
    raise exception '본인이 당일 등록한 판매만 수정할 수 있습니다'; end if;
  select * into pr from products where store_code = sl.store_code and product_code = sl.product_code for update;
  if found and pr.qty + sl.qty - p_qty < 0 then raise exception '재고 부족 (최대 %개)', pr.qty + sl.qty; end if;
  unit_cost := case when sl.qty > 0 and sl.cost is not null then sl.cost::numeric / sl.qty end;
  update products set qty = qty + sl.qty - p_qty where store_code = sl.store_code and product_code = sl.product_code;
  update sales set qty = p_qty, price_type = p_type, amount = p_amount, is_edited = true,
         cost = case when unit_cost is null then cost else round(unit_cost * p_qty) end
   where sale_id = p_sale;
end $$;

-- 6) 기간별 판매 합계 (취소 제외, 매입원가 합계는 Administrator·Manager·S에게만)
create or replace function sales_summary(p_from date, p_to date)
returns table(cnt bigint, qty bigint, amount numeric, cost numeric)
language sql stable security definer set search_path = public as $$
  select count(*), coalesce(sum(s.qty), 0), coalesce(sum(s.amount), 0),
         case when coalesce(my_grp()::text, '') in ('A','M','S') then coalesce(sum(s.cost), 0) end
  from sales s
  where s.store_code = my_store() and not s.is_canceled and s.sale_date between p_from and p_to
$$;

revoke all on function register_sale(text,int,text,bigint), cancel_sale(uuid), update_sale(uuid,int,text,bigint), sales_summary(date,date) from public, anon;
grant execute on function register_sale(text,int,text,bigint), cancel_sale(uuid), update_sale(uuid,int,text,bigint), sales_summary(date,date) to authenticated;

create index if not exists sales_store_date_idx on sales (store_code, sale_date desc, created_at desc);
