export default function Footer(){
return (
<footer className="mt-10 border-t">
<div className="container py-6 text-sm flex items-center justify-between flex-wrap gap-2">
<span>© {new Date().getFullYear()} Kansodata SpA. Todos los derechos reservados.</span>
<a href="https://github.com/Kansodata/ConsultaDoc" className="underline">Repositorio</a>
</div>
</footer>
)
}