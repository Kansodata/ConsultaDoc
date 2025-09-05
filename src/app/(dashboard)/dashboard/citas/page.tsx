'use client'
import { useEffect, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'


type Cita = { id: string; fecha: string; estado: string; motivo: string }


export default function CitasPage() {
const supabase = supabaseBrowser()
const [citas, setCitas] = useState<Cita[]>([])


useEffect(() => {
const load = async () => {
const { data } = await supabase
.from('citas')
.select('id, fecha, estado, motivo')
.order('fecha', { ascending: true })
.limit(50)
setCitas(data || [])
}
load()
}, [])


return (
<div className="card p-6">
<div className="flex items-center justify-between flex-wrap gap-2">
<h2 className="text-xl font-semibold">Citas</h2>
<a href="/dashboard/citas/nueva" className="btn">Nueva cita</a>
</div>
<div className="mt-4 overflow-x-auto">
<table className="min-w-full text-sm">
<thead>
<tr className="text-left">
<th className="py-2 pr-4">Fecha</th>
<th className="py-2 pr-4">Estado</th>
<th className="py-2 pr-4">Motivo</th>
</tr>
</thead>
<tbody>
{citas.map(c => (
<tr key={c.id} className="border-t">
<td className="py-2 pr-4">{new Date(c.fecha).toLocaleString()}</td>
<td className="py-2 pr-4 capitalize">{c.estado}</td>
<td className="py-2 pr-4">{c.motivo ?? '—'}</td>
</tr>
))}
</tbody>
</table>
</div>
</div>
)
}