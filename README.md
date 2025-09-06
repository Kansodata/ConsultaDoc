# ConsultaDoc

SaaS para gestión de consultas médicas. Stack: Next.js + Supabase.

## Requisitos

- Node.js 18.x y npm 9
  - Instala y usa nvm: `nvm install 18 && nvm use 18`
- Supabase CLI
  - Instala globalmente: `npm install -g supabase`

## Setup rápido

1. Copia `.env.local` desde `.env.local.example`.
2. `npm i`
3. `npm run dev`
4. Configura Supabase y ejecuta `supabase db push` con las migraciones.

## Scripts

- `dev`: entorno local
- `build` / `start`: producción

## Seguridad

- RLS activo en todas las tablas.
- Usa Service Role solo en Server Actions seguras.
