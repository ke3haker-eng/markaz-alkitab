-- =====================================================================
--  دوري فرسان القرآن — الجزء 2 من 6: إدارة المسابقات
--  شغّله بعد الجزء 1 بالترتيب. آمن ويمكن تكراره. الملف صغير ليُلصق كاملاً من الجوال.
-- =====================================================================
do $$ begin
  if to_regprocedure('public._comp_default_cats()') is null then raise exception 'شغّل الجزء 1 أولاً (الترتيب مهم)'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 3) إدارة المسابقات
-- ---------------------------------------------------------------------
create or replace function public.comp_defaults(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  return jsonb_build_object('ok', true, 'categories', public._comp_default_cats(), 'settings', public._comp_default_settings(),
                            'today', public._comp_today(public._comp_default_settings()));
end $$;

create or replace function public.comp_roster(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true,
    'halaqat', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name) order by h.name)
                           from public.halaqat h
                          where h.center_id::text = c.center_id::text
                            and (c.role::text <> 'teacher' or h.id::text = c.halaqa_id::text)), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'halaqa_id', s.halaqa_id,
                                                              'has_account', s.user_id is not null) order by s.name)
                            from public.students s
                           where s.halaqa_id::text in (select h.id::text from public.halaqat h
                                                        where h.center_id::text = c.center_id::text
                                                          and (c.role::text <> 'teacher' or h.id::text = c.halaqa_id::text))), '[]'::jsonb));
end $$;

create or replace function public._comp_row_json(k public.competitions, c public.users) returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object(
    'id', k.id, 'name', k.name, 'description', k.description,
    'start_date', k.start_date, 'end_date', k.end_date, 'status', k.status, 'state', public._comp_state(k),
    'halaqa_ids', to_jsonb(k.halaqa_ids), 'settings', k.settings, 'updated_at', k.updated_at,
    'weeks_total', public._comp_total_weeks(k), 'elapsed_weeks', public._comp_elapsed_weeks(k),
    'days_left', greatest(0, k.end_date - public._comp_today(k.settings)),
    'participants', (select count(*) from public.competition_participants p where p.competition_id = k.id and p.status = 'active'),
    'can_manage', case when c.role::text = 'student' then false else public._comp_manage_ok(c, k) end)
$$;

create or replace function public.comp_list(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; st public.students; rows jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if c.role::text = 'student' then
    st := public._app_student_of(c);
    if st.id is null then return jsonb_build_object('ok', true, 'rows', '[]'::jsonb); end if;
    select coalesce(jsonb_agg(public._comp_row_json(k, c) order by
             case public._comp_state(k) when 'running' then 0 when 'upcoming' then 1 when 'paused' then 2 else 4 end, k.start_date desc), '[]'::jsonb)
      into rows from public.competitions k
     where k.status <> 'draft'
       and exists (select 1 from public.competition_participants p
                    where p.competition_id = k.id and p.student_id = st.id::text and p.status = 'active');
    return jsonb_build_object('ok', true, 'rows', rows);
  end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select coalesce(jsonb_agg(public._comp_row_json(k, c) order by
           case public._comp_state(k) when 'running' then 0 when 'upcoming' then 1 when 'paused' then 2 when 'draft' then 3 else 4 end, k.start_date desc), '[]'::jsonb)
    into rows from public.competitions k
   where public._comp_view_ok(c, k);
  return jsonb_build_object('ok', true, 'rows', rows);
end $$;

create or replace function public.comp_get(p_token text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; st public.students; k public.competitions; staff boolean;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into k from public.competitions where id::text = p_id;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if c.role::text = 'student' then
    st := public._app_student_of(c);
    if st.id is null or k.status = 'draft' or not exists (select 1 from public.competition_participants p
         where p.competition_id = k.id and p.student_id = st.id::text and p.status = 'active') then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    return jsonb_build_object('ok', true, 'competition', public._comp_row_json(k, c),
      'categories', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'weekly_max_points', g.weekly_max_points,
                                'kind', g.kind) order by g.sort_order, g.name)
                                from public.competition_categories g where g.competition_id = k.id and g.is_active), '[]'::jsonb));
  end if;
  if not public._comp_view_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'competition', public._comp_row_json(k, c),
    'can_manage', public._comp_manage_ok(c, k),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'weekly_max_points', g.weekly_max_points,
                              'kind', g.kind, 'sort_order', g.sort_order, 'is_active', g.is_active) order by g.sort_order, g.name)
                              from public.competition_categories g where g.competition_id = k.id), '[]'::jsonb),
    'participants', coalesce((select jsonb_agg(jsonb_build_object('student_id', p.student_id, 'name', s.name, 'halaqa_id', p.halaqa_id,
                              'level', p.level, 'target_note', p.target_note, 'status', p.status) order by s.name)
                              from public.competition_participants p
                              left join public.students s on s.id::text = p.student_id
                             where p.competition_id = k.id
                               and (c.role::text <> 'teacher' or p.halaqa_id = c.halaqa_id::text)), '[]'::jsonb));
end $$;

create or replace function public._comp_sync_cats(k public.competitions, cats jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare it jsonb; i int := 0; nm text; mx numeric; kd text; ky text; keep uuid[] := '{}'; v_id uuid; v_act boolean; ex public.competition_categories;
begin
  if jsonb_typeof(cats) <> 'array' or jsonb_array_length(cats) = 0 or jsonb_array_length(cats) > 30 then
    return jsonb_build_object('ok', false, 'error', 'bad_categories');
  end if;
  for it in select * from jsonb_array_elements(cats) loop
    i := i + 1;
    nm := left(btrim(coalesce(it ->> 'name', '')), 60);
    if nm = '' then return jsonb_build_object('ok', false, 'error', 'bad_categories'); end if;
    if (it ->> 'weekly_max_points') !~ '^[0-9]+(\.[0-9]+)?$' or (it ->> 'weekly_max_points')::numeric > 1000 then
      return jsonb_build_object('ok', false, 'error', 'bad_points');
    end if;
    mx := (it ->> 'weekly_max_points')::numeric;
    kd := case when it ->> 'kind' = 'bonus' then 'bonus' else 'core' end;
    ky := case when it ->> 'key' in ('hifz','itqan','review','attendance','early','prayer','adab','participation','azkar','bonus') then it ->> 'key' else 'custom' end;
    v_act := coalesce((it ->> 'is_active')::boolean, true);
    ex := null;
    if coalesce(it ->> 'id', '') <> '' then
      select * into ex from public.competition_categories g where g.id::text = it ->> 'id' and g.competition_id = k.id;
    end if;
    begin
      if ex.id is not null then
        update public.competition_categories set name = nm, weekly_max_points = mx, kind = kd, key = ky, sort_order = i, is_active = v_act where id = ex.id;
        v_id := ex.id;
      else
        insert into public.competition_categories (competition_id, key, name, weekly_max_points, sort_order, kind, is_active)
        values (k.id, ky, nm, mx, i, kd, v_act) returning id into v_id;
      end if;
    exception when unique_violation then
      return jsonb_build_object('ok', false, 'error', 'dup_category', 'name', nm);
    end;
    keep := keep || v_id;
  end loop;
  -- المجالات المحذوفة: تُحذف إن لم تُستخدم، وإلا تُعطَّل حفاظاً على النتائج
  delete from public.competition_categories g where g.competition_id = k.id and g.id <> all (keep)
     and not exists (select 1 from public.competition_scores s where s.category_id = g.id);
  update public.competition_categories g set is_active = false where g.competition_id = k.id and g.id <> all (keep);
  if not exists (select 1 from public.competition_categories g where g.competition_id = k.id and g.is_active and g.kind = 'core') then
    return jsonb_build_object('ok', false, 'error', 'no_core_category');
  end if;
  return null;
end $$;

create or replace function public._comp_sync_parts(k public.competitions, parts jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare it jsonb; sid text; s public.students; lv text; keep text[] := '{}'; missing text[] := '{}';
begin
  if jsonb_typeof(parts) <> 'array' then return jsonb_build_object('ok', false, 'error', 'bad_participants'); end if;
  for it in select * from jsonb_array_elements(parts) loop
    sid := it ->> 'student_id';
    select * into s from public.students st where st.id::text = sid and st.halaqa_id::text = any (k.halaqa_ids);
    if s.id is null then missing := missing || coalesce(sid, '?'); continue; end if;
    lv := case when it ->> 'level' in ('مبتدئ','متوسط','متقدم') then it ->> 'level' else 'متوسط' end;
    insert into public.competition_participants (competition_id, student_id, halaqa_id, level, target_note, status)
    values (k.id, s.id::text, s.halaqa_id::text, lv, nullif(left(btrim(coalesce(it ->> 'target_note', '')), 200), ''), 'active')
    on conflict (competition_id, student_id) do update
       set level = excluded.level, target_note = excluded.target_note, halaqa_id = excluded.halaqa_id, status = 'active';
    keep := keep || s.id::text;
  end loop;
  if cardinality(missing) > 0 then
    return jsonb_build_object('ok', false, 'error', 'student_not_found', 'ids', to_jsonb(missing));
  end if;
  delete from public.competition_participants p where p.competition_id = k.id and p.student_id <> all (keep)
     and not exists (select 1 from public.competition_scores sc where sc.competition_id = k.id and sc.student_id = p.student_id);
  update public.competition_participants p set status = 'removed' where p.competition_id = k.id and p.student_id <> all (keep);
  return null;
end $$;

create or replace function public.comp_save(p_token text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; k public.competitions; v_new boolean := false; hids text[]; h text;
  v_name text := btrim(coalesce(p ->> 'name', '')); v_start date; v_end date; v_set jsonb; r jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('ok', false, 'error', 'bad_name'); end if;
  begin v_start := (p ->> 'start_date')::date; v_end := (p ->> 'end_date')::date;
  exception when others then return jsonb_build_object('ok', false, 'error', 'bad_dates'); end;
  if v_start is null or v_end is null or v_end < v_start or (v_end - v_start) > 366 then
    return jsonb_build_object('ok', false, 'error', 'bad_dates');
  end if;
  select coalesce(array_agg(distinct x), '{}') into hids from jsonb_array_elements_text(coalesce(p -> 'halaqa_ids', '[]'::jsonb)) x;
  if cardinality(hids) = 0 then return jsonb_build_object('ok', false, 'error', 'no_halaqa'); end if;
  foreach h in array hids loop
    if not public._comp_halaqa_in_center(c, h) then return jsonb_build_object('ok', false, 'error', 'bad_halaqa'); end if;
  end loop;
  if c.role::text = 'teacher' and hids <> array[c.halaqa_id::text] then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  if coalesce(p ->> 'id', '') <> '' then
    select * into k from public.competitions where id::text = p ->> 'id';
    if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if not public._comp_manage_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if public._comp_state(k) = 'ended' then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
    if coalesce(p ->> 'expected_updated_at', '') <> '' and (p ->> 'expected_updated_at')::timestamptz <> k.updated_at then
      return jsonb_build_object('ok', false, 'error', 'conflict');
    end if;
    if v_start <> k.start_date and exists (select 1 from public.competition_scores s where s.competition_id = k.id and not s.voided) then
      return jsonb_build_object('ok', false, 'error', 'start_locked');
    end if;
    if exists (select 1 from public.competition_scores s where s.competition_id = k.id and not s.voided and s.evaluation_date > v_end) then
      return jsonb_build_object('ok', false, 'error', 'end_before_scores');
    end if;
    v_set := public._comp_clean_settings(k.settings || coalesce(p -> 'settings', '{}'::jsonb));
    update public.competitions set name = v_name, description = left(coalesce(p ->> 'description', ''), 500), start_date = v_start,
           end_date = v_end, halaqa_ids = hids, settings = v_set, updated_at = now() where id = k.id returning * into k;
  else
    v_new := true;
    v_set := public._comp_clean_settings(coalesce(p -> 'settings', '{}'::jsonb));
    insert into public.competitions (center_id, name, description, start_date, end_date, status, halaqa_ids, settings, created_by, created_by_name)
    values (c.center_id::text, v_name, left(coalesce(p ->> 'description', ''), 500), v_start, v_end, 'draft', hids, v_set,
            c.id::text, coalesce(c.full_name, c.username)) returning * into k;
  end if;

  if jsonb_typeof(p -> 'categories') = 'array' then
    r := public._comp_sync_cats(k, p -> 'categories');
  elsif v_new then
    r := public._comp_sync_cats(k, public._comp_default_cats());
  end if;
  if r is not null then raise exception 'comp_save:%', r::text using errcode = 'P0001'; end if;
  if jsonb_typeof(p -> 'participants') = 'array' then
    r := public._comp_sync_parts(k, p -> 'participants');
    if r is not null then raise exception 'comp_save:%', r::text using errcode = 'P0001'; end if;
  end if;
  update public.competitions set updated_at = now() where id = k.id returning * into k;
  return jsonb_build_object('ok', true, 'id', k.id, 'updated_at', k.updated_at, 'created', v_new);
exception when sqlstate 'P0001' then
  if sqlerrm like 'comp_save:%' then return substr(sqlerrm, 11)::jsonb; end if;
  raise;
end $$;

create or replace function public.comp_set_status(p_token text, p_id text, p_status text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions; o public.competitions; v_state text;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into k from public.competitions where id::text = p_id;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._comp_manage_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  v_state := public._comp_state(k);
  if p_status not in ('active', 'paused', 'ended', 'reopen') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  if p_status = 'reopen' then
    if c.role::text = 'teacher' or v_state <> 'ended' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if k.end_date < public._comp_today(k.settings) then return jsonb_build_object('ok', false, 'error', 'past_end'); end if;
    update public.competitions set status = 'paused', ended_at = null, updated_at = now() where id = k.id;
    return jsonb_build_object('ok', true);
  end if;
  if v_state = 'ended' then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_status = 'active' then
    if not exists (select 1 from public.competition_participants p where p.competition_id = k.id and p.status = 'active') then
      return jsonb_build_object('ok', false, 'error', 'no_participants');
    end if;
    select * into o from public.competitions x
     where x.id <> k.id and x.center_id = k.center_id and x.status in ('active', 'paused')
       and x.halaqa_ids && k.halaqa_ids and x.start_date <= k.end_date and x.end_date >= k.start_date
       and public._comp_state(x) <> 'ended' limit 1;
    if o.id is not null then return jsonb_build_object('ok', false, 'error', 'overlap', 'name', o.name); end if;
  end if;
  update public.competitions set status = p_status, updated_at = now(),
         ended_at = case when p_status = 'ended' then now() else ended_at end where id = k.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.comp_delete(p_token text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into k from public.competitions where id::text = p_id;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._comp_manage_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if k.status <> 'draft' or exists (select 1 from public.competition_scores s where s.competition_id = k.id) then
    return jsonb_build_object('ok', false, 'error', 'not_deletable');
  end if;
  delete from public.competitions where id = k.id;
  return jsonb_build_object('ok', true);
end $$;

notify pgrst, 'reload schema';
select 'تم الجزء 2 من 6 بنجاح ✅' as status;
