'use client'

import Link from 'next/link'
import { useEffect, useRef, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'

type Paciente = { id: string; email: string; nombre: string }

export default function PacientesPage() {
  const supabase = supabaseBrowser()
  const [clinicaId, setClinicaId] = useState<string>('')
  const [q, setQ] = useState('')
  const [items, setItems] = useState<Paciente[]>([])
  const [loading, setLoading] = useState(false)
  const deb = useRef<ReturnType<typeof setTimeout> | null>(null)

  // toma primera clínica del usuario
  useEffect(() => {
    (async () => {
      const { data: s } = await supabase.auth.getSession()
      const uid = s.session?.user.id
      if (!uid) return
      const { data } = await supabase
        .from('clinicas_usuarios')
        .select('clinica_id')
        .eq('usuario_id', uid)
        .limit(1)
        .maybeSingle()
      if (data) setClinicaId(data.clinica_id)
    })()
  }, [supabase])

  useEffect(() => {
    if (!clinicaId) return
    if (deb.current) clearTimeout(deb.current)
    deb.current = setTimeout(async () => {
      setLoading(true)
      const { data, error } = await supabase.rpc('listar_pacientes', {
        p_clinica: clinicaId,
        p_q: q || null
      })
      setLoading(false)
      if (!error) setItems((data as Paciente[]) ?? [])
    }, 300)
  }, [q, clinicaId, supabase])

  return (
    <section className="p-6 grid gap-4">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Pacientes</h2>
        <Link href="/dashboard/citas/nueva" className="btn">+ Nueva cita</Link>
      </div>

      <input
        className="input max-w-lg"
        placeholder="Buscar por email o nombre…"
        value={q}
        onChange={(e)=>setQ(e.target.value)}
      />

      {loading ? <p>Cargando…</p> : items.length === 0 ? (
        <p className="text-sm text-slate-500">Sin pacientes.</p>
      ) : (
        <ul className="card divide-y">
          {items.map(p => (
            <li key={p.id} className="p-3 flex items-center justify-between">
              <div>
                <div className="font-medium">{p.nombre || p.email}</div>
                <div className="text-xs text-slate-500">{p.email}</div>
              </div>
              <Link className="btn" href={`/dashboard/pacientes/${p.id}`}>Abrir ficha</Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
