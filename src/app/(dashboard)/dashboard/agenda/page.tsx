'use client'

import { useEffect, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'
import WeeklyCalendar from '@/components/agenda/WeeklyCalendar'

type Clinica = { id: string; nombre: string; rol: string }

export default function AgendaPage(){
  const supabase = supabaseBrowser()
  const [clinicas, setClinicas] = useState<Clinica[]>([])
  const [clinicaId, setClinicaId] = useState<string>('')
  const [medicoId, setMedicoId]   = useState<string>('')

  useEffect(() => {
    (async () => {
      const { data: sess } = await supabase.auth.getSession()
      const uid = sess.session?.user.id
      if (!uid) return
      setMedicoId(uid)

      const { data } = await supabase.rpc('mis_clinicas', { p_q: null })
      const list = (data as Clinica[]) || []
      setClinicas(list)
      if (list.length) setClinicaId(list[0].id)
    })()
  }, [supabase])

  if (!medicoId) return <div className="p-6">Cargando sesión…</div>
  if (clinicas.length === 0) return <div className="p-6">No tienes clínicas asignadas.</div>

  return (
    <section className="p-6 grid gap-4">
      <div className="flex items-center gap-3">
        <h2 className="text-xl font-semibold">Agenda semanal</h2>
        <select
          className="input"
          value={clinicaId}
          onChange={(e) => setClinicaId(e.target.value)}
        >
          {clinicas.map(c => (
            <option key={c.id} value={c.id}>
              {c.nombre} {c.rol ? `· ${c.rol}` : ''}
            </option>
          ))}
        </select>
      </div>

      {clinicaId ? (
        <WeeklyCalendar clinicaId={clinicaId} medicoId={medicoId} />
      ) : (
        <p className="text-sm text-slate-500">Selecciona una clínica.</p>
      )}
    </section>
  )
}
