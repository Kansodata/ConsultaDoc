'use client'
import { useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'
import { useRouter } from 'next/navigation'


export default function NuevaCitaPage() {
const supabase = supabaseBrowser()
const router = useRouter()
const [fecha, setFecha] = useState('')
const [motivo, setMotivo] = useState('')
const [clinicaId, setClinicaId] = useState('')
const [pacienteId, setPacienteId] = useState('')
const [medicoId, setMedicoId] = useState('')
const [error, setError] = useState<string | null>(null)


const onSubmit = async (e: React.FormEvent) => {
e.preventDefault()
setError(null)
const { error } = await supabase.from('citas').insert({
clinica_id: clinicaId,
paciente_id: pacienteId,
medico_id: medicoId,
fecha: new Date(fecha).toISOString(),
motivo
})
if (error) return setError(error.message)
router.push('/dashboard/citas')
}


return (
<div className="max-w-lg card p-6 mx-auto">
<h2 className="text-xl font-semibold">Nueva cita</h2>
<form className="mt-4 space-y-3" onSubmit={onSubmit}>
<input className="input" placeholder="Clínica ID" value={clinicaId} onChange={e=>setClinicaId(e.target.value)} required />
<input className="input" placeholder="Paciente (UUID)" value={pacienteId} onChange={e=>setPacienteId(e.target.value)} required />
<input className="input" placeholder="Médico (UUID)" value={medicoId} onChange={e=>setMedicoId(e.target.value)} required />
<input className="input" type="datetime-local" value={fecha} onChange={e=>setFecha(e.target.value)} required />
<input className="input" placeholder="Motivo" value={motivo} onChange={e=>setMotivo(e.target.value)} />
{error && <p className="text-red-600 text-sm">{error}</p>}
<button className="btn w-full">Crear</button>
</form>
</div>
)
}