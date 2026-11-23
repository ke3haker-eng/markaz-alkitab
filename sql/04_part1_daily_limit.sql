-- =====================================================================
--  الإصدار 2.2.0 — الجزء 1 من 3: الحد اليومي للتقييم + تعديل النقاط لعدة طلاب ومجالات
--  شغّله بعد 03_competitions (كاملاً). آمن ويمكن تكراره. الملف صغير ليُلصق كاملاً من الجوال.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.comp_eval_save(text,text,text,jsonb,text)') is null then
    raise exception 'شغّل 03_competitions.sql أولاً';
  end if;
end $$;

alter table public.competition_categories add column if not exists daily_max_points numeric(7,2);

create or replace function public._comp_sync_cats(k public.competitions, cats jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare dm numeric; it jsonb; i int := 0; nm text; mx numeric; kd text; ky text; keep uuid[] := '{}'; v_id uuid; v_act boolean; ex public.competition_categories;
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
    dm := null;
    if coalesce(it ->> 'daily_max_points', '') <> '' then
      if (it ->> 'daily_max_points') !~ '^[0-9]+(\.[0-9]+)?$' or (it ->> 'daily_max_points')::numeric > mx then
        return jsonb_build_object('ok', false, 'error', 'bad_points');
      end if;
      dm := (it ->> 'daily_max_points')::numeric;
    end if;
    kd := case when it ->> 'kind' = 'bonus' then 'bonus' else 'core' end;
    ky := case when it ->> 'key' in ('hifz','itqan','review','attendance','early','prayer','adab','participation','azkar','bonus') then it ->> 'key' else 'custom' end;
    v_act := coalesce((it ->> 'is_active')::boolean, true);
    ex := null;
    if coalesce(it ->> 'id', '') <> '' then
      select * into ex from public.competition_categories g where g.id::text = it ->> 'id' and g.competition_id = k.id;
    end if;
    begin
      if ex.id is not null then
        update public.competition_categories set name = nm, weekly_max_points = mx, daily_max_points = dm, kind = kd, key = ky, sort_order = i, is_active = v_act where id = ex.id;
        v_id := ex.id;
      else
        insert into public.competition_categories (competition_id, key, name, weekly_max_points, daily_max_points, sort_order, kind, is_active)
        values (k.id, ky, nm, mx, dm, i, kd, v_act) returning id into v_id;
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
      'categories', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'weekly_max_points', g.weekly_max_points, 'daily_max_points', g.daily_max_points, 'daily_max', coalesce(g.daily_max_points, round(g.weekly_max_points / 5.0, 2)),
                                'kind', g.kind) order by g.sort_order, g.name)
                                from public.competition_categories g where g.competition_id = k.id and g.is_active), '[]'::jsonb));
  end if;
  if not public._comp_view_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'competition', public._comp_row_json(k, c),
    'can_manage', public._comp_manage_ok(c, k),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'weekly_max_points', g.weekly_max_points, 'daily_max_points', g.daily_max_points, 'daily_max', coalesce(g.daily_max_points, round(g.weekly_max_points / 5.0, 2)),
                              'kind', g.kind, 'sort_order', g.sort_order, 'is_active', g.is_active) order by g.sort_order, g.name)
                              from public.competition_categories g where g.competition_id = k.id), '[]'::jsonb),
    'participants', coalesce((select jsonb_agg(jsonb_build_object('student_id', p.student_id, 'name', s.name, 'halaqa_id', p.halaqa_id,
                              'level', p.level, 'target_note', p.target_note, 'status', p.status) order by s.name)
                              from public.competition_participants p
                              left join public.students s on s.id::text = p.student_id
                             where p.competition_id = k.id
                               and (c.role::text <> 'teacher' or p.halaqa_id = c.halaqa_id::text)), '[]'::jsonb));
end $$;

create or replace function public.comp_grid(p_token text, p_comp text, p_date text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions; d date; today date; wk int; cats jsonb; rows jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into k from public.competitions where id::text = p_comp;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._comp_view_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  today := public._comp_today(k.settings);
  begin d := coalesce(nullif(p_date, '')::date, least(greatest(today, k.start_date), k.end_date));
  exception when others then return jsonb_build_object('ok', false, 'error', 'bad_date'); end;
  if d < k.start_date or d > k.end_date then return jsonb_build_object('ok', false, 'error', 'out_of_window'); end if;
  wk := public._comp_week(k, d);
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'weekly_max', g.weekly_max_points, 'daily_max', coalesce(g.daily_max_points, round(g.weekly_max_points / 5.0, 2))) order by g.sort_order, g.name), '[]'::jsonb)
    into cats from public.competition_categories g where g.competition_id = k.id and g.is_active and g.kind = 'core';
  select coalesce(jsonb_agg(jsonb_build_object('student_id', p.student_id, 'name', coalesce(s.name, '—'), 'halaqa_id', p.halaqa_id, 'level', p.level,
      'cells', (select coalesce(jsonb_object_agg(g.id::text, jsonb_build_object('points', ev.points, 'ver', ev.ver, 'id', ev.id,
                  'used', public._comp_used(k, p.student_id, g.id, wk, null))), '{}'::jsonb)
                  from public.competition_categories g
                  left join public.competition_scores ev on ev.competition_id = k.id and ev.student_id = p.student_id and ev.category_id = g.id
                       and ev.evaluation_date = d and ev.entry_type = 'eval' and not ev.voided
                 where g.competition_id = k.id and g.is_active and g.kind = 'core')) order by coalesce(s.name, '—')), '[]'::jsonb)
    into rows
    from public.competition_participants p left join public.students s on s.id::text = p.student_id
   where p.competition_id = k.id and p.status = 'active' and public._comp_score_ok(c, k, p.halaqa_id);
  return jsonb_build_object('ok', true, 'date', d, 'week', wk, 'today', today, 'state', public._comp_state(k), 'status', k.status,
                            'start_date', k.start_date, 'end_date', k.end_date, 'categories', cats, 'rows', rows);
end $$;

create or replace function public.comp_eval_save(p_token text, p_comp text, p_date text, p_items jsonb, p_op text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_daily numeric; c public.users; k public.competitions; v_op uuid; dup jsonb; d date; wk int; today date;
  it jsonb; sid text; cid text; pts numeric; v_ver int; part public.competition_participants; g public.competition_categories;
  ex public.competition_scores; used numeric; res jsonb := '[]'::jsonb; saved int := 0; st text; gate text; out jsonb; v_id uuid;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  begin v_op := nullif(p_op, '')::uuid; exception when others then v_op := null; end;
  dup := public._comp_op_get(v_op); if dup is not null then return dup; end if;
  select * into k from public.competitions where id::text = p_comp;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._comp_view_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if public._comp_state(k) = 'ended' then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if k.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'not_active'); end if;
  begin d := p_date::date; exception when others then return jsonb_build_object('ok', false, 'error', 'bad_date'); end;
  today := public._comp_today(k.settings);
  if d is null or d < k.start_date or d > k.end_date or d > today then return jsonb_build_object('ok', false, 'error', 'out_of_window'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 600 then
    return jsonb_build_object('ok', false, 'error', 'bad_items');
  end if;
  wk := public._comp_week(k, d);

  for it in select * from jsonb_array_elements(p_items) loop
    sid := it ->> 'student_id'; cid := it ->> 'category_id'; v_ver := nullif(it ->> 'ver', '')::int;
    st := null; out := jsonb_build_object('student_id', sid, 'category_id', cid);
    begin
      select * into part from public.competition_participants pp where pp.competition_id = k.id and pp.student_id = sid and pp.status = 'active';
      select * into g from public.competition_categories gg where gg.id::text = cid and gg.competition_id = k.id and gg.is_active and gg.kind = 'core';
      if part.id is null then st := 'not_participant';
      elsif not public._comp_score_ok(c, k, part.halaqa_id) then st := 'forbidden';
      elsif g.id is null then st := 'bad_category';
      else
        select * into ex from public.competition_scores s where s.competition_id = k.id and s.student_id = sid and s.category_id = g.id
           and s.evaluation_date = d and s.entry_type = 'eval' and not s.voided;
        if (it ->> 'points') is null or btrim(it ->> 'points') = '' then
          if ex.id is null then st := 'noop';
          elsif v_ver is not null and v_ver <> ex.ver then st := 'conflict'; out := out || jsonb_build_object('points', ex.points, 'ver', ex.ver);
          else
            update public.competition_scores set voided = true, void_reason = 'مسح التقييم', ver = ver + 1, updated_at = now() where id = ex.id;
            perform public._comp_audit(k, c, ex.id, sid, g.name, ex.points, null, 'void', 'مسح التقييم');
            st := 'cleared'; saved := saved + 1;
          end if;
        elsif (it ->> 'points') !~ '^[0-9]+(\.[0-9]{1,2})?$' then st := 'bad_points';
        else
          pts := (it ->> 'points')::numeric;
          used := public._comp_used(k, sid, g.id, wk, ex.id);
          v_daily := coalesce(g.daily_max_points, round(g.weekly_max_points / 5.0, 2));
          if pts > v_daily then
            st := 'daily_cap'; out := out || jsonb_build_object('daily_max', v_daily);
          elsif pts > g.weekly_max_points or used + pts > g.weekly_max_points then
            st := 'cap'; out := out || jsonb_build_object('remaining', greatest(0, g.weekly_max_points - used));
          elsif ex.id is not null then
            if v_ver is not null and v_ver <> ex.ver then st := 'conflict'; out := out || jsonb_build_object('points', ex.points, 'ver', ex.ver);
            elsif ex.points = pts then st := 'same'; out := out || jsonb_build_object('ver', ex.ver, 'id', ex.id);
            else
              update public.competition_scores set points = pts, ver = ver + 1, updated_at = now(),
                     reason = coalesce(nullif(left(btrim(coalesce(it ->> 'note', '')), 200), ''), reason) where id = ex.id returning ver into v_ver;
              perform public._comp_audit(k, c, ex.id, sid, g.name, ex.points, pts, 'update', coalesce(it ->> 'note', 'تعديل التقييم اليومي'));
              st := 'saved'; saved := saved + 1; out := out || jsonb_build_object('ver', v_ver, 'id', ex.id);
            end if;
          else
            insert into public.competition_scores (competition_id, student_id, category_id, points, entry_type, week_number, evaluation_date, reason, created_by, created_by_name)
            values (k.id, sid, g.id, pts, 'eval', wk, d, coalesce(left(btrim(coalesce(it ->> 'note', '')), 200), ''), c.id::text, coalesce(c.full_name, c.username))
            returning id into v_id;
            perform public._comp_audit(k, c, v_id, sid, g.name, null, pts, 'create', coalesce(nullif(it ->> 'note', ''), 'تقييم يومي'));
            st := 'saved'; saved := saved + 1; out := out || jsonb_build_object('ver', 1, 'id', v_id);
          end if;
        end if;
      end if;
    exception when unique_violation then st := 'duplicate';
    end;
    res := res || (out || jsonb_build_object('status', st, 'points', coalesce(out -> 'points', to_jsonb(pts))));
  end loop;
  out := jsonb_build_object('ok', true, 'saved', saved, 'results', res, 'date', d, 'week', wk);
  perform public._comp_op_put(v_op, out);
  return out;
end $$;

create or replace function public.comp_adjust_many(p_token text, p_comp text, p_students text[], p_categories text[], p_points numeric,
                                                       p_reason text, p_date text default null, p_op text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; k public.competitions; v_op uuid; dup jsonb; d date; wk int; today date; part public.competition_participants;
  g public.competition_categories; used numeric; gate text; post boolean; v_reason text := btrim(coalesce(p_reason, ''));
  sid text; cid text; res jsonb := '[]'::jsonb; saved int := 0; st text; v_id uuid; out jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  begin v_op := nullif(p_op, '')::uuid; exception when others then v_op := null; end;
  dup := public._comp_op_get(v_op); if dup is not null then return dup; end if;
  select * into k from public.competitions where id::text = p_comp;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._comp_view_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  gate := public._comp_edit_gate(c, k);
  if gate is not null then return jsonb_build_object('ok', false, 'error', gate); end if;
  post := public._comp_state(k) = 'ended';
  if length(v_reason) < 2 then return jsonb_build_object('ok', false, 'error', 'reason_required'); end if;
  if p_points is null or p_points = 0 or abs(p_points) > 100 then return jsonb_build_object('ok', false, 'error', 'bad_points'); end if;
  if coalesce(cardinality(p_students), 0) = 0 or coalesce(cardinality(p_categories), 0) = 0
     or cardinality(p_students) * cardinality(p_categories) > 400 then return jsonb_build_object('ok', false, 'error', 'bad_items'); end if;
  today := public._comp_today(k.settings);
  begin d := coalesce(nullif(p_date, '')::date, least(today, k.end_date)); exception when others then return jsonb_build_object('ok', false, 'error', 'bad_date'); end;
  if d < k.start_date or d > k.end_date or (d > today and not post) then return jsonb_build_object('ok', false, 'error', 'out_of_window'); end if;
  wk := public._comp_week(k, d);
  foreach sid in array p_students loop
    select * into part from public.competition_participants pp where pp.competition_id = k.id and pp.student_id = sid and pp.status = 'active';
    foreach cid in array p_categories loop
      st := null;
      if part.id is null then st := 'not_participant';
      elsif not public._comp_score_ok(c, k, part.halaqa_id) then st := 'forbidden';
      elsif post and c.role::text = 'teacher' then st := 'locked';
      else
        select * into g from public.competition_categories gg where gg.id::text = cid and gg.competition_id = k.id and gg.is_active;
        if g.id is null then st := 'bad_category';
        else
          used := public._comp_used(k, sid, g.id, wk, null);
          if used + p_points > g.weekly_max_points then st := 'cap';
          elsif used + p_points < 0 then st := 'below_zero';
          else
            insert into public.competition_scores (competition_id, student_id, category_id, points, entry_type, week_number, evaluation_date,
                                                   reason, post_close, created_by, created_by_name)
            values (k.id, sid, g.id, p_points, case when g.kind = 'bonus' then 'bonus' else 'adjust' end, wk, d,
                    left(v_reason, 200), post, c.id::text, coalesce(c.full_name, c.username)) returning id into v_id;
            perform public._comp_audit(k, c, v_id, sid, g.name, null, p_points, case when post then 'adjust_after_close' else 'adjust' end, v_reason);
            st := 'saved'; saved := saved + 1;
          end if;
        end if;
      end if;
      res := res || jsonb_build_object('student_id', sid, 'category_id', cid, 'status', st);
    end loop;
  end loop;
  out := jsonb_build_object('ok', true, 'saved', saved, 'results', res);
  perform public._comp_op_put(v_op, out);
  return out;
end $$;

revoke all on function public.comp_adjust_many(text, text, text[], text[], numeric, text, text, text) from public, anon, authenticated;
grant execute on function public.comp_adjust_many(text, text, text[], text[], numeric, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
select 'تم الجزء 1 من 3 بنجاح ✅' as status;
