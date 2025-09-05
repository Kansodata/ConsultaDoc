import './styles/globals.css'
import Navbar from '@/components/Navbar'
import Footer from '@/components/Footer'


export const metadata = { title: 'ConsultaDoc', description: 'SaaS de consultas médicas' }


export default function RootLayout({ children }: { children: React.ReactNode }) {
return (
<html lang="es">
<body>
<Navbar />
<main className="container py-6 min-h-[70vh]">{children}</main>
<Footer />
</body>
</html>
)
}