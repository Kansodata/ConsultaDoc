'use client'
import Link from 'next/link'
import { useEffect, useState } from 'react'
import { supabaseBrowser } from '@/lib/supabase/browser'


export default function Navbar(){
const supabase = supabaseBrowser()
const [logged, setLogged] = useState(false)


useEffect(() => {
supabase.auth.getSession().then(({ data }) => setLogged(!!data.session))
const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setLogged(!!s))
return () => { sub.subscription.unsubscribe() }
}, [])


return (
<nav className="border-b bg-white">
<div className="container h-14 flex items-center justify-between">
<Link href="/" className="font-semibold">ConsultaDoc</Link>
<div className="flex items-center gap-3">
{logged ? (
<>
<Link className="btn" href="/dashboard">Dashboard</Link>
<button className="btn" onClick={() => supabase.auth.signOut()}>Salir</button>
</>
) : (
<Link className="btn" href="/login">Ingresar</Link>
)}
</div>
</div>
</nav>
)
}