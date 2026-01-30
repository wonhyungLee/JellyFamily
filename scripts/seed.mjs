import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) throw new Error('Missing env')

const supabase = createClient(url, serviceKey, { auth: { persistSession: false } })

const users = [
  { email: 'wonhyung@jelly.family', password: '7470', display_name: '이원형', role: 'PARENT' },
  { email: 'seolhwa@jelly.family',  password: '5373', display_name: '박설화', role: 'PARENT' },
  { email: 'jina@jelly.family',    password: '2132', display_name: '이진아', role: 'CHILD' },
  { email: 'jino@jelly.family',    password: '2174', display_name: '이진오', role: 'CHILD' },
  { email: 'jinseo@jelly.family',  password: '0000', display_name: '이진서', role: 'CHILD' },
]

for (const u of users) {
  const { error: e1 } = await supabase.auth.admin.createUser({
    email: u.email,
    password: u.password,
    email_confirm: true,
  })
  if (e1 && !String(e1.message).includes('already registered')) throw e1

  const { data: list, error: e2 } = await supabase.auth.admin.listUsers({ page: 1, perPage: 200 })
  if (e2) throw e2
  const found = list.users.find(x => x.email === u.email)
  if (!found) throw new Error('User not found after create: ' + u.email)

  const { error: e3 } = await supabase.from('profiles').upsert({
    id: found.id,
    display_name: u.display_name,
    role: u.role,
  })
  if (e3) throw e3

  const { error: e4 } = await supabase.from('wallets').upsert({
    user_id: found.id,
    jelly_normal: 0,
    jelly_special: 0,
    jelly_bonus: 0,
    cash_balance: 0,
  })
  if (e4) throw e4
}

console.log('✅ seed done')
