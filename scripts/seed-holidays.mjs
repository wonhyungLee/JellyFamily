import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !serviceKey) throw new Error('Missing env')

const supabase = createClient(url, serviceKey, { auth: { persistSession: false } })

const holidays = [
  { day_date: '2026-01-01', name: "New Year's Day" },
  { day_date: '2026-02-16', name: 'Seollal Holiday' },
  { day_date: '2026-02-17', name: 'Seollal' },
  { day_date: '2026-02-18', name: 'Seollal Holiday' },
  { day_date: '2026-03-01', name: 'Independence Movement Day' },
  { day_date: '2026-03-02', name: 'Substitute Holiday for Independence Movement Day' },
  { day_date: '2026-05-05', name: "Children's Day" },
  { day_date: '2026-05-24', name: "Buddha's Birthday" },
  { day_date: '2026-05-25', name: "Substitute Holiday for Buddha's Birthday" },
  { day_date: '2026-06-03', name: 'Local Election Day' },
  { day_date: '2026-06-06', name: 'Memorial Day' },
  { day_date: '2026-08-15', name: 'Liberation Day' },
  { day_date: '2026-08-17', name: 'Substitute Holiday for Liberation Day' },
  { day_date: '2026-09-24', name: 'Chuseok Holiday' },
  { day_date: '2026-09-25', name: 'Chuseok' },
  { day_date: '2026-09-26', name: 'Chuseok Holiday' },
  { day_date: '2026-10-03', name: 'National Foundation Day' },
  { day_date: '2026-10-05', name: 'Substitute Holiday for National Foundation Day' },
  { day_date: '2026-10-09', name: 'Hangeul Day' },
  { day_date: '2026-12-25', name: 'Christmas Day' },
]

const { error } = await supabase.from('public_holidays').upsert(holidays)
if (error) throw error
console.log('✅ holidays seeded:', holidays.length)
