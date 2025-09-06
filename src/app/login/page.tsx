'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabaseBrowser } from '@/lib/supabase/browser'

export default function LoginPage() {
  const supabase = supabaseBrowser()
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) { setError(error.message); return }
    router.push('/dashboard') // al dashboard al iniciar sesión
  }

  return (
    <main className="min-h-[60vh] grid place-items-center px-4">
      <div className="w-full max-w-sm rounded-2xl shadow p-6 bg-white">
        <h1 className="text-xl font-semibold text-center">Iniciar sesión</h1>
        <form onSubmit={onSubmit} className="mt-4 grid gap-3">
          <input className="input" type="email" placeholder="Correo" value={email} onChange={e=>setEmail(e.target.value)} required />
          <input className="input" type="password" placeholder="Contraseña" value={password} onChange={e=>setPassword(e.target.value)} required />
          {error && <p className="text-sm text-red-600">{error}</p>}
          <button className="btn w-full" disabled={loading}>{loading ? 'Ingresando…' : 'Ingresar'}</button>
        </form>
      </div>
    </main>
  )
}
