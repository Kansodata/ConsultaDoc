'use client'

import { useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'

type Props = {
  cita: {
    id: string
    estado: 'pendiente' | 'confirmada' | 'realizada' | 'cancelada' | 'no_show'
    fecha: string
    fin: string
    motivo?: string | null
  }
  onChanged?: () => void // para refrescar la lista del padre
}

export default function ActionsCita({ cita, onChanged }: Props) {
  const supabase = supabaseBrowser()
  const [loading, setLoading] = useState<string | null>(null)
  const [motivo, setMotivo] = useState('')

  async function run(fn: string, args: any) {
    setLoading(fn)
    const { error } = await supabase.rpc(fn, args)
    setLoading(null)
    if (error) alert(error.message)
    else onChanged?.()
  }

  return (
    <div className="flex items-center gap-2">
      {cita.estado === 'pendiente' && (
        <>
          <button
            className="btn"
            disabled={loading !== null}
            onClick={() => run('confirmar_cita', { p_cita: cita.id, p_detalle: 'Confirmada desde dashboard' })}
          >
            {loading === 'confirmar_cita' ? '...' : 'Confirmar'}
          </button>
          <div className="flex items-center gap-2">
            <input
              className="input w-40"
              placeholder="Motivo de cancelación"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
            />
            <button
              className="btn"
              disabled={loading !== null}
              onClick={() => run('cancelar_cita', { p_cita: cita.id, p_motivo: motivo || 'Cancelada desde dashboard' })}
            >
              {loading === 'cancelar_cita' ? '...' : 'Cancelar'}
            </button>
          </div>
        </>
      )}

      {cita.estado === 'confirmada' && (
        <>
          {/* Reprogramar ya lo tienes como modal en el dashboard */}
          <button
            className="btn"
            disabled={loading !== null}
            onClick={() => run('marcar_realizada', { p_cita: cita.id, p_detalle: 'Atendida' })}
          >
            {loading === 'marcar_realizada' ? '...' : 'Marcar atendida'}
          </button>
          <button
            className="btn"
            disabled={loading !== null}
            onClick={() => run('marcar_no_show', { p_cita: cita.id, p_detalle: 'No asistió' })}
          >
            {loading === 'marcar_no_show' ? '...' : 'No-show'}
          </button>
          <div className="flex items-center gap-2">
            <input
              className="input w-40"
              placeholder="Motivo de cancelación"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
            />
            <button
              className="btn"
              disabled={loading !== null}
              onClick={() => run('cancelar_cita', { p_cita: cita.id, p_motivo: motivo || 'Cancelada desde dashboard' })}
            >
              {loading === 'cancelar_cita' ? '...' : 'Cancelar'}
            </button>
          </div>
        </>
      )}

      {(cita.estado === 'realizada' || cita.estado === 'no_show' || cita.estado === 'cancelada') && (
        <span className="text-xs text-slate-500">Estado: {cita.estado}</span>
      )}
    </div>
  )
}
