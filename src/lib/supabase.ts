import { createClient } from '@supabase/supabase-js'

// Publishable keys are designed for browser use. Database access is protected by Auth + RLS.
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://ebtxkomgbzhdujuhgtdm.supabase.co'
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_vT_MaQncVz9Q3QpDmcNIGQ_N_RwhLx9'

export const supabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true,
  },
})
