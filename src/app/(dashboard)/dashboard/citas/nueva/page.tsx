'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabaseBrowser } from '@/lib/supabase/browser'

const STEP = 30
const DURATIONS = [15, 30, 45, 60] as const

function addMin(d: Date, m: number) { return new Date(d.getTime() + m * 60000) }
function utcAt(dateStr: string, hh: number, mm: number) {
  const [y, m, d] = dateStr.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d, hh, mm, 0))
}
function labelLocal(d: Date) {
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

type Slot = { ini: Date; fin: Date }
type Persona = { id: string; email: string; nombre: string; especialidad?: string }
type Clinica = { id: string; nombre: string; rol: string }
type Especialidad = { id: string; nombre: string }

export default function NuevaCitaPage() {
  const supabase = supabaseBrowser()
  const router = useRouter()

  // Sesión
  const [uid, setUid] = useState<string>('')

  // Clínicas
  const [clinicas, setClinicas] = useState<Clinica[]>([])
  const [clinicaId, setClinicaId] = useState<string>('')

  // Especialidades (⚠️ ahora vienen con id + nombre)
  const [especialidades, setEspecialidades] = useState<Especialidad[]>([])
  const [espSelId, setEspSelId] = useState<string>('') // '' = todas

  // Médico
  const [medico, setMedico] = useState<Persona | null>(null)
  const [qMed, setQMed] = useState('')
  const [foundMed, setFoundMed] = useState<Persona[]>([])
  const [searchingMed, setSearchingMed] = useState(false)
  const debMed = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Paciente (“para mí” o buscar)
  const [reservarParaMi, setReservarParaMi] = useState(true)
  const [paciente, setPaciente] = useState<Persona | null>(null)
  const [q, setQ] = useState('')
  const [found, setFound] = useState<Persona[]>([])
  const [searching, setSearching] = useState(false)
  const deb = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Fecha/duración + slots
  const [date, setDate] = useState<string>('') // YYYY-MM-DD
  const [duration, setDuration] = useState<number>(30)
  const [slots, setSlots] = useState<Slot[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const minDate = new Date().toISOString().slice(0, 10)

  // Init: sesión + clínicas
  useEffect(() => {
    (async () => {
      const { data: sess } = await supabase.auth.getSession()
      const u = sess.session?.user.id
      if (!u) return
      setUid(u)

      const { data } = await supabase.rpc('mis_clinicas', { p_q: null })
      const list = (data as Clinica[]) || []
      setClinicas(list)
      if (list.length) setClinicaId(list[0].id)

      setReservarParaMi(true)
      setPaciente(null)
    })()
  }, [supabase])

  // Cuando cambia la clínica, recarga especialidades y resetea médico/slots
  useEffect(() => {
    setMedico(null)
    setQMed('')
    setFoundMed([])
    setSlots([])
    setEspSelId('')

    if (!clinicaId) { setEspecialidades([]); return }

    ;(async () => {
      // ⚠️ Nueva RPC: devuelve [{ id, nombre }]
      const { data, error } = await supabase.rpc('listar_especialidades', { p_clinica: clinicaId })
      if (!error) setEspecialidades((data as Especialidad[]) ?? [])
    })()
  }, [clinicaId, supabase])

  // Buscar médicos (con filtro de especialidad UUID)
  useEffect(() => {
    if (!clinicaId) { setFoundMed([]); return }
    if (debMed.current) clearTimeout(debMed.current)
    debMed.current = setTimeout(async () => {
      // si no hay query ni especialidad → evita lista enorme
      if (!qMed && !espSelId) { setFoundMed([]); return }
      setSearchingMed(true)
      const { data, error } = await supabase.rpc('buscar_medicos_filtrado', {
        p_clinica: clinicaId,
        p_q: qMed || null,
        p_especialidad: espSelId || null
      })
      setSearchingMed(false)
      if (!error) setFoundMed((data as Persona[]) ?? [])
    }, 300)
  }, [qMed, espSelId, clinicaId, supabase])

  // Buscar pacientes (global) si NO es “para mí”
  useEffect(() => {
    if (!clinicaId || reservarParaMi) { setFound([]); return }
    if (deb.current) clearTimeout(deb.current)
    deb.current = setTimeout(async () => {
      setSearching(true)
      const { data, error } = await supabase.rpc('listar_pacientes', {
        p_clinica: clinicaId,
        p_q: q || null
      })
      setSearching(false)
      if (!error) setFound((data as Persona[]) ?? [])
    }, 300)
  }, [q, clinicaId, reservarParaMi, supabase])

  // Cargar slots según médico + fecha + clínica
  useEffect(() => {
    const fetchDay = async () => {
      setSlots([])
      setError(null)
      if (!clinicaId || !medico?.id || !date) return
      setLoading(true)
      try {
        const dow = new Date(date + 'T00:00:00Z').getUTCDay()
        const { data: disp, error: e1 } = await supabase
          .from('disponibilidad_medica')
          .select('hora_inicio, hora_fin')
          .eq('clinica_id', clinicaId)
          .eq('medico_id', medico.id)
          .eq('vigente', true)
          .eq('dia_semana', dow)
        if (e1) throw e1

        const dayStart = new Date(date + 'T00:00:00Z').toISOString()
        const dayEnd   = new Date(date + 'T23:59:59Z').toISOString()
        const { data: citas, error: e2 } = await supabase
          .from('citas')
          .select('fecha, fin, estado')
          .eq('clinica_id', clinicaId)
          .eq('medico_id', medico.id)
          .in('estado', ['pendiente','confirmada','realizada'])
          .gte('fecha', dayStart)
          .lte('fin', dayEnd)
        if (e2) throw e2

        const busy = (citas ?? []).map(c => ({ ini: new Date(c.fecha), fin: new Date(c.fin) }))
        const out: Slot[] = []
        for (const r of disp ?? []) {
          const [sh, sm] = String(r.hora_inicio).split(':').map(Number)
          const [eh, em] = String(r.hora_fin).split(':').map(Number)
          let p = utcAt(date, sh, sm)
          const lim = utcAt(date, eh, em)
          while (addMin(p, duration) <= lim) {
            const q2 = addMin(p, duration)
            const overlaps = busy.some(b => p < b.fin && q2 > b.ini)
            if (!overlaps) out.push({ ini: p, fin: q2 })
            p = addMin(p, STEP)
          }
        }
        setSlots(out)
      } catch (err: any) {
        setError(err.message ?? 'Error cargando disponibilidad')
      } finally {
        setLoading(false)
      }
    }
    fetchDay()
  }, [clinicaId, medico?.id, date, duration, supabase])

  // Reservar
  const reservar = async (ini: Date, fin: Date) => {
    setError(null)
    if (!clinicaId) { setError('Selecciona una clínica'); return }
    if (!medico?.id) { setError('Selecciona un médico'); return }
    const pacienteId = reservarParaMi ? uid : (paciente?.id ?? '')
    if (!pacienteId) { setError('Selecciona un paciente'); return }

    setLoading(true)
    try {
      // Si no es para mí, asegura afiliación como 'paciente'
      if (!reservarParaMi) {
        const { error: e1 } = await supabase.rpc('asegurar_membresia_paciente', {
          p_clinica: clinicaId,
          p_usuario: pacienteId
        })
        if (e1) throw e1
      }

      // Reserva
      const { error: e2 } = await supabase.rpc('reservar_cita', {
        p_clinica: clinicaId,
        p_paciente: pacienteId,
        p_medico: medico.id,
        p_inicio: ini.toISOString(),
        p_fin: fin.toISOString(),
        p_motivo: reservarParaMi ? 'Reserva (para mí)' : `Reserva para ${paciente?.email || paciente?.nombre || pacienteId}`,
      })
      if (e2) throw e2

      router.push('/dashboard')
    } catch (e: any) {
      setError(e.message ?? 'No se pudo reservar')
    } finally {
      setLoading(false)
    }
  }

  return (
    <section className="p-6 grid gap-5">
      <h2 className="text-xl font-semibold">Nueva cita</h2>

      {/* Selector de CLÍNICA */}
      <div className="grid gap-2 max-w-3xl">
        <label className="text-sm">Clínica</label>
        {clinicas.length === 0 ? (
          <p className="text-sm text-slate-500">No tienes clínicas asignadas.</p>
        ) : (
          <select className="input w-full" value={clinicaId} onChange={(e) => setClinicaId(e.target.value)}>
            {clinicas.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre} {c.rol ? `· ${c.rol}` : ''}
              </option>
            ))}
          </select>
        )}
      </div>

      {/* Selector de ESPECIALIDAD (usa uuid) */}
      <div className="grid gap-2 max-w-3xl">
        <label className="text-sm">Especialidad</label>
        <select
          className="input w-full"
          value={espSelId}
          onChange={(e) => setEspSelId(e.target.value)}
          disabled={!clinicaId}
        >
          <option value="">Todas</option>
          {especialidades.map((e) => (
            <option key={e.id} value={e.id}>{e.nombre}</option>
          ))}
        </select>
        {espSelId && (
          <span className="text-xs text-slate-500">
            Filtrando por: {especialidades.find(x => x.id === espSelId)?.nombre}
          </span>
        )}
      </div>

      {/* Selector de MÉDICO */}
      <div className="grid gap-2 max-w-3xl">
        <label className="text-sm">Médico</label>
        {medico ? (
          <div className="text-sm">
            Seleccionado: <b>{medico.nombre || medico.email || medico.id}</b>
            {medico.especialidad ? <span className="text-xs text-slate-500"> · {medico.especialidad}</span> : null}
            <button className="ml-2 underline" onClick={() => { setMedico(null); setQMed(''); setFoundMed([]) }}>
              Cambiar
            </button>
          </div>
        ) : (
          <>
            <input
              className="input"
              placeholder="Buscar por email o nombre"
              value={qMed}
              onChange={e => setQMed(e.target.value)}
              disabled={!clinicaId}
            />
            {searchingMed && <span className="text-xs text-slate-500">Buscando…</span>}
            {foundMed.length > 0 && (
              <ul className="border rounded divide-y">
                {foundMed.map(m => (
                  <li key={m.id}
                      className="p-2 hover:bg-slate-50 cursor-pointer"
                      onClick={() => { setMedico(m); setFoundMed([]) }}>
                    <div className="font-medium">{m.nombre || m.email}</div>
                    <div className="text-xs text-slate-500">
                      {m.email}{m.especialidad ? ` · ${m.especialidad}` : ''}
                    </div>
                  </li>
                ))}
              </ul>
            )}
            {!searchingMed && (qMed || espSelId) && foundMed.length === 0 && (
              <p className="text-xs text-slate-500">Sin resultados con esos filtros.</p>
            )}
          </>
        )}
      </div>

      {/* Selector de PACIENTE */}
      <div className="grid gap-2 max-w-3xl">
        <label className="flex items-center gap-2">
          <input
            type="checkbox"
            checked={reservarParaMi}
            onChange={e => { setReservarParaMi(e.target.checked); if (e.target.checked) { setPaciente(null); setQ('') } }}
          />
          <span>Reservar para mí</span>
        </label>

        {!reservarParaMi && (
          <>
            <label className="text-sm">Paciente (buscar por email o nombre)</label>
            <input
              className="input"
              placeholder="p.ej. juan@correo.com"
              value={q}
              onChange={e => setQ(e.target.value)}
              disabled={!clinicaId}
            />
            {searching && <span className="text-xs text-slate-500">Buscando…</span>}
            {paciente && (
              <div className="text-sm">
                Seleccionado: <b>{paciente.nombre || paciente.email}</b>{' '}
                <span className="text-xs text-slate-500">({paciente.email})</span>
                <button className="ml-2 underline" onClick={() => setPaciente(null)}>Cambiar</button>
              </div>
            )}
            {!paciente && found.length > 0 && (
              <ul className="border rounded divide-y">
                {found.map(p => (
                  <li key={p.id}
                      className="p-2 hover:bg-slate-50 cursor-pointer"
                      onClick={() => { setPaciente(p); setFound([]) }}>
                    <div className="font-medium">{p.nombre || p.email}</div>
                    <div className="text-xs text-slate-500">{p.email}</div>
                  </li>
                ))}
              </ul>
            )}
            {!paciente && !searching && q && found.length === 0 && (
              <p className="text-xs text-slate-500">
                Sin resultados. Si el usuario existe, se afilia automáticamente al reservar.
              </p>
            )}
          </>
        )}
      </div>

      {/* Fecha y duración */}
      <div className="grid sm:grid-cols-3 gap-3 max-w-3xl">
        <div>
          <label className="block text-sm mb-1">Fecha</label>
          <input className="input w-full" type="date" min={minDate} value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
        <div>
          <label className="block text-sm mb-1">Duración</label>
          <select className="input w-full" value={duration} onChange={(e) => setDuration(Number(e.target.value))}>
            {DURATIONS.map((m) => <option key={m} value={m}>{m} min</option>)}
          </select>
        </div>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      {/* Slots */}
      <div>
        <h3 className="font-medium mb-2">Horarios disponibles</h3>
        {!clinicaId || !medico?.id ? (
          <p className="text-sm text-slate-500">Selecciona clínica y médico para ver horarios.</p>
        ) : loading ? (
          <p>Cargando…</p>
        ) : slots.length === 0 ? (
          <p className="text-sm text-slate-500">No hay horarios para ese día.</p>
        ) : (
          <div className="flex flex-wrap gap-2">
            {slots.map((s, i) => (
              <button key={i} className="btn"
                onClick={() => reservar(s.ini, s.fin)}
                title={`${s.ini.toISOString()} → ${s.fin.toISOString()} (UTC)`}>
                {labelLocal(s.ini)}–{labelLocal(s.fin)}
              </button>
            ))}
          </div>
        )}
        <p className="text-xs text-slate-500 mt-2">
          * Los horarios se muestran en tu hora local. Internamente se guarda en UTC.
        </p>
      </div>
    </section>
  )
}
