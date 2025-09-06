

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "public"."estado_cita" AS ENUM (
    'pendiente',
    'confirmada',
    'cancelada',
    'realizada',
    'no_show'
);


ALTER TYPE "public"."estado_cita" OWNER TO "postgres";


CREATE TYPE "public"."prevision_salud" AS ENUM (
    'FONASA',
    'ISAPRE_CONSALUD',
    'ISAPRE_COLMENA',
    'ISAPRE_BANMEDICA',
    'ISAPRE_VIDA_TRES',
    'ISAPRE_NUEVA_MASVIDA',
    'ISAPRE_CRUZ_BLANCA',
    'CAPREDENA',
    'DIPRECA',
    'PARTICULAR',
    'OTRA'
);


ALTER TYPE "public"."prevision_salud" OWNER TO "postgres";


CREATE TYPE "public"."rol_clinica" AS ENUM (
    'admin',
    'medico',
    'recepcion',
    'paciente'
);


ALTER TYPE "public"."rol_clinica" OWNER TO "postgres";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "public"."actualizar_foto_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_foto_url" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not es_staff_de_clinica(p_clinica) then
    raise exception 'No autorizado';
  end if;

  update public.pacientes
     set foto_url = nullif(p_foto_url,'')
   where id = p_id and clinica_id = p_clinica;
end;
$$;


ALTER FUNCTION "public"."actualizar_foto_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_foto_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_nombre" "text" DEFAULT NULL::"text", "p_email" "text" DEFAULT NULL::"text", "p_telefono" "text" DEFAULT NULL::"text", "p_documento" "text" DEFAULT NULL::"text", "p_nacimiento" "date" DEFAULT NULL::"date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not es_staff_de_clinica(p_clinica) then
    raise exception 'No autorizado';
  end if;

  update public.pacientes
     set nombre     = coalesce(nullif(p_nombre,''), nombre),
         email      = case when p_email is null then email else nullif(p_email,'') end,
         telefono   = case when p_telefono is null then telefono else nullif(p_telefono,'') end,
         documento  = case when p_documento is null then documento else nullif(p_documento,'') end,
         nacimiento = coalesce(p_nacimiento, nacimiento)
   where id = p_id and clinica_id = p_clinica;
end;
$$;


ALTER FUNCTION "public"."actualizar_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."agregar_especialidad_a_clinica"("p_clinica" "uuid", "p_especialidad" "uuid", "p_nombre_publico" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.clinica_especialidades (clinica_id, especialidad_id, nombre_publico, activa)
  values (p_clinica, p_especialidad, p_nombre_publico, true)
  on conflict (clinica_id, especialidad_id) do update
    set nombre_publico = coalesce(excluded.nombre_publico, clinica_especialidades.nombre_publico),
        activa = true;
end;
$$;


ALTER FUNCTION "public"."agregar_especialidad_a_clinica"("p_clinica" "uuid", "p_especialidad" "uuid", "p_nombre_publico" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."aplicar_plantilla_disponibilidad"("p_clinica" "uuid", "p_medico" "uuid", "p_tramos" "jsonb", "p_reemplazar" boolean DEFAULT true) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_ins int := 0;
  r record;
begin
  -- ✅ Permisos: solo médico o admin de la clínica
  if not tiene_rol_en_clinica(p_clinica, array['admin','medico']) then
    raise exception 'No autorizado';
  end if;

  -- 🧹 Si se solicita reemplazar, borra dispo del médico en los días de la plantilla
  if p_reemplazar then
    delete from public.disponibilidad_medica dm
    using (
      select distinct (e->>'dia_semana')::int as d
      from jsonb_array_elements(p_tramos) e
    ) dias
    where dm.clinica_id = p_clinica
      and dm.medico_id  = p_medico
      and dm.dia_semana = dias.d;
  end if;

  -- ➕ Inserta todos los tramos de la plantilla
  for r in
    select
      (e->>'dia_semana')::int  as dia_semana,
      (e->>'inicio')::time     as hora_inicio,
      (e->>'fin')::time        as hora_fin
    from jsonb_array_elements(p_tramos) e
  loop
    insert into public.disponibilidad_medica
      (clinica_id, medico_id, dia_semana, hora_inicio, hora_fin, vigente)
    values
      (p_clinica, p_medico, r.dia_semana, r.hora_inicio, r.hora_fin, true);
    v_ins := v_ins + 1;
  end loop;

  return v_ins;
end;
$$;


ALTER FUNCTION "public"."aplicar_plantilla_disponibilidad"("p_clinica" "uuid", "p_medico" "uuid", "p_tramos" "jsonb", "p_reemplazar" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.clinicas_usuarios (clinica_id, usuario_id, rol)
  values (p_clinica, p_usuario, 'paciente')
  on conflict (clinica_id, usuario_id) do nothing;
end;
$$;


ALTER FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text" DEFAULT 'paciente'::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_exists boolean;
begin
  -- Solo miembros de la clínica pueden afiliar a otros (recepción/admin/médico)
  if not tiene_rol_en_clinica(p_clinica, array['admin','recepcion','medico']) then
    raise exception 'No autorizado';
  end if;

  select exists(
    select 1 from public.clinicas_usuarios
     where clinica_id = p_clinica and usuario_id = p_usuario
  ) into v_exists;

  if not v_exists then
    insert into public.clinicas_usuarios (clinica_id, usuario_id, rol)
    values (p_clinica, p_usuario, coalesce(nullif(p_rol,''),'paciente'))
    on conflict (clinica_id, usuario_id) do nothing;
    return true;   -- se insertó
  end if;

  return false;    -- ya existía
end;
$$;


ALTER FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."asignar_especialidad_medico"("p_clinica" "uuid", "p_medico" "uuid", "p_especialidad" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.medico_especialidades (clinica_id, medico_id, especialidad_id)
  values (p_clinica, p_medico, p_especialidad)
  on conflict do nothing;
end;
$$;


ALTER FUNCTION "public"."asignar_especialidad_medico"("p_clinica" "uuid", "p_medico" "uuid", "p_especialidad" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."asignar_rol_en_clinica"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not exists (
    select 1 from public.clinicas_usuarios cu
    where cu.clinica_id = p_clinica
      and cu.usuario_id = auth.uid()
      and cu.rol = 'admin'
  ) then
    raise exception 'Solo un admin de la clínica puede cambiar roles';
  end if;

  if p_rol not in ('admin','medico','recepcion','paciente') then
    raise exception 'Rol inválido';
  end if;

  insert into public.clinicas_usuarios (clinica_id, usuario_id, rol)
  values (p_clinica, p_usuario, p_rol)
  on conflict (clinica_id, usuario_id) do update set rol = excluded.rol;
end;
$$;


ALTER FUNCTION "public"."asignar_rol_en_clinica"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_medicos"("p_clinica" "uuid", "p_q" "text") RETURNS TABLE("id" "uuid", "email" "text", "nombre" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    u.id,
    u.email,
    coalesce(u.raw_user_meta_data->>'full_name','') as nombre
  from public.clinicas_usuarios cu
  join auth.users u on u.id = cu.usuario_id
  where cu.clinica_id = p_clinica
    and cu.rol = 'medico'
    and (
      p_q is null
      or u.email ilike '%'||p_q||'%'
      or (u.raw_user_meta_data->>'full_name') ilike '%'||p_q||'%'
    )
  order by u.email asc
  limit 30;
$$;


ALTER FUNCTION "public"."buscar_medicos"("p_clinica" "uuid", "p_q" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "email" "text", "nombre" "text", "especialidad" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    u.id,
    u.email,
    coalesce(u.raw_user_meta_data->>'full_name','') as nombre,
    coalesce(u.raw_user_meta_data->>'especialidad','') as especialidad
  from public.clinicas_usuarios cu
  join auth.users u on u.id = cu.usuario_id
  where cu.clinica_id = p_clinica
    and cu.rol = 'medico'
    and (
      p_q is null
      or u.email ilike '%'||p_q||'%'
      or (u.raw_user_meta_data->>'full_name') ilike '%'||p_q||'%'
    )
    and (
      p_especialidad is null
      or (u.raw_user_meta_data->>'especialidad') ilike p_especialidad
    )
  order by u.email asc
  limit 30;
$$;


ALTER FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text" DEFAULT NULL::"text", "p_especialidad" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "email" "text", "nombre" "text", "especialidad" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with base as (
    select u.id, u.email, coalesce(u.raw_user_meta_data->>'full_name','') as nombre
    from public.clinicas_usuarios cu
    join auth.users u on u.id = cu.usuario_id
    where cu.clinica_id = p_clinica
      and cu.rol in ('medico','admin')  -- ← antes solo 'medico'
      and (p_q is null
           or u.email ilike '%'||p_q||'%'
           or (u.raw_user_meta_data->>'full_name') ilike '%'||p_q||'%')
  ),
  fil as (
    select b.*
    from base b
    where p_especialidad is null
       or exists (
          select 1 from public.medico_especialidades me
          where me.clinica_id = p_clinica and me.medico_id = b.id and me.especialidad_id = p_especialidad
       )
  )
  select f.id, f.email, f.nombre,
         coalesce(string_agg(e.nombre, ', ' order by e.nombre), '') as especialidad
  from fil f
  left join public.medico_especialidades me
    on me.clinica_id = p_clinica and me.medico_id = f.id
  left join public.especialidades e on e.id = me.especialidad_id
  group by f.id, f.email, f.nombre
  order by f.nombre, f.email
  limit 100;
$$;


ALTER FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_pacientes"("p_clinica" "uuid", "p_q" "text") RETURNS TABLE("id" "uuid", "email" "text", "nombre" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    u.id,
    u.email,
    coalesce(u.raw_user_meta_data->>'full_name','') as nombre
  from auth.users u
  where
    p_q is null
    or u.email ilike '%'||p_q||'%'
    or (u.raw_user_meta_data->>'full_name') ilike '%'||p_q||'%'
  order by u.email asc
  limit 20;
$$;


ALTER FUNCTION "public"."buscar_pacientes"("p_clinica" "uuid", "p_q" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_usuario_por_email"("p_email" "text") RETURNS TABLE("id" "uuid", "email" "text", "nombre" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select u.id, u.email, coalesce(u.raw_user_meta_data->>'full_name','') as nombre
  from auth.users u
  where lower(u.email) = lower(p_email)
  limit 1;
$$;


ALTER FUNCTION "public"."buscar_usuario_por_email"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancelar_cita"("p_cita" "uuid", "p_motivo" "text" DEFAULT 'Cancelada por staff'::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v record;
begin
  select c.*, cu.rol
    into v
  from public.citas c
  join public.clinicas_usuarios cu
    on cu.clinica_id = c.clinica_id and cu.usuario_id = auth.uid()
  where c.id = p_cita;

  if not found then
    raise exception 'Cita no encontrada o sin permisos';
  end if;

  if v.rol not in ('admin','recepcion','medico') then
    raise exception 'No autorizado';
  end if;

  update public.citas
     set estado = 'cancelada',
         motivo = coalesce(p_motivo, motivo)
   where id = v.id;

  insert into public.cita_eventos(cita_id, actor_id, evento, detalle)
  values (v.id, auth.uid(), 'cancelada', p_motivo);

  -- Cancelar recordatorios pendientes
  update public.cita_recordatorios
     set status = 'cancelado'
   where cita_id = v.id and status = 'pendiente';

  return v.id;
end;
$$;


ALTER FUNCTION "public"."cancelar_cita"("p_cita" "uuid", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirmar_cita"("p_cita" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  update public.citas c
  set estado = 'confirmada'
  where c.id = p_cita
    and (
      c.medico_id = auth.uid()
      or exists (
        select 1 from public.clinicas_usuarios cu
        where cu.clinica_id = c.clinica_id
          and cu.usuario_id = auth.uid()
          and cu.rol in ('admin','recepcion')
      )
    );
$$;


ALTER FUNCTION "public"."confirmar_cita"("p_cita" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirmar_cita"("p_cita" "uuid", "p_detalle" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v record;
begin
  select c.*, cu.rol
    into v
  from public.citas c
  join public.clinicas_usuarios cu
    on cu.clinica_id = c.clinica_id and cu.usuario_id = auth.uid()
  where c.id = p_cita;

  if not found then
    raise exception 'Cita no encontrada o sin permisos';
  end if;

  if v.rol not in ('admin','recepcion','medico') then
    raise exception 'No autorizado';
  end if;

  update public.citas
     set estado = 'confirmada'
   where id = v.id;

  insert into public.cita_eventos(cita_id, actor_id, evento, detalle)
  values (v.id, auth.uid(), 'confirmada', p_detalle);

  -- Opcional: reprogramar recordatorios (por si venía 'pendiente')
  perform public.programar_recordatorios_cita(v.id);

  return v.id;
end;
$$;


ALTER FUNCTION "public"."confirmar_cita"("p_cita" "uuid", "p_detalle" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_paciente"("p_clinica" "uuid", "p_nombre" "text", "p_email" "text" DEFAULT NULL::"text", "p_telefono" "text" DEFAULT NULL::"text", "p_documento" "text" DEFAULT NULL::"text", "p_nacimiento" "date" DEFAULT NULL::"date") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_id uuid;
begin
  if not es_staff_de_clinica(p_clinica) then
    raise exception 'No autorizado';
  end if;

  insert into public.pacientes (clinica_id, nombre, email, telefono, documento, nacimiento)
  values (
    p_clinica,
    trim(p_nombre),
    nullif(p_email, ''),
    nullif(p_telefono, ''),
    nullif(p_documento, ''),
    p_nacimiento
  )
  returning id into v_id;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."crear_paciente"("p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."eliminar_paciente"("p_id" "uuid", "p_clinica" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not es_staff_de_clinica(p_clinica) then
    raise exception 'No autorizado';
  end if;

  delete from public.pacientes
  where id = p_id and clinica_id = p_clinica;
end;
$$;


ALTER FUNCTION "public"."eliminar_paciente"("p_id" "uuid", "p_clinica" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."es_miembro_clinica"("p_clinica" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select exists (
    select 1
    from public.clinicas_usuarios cu
    where cu.clinica_id = p_clinica
      and cu.usuario_id = auth.uid()
  );
$$;


ALTER FUNCTION "public"."es_miembro_clinica"("p_clinica" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."es_staff_de_clinica"("p_clinica" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select exists (
    select 1
    from public.clinicas_usuarios cu
    where cu.clinica_id = p_clinica
      and cu.usuario_id = auth.uid()
      and cu.rol in ('admin','medico','recepcion')
  );
$$;


ALTER FUNCTION "public"."es_staff_de_clinica"("p_clinica" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_trg_citas_programar_recordatorios"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform public.programar_recordatorios_cita(NEW.id);
  return NEW;
end;
$$;


ALTER FUNCTION "public"."fn_trg_citas_programar_recordatorios"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."listar_especialidades"("p_clinica" "uuid") RETURNS TABLE("id" "uuid", "nombre" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select e.id,
         coalesce(ce.nombre_publico, e.nombre) as nombre
  from public.clinica_especialidades ce
  join public.especialidades e on e.id = ce.especialidad_id
  where ce.clinica_id = p_clinica and ce.activa = true
  order by nombre;
$$;


ALTER FUNCTION "public"."listar_especialidades"("p_clinica" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."listar_pacientes_clinica"("p_clinica" "uuid", "p_q" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "uuid", "nombre" "text", "apellido" "text", "rut" "text", "email" "text", "telefono" "text", "nacimiento" "date", "direccion" "text", "prevision" "text", "foto_url" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select p.id, p.nombre, p.apellido, p.rut,
         p.email, p.telefono, p.nacimiento,
         p.direccion, (p.prevision::text), p.foto_url
  from public.pacientes p
  where p.clinica_id = p_clinica
    and (
      p_q is null
      or p.nombre    ilike '%'||p_q||'%'
      or p.apellido  ilike '%'||p_q||'%'
      or p.rut       ilike '%'||p_q||'%'
      or p.email     ilike '%'||p_q||'%'
      or p.telefono  ilike '%'||p_q||'%'
    )
  order by lower(p.apellido), lower(p.nombre), p.created_at desc
  limit greatest(1, p_limit);
$$;


ALTER FUNCTION "public"."listar_pacientes_clinica"("p_clinica" "uuid", "p_q" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."marcar_no_show"("p_cita" "uuid", "p_detalle" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v record;
begin
  select c.*, cu.rol
    into v
  from public.citas c
  join public.clinicas_usuarios cu
    on cu.clinica_id = c.clinica_id and cu.usuario_id = auth.uid()
  where c.id = p_cita;

  if not found then
    raise exception 'Cita no encontrada o sin permisos';
  end if;

  if v.rol not in ('admin','recepcion','medico') then
    raise exception 'No autorizado';
  end if;

  update public.citas
     set estado = 'no_show'
   where id = v.id;

  insert into public.cita_eventos(cita_id, actor_id, evento, detalle)
  values (v.id, auth.uid(), 'no_show', p_detalle);

  update public.cita_recordatorios
     set status = 'cancelado'
   where cita_id = v.id and status = 'pendiente';

  return v.id;
end;
$$;


ALTER FUNCTION "public"."marcar_no_show"("p_cita" "uuid", "p_detalle" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."marcar_realizada"("p_cita" "uuid", "p_detalle" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v record;
begin
  select c.*, cu.rol
    into v
  from public.citas c
  join public.clinicas_usuarios cu
    on cu.clinica_id = c.clinica_id and cu.usuario_id = auth.uid()
  where c.id = p_cita;

  if not found then
    raise exception 'Cita no encontrada o sin permisos';
  end if;

  if v.rol not in ('admin','recepcion','medico') then
    raise exception 'No autorizado';
  end if;

  update public.citas
     set estado = 'realizada'
   where id = v.id;

  insert into public.cita_eventos(cita_id, actor_id, evento, detalle)
  values (v.id, auth.uid(), 'realizada', p_detalle);

  -- recordatorios futuros ya no aplican
  update public.cita_recordatorios
     set status = 'cancelado'
   where cita_id = v.id and status = 'pendiente';

  return v.id;
end;
$$;


ALTER FUNCTION "public"."marcar_realizada"("p_cita" "uuid", "p_detalle" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mis_clinicas"("p_q" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "nombre" "text", "ciudad" "text", "region" "text", "rol" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    c.id,
    c.nombre,
    c.ciudad,
    c.region,
    cu.rol
  from public.clinicas c
  join public.clinicas_usuarios cu on cu.clinica_id = c.id
  where cu.usuario_id = auth.uid()
    and (p_q is null or c.nombre ilike '%'||p_q||'%')
  order by c.nombre asc
$$;


ALTER FUNCTION "public"."mis_clinicas"("p_q" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."programar_recordatorios_cita"("p_cita" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_cita record;
  v_now timestamptz := now();
  v_24h timestamptz;
  v_1h  timestamptz;
begin
  select c.id, c.fecha, c.fin, c.estado, c.paciente_id, c.medico_id, c.clinica_id
    into v_cita
  from public.citas c
  where c.id = p_cita;

  if not found then
    raise exception 'Cita no encontrada';
  end if;

  -- Limpia recordatorios futuros pendientes (por si reprogramamos)
  delete from public.cita_recordatorios
   where cita_id = p_cita and status = 'pendiente';

  -- Inmediato (entra al ciclo del worker en <=5min)
  insert into public.cita_recordatorios (cita_id, send_at)
  values (p_cita, v_now);

  -- 24h antes
  v_24h := v_cita.fecha - interval '24 hours';
  if v_24h > v_now then
    insert into public.cita_recordatorios (cita_id, send_at)
    values (p_cita, v_24h);
  end if;

  -- 1h antes
  v_1h := v_cita.fecha - interval '1 hour';
  if v_1h > v_now then
    insert into public.cita_recordatorios (cita_id, send_at)
    values (p_cita, v_1h);
  end if;
end;
$$;


ALTER FUNCTION "public"."programar_recordatorios_cita"("p_cita" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reprogramar_cita"("p_cita" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v record;
begin
  if p_inicio >= p_fin then
    raise exception 'Rango de tiempo inválido';
  end if;

  -- Carga cita + contexto
  select c.*, cu.rol
    into v
  from public.citas c
  join public.clinicas_usuarios cu
    on cu.clinica_id = c.clinica_id and cu.usuario_id = auth.uid()
  where c.id = p_cita;

  if not found then
    raise exception 'Cita no encontrada o sin permisos';
  end if;

  -- Permisos: admin/recepcion/medico de la clínica
  if v.rol not in ('admin','recepcion','medico') then
    raise exception 'No autorizado';
  end if;

  -- Disponibilidad del médico
  if not exists (
    select 1
    from public.disponibilidad_medica d
    where d.clinica_id = v.clinica_id
      and d.medico_id  = v.medico_id
      and d.vigente    = true
      and d.dia_semana = extract(dow from p_inicio)::int
      and d.hora_inicio <= (p_inicio::time)
      and d.hora_fin    >= (p_fin::time)
  ) then
    raise exception 'El intervalo no está dentro de la disponibilidad del médico';
  end if;

  -- Solape por MÉDICO (excluye la propia cita)
  if exists (
    select 1
    from public.citas c
    where c.id <> v.id
      and c.clinica_id = v.clinica_id
      and c.medico_id  = v.medico_id
      and c.estado in ('pendiente','confirmada','realizada')
      and tstzrange(c.fecha, c.fin, '[)') && tstzrange(p_inicio, p_fin, '[)')
  ) then
    raise exception 'Ya existe una cita del médico en ese rango';
  end if;

  -- Solape por PACIENTE (excluye la propia cita)
  if exists (
    select 1
    from public.citas c
    where c.id <> v.id
      and c.clinica_id = v.clinica_id
      and c.paciente_id = v.paciente_id
      and c.estado in ('pendiente','confirmada','realizada')
      and tstzrange(c.fecha, c.fin, '[)') && tstzrange(p_inicio, p_fin, '[)')
  ) then
    raise exception 'El paciente ya tiene una cita en ese rango';
  end if;

  -- Actualiza cita (dejamos estado igual; opcional: forzar 'pendiente')
  update public.citas
     set fecha = p_inicio,
         fin   = p_fin,
         motivo = coalesce(p_motivo, motivo)
   where id = v.id;

  -- Reprograma recordatorios para la cita movida
  perform public.programar_recordatorios_cita(v.id);

  return v.id;
end;
$$;


ALTER FUNCTION "public"."reprogramar_cita"("p_cita" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reservar_cita"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
begin
  if p_inicio >= p_fin then
    raise exception 'Rango de tiempo inválido';
  end if;

  -- Quien llama debe pertenecer a la clínica (admin/recepción/médico)
  if not tiene_rol_en_clinica(p_clinica, array['admin','recepcion','medico']) then
    raise exception 'No eres miembro de la clínica';
  end if;

  -- El médico debe pertenecer a la clínica
  if not exists (
    select 1 from public.clinicas_usuarios
    where clinica_id = p_clinica and usuario_id = p_medico
      and rol in ('medico','admin')
  ) then
    raise exception 'El médico no pertenece a la clínica';
  end if;

  -- Serializar reservas concurrentes (médico y paciente)
  perform pg_advisory_xact_lock(hashtext(p_medico::text));
  perform pg_advisory_xact_lock(hashtext(p_paciente::text));

  -- Debe estar dentro de la disponibilidad del médico
  if not exists (
    select 1
    from public.disponibilidad_medica d
    where d.clinica_id = p_clinica
      and d.medico_id  = p_medico
      and d.vigente    = true
      and d.dia_semana = extract(dow from p_inicio)::int
      and d.hora_inicio <= (p_inicio::time)
      and d.hora_fin    >= (p_fin::time)
  ) then
    raise exception 'El intervalo no está dentro de la disponibilidad del médico';
  end if;

  -- ❌ Solape por MÉDICO
  if exists (
    select 1
    from public.citas c
    where c.clinica_id = p_clinica
      and c.medico_id  = p_medico
      and c.estado in ('pendiente','confirmada','realizada')
      and tstzrange(c.fecha, c.fin, '[)') && tstzrange(p_inicio, p_fin, '[)')
  ) then
    raise exception 'Ya existe una cita del médico en ese rango';
  end if;

  -- ❌ Solape por PACIENTE (NUEVO)
  if exists (
    select 1
    from public.citas c
    where c.clinica_id = p_clinica
      and c.paciente_id = p_paciente
      and c.estado in ('pendiente','confirmada','realizada')
      and tstzrange(c.fecha, c.fin, '[)') && tstzrange(p_inicio, p_fin, '[)')
  ) then
    raise exception 'El paciente ya tiene una cita en ese rango';
  end if;

  -- ✅ Crear cita
  insert into public.citas (clinica_id, paciente_id, medico_id, fecha, fin, estado, motivo, created_by)
  values (p_clinica, p_paciente, p_medico, p_inicio, p_fin, 'pendiente', p_motivo, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."reservar_cita"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reservar_cita_con_afiliacion"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
begin
  -- asegura que el paciente figure en la clínica antes de reservar
  perform public.asegurar_membresia_paciente(p_clinica, p_paciente, 'paciente');

  -- reutiliza la lógica/validaciones de la RPC principal
  select public.reservar_cita(p_clinica, p_paciente, p_medico, p_inicio, p_fin, p_motivo)
    into v_id;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."reservar_cita_con_afiliacion"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."slugify"("p" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select regexp_replace(lower(trim(p)), '\s+', '-', 'g')
$$;


ALTER FUNCTION "public"."slugify"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_cita_default_prevision"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  -- Si no viene nada, copiamos la del paciente
  if new.prevision_id is null and new.prevision_otro is null and new.paciente_id is not null then
    select p.prevision_id, p.prevision_otro
      into new.prevision_id, new.prevision_otro
    from public.pacientes p
    where p.id = new.paciente_id;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."tg_cita_default_prevision"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_cita_prevision_otro"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare req boolean;
begin
  -- Sin previsión => limpiar texto
  if new.prevision_id is null then
    new.prevision_otro := null;
    return new;
  end if;

  select s.requiere_otro
    into req
  from public.previsiones_salud s
  where s.id = new.prevision_id;

  if req and coalesce(trim(new.prevision_otro),'') = '' then
    raise exception 'Debe indicar detalle de previsión (OTRA)';
  end if;

  if not req then
    new.prevision_otro := null;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."tg_cita_prevision_otro"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_paciente_prevision_otro"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare req boolean;
begin
  if new.prevision_id is null then
    new.prevision_otro := null;
    return new;
  end if;

  select requiere_otro into req
  from public.previsiones_salud
  where id = new.prevision_id;

  if req and coalesce(trim(new.prevision_otro),'') = '' then
    raise exception 'Debe indicar detalle de previsión (OTRA) en paciente';
  end if;

  if not req then
    new.prevision_otro := null;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."tg_paciente_prevision_otro"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "public"."tg_touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tiene_rol_en_clinica"("p_clinica" "uuid", "roles" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select exists (
    select 1
    from public.clinicas_usuarios cu
    where cu.clinica_id = p_clinica
      and cu.usuario_id = auth.uid()
      and cu.rol::text = any (roles)
  );
$$;


ALTER FUNCTION "public"."tiene_rol_en_clinica"("p_clinica" "uuid", "roles" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_especialidad_global"("p_nombre" "text", "p_codigo" "text" DEFAULT NULL::"text", "p_sistema" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
  v_slug text := slugify(p_nombre);
begin
  insert into public.especialidades (nombre, slug, codigo, sistema)
  values (p_nombre, v_slug, p_codigo, p_sistema)
  on conflict (slug) do update
    set nombre = excluded.nombre,
        codigo = excluded.codigo,
        sistema = excluded.sistema
  returning id into v_id;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."upsert_especialidad_global"("p_nombre" "text", "p_codigo" "text", "p_sistema" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage"."add_prefixes"("_bucket_id" "text", "_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    prefixes text[];
BEGIN
    prefixes := "storage"."get_prefixes"("_name");

    IF array_length(prefixes, 1) > 0 THEN
        INSERT INTO storage.prefixes (name, bucket_id)
        SELECT UNNEST(prefixes) as name, "_bucket_id" ON CONFLICT DO NOTHING;
    END IF;
END;
$$;


ALTER FUNCTION "storage"."add_prefixes"("_bucket_id" "text", "_name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_prefix"("_bucket_id" "text", "_name" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Check if we can delete the prefix
    IF EXISTS(
        SELECT FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name") + 1
          AND "prefixes"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    )
    OR EXISTS(
        SELECT FROM "storage"."objects"
        WHERE "objects"."bucket_id" = "_bucket_id"
          AND "storage"."get_level"("objects"."name") = "storage"."get_level"("_name") + 1
          AND "objects"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    ) THEN
    -- There are sub-objects, skip deletion
    RETURN false;
    ELSE
        DELETE FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name")
          AND "prefixes"."name" = "_name";
        RETURN true;
    END IF;
END;
$$;


ALTER FUNCTION "storage"."delete_prefix"("_bucket_id" "text", "_name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_prefix_hierarchy_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    prefix text;
BEGIN
    prefix := "storage"."get_prefix"(OLD."name");

    IF coalesce(prefix, '') != '' THEN
        PERFORM "storage"."delete_prefix"(OLD."bucket_id", prefix);
    END IF;

    RETURN OLD;
END;
$$;


ALTER FUNCTION "storage"."delete_prefix_hierarchy_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_level"("name" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


ALTER FUNCTION "storage"."get_level"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_prefix"("name" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


ALTER FUNCTION "storage"."get_prefix"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_prefixes"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


ALTER FUNCTION "storage"."get_prefixes"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"() RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(name COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                        substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1)))
                    ELSE
                        name
                END AS name, id, metadata, updated_at
            FROM
                storage.objects
            WHERE
                bucket_id = $5 AND
                name ILIKE $1 || ''%'' AND
                CASE
                    WHEN $6 != '''' THEN
                    name COLLATE "C" > $6
                ELSE true END
                AND CASE
                    WHEN $4 != '''' THEN
                        CASE
                            WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                                substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                name COLLATE "C" > $4
                            END
                    ELSE
                        true
                END
            ORDER BY
                name COLLATE "C" ASC) as e order by name COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_token, bucket_id, start_after;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_insert_prefix_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    NEW.level := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."objects_insert_prefix_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_update_prefix_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    old_prefixes TEXT[];
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Retrieve old prefixes
        old_prefixes := "storage"."get_prefixes"(OLD."name");

        -- Remove old prefixes that are only used by this object
        WITH all_prefixes as (
            SELECT unnest(old_prefixes) as prefix
        ),
        can_delete_prefixes as (
             SELECT prefix
             FROM all_prefixes
             WHERE NOT EXISTS (
                 SELECT 1 FROM "storage"."objects"
                 WHERE "bucket_id" = OLD."bucket_id"
                   AND "name" <> OLD."name"
                   AND "name" LIKE (prefix || '%')
             )
         )
        DELETE FROM "storage"."prefixes" WHERE name IN (SELECT prefix FROM can_delete_prefixes);

        -- Add new prefixes
        PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    END IF;
    -- Set the new level
    NEW."level" := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."objects_update_prefix_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."prefixes_insert_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."prefixes_insert_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
declare
    can_bypass_rls BOOLEAN;
begin
    SELECT rolbypassrls
    INTO can_bypass_rls
    FROM pg_roles
    WHERE rolname = coalesce(nullif(current_setting('role', true), 'none'), current_user);

    IF can_bypass_rls THEN
        RETURN QUERY SELECT * FROM storage.search_v1_optimised(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    ELSE
        RETURN QUERY SELECT * FROM storage.search_legacy_v1(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    END IF;
end;
$$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_legacy_v1"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION "storage"."search_legacy_v1"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v1_optimised"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select (string_to_array(name, ''/''))[level] as name
           from storage.prefixes
             where lower(prefixes.name) like lower($2 || $3) || ''%''
               and bucket_id = $4
               and level = $1
           order by name ' || v_sort_order || '
     )
     (select name,
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[level] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where lower(objects.name) like lower($2 || $3) || ''%''
       and bucket_id = $4
       and level = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION "storage"."search_v1_optimised"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
BEGIN
    RETURN query EXECUTE
        $sql$
        SELECT * FROM (
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name || '/' AS name,
                    NULL::uuid AS id,
                    NULL::timestamptz AS updated_at,
                    NULL::timestamptz AS created_at,
                    NULL::jsonb AS metadata
                FROM storage.prefixes
                WHERE name COLLATE "C" LIKE $1 || '%'
                AND bucket_id = $2
                AND level = $4
                AND name COLLATE "C" > $5
                ORDER BY prefixes.name COLLATE "C" LIMIT $3
            )
            UNION ALL
            (SELECT split_part(name, '/', $4) AS key,
                name,
                id,
                updated_at,
                created_at,
                metadata
            FROM storage.objects
            WHERE name COLLATE "C" LIKE $1 || '%'
                AND bucket_id = $2
                AND level = $4
                AND name COLLATE "C" > $5
            ORDER BY name COLLATE "C" LIMIT $3)
        ) obj
        ORDER BY name COLLATE "C" LIMIT $3;
        $sql$
        USING prefix, bucket_name, limits, levels, start_after;
END;
$_$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."cita_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cita_id" "uuid" NOT NULL,
    "actor_id" "uuid",
    "evento" "text" NOT NULL,
    "detalle" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cita_eventos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cita_recordatorios" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cita_id" "uuid" NOT NULL,
    "send_at" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "last_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cita_recordatorios" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."citas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "clinica_id" "uuid" NOT NULL,
    "paciente_id" "uuid" NOT NULL,
    "medico_id" "uuid" NOT NULL,
    "fecha" timestamp with time zone NOT NULL,
    "fin" timestamp with time zone NOT NULL,
    "estado" "public"."estado_cita" DEFAULT 'pendiente'::"public"."estado_cita" NOT NULL,
    "motivo" "text",
    "observaciones" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "prevision_id" "uuid",
    "prevision_otro" "text",
    CONSTRAINT "chk_citas_rango_valido" CHECK (("fin" > "fecha"))
);


ALTER TABLE "public"."citas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clinica_especialidades" (
    "clinica_id" "uuid" NOT NULL,
    "especialidad_id" "uuid" NOT NULL,
    "nombre_publico" "text",
    "activa" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."clinica_especialidades" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clinicas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "rut" "text",
    "telefono" "text",
    "direccion" "text",
    "ciudad" "text",
    "region" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."clinicas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clinicas_usuarios" (
    "clinica_id" "uuid" NOT NULL,
    "usuario_id" "uuid" NOT NULL,
    "rol" "public"."rol_clinica" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."clinicas_usuarios" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."disponibilidad_medica" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "clinica_id" "uuid" NOT NULL,
    "medico_id" "uuid" NOT NULL,
    "dia_semana" integer NOT NULL,
    "hora_inicio" time without time zone NOT NULL,
    "hora_fin" time without time zone NOT NULL,
    "vigente" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chk_dm_rango_valido" CHECK (("hora_fin" > "hora_inicio")),
    CONSTRAINT "disponibilidad_medica_dia_semana_check" CHECK ((("dia_semana" >= 0) AND ("dia_semana" <= 6)))
);


ALTER TABLE "public"."disponibilidad_medica" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."especialidades" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "codigo" "text",
    "sistema" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."especialidades" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medico_especialidades" (
    "clinica_id" "uuid" NOT NULL,
    "medico_id" "uuid" NOT NULL,
    "especialidad_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."medico_especialidades" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pacientes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "clinica_id" "uuid" NOT NULL,
    "nombre" "text" NOT NULL,
    "email" "text",
    "telefono" "text",
    "documento" "text",
    "nacimiento" "date",
    "foto_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "apellido" "text",
    "rut" "text",
    "direccion" "text",
    "prevision" "public"."prevision_salud",
    "prevision_id" "uuid",
    "prevision_otro" "text"
);


ALTER TABLE "public"."pacientes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."previsiones_salud" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "nombre" "text" NOT NULL,
    "grupo" "text" NOT NULL,
    "requiere_otro" boolean DEFAULT false NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "previsiones_salud_grupo_check" CHECK (("grupo" = ANY (ARRAY['FONASA'::"text", 'ISAPRE'::"text", 'FFAA'::"text", 'PARTICULAR'::"text", 'OTRA'::"text"])))
);


ALTER TABLE "public"."previsiones_salud" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb",
    "level" integer
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."prefixes" (
    "bucket_id" "text" NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "level" integer GENERATED ALWAYS AS ("storage"."get_level"("name")) STORED NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "storage"."prefixes" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "public"."cita_eventos"
    ADD CONSTRAINT "cita_eventos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cita_recordatorios"
    ADD CONSTRAINT "cita_recordatorios_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."citas"
    ADD CONSTRAINT "citas_no_solape_medico" EXCLUDE USING "gist" ("medico_id" WITH =, "tstzrange"("fecha", "fin", '[)'::"text") WITH &&) WHERE (("estado" = ANY (ARRAY['pendiente'::"public"."estado_cita", 'confirmada'::"public"."estado_cita", 'realizada'::"public"."estado_cita"])));



ALTER TABLE ONLY "public"."citas"
    ADD CONSTRAINT "citas_no_solape_paciente" EXCLUDE USING "gist" ("paciente_id" WITH =, "tstzrange"("fecha", "fin", '[)'::"text") WITH &&) WHERE (("estado" = ANY (ARRAY['pendiente'::"public"."estado_cita", 'confirmada'::"public"."estado_cita", 'realizada'::"public"."estado_cita"])));



ALTER TABLE ONLY "public"."citas"
    ADD CONSTRAINT "citas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clinica_especialidades"
    ADD CONSTRAINT "clinica_especialidades_pkey" PRIMARY KEY ("clinica_id", "especialidad_id");



ALTER TABLE ONLY "public"."clinicas"
    ADD CONSTRAINT "clinicas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clinicas"
    ADD CONSTRAINT "clinicas_rut_key" UNIQUE ("rut");



ALTER TABLE ONLY "public"."clinicas_usuarios"
    ADD CONSTRAINT "clinicas_usuarios_pkey" PRIMARY KEY ("clinica_id", "usuario_id");



ALTER TABLE ONLY "public"."disponibilidad_medica"
    ADD CONSTRAINT "disponibilidad_medica_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."especialidades"
    ADD CONSTRAINT "especialidades_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."especialidades"
    ADD CONSTRAINT "especialidades_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."medico_especialidades"
    ADD CONSTRAINT "medico_especialidades_pkey" PRIMARY KEY ("clinica_id", "medico_id", "especialidad_id");



ALTER TABLE ONLY "public"."pacientes"
    ADD CONSTRAINT "pacientes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."previsiones_salud"
    ADD CONSTRAINT "previsiones_salud_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."previsiones_salud"
    ADD CONSTRAINT "previsiones_salud_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."prefixes"
    ADD CONSTRAINT "prefixes_pkey" PRIMARY KEY ("bucket_id", "level", "name");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_cita_eventos_cita" ON "public"."cita_eventos" USING "btree" ("cita_id");



CREATE INDEX "idx_cita_recordatorios_due" ON "public"."cita_recordatorios" USING "btree" ("status", "send_at");



CREATE INDEX "idx_citas_clinica_fecha" ON "public"."citas" USING "btree" ("clinica_id", "fecha");



CREATE INDEX "idx_citas_medico_rango" ON "public"."citas" USING "btree" ("medico_id", "fecha", "fin");



CREATE INDEX "idx_citas_paciente_fecha" ON "public"."citas" USING "btree" ("paciente_id", "fecha");



CREATE INDEX "idx_cu_usuario" ON "public"."clinicas_usuarios" USING "btree" ("usuario_id");



CREATE INDEX "idx_dm_clinica" ON "public"."disponibilidad_medica" USING "btree" ("clinica_id", "dia_semana");



CREATE INDEX "idx_dm_medico" ON "public"."disponibilidad_medica" USING "btree" ("medico_id", "dia_semana");



CREATE INDEX "idx_pacientes_clinica_nombre" ON "public"."pacientes" USING "btree" ("clinica_id", "lower"("nombre"));



CREATE UNIQUE INDEX "uq_pacientes_clinica_rut" ON "public"."pacientes" USING "btree" ("clinica_id", "lower"("rut")) WHERE (("rut" IS NOT NULL) AND ("rut" <> ''::"text"));



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE UNIQUE INDEX "bucketid_objname" ON "storage"."objects" USING "btree" ("bucket_id", "name");



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE UNIQUE INDEX "idx_name_bucket_level_unique" ON "storage"."objects" USING "btree" ("name" COLLATE "C", "bucket_id", "level");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_lower_name" ON "storage"."objects" USING "btree" (("path_tokens"["level"]), "lower"("name") "text_pattern_ops", "bucket_id", "level");



CREATE INDEX "idx_prefixes_lower_name" ON "storage"."prefixes" USING "btree" ("bucket_id", "level", (("string_to_array"("name", '/'::"text"))["level"]), "lower"("name") "text_pattern_ops");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "objects_bucket_id_level_idx" ON "storage"."objects" USING "btree" ("bucket_id", "level", "name" COLLATE "C");



CREATE OR REPLACE TRIGGER "tg_cita_default_prevision" BEFORE INSERT ON "public"."citas" FOR EACH ROW EXECUTE FUNCTION "public"."tg_cita_default_prevision"();



CREATE OR REPLACE TRIGGER "tg_cita_prevision_otro" BEFORE INSERT OR UPDATE ON "public"."citas" FOR EACH ROW EXECUTE FUNCTION "public"."tg_cita_prevision_otro"();



CREATE OR REPLACE TRIGGER "tg_paciente_prevision_otro" BEFORE INSERT OR UPDATE ON "public"."pacientes" FOR EACH ROW EXECUTE FUNCTION "public"."tg_paciente_prevision_otro"();



CREATE OR REPLACE TRIGGER "tg_pacientes_updated" BEFORE UPDATE ON "public"."pacientes" FOR EACH ROW EXECUTE FUNCTION "public"."tg_touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_citas_programar_recordatorios" AFTER INSERT OR UPDATE OF "fecha", "fin" ON "public"."citas" FOR EACH ROW EXECUTE FUNCTION "public"."fn_trg_citas_programar_recordatorios"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "objects_delete_delete_prefix" AFTER DELETE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."delete_prefix_hierarchy_trigger"();



CREATE OR REPLACE TRIGGER "objects_insert_create_prefix" BEFORE INSERT ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."objects_insert_prefix_trigger"();



CREATE OR REPLACE TRIGGER "objects_update_create_prefix" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW WHEN ((("new"."name" <> "old"."name") OR ("new"."bucket_id" <> "old"."bucket_id"))) EXECUTE FUNCTION "storage"."objects_update_prefix_trigger"();



CREATE OR REPLACE TRIGGER "prefixes_create_hierarchy" BEFORE INSERT ON "storage"."prefixes" FOR EACH ROW WHEN (("pg_trigger_depth"() < 1)) EXECUTE FUNCTION "storage"."prefixes_insert_trigger"();



CREATE OR REPLACE TRIGGER "prefixes_delete_hierarchy" AFTER DELETE ON "storage"."prefixes" FOR EACH ROW EXECUTE FUNCTION "storage"."delete_prefix_hierarchy_trigger"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



ALTER TABLE ONLY "public"."cita_eventos"
    ADD CONSTRAINT "cita_eventos_cita_id_fkey" FOREIGN KEY ("cita_id") REFERENCES "public"."citas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cita_recordatorios"
    ADD CONSTRAINT "cita_recordatorios_cita_id_fkey" FOREIGN KEY ("cita_id") REFERENCES "public"."citas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."citas"
    ADD CONSTRAINT "citas_clinica_id_fkey" FOREIGN KEY ("clinica_id") REFERENCES "public"."clinicas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."citas"
    ADD CONSTRAINT "citas_medico_id_fkey" FOREIGN KEY ("medico_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."citas"
    ADD CONSTRAINT "citas_paciente_id_fkey" FOREIGN KEY ("paciente_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."citas"
    ADD CONSTRAINT "citas_prevision_fk" FOREIGN KEY ("prevision_id") REFERENCES "public"."previsiones_salud"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."clinica_especialidades"
    ADD CONSTRAINT "clinica_especialidades_clinica_id_fkey" FOREIGN KEY ("clinica_id") REFERENCES "public"."clinicas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clinica_especialidades"
    ADD CONSTRAINT "clinica_especialidades_especialidad_id_fkey" FOREIGN KEY ("especialidad_id") REFERENCES "public"."especialidades"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clinicas_usuarios"
    ADD CONSTRAINT "clinicas_usuarios_clinica_id_fkey" FOREIGN KEY ("clinica_id") REFERENCES "public"."clinicas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clinicas_usuarios"
    ADD CONSTRAINT "clinicas_usuarios_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."disponibilidad_medica"
    ADD CONSTRAINT "disponibilidad_medica_clinica_id_fkey" FOREIGN KEY ("clinica_id") REFERENCES "public"."clinicas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."disponibilidad_medica"
    ADD CONSTRAINT "disponibilidad_medica_medico_id_fkey" FOREIGN KEY ("medico_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medico_especialidades"
    ADD CONSTRAINT "medico_especialidades_clinica_id_fkey" FOREIGN KEY ("clinica_id") REFERENCES "public"."clinicas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medico_especialidades"
    ADD CONSTRAINT "medico_especialidades_especialidad_id_fkey" FOREIGN KEY ("especialidad_id") REFERENCES "public"."especialidades"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medico_especialidades"
    ADD CONSTRAINT "medico_especialidades_medico_id_fkey" FOREIGN KEY ("medico_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pacientes"
    ADD CONSTRAINT "pacientes_clinica_id_fkey" FOREIGN KEY ("clinica_id") REFERENCES "public"."clinicas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pacientes"
    ADD CONSTRAINT "pacientes_prevision_fk" FOREIGN KEY ("prevision_id") REFERENCES "public"."previsiones_salud"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."prefixes"
    ADD CONSTRAINT "prefixes_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



CREATE POLICY "cesp_iud_staff" ON "public"."clinica_especialidades" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."clinicas_usuarios" "cu"
  WHERE (("cu"."clinica_id" = "clinica_especialidades"."clinica_id") AND ("cu"."usuario_id" = "auth"."uid"()) AND ("cu"."rol" = ANY (ARRAY['admin'::"public"."rol_clinica", 'medico'::"public"."rol_clinica", 'recepcion'::"public"."rol_clinica"])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."clinicas_usuarios" "cu"
  WHERE (("cu"."clinica_id" = "clinica_especialidades"."clinica_id") AND ("cu"."usuario_id" = "auth"."uid"()) AND ("cu"."rol" = ANY (ARRAY['admin'::"public"."rol_clinica", 'medico'::"public"."rol_clinica", 'recepcion'::"public"."rol_clinica"]))))));



CREATE POLICY "cesp_select_miembros" ON "public"."clinica_especialidades" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."clinicas_usuarios" "cu"
  WHERE (("cu"."clinica_id" = "clinica_especialidades"."clinica_id") AND ("cu"."usuario_id" = "auth"."uid"())))));



ALTER TABLE "public"."citas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "citas_insert_paciente_o_admin" ON "public"."citas" FOR INSERT WITH CHECK (("public"."es_miembro_clinica"("clinica_id") AND (("paciente_id" = "auth"."uid"()) OR "public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'recepcion'::"text"]))));



CREATE POLICY "citas_select_scope" ON "public"."citas" FOR SELECT USING (("public"."es_miembro_clinica"("clinica_id") AND (("paciente_id" = "auth"."uid"()) OR ("medico_id" = "auth"."uid"()) OR "public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'recepcion'::"text"]))));



CREATE POLICY "citas_update_medico_admin" ON "public"."citas" FOR UPDATE USING (("public"."es_miembro_clinica"("clinica_id") AND (("medico_id" = "auth"."uid"()) OR "public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'recepcion'::"text"])))) WITH CHECK (("public"."es_miembro_clinica"("clinica_id") AND (("medico_id" = "auth"."uid"()) OR "public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'recepcion'::"text"]))));



ALTER TABLE "public"."clinica_especialidades" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "disp_delete_medico_admin" ON "public"."disponibilidad_medica" FOR DELETE USING ("public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'medico'::"text"]));



CREATE POLICY "disp_insert_medico_admin" ON "public"."disponibilidad_medica" FOR INSERT WITH CHECK ("public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'medico'::"text"]));



CREATE POLICY "disp_select_miembros" ON "public"."disponibilidad_medica" FOR SELECT USING ("public"."es_miembro_clinica"("clinica_id"));



CREATE POLICY "disp_update_medico_admin" ON "public"."disponibilidad_medica" FOR UPDATE USING ("public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'medico'::"text"])) WITH CHECK ("public"."tiene_rol_en_clinica"("clinica_id", ARRAY['admin'::"text", 'medico'::"text"]));



ALTER TABLE "public"."disponibilidad_medica" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "esp_select_all" ON "public"."especialidades" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."especialidades" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medico_especialidades" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mesp_iud_staff" ON "public"."medico_especialidades" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."clinicas_usuarios" "cu"
  WHERE (("cu"."clinica_id" = "medico_especialidades"."clinica_id") AND ("cu"."usuario_id" = "auth"."uid"()) AND ("cu"."rol" = ANY (ARRAY['admin'::"public"."rol_clinica", 'medico'::"public"."rol_clinica", 'recepcion'::"public"."rol_clinica"])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."clinicas_usuarios" "cu"
  WHERE (("cu"."clinica_id" = "medico_especialidades"."clinica_id") AND ("cu"."usuario_id" = "auth"."uid"()) AND ("cu"."rol" = ANY (ARRAY['admin'::"public"."rol_clinica", 'medico'::"public"."rol_clinica", 'recepcion'::"public"."rol_clinica"]))))));



CREATE POLICY "mesp_select_miembros" ON "public"."medico_especialidades" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."clinicas_usuarios" "cu"
  WHERE (("cu"."clinica_id" = "medico_especialidades"."clinica_id") AND ("cu"."usuario_id" = "auth"."uid"())))));



CREATE POLICY "pac_delete" ON "public"."pacientes" FOR DELETE USING ("public"."es_staff_de_clinica"("clinica_id"));



CREATE POLICY "pac_insert" ON "public"."pacientes" FOR INSERT WITH CHECK ("public"."es_staff_de_clinica"("clinica_id"));



CREATE POLICY "pac_select" ON "public"."pacientes" FOR SELECT USING ("public"."es_staff_de_clinica"("clinica_id"));



CREATE POLICY "pac_update" ON "public"."pacientes" FOR UPDATE USING ("public"."es_staff_de_clinica"("clinica_id")) WITH CHECK ("public"."es_staff_de_clinica"("clinica_id"));



ALTER TABLE "public"."pacientes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "previsiones_read" ON "public"."previsiones_salud" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."previsiones_salud" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Delete pacientes (auth) sx55b6_0" ON "storage"."objects" FOR DELETE TO "authenticated" USING (("bucket_id" = 'pacientes'::"text"));



CREATE POLICY "Insert pacientes (auth) sx55b6_0" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK (("bucket_id" = 'pacientes'::"text"));



CREATE POLICY "Read pacientes (auth) sx55b6_0" ON "storage"."objects" FOR SELECT TO "authenticated" USING (("bucket_id" = 'pacientes'::"text"));



ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pacientes_delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING (("bucket_id" = 'pacientes'::"text"));



CREATE POLICY "pacientes_insert" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK (("bucket_id" = 'pacientes'::"text"));



CREATE POLICY "pacientes_read" ON "storage"."objects" FOR SELECT TO "authenticated" USING (("bucket_id" = 'pacientes'::"text"));



CREATE POLICY "pacientes_update" ON "storage"."objects" FOR UPDATE TO "authenticated" USING (("bucket_id" = 'pacientes'::"text")) WITH CHECK (("bucket_id" = 'pacientes'::"text"));



ALTER TABLE "storage"."prefixes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin";
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



GRANT ALL ON FUNCTION "public"."actualizar_foto_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_foto_url" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_foto_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_foto_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_foto_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_foto_url" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_paciente"("p_id" "uuid", "p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."agregar_especialidad_a_clinica"("p_clinica" "uuid", "p_especialidad" "uuid", "p_nombre_publico" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."agregar_especialidad_a_clinica"("p_clinica" "uuid", "p_especialidad" "uuid", "p_nombre_publico" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."agregar_especialidad_a_clinica"("p_clinica" "uuid", "p_especialidad" "uuid", "p_nombre_publico" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."aplicar_plantilla_disponibilidad"("p_clinica" "uuid", "p_medico" "uuid", "p_tramos" "jsonb", "p_reemplazar" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."aplicar_plantilla_disponibilidad"("p_clinica" "uuid", "p_medico" "uuid", "p_tramos" "jsonb", "p_reemplazar" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."aplicar_plantilla_disponibilidad"("p_clinica" "uuid", "p_medico" "uuid", "p_tramos" "jsonb", "p_reemplazar" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."asegurar_membresia_paciente"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."asignar_especialidad_medico"("p_clinica" "uuid", "p_medico" "uuid", "p_especialidad" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."asignar_especialidad_medico"("p_clinica" "uuid", "p_medico" "uuid", "p_especialidad" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."asignar_especialidad_medico"("p_clinica" "uuid", "p_medico" "uuid", "p_especialidad" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."asignar_rol_en_clinica"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."asignar_rol_en_clinica"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."asignar_rol_en_clinica"("p_clinica" "uuid", "p_usuario" "uuid", "p_rol" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."buscar_medicos"("p_clinica" "uuid", "p_q" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."buscar_medicos"("p_clinica" "uuid", "p_q" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."buscar_medicos"("p_clinica" "uuid", "p_q" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."buscar_medicos_filtrado"("p_clinica" "uuid", "p_q" "text", "p_especialidad" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."buscar_pacientes"("p_clinica" "uuid", "p_q" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."buscar_pacientes"("p_clinica" "uuid", "p_q" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."buscar_pacientes"("p_clinica" "uuid", "p_q" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."buscar_usuario_por_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."buscar_usuario_por_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."buscar_usuario_por_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cancelar_cita"("p_cita" "uuid", "p_motivo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cancelar_cita"("p_cita" "uuid", "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancelar_cita"("p_cita" "uuid", "p_motivo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."confirmar_cita"("p_cita" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."confirmar_cita"("p_cita" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirmar_cita"("p_cita" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."confirmar_cita"("p_cita" "uuid", "p_detalle" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."confirmar_cita"("p_cita" "uuid", "p_detalle" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirmar_cita"("p_cita" "uuid", "p_detalle" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_paciente"("p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."crear_paciente"("p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_paciente"("p_clinica" "uuid", "p_nombre" "text", "p_email" "text", "p_telefono" "text", "p_documento" "text", "p_nacimiento" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."eliminar_paciente"("p_id" "uuid", "p_clinica" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."eliminar_paciente"("p_id" "uuid", "p_clinica" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."eliminar_paciente"("p_id" "uuid", "p_clinica" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."es_miembro_clinica"("p_clinica" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."es_miembro_clinica"("p_clinica" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."es_miembro_clinica"("p_clinica" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."es_staff_de_clinica"("p_clinica" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."es_staff_de_clinica"("p_clinica" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."es_staff_de_clinica"("p_clinica" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_trg_citas_programar_recordatorios"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_trg_citas_programar_recordatorios"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_trg_citas_programar_recordatorios"() TO "service_role";



GRANT ALL ON FUNCTION "public"."listar_especialidades"("p_clinica" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."listar_especialidades"("p_clinica" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."listar_especialidades"("p_clinica" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."listar_pacientes_clinica"("p_clinica" "uuid", "p_q" "text", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."listar_pacientes_clinica"("p_clinica" "uuid", "p_q" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."listar_pacientes_clinica"("p_clinica" "uuid", "p_q" "text", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."marcar_no_show"("p_cita" "uuid", "p_detalle" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."marcar_no_show"("p_cita" "uuid", "p_detalle" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."marcar_no_show"("p_cita" "uuid", "p_detalle" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."marcar_realizada"("p_cita" "uuid", "p_detalle" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."marcar_realizada"("p_cita" "uuid", "p_detalle" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."marcar_realizada"("p_cita" "uuid", "p_detalle" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."mis_clinicas"("p_q" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mis_clinicas"("p_q" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mis_clinicas"("p_q" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."programar_recordatorios_cita"("p_cita" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."programar_recordatorios_cita"("p_cita" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."programar_recordatorios_cita"("p_cita" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reprogramar_cita"("p_cita" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."reprogramar_cita"("p_cita" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reprogramar_cita"("p_cita" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."reservar_cita"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."reservar_cita"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reservar_cita"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."reservar_cita_con_afiliacion"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."reservar_cita_con_afiliacion"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reservar_cita_con_afiliacion"("p_clinica" "uuid", "p_paciente" "uuid", "p_medico" "uuid", "p_inicio" timestamp with time zone, "p_fin" timestamp with time zone, "p_motivo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."slugify"("p" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."slugify"("p" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."slugify"("p" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_cita_default_prevision"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_cita_default_prevision"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_cita_default_prevision"() TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_cita_prevision_otro"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_cita_prevision_otro"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_cita_prevision_otro"() TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_paciente_prevision_otro"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_paciente_prevision_otro"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_paciente_prevision_otro"() TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_touch_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_touch_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."tiene_rol_en_clinica"("p_clinica" "uuid", "roles" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."tiene_rol_en_clinica"("p_clinica" "uuid", "roles" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tiene_rol_en_clinica"("p_clinica" "uuid", "roles" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_especialidad_global"("p_nombre" "text", "p_codigo" "text", "p_sistema" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_especialidad_global"("p_nombre" "text", "p_codigo" "text", "p_sistema" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_especialidad_global"("p_nombre" "text", "p_codigo" "text", "p_sistema" "text") TO "service_role";



GRANT ALL ON TABLE "public"."cita_eventos" TO "anon";
GRANT ALL ON TABLE "public"."cita_eventos" TO "authenticated";
GRANT ALL ON TABLE "public"."cita_eventos" TO "service_role";



GRANT ALL ON TABLE "public"."cita_recordatorios" TO "anon";
GRANT ALL ON TABLE "public"."cita_recordatorios" TO "authenticated";
GRANT ALL ON TABLE "public"."cita_recordatorios" TO "service_role";



GRANT ALL ON TABLE "public"."citas" TO "anon";
GRANT ALL ON TABLE "public"."citas" TO "authenticated";
GRANT ALL ON TABLE "public"."citas" TO "service_role";



GRANT ALL ON TABLE "public"."clinica_especialidades" TO "anon";
GRANT ALL ON TABLE "public"."clinica_especialidades" TO "authenticated";
GRANT ALL ON TABLE "public"."clinica_especialidades" TO "service_role";



GRANT ALL ON TABLE "public"."clinicas" TO "anon";
GRANT ALL ON TABLE "public"."clinicas" TO "authenticated";
GRANT ALL ON TABLE "public"."clinicas" TO "service_role";



GRANT ALL ON TABLE "public"."clinicas_usuarios" TO "anon";
GRANT ALL ON TABLE "public"."clinicas_usuarios" TO "authenticated";
GRANT ALL ON TABLE "public"."clinicas_usuarios" TO "service_role";



GRANT ALL ON TABLE "public"."disponibilidad_medica" TO "anon";
GRANT ALL ON TABLE "public"."disponibilidad_medica" TO "authenticated";
GRANT ALL ON TABLE "public"."disponibilidad_medica" TO "service_role";



GRANT ALL ON TABLE "public"."especialidades" TO "anon";
GRANT ALL ON TABLE "public"."especialidades" TO "authenticated";
GRANT ALL ON TABLE "public"."especialidades" TO "service_role";



GRANT ALL ON TABLE "public"."medico_especialidades" TO "anon";
GRANT ALL ON TABLE "public"."medico_especialidades" TO "authenticated";
GRANT ALL ON TABLE "public"."medico_especialidades" TO "service_role";



GRANT ALL ON TABLE "public"."pacientes" TO "anon";
GRANT ALL ON TABLE "public"."pacientes" TO "authenticated";
GRANT ALL ON TABLE "public"."pacientes" TO "service_role";



GRANT ALL ON TABLE "public"."previsiones_salud" TO "anon";
GRANT ALL ON TABLE "public"."previsiones_salud" TO "authenticated";
GRANT ALL ON TABLE "public"."previsiones_salud" TO "service_role";



GRANT ALL ON TABLE "storage"."buckets" TO "anon";
GRANT ALL ON TABLE "storage"."buckets" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT ALL ON TABLE "storage"."objects" TO "anon";
GRANT ALL ON TABLE "storage"."objects" TO "authenticated";
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."prefixes" TO "service_role";
GRANT ALL ON TABLE "storage"."prefixes" TO "authenticated";
GRANT ALL ON TABLE "storage"."prefixes" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";



RESET ALL;
