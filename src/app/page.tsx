import Link from "next/link";

export default function HomePage() {
  return (
    <section className="container">
      <div className="card p-8 text-center">
        <h1 className="text-3xl font-semibold">ConsultaDoc</h1>
        <p className="mt-2">
          Agenda y gestiona consultas médicas de forma segura.
        </p>
        <Link href="/login" className="btn mt-6">
          Ingresar
        </Link>
      </div>
    </section>
  );
}
