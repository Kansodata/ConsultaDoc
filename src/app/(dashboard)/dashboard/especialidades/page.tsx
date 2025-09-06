'use client'

import { useEffect, useRef, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'

type Clinica = { id: string; nombre: string; rol: string }
type Especialidad = { id: string; nombre: string }
type CatalogItem = { id: string; nombre: string; slug: string }
type Medico = { id: string; email: string; nombre: string; especialidad?: string }

export default function EspecialidadesPage() {
  const supabase = supabaseBrowser()

  const [clinicaId, setClinicaId] = useState<string>('')
  const [clinicas, setClinicas] = useState<Clinica[]>([])

  // Especialidades activas en clínica
  const [espActivas, setEspActivas] = useState<Especialidad[]>([])
  const [loadingEsp, setLoadingEsp] = useState(false)

  // Catálogo global (búsqueda)
  const [qCat, setQCat] = useState('')
  const [cat, setCat] = useState<CatalogItem[]>([])
  const [loadingCat, setLoadingCat] = useState(false)
  const debCat = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Crear nueva global
  const [newEsp, setNewEsp] = useState('')

  // Renombrar público (por clínica)
  const [editNombre, setEditNombre] = useState<{ [espId: string]: string }>({})

  // Médicos (búsqueda y selección)
  const [qMed, setQMed] = useState('')
  const [medicos, setMedicos] = useState<Medico[]>([])
  const [selMed, setSelMed] = useState<Medico | null>(null)
  const [loadingMed, setLoadingMed] = useState(false)
  const debMed = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Asignaciones del médico seleccionado
  const [espMedico, setEspMedico] = useState<string[]>([]) // ids
  const [saving, setSaving] = useState(false)

  // Habilitar usuario como médico (promoción de rol)
  const [promoteEmail, setPromoteEmail] = useState('')
  const [promoting, setPromoting] = useState(false)

  // -------- Init: clínicas del usuario ----------
  useEffect(() => {
    (async () => {
      const { data } = await supabase.rpc('mis_clinicas', { p_q: null })
      const list = (data as Clinica[]) ?? []
      setClinicas(list)
      if (list.length) setClinicaId(list[0].id)
    })()
  }, [supabase])

  // -------- Cargar especialidades activas de la clínica ----------
  const loadEsp = async () => {
    if (!clinicaId) return
    setLoadingEsp(true)
    const { data, error } = await supabase.rpc('listar_especialidades', { p_clinica: clinicaId })
    setLoadingEsp(false)
    if (!error) setEspActivas((data as Especialidad[]) ?? [])
  }
  useEffect(() => {
    setEspActivas([])
    setEditNombre({})
    loadEsp()
  }, [clinicaId])

  // -------- Buscar catálogo ----------
  useEffect(() => {
    if (!clinicaId) return
    if (debCat.current) clearTimeout(debCat.current)
    debCat.current = setTimeout(async () => {
      setLoadingCat(true)
      const q = qCat.trim()
      let query = supabase.from('especialidades').select('id, nombre, slug').order('nombre', { ascending: true }).limit(30)
      if (q) query = query.ilike('nombre', `%${q}%`)
      const { data } = await query
      setLoadingCat(false)
      setCat((data as CatalogItem[]) ?? [])
    }, 300)
  }, [qCat, clinicaId, supabase])

  // -------- Médicos: búsqueda (RPC permite admin o medico) ----------
  useEffect(() => {
    if (!clinicaId) return
    if (debMed.current) clearTimeout(debMed.current)
    debMed.current = setTimeout(async () => {
      setLoadingMed(true)
      const { data, error } = await supabase.rpc('buscar_medicos_filtrado', {
        p_clinica: clinicaId,
        p_q: qMed || null,
        p_especialidad: null
      })
      setLoadingMed(false)
      if (!error) setMedicos((data as Medico[]) ?? [])
    }, 300)
  }, [qMed, clinicaId, supabase])

  // -------- Cargar asignaciones del médico seleccionado ----------
  const loadEspMedico = async (medicoId: string) => {
    if (!clinicaId) return
    const { data } = await supabase
      .from('medico_especialidades')
      .select('especialidad_id')
      .eq('clinica_id', clinicaId)
      .eq('medico_id', medicoId)
    setEspMedico(((data as any[]) ?? []).map(x => x.especialidad_id as string))
  }

  // -------- Acciones (catálogo/clinic) ----------
  async function agregarDesdeCatalogo(espId: string) {
    if (!clinicaId) return
    const { error } = await supabase.rpc('agregar_especialidad_a_clinica', {
      p_clinica: clinicaId,
      p_especialidad: espId,
      p_nombre_publico: null
    })
    if (error) return alert(error.message)
    setQCat('')
    loadEsp()
  }

  async function crearYAgregar() {
    if (!clinicaId || !newEsp.trim()) return
    setSaving(true)
    try {
      const { data: idRes, error: e1 } = await supabase.rpc('upsert_especialidad_global', {
        p_nombre: newEsp.trim(),
        p_codigo: null,
        p_sistema: null
      })
      if (e1) throw e1
      const newId = idRes as string
      const { error: e2 } = await supabase.rpc('agregar_especialidad_a_clinica', {
        p_clinica: clinicaId,
        p_especialidad: newId,
        p_nombre_publico: null
      })
      if (e2) throw e2
      setNewEsp('')
      await loadEsp()
    } catch (e: any) {
      alert(e.message ?? 'No se pudo crear')
    } finally {
      setSaving(false)
    }
  }

  async function renamePublic(espId: string) {
    const nuevo = editNombre[espId] ?? ''
    setSaving(true)
    const { error } = await supabase
      .from('clinica_especialidades')
      .update({ nombre_publico: nuevo || null })
      .eq('clinica_id', clinicaId)
      .eq('especialidad_id', espId)
    setSaving(false)
    if (error) return alert(error.message)
    await loadEsp()
  }

  async function toggleActiva(espId: string, activa: boolean) {
    setSaving(true)
    const { error } = await supabase
      .from('clinica_especialidades')
      .update({ activa })
      .eq('clinica_id', clinicaId)
      .eq('especialidad_id', espId)
    setSaving(false)
    if (error) return alert(error.message)
    await loadEsp()
  }

  function isAsignada(espId: string) {
    return espMedico.includes(espId)
  }

  // Upsert de asignación (evita duplicados de forma explícita)
  async function addAsignacion(espId: string) {
    if (!selMed) return
    setSaving(true)
    const { error } = await supabase
      .from('medico_especialidades')
      .upsert(
        { clinica_id: clinicaId, medico_id: selMed.id, especialidad_id: espId } as any,
        { onConflict: 'clinica_id,medico_id,especialidad_id' }
      )
    setSaving(false)
    if (error) return alert(error.message)
    await loadEspMedico(selMed.id)
  }

  async function delAsignacion(espId: string) {
    if (!selMed) return
    setSaving(true)
    const { error } = await supabase
      .from('medico_especialidades')
      .delete()
      .eq('clinica_id', clinicaId)
      .eq('medico_id', selMed.id)
      .eq('especialidad_id', espId)
    setSaving(false)
    if (error) return alert(error.message)
    await loadEspMedico(selMed.id)
  }

  // -------- Habilitar usuario como médico (admin) ----------
  async function habilitarComoMedico() {
    if (!clinicaId || !promoteEmail.trim()) return
    setPromoting(true)
    try {
      const { data: usr, error: e1 } = await supabase.rpc('buscar_usuario_por_email', {
        p_email: promoteEmail.trim()
      })
      if (e1) throw e1
      const u = (usr as any[])?.[0]
      if (!u) throw new Error('Usuario no encontrado')

      const { error: e2 } = await supabase.rpc('asignar_rol_en_clinica', {
        p_clinica: clinicaId,
        p_usuario: u.id,
        p_rol: 'medico'
      })
      if (e2) throw e2

      // refrescar búsqueda y limpiar input
      setQMed(promoteEmail.trim())
      setPromoteEmail('')
      alert('Usuario habilitado como médico en esta clínica.')
    } catch (err: any) {
      alert(err.message ?? 'No se pudo habilitar')
    } finally {
      setPromoting(false)
    }
  }

  return (
    <section className="p-6 grid gap-6">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Especialidades</h2>
        <div className="flex gap-2">
          {clinicas.length > 0 && (
            <select className="input" value={clinicaId} onChange={(e)=>setClinicaId(e.target.value)}>
              {clinicas.map(c => <option key={c.id} value={c.id}>{c.nombre} {c.rol ? `· ${c.rol}` : ''}</option>)}
            </select>
          )}
          <button className="btn" onClick={loadEsp}>Actualizar</button>
        </div>
      </div>

      {!clinicaId ? (
        <p className="text-sm text-slate-500">No se detectó clínica.</p>
      ) : (
        <>
          {/* Activas en clínica */}
          <div className="card p-4 grid gap-3">
            <h3 className="font-semibold">Especialidades activas en la clínica</h3>
            {loadingEsp ? (
              <p>Cargando…</p>
            ) : espActivas.length === 0 ? (
              <p className="text-sm text-slate-500">Aún no hay especialidades activas.</p>
            ) : (
              <ul className="divide-y">
                {espActivas.map(e => (
                  <li key={e.id} className="py-3 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                    <div>
                      <div className="font-medium">{e.nombre}</div>
                      <div className="text-xs text-slate-500">ID: {e.id}</div>
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                      <input
                        className="input w-56"
                        placeholder="Nombre público (opcional)"
                        value={editNombre[e.id] ?? ''}
                        onChange={(ev) => setEditNombre(prev => ({ ...prev, [e.id]: ev.target.value }))}
                      />
                      <button className="btn" disabled={saving} onClick={() => renamePublic(e.id)}>
                        Guardar nombre
                      </button>

                      <button className="btn" disabled={saving} onClick={() => toggleActiva(e.id, false)}>
                        Desactivar
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* Agregar a clínica */}
          <div className="card p-4 grid gap-4">
            <h3 className="font-semibold">Agregar especialidades a la clínica</h3>

            <div className="grid gap-2">
              <label className="text-sm">Buscar en catálogo</label>
              <input className="input max-w-lg" placeholder="Ej. Dermatología" value={qCat} onChange={(e)=>setQCat(e.target.value)} />
              {loadingCat ? <span className="text-xs text-slate-500">Buscando…</span> : null}
              {cat.length > 0 && (
                <ul className="border rounded divide-y max-w-2xl">
                  {cat.map(c => (
                    <li key={c.id} className="p-2 flex items-center justify-between">
                      <div>
                        <div className="font-medium text-sm">{c.nombre}</div>
                        <div className="text-xs text-slate-500">{c.slug}</div>
                      </div>
                      <button className="btn" onClick={() => agregarDesdeCatalogo(c.id)}>Agregar</button>
                    </li>
                  ))}
                </ul>
              )}
              {qCat && !loadingCat && cat.length === 0 && (
                <p className="text-xs text-slate-500">Sin resultados en catálogo.</p>
              )}
            </div>

            <div className="grid gap-2">
              <label className="text-sm">Crear nueva en catálogo</label>
              <div className="flex items-center gap-2">
                <input className="input max-w-lg" placeholder="Nombre de especialidad…" value={newEsp} onChange={(e)=>setNewEsp(e.target.value)} />
                <button className="btn" disabled={saving || !newEsp.trim()} onClick={crearYAgregar}>Crear y activar</button>
              </div>
              <p className="text-xs text-slate-500">Se creará en el catálogo global y quedará activa en esta clínica.</p>
            </div>
          </div>

          {/* Asignar a médicos */}
          <div className="card p-4 grid gap-4">
            <h3 className="font-semibold">Asignar especialidades a médicos</h3>

            {/* Habilitar como médico */}
            <div className="grid gap-2">
              <label className="text-sm">Habilitar usuario como médico</label>
              <div className="flex items-center gap-2 max-w-xl">
                <input
                  className="input flex-1"
                  placeholder="email@dominio.com"
                  value={promoteEmail}
                  onChange={(e)=>setPromoteEmail(e.target.value)}
                />
                <button className="btn" disabled={promoting || !promoteEmail.trim()} onClick={habilitarComoMedico}>
                  Habilitar
                </button>
              </div>
              <p className="text-xs text-slate-500">
                Solo los <b>admins</b> de la clínica pueden cambiar roles. Luego podrás asignarle especialidades.
              </p>
            </div>

            <div className="grid sm:grid-cols-2 gap-4">
              <div className="grid gap-2">
                <label className="text-sm">Buscar médico</label>
                <input className="input" placeholder="Nombre o email" value={qMed} onChange={(e)=>setQMed(e.target.value)} />
                {loadingMed ? <span className="text-xs text-slate-500">Buscando…</span> : null}
                <ul className="border rounded divide-y max-h-64 overflow-auto">
                  {medicos.map(m => (
                    <li key={m.id}
                        className={`p-2 cursor-pointer hover:bg-slate-50 ${selMed?.id===m.id?'bg-slate-50':''}`}
                        onClick={() => { setSelMed(m); loadEspMedico(m.id)}}
                    >
                      <div className="font-medium text-sm">{m.nombre || m.email}</div>
                      <div className="text-xs text-slate-500">{m.email}</div>
                    </li>
                  ))}
                  {(!loadingMed && medicos.length === 0) && (
                    <li className="p-2 text-xs text-slate-500">Sin resultados.</li>
                  )}
                </ul>
              </div>

              {/* Especialidades para asignar */}
              <div className="grid gap-2">
                <label className="text-sm">Especialidades activas</label>
                {!selMed ? (
                  <p className="text-sm text-slate-500">Selecciona un médico para ver/asignar.</p>
                ) : espActivas.length === 0 ? (
                  <p className="text-sm text-slate-500">No hay especialidades activas en la clínica.</p>
                ) : (
                  <ul className="border rounded divide-y max-h-64 overflow-auto">
                    {espActivas.map(e => {
                      const asignada = isAsignada(e.id)
                      return (
                        <li key={e.id} className="p-2 flex items-center justify-between">
                          <span className="text-sm">{e.nombre}</span>
                          {asignada ? (
                            <button className="btn" disabled={saving} onClick={() => delAsignacion(e.id)}>Quitar</button>
                          ) : (
                            <button className="btn" disabled={saving} onClick={() => addAsignacion(e.id)}>Asignar</button>
                          )}
                        </li>
                      )
                    })}
                  </ul>
                )}
              </div>
            </div>
          </div>
        </>
      )}
    </section>
  )
}
