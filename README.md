# ConsultaDoc

ConsultaDoc es un SaaS para la gestión integral de consultas médicas. Permite a clínicas y profesionales de la salud administrar pacientes, programar citas y mantener el seguimiento de los historiales médicos. La aplicación está construida con Next.js en el frontend y utiliza Supabase como backend y base de datos.

## Características esenciales

- Gestión de pacientes y historiales
- Programación de citas médicas
- Autenticación y control de acceso
- Integración con Supabase para almacenamiento y datos en tiempo real

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

## Testing

Actualmente no hay pruebas automatizadas.

Para añadirlas en el futuro:

1. Instala dependencias de testing: `npm install --save-dev jest @testing-library/react @testing-library/jest-dom`.
2. Agrega el script `"test": "jest"` en `package.json`.
3. Crea archivos de prueba en `__tests__/` o junto a los componentes.

## Seguridad

- RLS activo en todas las tablas.
- Usa Service Role solo en Server Actions seguras.
