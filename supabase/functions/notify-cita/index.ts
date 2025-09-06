// Deno Deploy / Supabase Functions
// Enviar email "Cita creada" a paciente (y cc opcional al médico)
// Requiere: RESEND_API_KEY, FROM_EMAIL, PUBLIC_APP_URL, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL")!;
const APP_URL = Deno.env.get("PUBLIC_APP_URL") || "https://example.com";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Pequeño helper para leer cita + emails
async function getCita(citaId: string) {
  const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  const { data, error } = await supabase
    .from("citas")
    .select("id, fecha, fin, clinica_id, paciente_id, medico_id, motivo")
    .eq("id", citaId)
    .maybeSingle();
  if (error || !data) throw new Error("Cita no encontrada");

  const { data: p } = await supabase.auth.admin.getUserById(data.paciente_id);
  const { data: m } = await supabase.auth.admin.getUserById(data.medico_id);

  return { cita: data, paciente: p?.user, medico: m?.user };
}

async function sendEmail(to: string, subject: string, html: string) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [to],
      subject,
      html
    })
  });
  if (!r.ok) {
    const t = await r.text();
    throw new Error(`Resend error: ${t}`);
  }
}

serve(async (req) => {
  try {
    const { citaId } = await req.json();
    if (!citaId) return new Response("Missing citaId", { status: 400 });

    const { cita, paciente, medico } = await getCita(citaId);

    const ini = new Date(cita.fecha);
    const fin = new Date(cita.fin);
    const rango = `${ini.toLocaleString()} – ${fin.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`;

    const html = `
      <h2>Cita creada</h2>
      <p>Hola ${paciente?.user_metadata?.full_name ?? ""}, tu cita ha sido programada.</p>
      <ul>
        <li><b>Fecha:</b> ${rango}</li>
        <li><b>Médico:</b> ${medico?.user_metadata?.full_name ?? medico?.email}</li>
        <li><b>Motivo:</b> ${cita.motivo ?? "-"}</li>
      </ul>
      <p>Puedes ver tus citas en: <a href="${APP_URL}/dashboard">${APP_URL}/dashboard</a></p>
    `;

    await sendEmail(paciente?.email ?? "", "Tu cita fue creada", html);
    return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 500 });
  }
});
