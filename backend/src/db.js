import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceKey) {
  throw new Error(
    'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY — copy .env.example to .env and fill it in.'
  );
}

// Service-role client: full DB access, bypasses RLS.
// This must only ever run server-side.
export const db = createClient(url, serviceKey, {
  auth: { persistSession: false },
});
