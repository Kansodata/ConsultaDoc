'use client'
import Link from 'next/link'
import { useEffect, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'

export default function Navbar() {
  const supabase = supabaseBrowser() // ← instancia del cliente
  const [logged, setLogged] = useState(false)

  useEffect(() => {
    // sesión inicial
    supabase.auth.getSession().then(({ data }) => setLogged(!!data.session))
    // suscripción a cambios de auth
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setLogged(!!s)
    })
    return () => {
      sub?.subscription.unsubscribe()
    }
  }, [supabase])

  const onSignOut = async () => {
    await supabase.auth.signOut()
  }

  return (
    <nav className="border-b bg-white">
      <div className="container h-14 flex items-center justify-between">
        <Link href="/" className="font-semibold">ConsultaDoc</Link>

        <div className="flex items-center gap-3">
          {logged ? (
            <>
              <Link className="hover:underline" href="/dashboard">Dashboard</Link>
              <Link className="hover:underline" href="/dashboard/agenda">Agenda</Link>
              <button className="btn" onClick={onSignOut}>Salir</button>
            </>
          ) : (
            <>
              <Link className="hover:underline" href="/dashboard/agenda">Agenda</Link>
              <Link className="btn" href="/login">Ingresar</Link>
            </>
          )}
        </div>
      </div>
    </nav>
  )
}
