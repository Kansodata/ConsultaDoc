-- Extensiones
create policy "cu_delete_admin" on public.clinicas_usuarios
for delete using (tiene_rol_en_clinica(clinica_id, array['admin']));


-- Especialidades: visibles a miembros de cualquier clínica (catálogo general)
create policy "esp_select_all" on public.especialidades for select using (true);
create policy "esp_ins_admin" on public.especialidades for insert with check (true);


-- Médicos: visibles en su clínica
create policy "medicos_select_miembros" on public.medicos
for select using (es_miembro_clinica(clinica_id));
create policy "medicos_upsert_admin" on public.medicos
for insert with check (tiene_rol_en_clinica(clinica_id, array['admin','recepcion']));
create policy "medicos_update_self_or_admin" on public.medicos
for update using (usuario_id = auth.uid() or tiene_rol_en_clinica(clinica_id, array['admin']));


-- Pacientes: visibles en su clínica
create policy "pacientes_select_self_or_miembros" on public.pacientes
for select using (
usuario_id = auth.uid() or es_miembro_clinica(clinica_id)
);
create policy "pacientes_upsert_admin" on public.pacientes
for insert with check (tiene_rol_en_clinica(clinica_id, array['admin','recepcion']));
create policy "pacientes_update_self_or_admin" on public.pacientes
for update using (usuario_id = auth.uid() or tiene_rol_en_clinica(clinica_id, array['admin']));


-- Citas: paciente ve las suyas; médico las asignadas; admin todas en su clínica
create policy "citas_select_scope" on public.citas
for select using (
es_miembro_clinica(clinica_id)
and (
paciente_id = auth.uid() or medico_id = auth.uid() or tiene_rol_en_clinica(clinica_id, array['admin','recepcion'])
)
);
create policy "citas_insert_paciente_o_admin" on public.citas
for insert with check (
es_miembro_clinica(clinica_id)
and (paciente_id = auth.uid() or tiene_rol_en_clinica(clinica_id, array['admin','recepcion']))
);
create policy "citas_update_medico_admin" on public.citas
for update using (
es_miembro_clinica(clinica_id)
and (medico_id = auth.uid() or tiene_rol_en_clinica(clinica_id, array['admin','recepcion']))
);


-- Disponibilidad médica: visible para miembros de la clínica
create policy "disp_select_miembros" on public.disponibilidad_medica
for select using (es_miembro_clinica(clinica_id));
create policy "disp_insert_medico_admin" on public.disponibilidad_medica
for insert with check (tiene_rol_en_clinica(clinica_id, array['admin','medico']));
create policy "disp_update_medico_admin" on public.disponibilidad_medica
for update using (tiene_rol_en_clinica(clinica_id, array['admin','medico']));


-- Notas y recetas: sólo médico asignado, paciente y admin clínica
create policy "notas_select_scope" on public.notas_clinicas
for select using (
es_miembro_clinica(clinica_id) and (
medico_id = auth.uid() or paciente_id = auth.uid() or tiene_rol_en_clinica(clinica_id, array['admin'])
)
);
create policy "notas_insert_medico" on public.notas_clinicas
for insert with check (medico_id = auth.uid() and es_miembro_clinica(clinica_id));


create policy "recetas_select_scope" on public.recetas
for select using (
es_miembro_clinica(clinica_id) and (
medico_id = auth.uid() or paciente_id = auth.uid() or tiene_rol_en_clinica(clinica_id, array['admin'])
)
);
create policy "recetas_insert_medico" on public.recetas
for insert with check (medico_id = auth.uid() and es_miembro_clinica(clinica_id));