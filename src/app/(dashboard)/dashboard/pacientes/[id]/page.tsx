'use client'

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { supabaseBrowser } from '@/lib/supabase/browser'

type Perfil = {
  telefono?: string | null
  fecha_nacimiento?: string | null
  sexo?: string | null
  direccion?: string | null
  ciudad?: string | null
  region?: string | null
  alergias?: string | null
}

type Nota = {
  id: string
  texto: string
  compartir_con_paciente: boolean
  created_at: string
  medico_id: string
}

type Archivo = {
  id: string
  path: string
  nombre: string
  mime: string | null
  size: number | null
  compartir_con_paciente: boolean
  created_at: string
}

export default function PacienteFichaPage() {
  const { id } = useParams<{ id: string }>()
  const supabase = supabaseBrowser()
  const [clinicaId, setClinicaId] = useState<string>('')

  const [userEmail, setUserEmail] = useState<string>('')
  const [userName, setUserName] = useState<string>('')

  const [perfil, setPerfil] = useState<Perfil>({})
  const [saving, setSaving] = useState(false)

  const [notas, setNotas] = useState<Nota[]>([])
  const [nuevaNota, setNuevaNota] = useState('')
  const [compartirNota, setCompartirNota] = useState(false)

  const [archivos, setArchivos] = useState<Archivo[]>([])
  const [subiendo, setSubiendo] = useState(false)

  // Carga clínica actual + datos base
  useEffect(() => {
    (async () => {
      const { data: s } = await supabase.auth.getSession()
      const uid = s.session?.user.id
      if (!uid) return
      const { data: cu } = await supabase
        .from('clinicas_usuarios')
        .select('clinica_id')
        .eq('usuario_id', uid)
        .limit(1)
        .maybeSingle()
      if (cu) setClinicaId(cu.clinica_id)

      // auth.users (solo lectura vía admin endpoints no disponibles desde cliente,
      // así que lo tomamos de registros de las tablas/funciones: listar_pacientes ya lo expone).
      // Como fallback, pedimos por RPC listar_pacientes con filtro preciso:
      if (cu) {
        const { data } = await supabase.rpc('listar_pacientes', { p_clinica: cu.clinica_id, p_q: null })
        const me = (data as any[])?.find(x => x.id === id)
        if (me) {
          setUserEmail(me.email)
          setUserName(me.nombre || '')
        }
      }

      // Perfil
      const { data: pf } = await supabase
        .from('paciente_perfil')
        .select('*')
        .eq('paciente_id', id)
        .maybeSingle()
      if (pf) setPerfil(pf)
      // Notas
      await cargarNotas()
      // Archivos
      await cargarArchivos()
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, supabase])

  async function cargarNotas() {
    if (!clinicaId) return
    const { data } = await supabase
      .from('paciente_notas')
      .select('id, texto, compartir_con_paciente, created_at, medico_id')
      .eq('clinica_id', clinicaId)
      .eq('paciente_id', id)
      .order('created_at', { ascending: false })
    setNotas((data as Nota[]) ?? [])
  }

  async function cargarArchivos() {
    if (!clinicaId) return
    const { data } = await supabase
      .from('paciente_archivos')
      .select('id, path, nombre, mime, size, compartir_con_paciente, created_at')
      .eq('clinica_id', clinicaId)
      .eq('paciente_id', id)
      .order('created_at', { ascending: false })
    setArchivos((data as Archivo[]) ?? [])
  }

  async function guardarPerfil() {
    setSaving(true)
    const { error } = await supabase.rpc('upsert_paciente_perfil', {
      p_paciente: id,
      p_telefono: perfil.telefono ?? null,
      p_fecha_nac: perfil.fecha_nacimiento ?? null,
      p_sexo: perfil.sexo ?? null,
      p_direccion: perfil.direccion ?? null,
      p_ciudad: perfil.ciudad ?? null,
      p_region: perfil.region ?? null,
      p_alergias: perfil.alergias ?? null
    })
    setSaving(false)
    if (error) alert(error.message)
    else alert('Perfil guardado')
  }

  async function crearNota() {
    if (!nuevaNota.trim() || !clinicaId) return
    const { error } = await supabase.rpc('crear_nota_paciente', {
      p_clinica: clinicaId,
      p_paciente: id,
      p_texto: nuevaNota.trim(),
      p_compartir: compartirNota
    })
    if (error) return alert(error.message)
    setNuevaNota('')
    setCompartirNota(false)
    cargarNotas()
  }

  async function subirArchivo(e: React.ChangeEvent<HTMLInputElement>) {
    if (!e.target.files || !clinicaId) return
    const file = e.target.files[0]
    if (!file) return
    setSubiendo(true)
    try {
      const path = `${clinicaId}/${id}/${Date.now()}_${file.name}`
      const { error: upErr } = await supabase.storage
        .from('pacientes')
        .upload(path, file, { cacheControl: '3600', upsert: false })
      if (upErr) throw upErr

      // guarda metadatos
      const { error: dbErr } = await supabase
        .from('paciente_archivos')
        .insert({
          clinica_id: clinicaId,
          paciente_id: id,
          medico_id: (await supabase.auth.getUser()).data.user?.id,
          path,
          nombre: file.name,
          mime: file.type,
          size: file.size,
          compartir_con_paciente: false
        } as any)
      if (dbErr) throw dbErr

      await cargarArchivos()
    } catch (err: any) {
      alert(err.message)
    } finally {
      setSubiendo(false)
      e.target.value = ''
    }
  }

  async function descargarArchivo(path: string) {
    const { data, error } = await supabase.storage
      .from('pacientes')
      .createSignedUrl(path, 60)
    if (error || !data?.signedUrl) return alert(error?.message || 'No se pudo generar URL')
    window.open(data.signedUrl, '_blank')
  }

  return (
    <section className="p-6 grid gap-6">
      <div>
        <h2 className="text-xl font-semibold">Ficha del paciente</h2>
        <div className="text-sm text-slate-600">
          {userName ? <span className="mr-2">{userName}</span> : null}
          <span>{userEmail}</span>
        </div>
      </div>

      {/* Datos del perfil */}
      <div className="card p-4 grid gap-3">
        <h3 className="font-semibold">Datos generales</h3>
        <div className="grid sm:grid-cols-2 gap-3">
          <input className="input" placeholder="Teléfono"
                 value={perfil.telefono ?? ''} onChange={e=>setPerfil(p=>({...p, telefono:e.target.value}))} />
          <input className="input" type="date" placeholder="Fecha de nacimiento"
                 value={perfil.fecha_nacimiento ?? ''} onChange={e=>setPerfil(p=>({...p, fecha_nacimiento:e.target.value}))} />
          <input className="input" placeholder="Sexo"
                 value={perfil.sexo ?? ''} onChange={e=>setPerfil(p=>({...p, sexo:e.target.value}))} />
          <input className="input" placeholder="Ciudad"
                 value={perfil.ciudad ?? ''} onChange={e=>setPerfil(p=>({...p, ciudad:e.target.value}))} />
          <input className="input sm:col-span-2" placeholder="Dirección"
                 value={perfil.direccion ?? ''} onChange={e=>setPerfil(p=>({...p, direccion:e.target.value}))} />
          <input className="input" placeholder="Región"
                 value={perfil.region ?? ''} onChange={e=>setPerfil(p=>({...p, region:e.target.value}))} />
          <input className="input sm:col-span-2" placeholder="Alergias"
                 value={perfil.alergias ?? ''} onChange={e=>setPerfil(p=>({...p, alergias:e.target.value}))} />
        </div>
        <div className="flex justify-end">
          <button className="btn" onClick={guardarPerfil} disabled={saving}>
            {saving ? 'Guardando…' : 'Guardar'}
          </button>
        </div>
      </div>

      {/* Notas clínicas */}
      <div className="card p-4 grid gap-3">
        <h3 className="font-semibold">Notas clínicas</h3>
        <div className="grid gap-2">
          <textarea className="input" rows={3}
                    placeholder="Escribe una nota…"
                    value={nuevaNota}
                    onChange={(e)=>setNuevaNota(e.target.value)} />
          <label className="text-sm flex items-center gap-2">
            <input type="checkbox" checked={compartirNota} onChange={e=>setCompartirNota(e.target.checked)} />
            Compartir con el paciente
          </label>
          <div className="flex justify-end">
            <button className="btn" onClick={crearNota}>Agregar nota</button>
          </div>
        </div>
        <ul className="divide-y">
          {notas.map(n => (
            <li key={n.id} className="py-2">
              <div className="text-sm whitespace-pre-wrap">{n.texto}</div>
              <div className="text-xs text-slate-500">
                {new Date(n.created_at).toLocaleString()}
                {n.compartir_con_paciente ? ' · Compartida' : ''}
              </div>
            </li>
          ))}
          {notas.length === 0 && <p className="text-sm text-slate-500">Sin notas.</p>}
        </ul>
      </div>

      {/* Archivos */}
      <div className="card p-4 grid gap-3">
        <h3 className="font-semibold">Archivos</h3>
        <div className="flex items-center gap-3">
          <input type="file" onChange={subirArchivo} disabled={subiendo} />
          {subiendo && <span className="text-sm">Subiendo…</span>}
        </div>
        <ul className="divide-y">
          {archivos.map(a => (
            <li key={a.id} className="py-2 flex items-center justify-between">
              <div>
                <div className="font-medium text-sm">{a.nombre}</div>
                <div className="text-xs text-slate-500">
                  {a.mime || ''} · {(a.size ?? 0)/1024 | 0} KB · {new Date(a.created_at).toLocaleString()}
                </div>
              </div>
              <button className="btn" onClick={()=>descargarArchivo(a.path)}>Descargar</button>
            </li>
          ))}
          {archivos.length === 0 && <p className="text-sm text-slate-500">Sin archivos.</p>}
        </ul>
      </div>
    </section>
  )
}
