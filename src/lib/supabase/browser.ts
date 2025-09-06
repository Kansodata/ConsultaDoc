// Reemplaza TODO el archivo por esto:
import { createClientComponentClient } from '@supabase/auth-helpers-nextjs'
// Si tipaste tu DB, puedes pasar el tipo: createClientComponentClient<Database>()
export const supabaseBrowser = () => createClientComponentClient()
