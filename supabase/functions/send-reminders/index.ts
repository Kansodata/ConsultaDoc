import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function sendEmail(to: string, subject: string, html: string) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ from: FROM_EMAIL, to: [to], subject, html })
  });
  if (!r.ok) throw new Error(await r.text());
}

serve(async () => {
  const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  // 1) Tomar recordatorios vencidos
  const { data: recs, error } = await supabase
    .from("cita_recordatorios")
    .select("id, cita_id")
    .eq("status", "pendiente")
    .lte("send_at", new Date().toISOString())
    .limit(100);
  if (error) throw error;

  for (const r of recs ?? []) {
    try {
      // 2) Datos de la cita + emails
      const { data: cita } = await supabase
        .from("citas")
        .select("id, fecha, fin, motivo, paciente_id, medico_id")
        .eq("id", r.cita_id).maybeSingle();

      if (!cita) throw new Error("cita no encontrada");

      const { data: p } = await supabase.auth.admin.getUserById(cita.paciente_id);
      const { data: m } = await supabase.auth.admin.getUserById(cita.medico_id);

      const ini = new Date(cita.fecha);
      const fin = new Date(cita.fin);
      const rango = `${ini.toLocaleString()} – ${fin.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`;

      // 3) Email
      const html = `
        <h2>Recordatorio de cita</h2>
        <p>Hola ${p?.user.user_metadata?.full_name ?? ""}, te recordamos tu cita:</p>
        <ul>
          <li><b>Fecha:</b> ${rango}</li>
          <li><b>Médico:</b> ${m?.user.user_metadata?.full_name ?? m?.user.email}</li>
          <li><b>Motivo:</b> ${cita.motivo ?? "-"}</li>
        </ul>
      `;

      await sendEmail(p?.user.email ?? "", "Recordatorio de cita", html);

      // 4) Marcar enviado
      await supabase
        .from("cita_recordatorios")
        .update({ status: "enviado", last_error: null })
        .eq("id", r.id);
    } catch (e) {
      await supabase
        .from("cita_recordatorios")
        .update({ status: "fallido", last_error: String(e) })
        .eq("id", r.id);
    }
  }

  return new Response(JSON.stringify({ processed: recs?.length ?? 0 }), {
    headers: { "Content-Type": "application/json" },
  });
});
