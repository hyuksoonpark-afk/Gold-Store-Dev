-- 2-2단계(제품·사진) SQL — SQL Editor에서 1회 실행 (schema.sql, step1_auth.sql 실행 후)

-- 1) 직원(User)용 제품 뷰: 매입원가·입고일·판매 배수는 보이지 않게 하고,
--    단가제 판매가 계산에 필요한 값(u_base = 단가제 정상가, 반올림 전)과 VAT 구분만 추가합니다.
create or replace view products_staff with (security_invoker = false) as
  select store_code, product_code, model_name, cat_code, vendor_code, material, color, purity, size,
         total_wt_g, pure_wt_g, wt18_g, wt14_g, base_labor + stone_labor as labor_sum, policy, qty,
         vat_flag,
         case when policy = 'U'
              then direct_cost * (case when vat_flag = 0 then 1.1 else 1 end) * sale_mult end as u_base
  from products where store_code = my_store();
grant select on products_staff to authenticated;
revoke all on products_staff from anon;

-- 2) 제품 사진 저장소 (비공개). 경로 규칙: {매장코드}/{제품코드}/{파일명}.jpg
insert into storage.buckets (id, name, public) values ('product-photos', 'product-photos', false)
  on conflict (id) do nothing;

drop policy if exists "product photos read" on storage.objects;
create policy "product photos read" on storage.objects for select to authenticated
  using (bucket_id = 'product-photos'
         and (public.my_grp() = 'A' or (storage.foldername(name))[1] = public.my_store()));

drop policy if exists "product photos insert" on storage.objects;
create policy "product photos insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'product-photos'
         and (public.my_grp() = 'A' or (public.my_grp() in ('M','S') and (storage.foldername(name))[1] = public.my_store())));

drop policy if exists "product photos delete" on storage.objects;
create policy "product photos delete" on storage.objects for delete to authenticated
  using (bucket_id = 'product-photos'
         and (public.my_grp() = 'A' or (public.my_grp() in ('M','S') and (storage.foldername(name))[1] = public.my_store())));

-- 3) 검색 속도용 인덱스
create index if not exists products_model_idx on products (store_code, model_name);
