'use client'
import { useEffect, useState } from 'react'
import WeeklyCalendar from '@/components/agenda/WeeklyCalendar'
import { supabaseBrowser } from '@/lib/supabase/browser'

export default function AgendaPage(){
  const supabase = supabaseBrowser()
  const [clinicaId, setClinicaId] = useState<string>('')
  const [medicoId, setMedicoId]   = useState<string>('')

  useEffect(() => {
    const init = async () => {
      const { data: sess } = await supabase.auth.getSession()
      const uid = sess.session?.user.id
      if (!uid) return
      setMedicoId(uid)

      // toma la primera clínica donde esté el usuario
      const { data, error } = await supabase
        .from('clinicas_usuarios')
        .select('clinica_id')
        .eq('usuario_id', uid)
        .limit(1)
        .maybeSingle()
      if (!error && data) setClinicaId(data.clinica_id)
    }
    init()
  }, [supabase])

  if (!medicoId || !clinicaId) {
    return <div className="p-6">Cargando afiliación y rol…</div>
  }

  return (
    <section className="p-6">
      <WeeklyCalendar clinicaId={clinicaId} medicoId={medicoId} />
    </section>
  )
}
