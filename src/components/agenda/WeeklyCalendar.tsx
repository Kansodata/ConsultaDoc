'use client'

import { useEffect, useMemo, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'

type Tramo = { dia_semana: number; inicio: string; fin: string } // "HH:MM"

// Config grilla
const DAYS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'] as const
const START = 8   // 08:00
const END = 18    // 18:00 (no inclusivo para la grilla)
const STEP = 30   // minutos

function rangeSlots() {
  const out: string[] = []
  for (let h = START; h < END; h++) {
    out.push(`${String(h).padStart(2, '0')}:00`)
    if (STEP === 30) out.push(`${String(h).padStart(2, '0')}:30`)
  }
  return out
}

// ====== PLANTILLAS RÁPIDAS ======
function plantilla_LV_Cortada(): Tramo[] {
  const days = [1, 2, 3, 4, 5] // Lun–Vie
  return days.flatMap((d) => [
    { dia_semana: d, inicio: '09:00', fin: '13:00' },
    { dia_semana: d, inicio: '15:00', fin: '18:00' },
  ])
}
function plantilla_LV_Corrida(): Tramo[] {
  const days = [1, 2, 3, 4, 5]
  return days.map((d) => ({ dia_semana: d, inicio: '09:00', fin: '18:00' }))
}

type SlotKey = `${number}-${string}` // `${dia}-${HH:MM}`

export default function WeeklyCalendar({
  clinicaId,
  medicoId,
}: {
  clinicaId: string
  medicoId: string
}) {
  const supabase = supabaseBrowser()
  const [busy, setBusy] = useState(false)
  const [rows, setRows] = useState<any[]>([])
  const times = useMemo(() => rangeSlots(), [])

  useEffect(() => {
    if (clinicaId && medicoId) reload()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clinicaId, medicoId])

  // ====== ACCIONES ======
  const reload = async () => {
    const { data, error } = await supabase
      .from('disponibilidad_medica')
      .select('id, dia_semana, hora_inicio, hora_fin, vigente')
      .eq('clinica_id', clinicaId)
      .eq('medico_id', medicoId)
      .eq('vigente', true)
      .order('dia_semana', { ascending: true })
    if (!error) setRows(data || [])
  }

  const applyTemplate = async (tramos: Tramo[]) => {
    if (!clinicaId || !medicoId) return
    setBusy(true)
    try {
      const { error } = await supabase.rpc('aplicar_plantilla_disponibilidad', {
        p_clinica: clinicaId,
        p_medico: medicoId,
        p_tramos: tramos, // se serializa a JSONB
        p_reemplazar: true,
      })
      if (error) throw error
      await reload()
    } finally {
      setBusy(false)
    }
  }

  const clearWeek = async () => {
    if (!clinicaId || !medicoId) return
    setBusy(true)
    try {
      const { error } = await supabase
        .from('disponibilidad_medica')
        .delete()
        .eq('clinica_id', clinicaId)
        .eq('medico_id', medicoId)
        .in('dia_semana', [1, 2, 3, 4, 5]) // L–V
      if (error) throw error
      await reload()
    } finally {
      setBusy(false)
    }
  }
  // ====== FIN ACCIONES ======

  // Conjunto de slots activos para pintar la grilla
  const activeSet = useMemo(() => {
    const set = new Set<SlotKey>()
    for (const r of rows) {
      const start = String(r.hora_inicio) // 'HH:MM:SS'
      const end = String(r.hora_fin)
      const [sh, sm] = start.split(':').map(Number)
      const [eh, em] = end.split(':').map(Number)
      let h = sh,
        m = sm
      while (h < eh || (h === eh && m < em)) {
        const key = `${r.dia_semana}-${String(h).padStart(2, '0')}:${String(m).padStart(
          2,
          '0'
        )}` as SlotKey
        set.add(key)
        m += STEP
        if (m >= 60) {
          h += 1
          m = 0
        }
      }
    }
    return set
  }, [rows])

  // Alterna un slot: inserta bloque STEP o recorta el bloque existente
  const toggle = async (dia: number, hhmm: string) => {
    setBusy(true)
    try {
      const key = `${dia}-${hhmm}` as SlotKey
      const isOn = activeSet.has(key)

      if (!isOn) {
        // Añadir un tramo mínimo STEP
        const { error } = await supabase.from('disponibilidad_medica').insert({
          clinica_id: clinicaId,
          medico_id: medicoId,
          dia_semana: dia,
          hora_inicio: `${hhmm}:00`,
          hora_fin: nextStep(hhmm),
          vigente: true,
        })
        if (error) throw error
      } else {
        // Quitar: localizar el bloque que cubre el slot y partirlo
        const { data, error } = await supabase
          .from('disponibilidad_medica')
          .select('id, hora_inicio, hora_fin')
          .eq('clinica_id', clinicaId)
          .eq('medico_id', medicoId)
          .eq('dia_semana', dia)
          .eq('vigente', true)
        if (error) throw error

        const hit = (data || []).find((r: any) => covers(r.hora_inicio, r.hora_fin, hhmm))
        if (hit) {
          const s = toMinutes(hit.hora_inicio)
          const e = toMinutes(hit.hora_fin)
          const t0 = toMinutes(`${hhmm}:00`)
          const t1 = toMinutes(nextStep(hhmm))
          const ops: Promise<any>[] = []

          // borra original
          ops.push(supabase.from('disponibilidad_medica').delete().eq('id', hit.id))
          // tramo izquierdo
          if (s < t0) {
            ops.push(
              supabase.from('disponibilidad_medica').insert({
                clinica_id: clinicaId,
                medico_id: medicoId,
                dia_semana: dia,
                hora_inicio: fromMinutes(s),
                hora_fin: fromMinutes(t0),
                vigente: true,
              })
            )
          }
          // tramo derecho
          if (t1 < e) {
            ops.push(
              supabase.from('disponibilidad_medica').insert({
                clinica_id: clinicaId,
                medico_id: medicoId,
                dia_semana: dia,
                hora_inicio: fromMinutes(t1),
                hora_fin: fromMinutes(e),
                vigente: true,
              })
            )
          }
          await Promise.all(ops)
        }
      }
      await reload()
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="card p-4">
      <div className="flex items-center justify-between mb-3 gap-2 flex-wrap">
        <h3 className="font-semibold">Agenda semanal</h3>
        <div className="flex gap-2">
          <button
            className="btn"
            onClick={() => applyTemplate(plantilla_LV_Cortada())}
            disabled={busy}
            title="L–V 09:00–13:00 y 15:00–18:00 (reemplaza días L–V)"
          >
            Plantilla L–V (cortada)
          </button>
          <button
            className="btn"
            onClick={() => applyTemplate(plantilla_LV_Corrida())}
            disabled={busy}
            title="L–V 09:00–18:00 (reemplaza L–V)"
          >
            L–V 09–18
          </button>
          <button
            className="btn"
            onClick={clearWeek}
            disabled={busy}
            title="Eliminar disponibilidad de L–V"
          >
            Limpiar L–V
          </button>
        </div>
      </div>

      {busy && <span className="text-sm">guardando…</span>}

      <div className="overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead>
            <tr>
              <th className="w-16"></th>
              {DAYS.map((d, i) => (
                <th key={i} className="px-2 py-1 text-left font-medium">
                  {d}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {times.map((t) => (
              <tr key={t} className="border-t">
                <td className="px-2 py-1 whitespace-nowrap text-slate-500">{t}</td>
                {DAYS.map((_d, dia) => {
                  const on = activeSet.has(`${dia}-${t}` as SlotKey)
                  return (
                    <td key={dia} className="px-2 py-1">
                      <button
                        onClick={() => toggle(dia, t)}
                        className={`block w-full h-7 rounded ${
                          on ? 'bg-emerald-500' : 'bg-slate-200'
                        } hover:opacity-80 transition`}
                        aria-pressed={on}
                        aria-label={`${on ? 'Quitar' : 'Agregar'} ${_d} ${t}`}
                      />
                    </td>
                  )
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <p className="text-xs text-slate-500 mt-3">
        Clic para alternar disponibilidad en bloques de {STEP} min.
      </p>
    </div>
  )
}

// ====== utilidades ======
function toMinutes(hms: string) {
  const [h, m] = hms.split(':').map(Number)
  return h * 60 + m
}
function fromMinutes(min: number) {
  const h = Math.floor(min / 60),
    m = min % 60
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00`
}
function nextStep(hhmm: string) {
  const [h, m] = hhmm.split(':').map(Number)
  const mm = m + STEP >= 60 ? '00' : String(m + STEP).padStart(2, '0')
  const hh = m + STEP >= 60 ? String(h + 1).padStart(2, '0') : String(h).padStart(2, '0')
  return `${hh}:${mm}:00`
}
function covers(hIni: string, hFin: string, hhmm: string) {
  const s = toMinutes(hIni)
  const e = toMinutes(hFin)
  const t0 = toMinutes(`${hhmm}:00`)
  const t1 = toMinutes(nextStep(hhmm))
  return s <= t0 && t1 <= e
}
