'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabaseBrowser } from '@/lib/supabase/browser'

export default function LoginPage() {
  const supabase = supabaseBrowser()
  const router = useRouter()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Si ya hay sesión, no muestres /login
  useEffect(() => {
    let unsub: { unsubscribe: () => void } | undefined
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) router.replace('/dashboard')
    })
    const { data } = supabase.auth.onAuthStateChange((_e, s) => {
      if (s) router.replace('/dashboard')
    })
    unsub = data.subscription
    return () => unsub?.unsubscribe()
  }, [supabase, router])

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)

    if (error) {
      setError(error.message) // ej: Invalid login credentials, Email not confirmed, etc.
      return
    }
    if (data?.session) {
      // Redirige inmediatamente; las cookies ya quedan sincronizadas por el helper
      router.replace('/dashboard')
    }
  }

  return (
    <section className="p-6 grid place-items-center">
      <form onSubmit={onSubmit} className="card p-6 w-full max-w-md grid gap-3">
        <h2 className="text-xl font-semibold text-center">Iniciar sesión</h2>

        <input
          className="input"
          type="email"
          placeholder="email@dominio.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />

        <input
          className="input"
          type="password"
          placeholder="••••••••"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />

        {error && <p className="text-sm text-red-600">{error}</p>}

        <button className="btn" type="submit" disabled={loading}>
          {loading ? 'Ingresando…' : 'Ingresar'}
        </button>
      </form>
    </section>
  )
}
