insert into public.clinicas (id, nombre, ciudad, region) values
('00000000-0000-0000-0000-000000000001','Clínica Demo','Talca','Maule')
on conflict (id) do nothing;


insert into public.especialidades (nombre) values
('Medicina General'), ('Pediatría'), ('Ginecología')
on conflict do nothing;