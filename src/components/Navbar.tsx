'use client'
import Link from 'next/link'
import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { supabaseBrowser } from '@/lib/supabase/browser'

export default function Navbar() {
  const supabase = supabaseBrowser()
  const pathname = usePathname()
  const [ready, setReady] = useState(false)
  const [logged, setLogged] = useState(false)

  useEffect(() => {
    let unsub: { unsubscribe: () => void } | undefined
    ;(async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setLogged(!!session)
      setReady(true)
      const { data } = supabase.auth.onAuthStateChange((_e, s) => setLogged(!!s))
      unsub = data.subscription
    })()
    return () => unsub?.unsubscribe()
  }, [supabase])

  const signOut = async () => { await supabase.auth.signOut() }

  // No mostramos menú en /login
  const hideMenu = pathname?.startsWith('/login')

  return (
    <nav className="border-b bg-white">
      <div className="container h-14 flex items-center justify-between">
        <Link href="/" className="font-semibold">ConsultaDoc</Link>

        {ready && !hideMenu && logged && (
          <div className="flex items-center gap-3">
            <Link className="hover:underline" href="/dashboard">Dashboard</Link>
            <Link className="hover:underline" href="/dashboard/agenda">Agenda</Link>
            <Link className="hover:underline" href="/dashboard/pacientes">Pacientes</Link>
            <Link className="hover:underline" href="/dashboard/especialidades">Especialidades</Link>
            <button className="btn" onClick={signOut}>Salir</button>
          </div>
        )}
      </div>
    </nav>
  )
}
