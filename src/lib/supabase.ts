import { createClient } from '@supabase/supabase-js'

// Only the public publishable key belongs in browser code.
// Authentication and Row Level Security protect all household data.
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!supabaseUrl || !supabasePublishableKey) {
  throw new Error('MealMate is missing VITE_SUPABASE_URL or VITE_SUPABASE_PUBLISHABLE_KEY. Configure both environment variables before starting the app.')
}

export const supabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true,
  },
})
