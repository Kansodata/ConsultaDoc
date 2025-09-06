'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'

type Cita = {
  id: string
  fecha: string   // ISO
  fin: string     // ISO
  estado: 'pendiente' | 'confirmada' | 'cancelada' | 'realizada' | 'no_show'
  motivo: string | null
}

export default function DashboardPage() {
  const supabase = supabaseBrowser()

  const [uid, setUid] = useState<string>('')
  const [clinicaId, setClinicaId] = useState<string>('')

  const [citas, setCitas] = useState<Cita[]>([])
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  // ------- Reprogramación (modal) -------
  const [reprog, setReprog] = useState<Cita | null>(null)
  const [newDate, setNewDate] = useState<string>('')   // YYYY-MM-DD
  const [newTime, setNewTime] = useState<string>('')   // HH:MM
  const [newDur, setNewDur]   = useState<number>(30)   // minutos

  // ------- Sesión + clínica -------
  useEffect(() => {
    const init = async () => {
      const { data: s } = await supabase.auth.getSession()
      const me = s.session?.user.id
      if (!me) return
      setUid(me)

      const { data } = await supabase
        .from('clinicas_usuarios')
        .select('clinica_id')
        .eq('usuario_id', me)
        .limit(1)
        .maybeSingle()

      if (data) setClinicaId(data.clinica_id)
    }
    init()
  }, [supabase])

  // ------- Cargar citas de HOY -------
  const fetchCitasHoy = async () => {
    if (!uid || !clinicaId) return
    setLoading(true)
    setErr(null)
    try {
      const startLocal = new Date()
      startLocal.setHours(0, 0, 0, 0)
      const endLocal = new Date()
      endLocal.setHours(23, 59, 59, 999)

      const start = startLocal.toISOString()
      const end = endLocal.toISOString()

      const { data, error } = await supabase
        .from('citas')
        .select('id, fecha, fin, estado, motivo')
        .eq('clinica_id', clinicaId)
        .eq('medico_id', uid) // panel del médico actual
        .in('estado', ['pendiente', 'confirmada', 'realizada', 'no_show'])
        .gte('fecha', start)
        .lte('fin', end)
        .order('fecha', { ascending: true })

      if (error) throw error
      setCitas((data as Cita[]) ?? [])
    } catch (e: any) {
      setErr(e.message ?? 'No se pudieron cargar las citas')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchCitasHoy()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [uid, clinicaId])

  // ------- Acciones -------
  const confirmar = async (id: string) => {
    const { error } = await supabase.rpc('confirmar_cita', {
      p_cita: id,
      p_detalle: 'Confirmada desde dashboard',
    })
    if (error) return alert(error.message)
    fetchCitasHoy()
  }

  const cancelar = async (id: string) => {
    const motivo = window.prompt('Motivo de cancelación:', 'Cancelada desde dashboard') || 'Cancelada desde dashboard'
    const { error } = await supabase.rpc('cancelar_cita', {
      p_cita: id,
      p_motivo: motivo,
    })
    if (error) return alert(error.message)
    fetchCitasHoy()
  }

  const marcadaRealizada = async (id: string) => {
    const { error } = await supabase.rpc('marcar_realizada', {
      p_cita: id,
      p_detalle: 'Atendida',
    })
    if (error) return alert(error.message)
    fetchCitasHoy()
  }

  const marcarNoShow = async (id: string) => {
    const { error } = await supabase.rpc('marcar_no_show', {
      p_cita: id,
      p_detalle: 'No asistió',
    })
    if (error) return alert(error.message)
    fetchCitasHoy()
  }

  // ------- Modal de reprogramación -------
  const abrirReprog = (c: Cita) => {
    setReprog(c)
    // init con fecha/hora actuales de la cita (en local)
    const d = new Date(c.fecha)
    const y = d.getFullYear()
    const m = String(d.getMonth() + 1).padStart(2, '0')
    const day = String(d.getDate()).padStart(2, '0')
    const hh = String(d.getHours()).padStart(2, '0')
    const mm = String(d.getMinutes()).padStart(2, '0')
    setNewDate(`${y}-${m}-${day}`)
    setNewTime(`${hh}:${mm}`)
    setNewDur(Math.max(10, Math.round((new Date(c.fin).getTime() - d.getTime()) / 60000)))
  }

  const confirmarReprog = async () => {
    if (!reprog || !newDate || !newTime) return
    const [hh, mm] = newTime.split(':').map(Number)

    // Construimos en UTC para mantener coherencia con el resto de la app
    const start = new Date(`${newDate}T00:00:00Z`)
    start.setUTCHours(hh, mm, 0, 0)
    const end = new Date(start.getTime() + newDur * 60000)

    const { error } = await supabase.rpc('reprogramar_cita', {
      p_cita: reprog.id,
      p_inicio: start.toISOString(),
      p_fin: end.toISOString(),
      p_motivo: 'Reprogramado desde dashboard',
    })
    if (error) return alert(error.message)
    setReprog(null)
    fetchCitasHoy()
  }

  return (
    <section className="p-6 grid gap-6">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Mi panel</h2>
        <div className="flex gap-2">
          <button className="btn" onClick={fetchCitasHoy}>Actualizar</button>
          <Link href="/dashboard/citas/nueva" className="btn">+ Nueva cita</Link>
          <Link href="/dashboard/agenda" className="btn">Agenda</Link>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        {/* Citas de hoy */}
        <div className="card p-6 md:col-span-2">
          <h3 className="font-semibold mb-2">Citas de hoy</h3>
          {err && <p className="text-sm text-red-600">{err}</p>}
          {loading ? (
            <p>Cargando…</p>
          ) : citas.length === 0 ? (
            <p className="text-sm text-slate-500">No hay citas para hoy.</p>
          ) : (
            <ul className="divide-y">
              {citas.map((c) => {
                const inicio = new Date(c.fecha).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
                const fin = new Date(c.fin).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
                return (
                  <li key={c.id} className="py-3">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="font-medium">{inicio} – {fin}</div>
                        <div className="text-xs text-slate-500">
                          {c.estado.toUpperCase()} {c.motivo ? `· ${c.motivo}` : ''}
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-2">
                        {/* Acciones según estado */}
                        {c.estado === 'pendiente' && (
                          <>
                            <button className="btn" onClick={() => confirmar(c.id)}>Confirmar</button>
                            <button className="btn" onClick={() => abrirReprog(c)}>Reprogramar</button>
                            <button className="btn" onClick={() => cancelar(c.id)}>Cancelar</button>
                          </>
                        )}

                        {c.estado === 'confirmada' && (
                          <>
                            <button className="btn" onClick={() => marcadaRealizada(c.id)}>Marcar atendida</button>
                            <button className="btn" onClick={() => marcarNoShow(c.id)}>No-show</button>
                            <button className="btn" onClick={() => abrirReprog(c)}>Reprogramar</button>
                            <button className="btn" onClick={() => cancelar(c.id)}>Cancelar</button>
                          </>
                        )}

                        {(c.estado === 'realizada' || c.estado === 'no_show') && (
                          <button className="btn" onClick={() => cancelar(c.id)}>Cancelar</button>
                        )}
                      </div>
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </div>

        {/* Acceso a Agenda */}
        <div className="card p-6">
          <h3 className="font-semibold">Mi disponibilidad</h3>
          <p className="text-sm mb-3">Gestiona tus horarios semanales.</p>
          <Link href="/dashboard/agenda" className="underline">Abrir Agenda</Link>
        </div>
      </div>

      {/* Modal Reprogramar */}
      {reprog && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl p-4 w-full max-w-md shadow-lg">
            <h3 className="font-semibold text-lg mb-3">Reprogramar cita</h3>
            <div className="grid gap-3">
              <div>
                <label className="block text-sm mb-1">Nueva fecha</label>
                <input className="input w-full" type="date" value={newDate} onChange={e=>setNewDate(e.target.value)} />
              </div>
              <div>
                <label className="block text-sm mb-1">Nueva hora</label>
                <input className="input w-full" type="time" value={newTime} onChange={e=>setNewTime(e.target.value)} />
              </div>
              <div>
                <label className="block text-sm mb-1">Duración (min)</label>
                <input className="input w-full" type="number" min={10} step={5} value={newDur} onChange={e=>setNewDur(Number(e.target.value))} />
              </div>
            </div>
            <div className="mt-4 flex justify-end gap-2">
              <button className="btn" onClick={() => setReprog(null)}>Cancelar</button>
              <button className="btn" onClick={confirmarReprog}>Guardar</button>
            </div>
          </div>
        </div>
      )}
    </section>
  )
}
