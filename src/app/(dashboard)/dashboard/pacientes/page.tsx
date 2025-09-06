'use client'

import { useEffect, useRef, useState, useMemo } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'

type Clinica = { id: string; nombre: string; rol: string }
type Prevision = { id: string; code: string; nombre: string; grupo: string; requiere_otro: boolean; activo: boolean }
type Paciente = {
  id: string
  nombre: string
  apellido: string | null
  rut: string | null
  email: string | null
  telefono: string | null
  direccion: string | null
  foto_url: string | null
  prevision_code: string | null
  prevision_nombre: string | null
  prevision_otro: string | null
}

export default function PacientesPage() {
  const supabase = supabaseBrowser()

  const [clinicaId, setClinicaId] = useState('')
  const [clinicas, setClinicas] = useState<Clinica[]>([])

  const [q, setQ] = useState('')
  const [loading, setLoading] = useState(false)
  const [list, setList] = useState<Paciente[]>([])
  const deb = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Catálogo de previsiones
  const [prevs, setPrevs] = useState<Prevision[]>([])
  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from('previsiones_salud')
        .select('id,code,nombre,grupo,requiere_otro,activo')
        .eq('activo', true)
      setPrevs((data as Prevision[] | null) ?? [])
    })()
  }, [supabase])

  const prevsPorGrupo = useMemo(() => {
    const m = new Map<string, Prevision[]>()
    prevs
      .slice()
      .sort((a, b) => a.grupo.localeCompare(b.grupo) || a.nombre.localeCompare(b.nombre))
      .forEach(p => {
        if (!m.has(p.grupo)) m.set(p.grupo, [])
        m.get(p.grupo)!.push(p)
      })
    return m
  }, [prevs])

  // Alta rápida
  const [openNew, setOpenNew] = useState(false)
  const [nNombre, setNNombre] = useState('')
  const [nApellido, setNApellido] = useState('')
  const [nRut, setNRut] = useState('')
  const [nEmail, setNEmail] = useState('')
  const [nTel, setNTel] = useState('')
  const [nDir, setNDir] = useState('')
  const [nNac, setNNac] = useState('')
  const [nPrevCode, setNPrevCode] = useState<string>('')
  const [nPrevOtro, setNPrevOtro] = useState('')
  const [saving, setSaving] = useState(false)

  // Foto
  const [uploadingId, setUploadingId] = useState<string | null>(null)

  // Clínicas del usuario
  useEffect(() => {
    (async () => {
      const { data } = await supabase.rpc('mis_clinicas', { p_q: null })
      const rows = (data as Clinica[]) ?? []
      setClinicas(rows)
      if (rows.length) setClinicaId(rows[0].id)
    })()
  }, [supabase])

  // Carga listado
  const load = async () => {
    if (!clinicaId) return
    setLoading(true)
    const { data, error } = await supabase.rpc('listar_pacientes_clinica', {
      p_clinica: clinicaId,
      p_q: q || null,
      p_limit: 100
    })
    setLoading(false)
    if (!error) setList((data as Paciente[]) ?? [])
  }
  useEffect(() => { load() }, [clinicaId]) // primera carga
  useEffect(() => {
    if (deb.current) clearTimeout(deb.current)
    deb.current = setTimeout(load, 300)
  }, [q]) // búsqueda

  // Crear
  const crear = async () => {
    if (!clinicaId || !nNombre.trim()) return
    // Si la previsión elegida requiere texto, validar
    const prevReq = prevs.find(p => p.code === nPrevCode)?.requiere_otro
    if (prevReq && !nPrevOtro.trim()) {
      alert('Debes indicar el detalle de la previsión (OTRA).')
      return
    }

    setSaving(true)
    try {
      const { data: idRes, error } = await supabase.rpc('crear_paciente', {
        p_clinica: clinicaId,
        p_nombre: nNombre.trim(),
        p_apellido: nApellido.trim() || null,
        p_rut: nRut.trim() || null,
        p_telefono: nTel.trim() || null,
        p_nacimiento: nNac || null,
        p_direccion: nDir.trim() || null,
        p_prevision_code: nPrevCode || null,
        p_prevision_otro: nPrevCode === 'OTRA' ? (nPrevOtro.trim() || null) : null,
        p_email: nEmail.trim() || null
      })
      if (error) throw error
      setOpenNew(false)
      setNNombre(''); setNApellido(''); setNRut(''); setNEmail(''); setNTel(''); setNDir(''); setNNac('')
      setNPrevCode(''); setNPrevOtro('')
      await load()
    } catch (e: any) {
      alert(e.message ?? 'No se pudo crear el paciente')
    } finally {
      setSaving(false)
    }
  }

  // Foto (Storage)
  const subirFoto = async (p: Paciente, file: File) => {
    if (!clinicaId || !file) return
    try {
      setUploadingId(p.id)
      const path = `${clinicaId}/${p.id}/avatar.jpg`
      const { error: upErr } = await supabase.storage.from('pacientes').upload(path, file, {
        contentType: file.type || 'image/jpeg',
        upsert: true
      })
      if (upErr) throw upErr

      // URL pública (getPublicUrl)
      const { data: pub } = await supabase.storage.from('pacientes').getPublicUrl(path)
      const url = pub.publicUrl

      const { error: updErr } = await supabase
        .from('pacientes')
        .update({ foto_url: url })
        .eq('id', p.id)
        .eq('clinica_id', clinicaId)
      if (updErr) throw updErr

      await load()
    } catch (e: any) {
      alert(e.message ?? 'No se pudo subir la foto')
    } finally {
      setUploadingId(null)
    }
  }

  return (
    <section className="p-6 grid gap-6">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Pacientes</h2>
        <div className="flex items-center gap-2">
          {clinicas.length > 0 && (
            <select className="input" value={clinicaId} onChange={(e)=>setClinicaId(e.target.value)}>
              {clinicas.map(c => <option key={c.id} value={c.id}>{c.nombre} {c.rol ? `· ${c.rol}` : ''}</option>)}
            </select>
          )}
          <button className="btn" onClick={() => setOpenNew(true)}>Nuevo</button>
        </div>
      </div>

      <div className="grid gap-2 max-w-lg">
        <input className="input" placeholder="Buscar por nombre, email, teléfono o RUT…" value={q} onChange={(e)=>setQ(e.target.value)} />
        {loading && <span className="text-xs text-slate-500">Cargando…</span>}
      </div>

      {list.length === 0 ? (
        <p className="text-sm text-slate-500">Sin resultados.</p>
      ) : (
        <ul className="grid gap-2">
          {list.map(p => (
            <li key={p.id} className="card p-3 flex items-center justify-between gap-3">
              <div className="flex items-center gap-3">
                {p.foto_url ? (
                  <img src={p.foto_url} alt={p.nombre} className="h-12 w-12 rounded-full object-cover" />
                ) : (
                  <div className="h-12 w-12 rounded-full bg-slate-200" />
                )}
                <div>
                  <div className="font-medium">
                    {p.nombre}{p.apellido ? ` ${p.apellido}` : ''}
                  </div>
                  <div className="text-xs text-slate-500">
                    {p.email || '—'} · {p.telefono || '—'} · {p.rut || '—'}
                  </div>
                  <div className="text-[11px] text-slate-500">
                    {p.prevision_nombre ? `Previsión: ${p.prevision_nombre}${p.prevision_otro ? ` (${p.prevision_otro})` : ''}` : 'Sin previsión'}
                  </div>
                </div>
              </div>

              <label className="text-xs cursor-pointer">
                <input
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={(e)=> e.target.files?.[0] && subirFoto(p, e.target.files[0])}
                />
                <span className="btn">{uploadingId===p.id ? 'Subiendo…' : 'Actualizar foto'}</span>
              </label>
            </li>
          ))}
        </ul>
      )}

      {/* Modal Nuevo paciente */}
      {openNew && (
        <div className="fixed inset-0 bg-black/40 grid place-items-center z-50">
          <div className="card p-5 w-full max-w-2xl grid gap-3">
            <h3 className="font-semibold">Nuevo paciente</h3>

            <div className="grid md:grid-cols-2 gap-3">
              <input className="input" placeholder="Nombre *" value={nNombre} onChange={(e)=>setNNombre(e.target.value)} />
              <input className="input" placeholder="Apellido" value={nApellido} onChange={(e)=>setNApellido(e.target.value)} />
            </div>

            <div className="grid md:grid-cols-2 gap-3">
              <input className="input" placeholder="RUT (ej. 12.345.678-9)" value={nRut} onChange={(e)=>setNRut(e.target.value)} />
              <input className="input" placeholder="Teléfono" value={nTel} onChange={(e)=>setNTel(e.target.value)} />
            </div>

            <div className="grid md:grid-cols-2 gap-3">
              <input className="input" placeholder="Email" value={nEmail} onChange={(e)=>setNEmail(e.target.value)} />
              <div className="grid gap-1">
                <label className="text-sm">Fecha de nacimiento</label>
                <input className="input" type="date" value={nNac} onChange={(e)=>setNNac(e.target.value)} />
              </div>
            </div>

            <input className="input" placeholder="Dirección" value={nDir} onChange={(e)=>setNDir(e.target.value)} />

            {/* Previsión */}
            <div className="grid md:grid-cols-2 gap-3">
              <div className="grid gap-1">
                <label className="text-sm">Previsión</label>
                <select className="input" value={nPrevCode} onChange={(e)=>setNPrevCode(e.target.value)}>
                  <option value="">— Selecciona —</option>
                  {[...prevsPorGrupo.entries()].map(([grupo, arr]) => (
                    <optgroup key={grupo} label={grupo}>
                      {arr.map(p => (
                        <option key={p.id} value={p.code}>{p.nombre}</option>
                      ))}
                    </optgroup>
                  ))}
                </select>
              </div>

              {prevs.find(p => p.code === nPrevCode)?.requiere_otro && (
                <div className="grid gap-1">
                  <label className="text-sm">Detalle (OTRA)</label>
                  <input className="input" placeholder="Especifica la previsión" value={nPrevOtro} onChange={(e)=>setNPrevOtro(e.target.value)} />
                </div>
              )}
            </div>

            <div className="flex gap-2 justify-end pt-2">
              <button className="btn" onClick={()=>setOpenNew(false)} type="button">Cancelar</button>
              <button
                className="btn"
                onClick={crear}
                disabled={saving || !nNombre.trim() || (prevs.find(p => p.code === nPrevCode)?.requiere_otro && !nPrevOtro.trim())}
              >
                {saving ? 'Guardando…' : 'Guardar'}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  )
}
