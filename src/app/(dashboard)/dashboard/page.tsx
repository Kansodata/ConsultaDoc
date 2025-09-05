import { supabaseBrowser } from '@/lib/supabase/browser'


export default async function DashboardPage() {
// Placeholder serverless fetch; en producción usar Server Components con cookies
return (
<section className="grid gap-4 md:grid-cols-3">
<div className="card p-6"><h3 className="font-semibold">Citas de hoy</h3><p className="text-sm">Próximamente…</p></div>
<div className="card p-6"><h3 className="font-semibold">Pacientes</h3><p className="text-sm">Próximamente…</p></div>
<div className="card p-6"><h3 className="font-semibold">Mi disponibilidad</h3><p className="text-sm">Próximamente…</p></div>
</section>
)
}