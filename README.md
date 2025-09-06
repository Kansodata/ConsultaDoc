# ConsultaDoc

SaaS para gestión de consultas médicas. Stack: Next.js + Supabase.

## Setup rápido

1. Copia `.env.local` desde `.env.local.example`.
2. `npm i`
3. `npm run dev`
4. Configura Supabase y ejecuta `supabase db push` con las migraciones.

## Scripts

- `dev`: entorno local
- `build` / `start`: producción

## Testing

Actualmente no hay pruebas automatizadas.

Para añadirlas en el futuro:

1. Instala dependencias de testing: `npm install --save-dev jest @testing-library/react @testing-library/jest-dom`.
2. Agrega el script `"test": "jest"` en `package.json`.
3. Crea archivos de prueba en `__tests__/` o junto a los componentes.

## Seguridad

- RLS activo en todas las tablas.
- Usa Service Role solo en Server Actions seguras.
