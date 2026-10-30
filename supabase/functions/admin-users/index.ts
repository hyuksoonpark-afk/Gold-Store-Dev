// Supabase Edge Function: admin-users
// 사용자 계정 생성 · 비밀번호 초기화 · 정보 수정을 서버에서만 처리합니다.
// 필요한 Secrets: AUTH_DOMAIN (예: mycompany.co.kr)  — SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 는 자동 제공
// 권한: Administrator → Manager·S 계정(매장 '000' 제외) / Manager → 자기 매장의 User·S 계정
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
})
const DOMAIN = (Deno.env.get('AUTH_DOMAIN') || '').trim().toLowerCase()

const pwOk = (p: unknown, id: string) =>
  typeof p === 'string' && p.length >= 8 && p.length <= 20 && !/\s/.test(p) &&
  /[A-Za-z]/.test(p) && /\d/.test(p) && !p.toLowerCase().includes(id.toLowerCase())

function tempPw() {
  const L = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz', D = '23456789'
  const r = (n: number) => crypto.getRandomValues(new Uint32Array(1))[0] % n
  const a = [...Array(6)].map(() => L[r(L.length)]).concat([...Array(3)].map(() => D[r(D.length)]))
  for (let i = a.length - 1; i > 0; i--) { const j = r(i + 1); [a[i], a[j]] = [a[j], a[i]] }
  return a.join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!DOMAIN) return json({ error: '서버 설정(AUTH_DOMAIN)이 없습니다' }, 500)
    const token = (req.headers.get('Authorization') || '').replace('Bearer ', '')
    const { data: au } = await admin.auth.getUser(token)
    if (!au?.user) return json({ error: '로그인이 필요합니다' }, 401)
    const { data: me } = await admin.from('profiles').select('*').eq('id', au.user.id).single()
    const today = new Date().toISOString().slice(0, 10)
    if (!me || !me.active || me.expires_on < today) return json({ error: '사용할 수 없는 계정입니다' }, 403)

    // 대상 권한 확인: A → M·S(본사 제외), M → 자기 매장의 U·S
    const allowed = (grp: string, store: string) =>
      me.grp === 'A' ? ['M', 'S'].includes(grp) && store !== '000'
      : me.grp === 'M' ? store === me.store_code && ['U', 'S'].includes(grp)
      : false

    const b = await req.json()

    if (b.action === 'create') {
      const loginId = String(b.login_id || '').trim()
      const store = String(b.store_code || '').trim()
      const grp = String(b.grp || '')
      if (!/^[A-Za-z0-9_.-]{3,20}$/.test(loginId)) return json({ error: 'ID는 영문·숫자·._- 3~20자로 입력하세요' }, 400)
      if (!allowed(grp, store)) return json({ error: '이 그룹의 계정을 만들 권한이 없습니다' }, 403)
      if (!pwOk(b.password, loginId)) return json({ error: '비밀번호는 8~20자, 영문과 숫자 포함, 공백·아이디 포함 불가' }, 400)
      if (!String(b.full_name || '').trim()) return json({ error: '성명을 입력하세요' }, 400)
      const { data: st } = await admin.from('stores').select('store_code').eq('store_code', store).maybeSingle()
      if (!st) return json({ error: '등록되지 않은 매장입니다. 매장 관리에서 먼저 등록하세요' }, 400)
      const { data: dup } = await admin.from('profiles').select('id').eq('store_code', store).eq('login_id', loginId).maybeSingle()
      if (dup) return json({ error: '이 매장에서 이미 사용 중인 ID입니다' }, 400)
      const email = `${store}.${loginId}@${DOMAIN}`.toLowerCase()
      const { data: cu, error: ce } = await admin.auth.admin.createUser({ email, password: b.password, email_confirm: true })
      if (ce || !cu?.user) return json({ error: '계정을 만들지 못했습니다: ' + (ce?.message || '') }, 400)
      const { error: pe } = await admin.from('profiles').insert({
        id: cu.user.id, store_code: store, login_id: loginId, full_name: String(b.full_name).trim(),
        tel: b.tel || null, grp, expires_on: b.expires_on || '2099-12-31', must_change: true,
      })
      if (pe) { await admin.auth.admin.deleteUser(cu.user.id); return json({ error: '저장하지 못했습니다: ' + pe.message }, 400) }
      return json({ ok: true })
    }

    // reset / update 는 대상 사용자 필요
    const { data: t } = await admin.from('profiles').select('*').eq('id', String(b.user_id || '')).maybeSingle()
    if (!t) return json({ error: '대상 사용자를 찾을 수 없습니다' }, 404)
    if (t.id === me.id) return json({ error: '본인 계정은 이 화면에서 바꿀 수 없습니다' }, 400)
    if (!allowed(t.grp, t.store_code)) return json({ error: '이 사용자를 관리할 권한이 없습니다' }, 403)

    if (b.action === 'reset') {
      const temp = tempPw()
      const { error: ue } = await admin.auth.admin.updateUserById(t.id, { password: temp })
      if (ue) return json({ error: '초기화하지 못했습니다: ' + ue.message }, 400)
      await admin.from('profiles').update({ must_change: true }).eq('id', t.id)
      return json({ ok: true, temp_password: temp })
    }

    if (b.action === 'update') {
      const grp = String(b.grp || t.grp)
      if (!allowed(grp, t.store_code)) return json({ error: '이 그룹으로 변경할 권한이 없습니다' }, 403)
      const { error: ue } = await admin.from('profiles').update({
        full_name: String(b.full_name || t.full_name).trim(), tel: b.tel || null, grp,
        expires_on: b.expires_on || t.expires_on, active: b.active !== false,
      }).eq('id', t.id)
      if (ue) return json({ error: '저장하지 못했습니다: ' + ue.message }, 400)
      return json({ ok: true })
    }

    return json({ error: '알 수 없는 요청입니다' }, 400)
  } catch (e) {
    return json({ error: '처리 중 오류가 발생했습니다: ' + (e as Error).message }, 500)
  }
})
