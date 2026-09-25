-- ============================================================================
-- CRM Región San Miguel de Allende — esquema inicial de Supabase
-- ============================================================================
-- Qué hace este archivo:
--   1. Crea las tablas asesores, capturas y admin_users.
--   2. Activa Row Level Security (RLS) en las tres tablas.
--   3. Crea la función is_admin() (usada por las políticas de RLS).
--   4. Crea las funciones RPC públicas: asesores_publico, crear_captura,
--      acumulado_dia, capturas_resumen y actualizar_captura.
--   5. Otorga los permisos necesarios a los roles anon/authenticated.
--
-- Cómo ejecutarlo: pega el contenido completo de este archivo en el
-- SQL Editor de tu proyecto de Supabase y da clic en "Run". Ver
-- supabase/LEEME.md para la guía paso a paso completa (incluye cómo crear
-- el usuario administrador después de correr esto).
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. Tablas
-- ----------------------------------------------------------------------------

-- Catálogo de asesores. Espejo exacto del objeto "advisor" que ya usa
-- index.html (ver seedAdvisors / saveAdvisor / deactivateAdvisor /
-- reactivateAdvisor en el código).
create table if not exists public.asesores (
  id text primary key default ('adv-' || replace(gen_random_uuid()::text, '-', '')),
  emp text not null,
  name text not null,
  branch text not null,
  status text not null default 'Activo'
    check (status in ('Activo','Vacaciones','Incapacidad','Baja')),
  puesto text
    check (puesto is null or puesto in ('BANCO','COMERCIO')),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deactivated_at timestamptz,
  deactivated_by text,
  reactivated_at timestamptz,
  reactivated_by text
);
create unique index if not exists asesores_emp_key on public.asesores(emp);

-- Capturas de avance de Banco y Comercio. La columna "data" reproduce
-- exactamente lo que hoy arman getBankDraft() / getCommerceDraft() en
-- index.html; no se resume ni se inventan campos nuevos.
create table if not exists public.capturas (
  folio text primary key,
  tipo text not null check (tipo in ('Banco','Comercio')),
  created_at timestamptz not null default now(),
  day date not null,
  week integer not null,
  emp text not null,
  advisor text not null,
  branch text not null,
  data jsonb not null,
  totals jsonb,
  status text not null default 'confirmed',
  admin_modified_at timestamptz
);
create index if not exists capturas_tipo_idx on public.capturas(tipo);
create index if not exists capturas_emp_branch_day_idx on public.capturas(emp, branch, day);
create index if not exists capturas_week_idx on public.capturas(week);

-- Lista de administradores. No tiene políticas públicas: solo se
-- gestiona desde el SQL Editor / Table Editor de Supabase (ver LEEME.md).
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. RLS
-- ----------------------------------------------------------------------------

alter table public.asesores enable row level security;
alter table public.capturas enable row level security;
alter table public.admin_users enable row level security;

-- ----------------------------------------------------------------------------
-- 3. is_admin()
-- ----------------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.admin_users where user_id = auth.uid()
  );
$$;

grant execute on function public.is_admin() to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. Políticas de RLS
-- ----------------------------------------------------------------------------

-- Asesores: lectura pública (el Resumen ejecutivo y la pantalla de avance
-- no requieren login); alta/edición solo para el administrador autenticado.
drop policy if exists asesores_select_publico on public.asesores;
create policy asesores_select_publico on public.asesores
  for select using (true);

drop policy if exists asesores_insert_admin on public.asesores;
create policy asesores_insert_admin on public.asesores
  for insert with check (public.is_admin());

drop policy if exists asesores_update_admin on public.asesores;
create policy asesores_update_admin on public.asesores
  for update using (public.is_admin()) with check (public.is_admin());

-- Capturas: lectura pública (Resumen ejecutivo / Administración > Registros).
-- No hay políticas de insert/update/delete: toda escritura pasa por las
-- funciones RPC crear_captura() / actualizar_captura(), que son
-- SECURITY DEFINER y validan los datos antes de tocar la tabla.
drop policy if exists capturas_select_publico on public.capturas;
create policy capturas_select_publico on public.capturas
  for select using (true);

-- admin_users: sin políticas -> nadie puede leerlo ni escribirlo desde el
-- cliente (ni con anon key ni ya autenticado). Se administra a mano desde
-- el SQL Editor / Table Editor de Supabase.

-- ----------------------------------------------------------------------------
-- 5. Funciones RPC
-- ----------------------------------------------------------------------------

-- Lectura pública del catálogo de asesores.
create or replace function public.asesores_publico()
returns setof public.asesores
language sql
security definer
stable
set search_path = public
as $$
  select * from public.asesores order by name;
$$;

grant execute on function public.asesores_publico() to anon, authenticated;

-- Lectura pública de capturas, opcionalmente filtrada por tipo
-- ('Banco' o 'Comercio'). Usada para llenar bankCaptures/commerceCaptures
-- y para Resumen ejecutivo / Administración > Registros.
create or replace function public.capturas_resumen(p_tipo text default null)
returns setof public.capturas
language sql
security definer
stable
set search_path = public
as $$
  select * from public.capturas
  where p_tipo is null or tipo = p_tipo
  order by created_at desc;
$$;

grant execute on function public.capturas_resumen(text) to anon, authenticated;

-- Acumulado del día para un asesor/sucursal/fecha, replicando la lógica
-- de currentAccum()/bankAccum() en index.html. No la usa el cliente en
-- esta primera etapa (bankCaptures/commerceCaptures ya viven completos en
-- memoria tras el arranque), pero queda disponible para no depender de
-- cargar todo el historial en el futuro. p_tipo: 'Banco' o 'Comercio'.
create or replace function public.acumulado_dia(p_tipo text, p_emp text, p_branch text, p_day date)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if p_tipo = 'Banco' then
    select jsonb_build_object(
      'aff', coalesce(sum((c.data->>'aff')::int), 0),
      'port', coalesce(sum((c.data->>'port')::int), 0),
      'funds', coalesce(sum((c.data->>'funds')::numeric), 0),
      'guardCount', coalesce(sum((c.data->>'guardCount')::int), 0),
      'guardAmt', coalesce(sum(el.val), 0)
    ) into v_result
    from public.capturas c
    left join lateral jsonb_array_elements_text(coalesce(c.data->'guardAmounts','[]'::jsonb)) e(v) on true
    left join lateral (select e.v::numeric as val) el on true
    where c.tipo='Banco' and c.emp=p_emp and c.branch=p_branch and c.day=p_day;
    return coalesce(v_result, '{}'::jsonb);
  elsif p_tipo = 'Comercio' then
    select jsonb_build_object(
      'requests', coalesce(sum((c.data->'totals'->>'requests')::int), 0),
      'served', coalesce(sum((c.data->'totals'->>'served')::int), 0),
      'newAmt', coalesce(sum((c.data->'totals'->>'newAmt')::numeric), 0),
      'inactiveAmt', coalesce(sum((c.data->'totals'->>'inactiveAmt')::numeric), 0),
      'vda', coalesce(sum((c.data->'totals'->>'vda')::numeric), 0)
    ) into v_result
    from public.capturas c
    where c.tipo='Comercio' and c.emp=p_emp and c.branch=p_branch and c.day=p_day
      and c.status <> 'correction_rejected';
    return coalesce(v_result, '{}'::jsonb);
  else
    raise exception 'p_tipo debe ser Banco o Comercio';
  end if;
end;
$$;

grant execute on function public.acumulado_dia(text, text, text, date) to anon, authenticated;

-- Crea una captura de Banco o Comercio. SECURITY DEFINER: valida los
-- datos server-side (no confía en folio/semana/totales que mande el
-- cliente) y luego inserta. p_data debe traer exactamente los campos que
-- ya arman getBankDraft() / getCommerceDraft() en index.html.
create or replace function public.crear_captura(
  p_tipo text,
  p_emp text,
  p_advisor text,
  p_branch text,
  p_day date,
  p_data jsonb
)
returns public.capturas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq int;
  v_folio text;
  v_week int;
  v_data jsonb := p_data;
  v_totals jsonb := null;
  v_row public.capturas;
  v_req int[]; v_srv int[];
  v_sum_nested numeric;
begin
  if p_tipo not in ('Banco','Comercio') then
    raise exception 'p_tipo debe ser Banco o Comercio';
  end if;
  if p_emp is null or p_emp = '' then raise exception 'emp requerido'; end if;
  if p_advisor is null or p_advisor = '' then raise exception 'advisor requerido'; end if;
  if p_branch is null or p_branch = '' then raise exception 'branch requerido'; end if;
  if p_day is null then raise exception 'day requerido'; end if;

  if p_tipo = 'Banco' then
    if (p_data->>'aff') is null or (p_data->>'aff')::int < 0 then raise exception 'aff inválido'; end if;
    if (p_data->>'port') is null or (p_data->>'port')::int < 0 then raise exception 'port inválido'; end if;
    if (p_data->>'funds') is null or (p_data->>'funds')::numeric < 0 then raise exception 'funds inválido'; end if;
    if (p_data->>'tazDelivered') is null or (p_data->>'tazDelivered')::int < 0 then raise exception 'tazDelivered inválido'; end if;
    if (p_data->>'tazActivated') is null or (p_data->>'tazActivated')::int < 0 then raise exception 'tazActivated inválido'; end if;
    if (p_data->>'tazActivated')::int > (p_data->>'tazDelivered')::int then
      raise exception 'Las TAZ activadas no pueden ser mayores que las TAZ entregadas.';
    end if;
    if jsonb_array_length(coalesce(p_data->'guardAmounts','[]'::jsonb)) <> coalesce((p_data->>'guardCount')::int,0) then
      raise exception 'guardAmounts no coincide con guardCount';
    end if;
    if jsonb_array_length(coalesce(p_data->'somosAmounts','[]'::jsonb)) <> coalesce((p_data->>'somosCount')::int,0) then
      raise exception 'somosAmounts no coincide con somosCount';
    end if;
    if jsonb_array_length(coalesce(p_data->'invAmounts','[]'::jsonb)) <> coalesce((p_data->>'invCount')::int,0) then
      raise exception 'invAmounts no coincide con invCount';
    end if;
    v_totals := null;
  else
    if jsonb_typeof(p_data->'req') <> 'array' or jsonb_array_length(p_data->'req') <> 3 then
      raise exception 'req debe ser un arreglo de 3 elementos';
    end if;
    if jsonb_typeof(p_data->'srv') <> 'array' or jsonb_array_length(p_data->'srv') <> 3 then
      raise exception 'srv debe ser un arreglo de 3 elementos';
    end if;
    if jsonb_typeof(p_data->'nw') <> 'array' or jsonb_array_length(p_data->'nw') <> 3
       or jsonb_typeof(p_data->'ina') <> 'array' or jsonb_array_length(p_data->'ina') <> 3
       or jsonb_typeof(p_data->'vda') <> 'array' or jsonb_array_length(p_data->'vda') <> 3 then
      raise exception 'nw, ina y vda deben ser arreglos de 3 elementos';
    end if;
    -- recalcula totals server-side a partir de req/srv/nw/ina/vda (no se
    -- confía en el totals que mande el cliente).
    select
      jsonb_build_object(
        'requests', (select sum((v)::int) from jsonb_array_elements_text(p_data->'req') v),
        'served', (select sum((v)::int) from jsonb_array_elements_text(p_data->'srv') v),
        'newAmt', (select coalesce(sum((elem)::numeric),0) from jsonb_array_elements(p_data->'nw') grp, jsonb_array_elements_text(grp) elem),
        'inactiveAmt', (select coalesce(sum((elem)::numeric),0) from jsonb_array_elements(p_data->'ina') grp, jsonb_array_elements_text(grp) elem),
        'vda', (select coalesce(sum((elem)::numeric),0) from jsonb_array_elements(p_data->'vda') grp, jsonb_array_elements_text(grp) elem)
      ) into v_totals;
    v_data := p_data || jsonb_build_object('totals', v_totals);
  end if;

  select count(*) + 1 into v_seq from public.capturas where tipo = p_tipo;
  v_folio := (case when p_tipo = 'Banco' then 'BAN' else 'COM' end)
    || '-' || to_char(now(), 'DDMMYY') || '-' || lpad(v_seq::text, 4, '0');
  v_week := extract(week from p_day)::int;

  insert into public.capturas(folio, tipo, day, week, emp, advisor, branch, data, totals, status)
  values (v_folio, p_tipo, p_day, v_week, p_emp, p_advisor, p_branch, v_data, v_totals, 'confirmed')
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.crear_captura(text, text, text, text, date, jsonb) to anon, authenticated;

-- Edita una captura existente. Solo el administrador puede llamarla (se
-- verifica is_admin() dentro de la función, igual que cualquier otra
-- escritura administrativa). Replica saveBankRecordEdit()/
-- saveCommerceRecordEdit(): cambia fecha/semana/data/totals y marca
-- admin_modified_at.
create or replace function public.actualizar_captura(
  p_folio text,
  p_tipo text,
  p_day date,
  p_data jsonb
)
returns public.capturas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.capturas;
  v_week int;
  v_data jsonb := p_data;
  v_totals jsonb := null;
  v_row public.capturas;
begin
  if not public.is_admin() then
    raise exception 'Solo el administrador puede editar registros.';
  end if;

  select * into v_existing from public.capturas where folio = p_folio;
  if not found then
    raise exception 'No existe una captura con folio %', p_folio;
  end if;
  if v_existing.tipo <> p_tipo then
    raise exception 'El tipo no coincide con el registro existente.';
  end if;

  if p_tipo = 'Banco' then
    if (p_data->>'tazActivated')::int > (p_data->>'tazDelivered')::int then
      raise exception 'Las TAZ activadas no pueden ser mayores que las TAZ entregadas.';
    end if;
    if jsonb_array_length(coalesce(p_data->'guardAmounts','[]'::jsonb)) <> coalesce((p_data->>'guardCount')::int,0)
       or jsonb_array_length(coalesce(p_data->'somosAmounts','[]'::jsonb)) <> coalesce((p_data->>'somosCount')::int,0)
       or jsonb_array_length(coalesce(p_data->'invAmounts','[]'::jsonb)) <> coalesce((p_data->>'invCount')::int,0) then
      raise exception 'Guardadito, Somos e Inversiones deben tener exactamente un monto por cada operación.';
    end if;
    v_totals := null;
  else
    select
      jsonb_build_object(
        'requests', (select sum((v)::int) from jsonb_array_elements_text(p_data->'req') v),
        'served', (select sum((v)::int) from jsonb_array_elements_text(p_data->'srv') v),
        'newAmt', (select coalesce(sum((elem)::numeric),0) from jsonb_array_elements(p_data->'nw') grp, jsonb_array_elements_text(grp) elem),
        'inactiveAmt', (select coalesce(sum((elem)::numeric),0) from jsonb_array_elements(p_data->'ina') grp, jsonb_array_elements_text(grp) elem),
        'vda', (select coalesce(sum((elem)::numeric),0) from jsonb_array_elements(p_data->'vda') grp, jsonb_array_elements_text(grp) elem)
      ) into v_totals;
    v_data := p_data || jsonb_build_object('totals', v_totals);
  end if;

  v_week := extract(week from p_day)::int;

  update public.capturas
  set day = p_day, week = v_week, data = v_data, totals = v_totals, admin_modified_at = now()
  where folio = p_folio
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.actualizar_captura(text, text, date, jsonb) to anon, authenticated;
