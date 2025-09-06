"use client";
import { useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/browser";
import { useRouter } from "next/navigation";
import Input from "@/components/ui/Input";

export default function LoginPage() {
  const supabase = supabaseBrowser;
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    setLoading(false);
    if (error) return setError(error.message);
    if (data.session) router.push("/dashboard");
  };

  return (
    <div className="max-w-md mx-auto card p-6">
      <h2 className="text-2xl font-semibold">Iniciar sesión</h2>
      <form className="mt-4 space-y-3" onSubmit={onSubmit}>
        <Input
          placeholder="Email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <Input
          placeholder="Contraseña"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        {error && <p className="text-red-600 text-sm">{error}</p>}
        <button className="btn w-full" disabled={loading}>
          {loading ? "Ingresando…" : "Entrar"}
        </button>
      </form>
    </div>
  );
}
