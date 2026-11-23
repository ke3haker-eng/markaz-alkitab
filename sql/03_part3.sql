-- =====================================================================
--  دوري فرسان القرآن — الجزء 3 من 6: النقاط والتقييم اليومي
--  شغّله بعد الجزء 2 بالترتيب. آمن ويمكن تكراره. الملف صغير ليُلصق كاملاً من الجوال.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.comp_save(text, jsonb)') is null then raise exception 'شغّل الجزء 2 أولاً (الترتيب مهم)'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 4) النقاط: التقييم اليومي، التعديل اليدوي، التصحيح والحذف (مع سجل تدقيق)
-- ---------------------------------------------------------------------
create or replace function public._comp_used(k public.competitions, p_sid text, p_cid uuid, p_week int, p_excl uuid) returns numeric
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(sum(s.points), 0) from public.competition_scores s
   where s.competition_id = k.id and s.student_id = p_sid and s.category_id = p_cid
     and s.week_number = p_week and not s.voided and (p_excl is null or s.id <> p_excl)
$$;

-- هل يمكن تعديل نقاط هذه المسابقة الآن؟ (null = نعم)
create or replace function public._comp_edit_gate(c public.users, k public.competitions) returns text
language sql stable set search_path = public, extensions, pg_temp as $$
  select case
    when public._comp_state(k) = 'ended' then case when c.role::text = 'teacher' then 'locked' else null end
    when k.status <> 'active' then 'not_active'
    else null end
$$;

create or replace function public.comp_eval_save(p_token text, p_comp text, p_date text, p_items jsonb, p_op text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; k public.competitions; v_op uuid; dup jsonb; d date; wk int; today date;
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
          if pts > g.weekly_max_points or used + pts > g.weekly_max_points then
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

create or replace function public.comp_adjust(p_token text, p_comp text, p_student text, p_category text, p_points numeric,
                                              p_reason text, p_date text default null, p_op text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; k public.competitions; v_op uuid; dup jsonb; d date; wk int; today date; part public.competition_participants;
  g public.competition_categories; used numeric; gate text; v_id uuid; post boolean; out jsonb; v_reason text := btrim(coalesce(p_reason, ''));
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
  today := public._comp_today(k.settings);
  begin d := coalesce(nullif(p_date, '')::date, least(today, k.end_date)); exception when others then return jsonb_build_object('ok', false, 'error', 'bad_date'); end;
  if d < k.start_date or d > k.end_date or (d > today and not post) then return jsonb_build_object('ok', false, 'error', 'out_of_window'); end if;
  wk := public._comp_week(k, d);
  select * into part from public.competition_participants pp where pp.competition_id = k.id and pp.student_id = p_student and pp.status = 'active';
  if part.id is null then return jsonb_build_object('ok', false, 'error', 'not_participant'); end if;
  if not public._comp_score_ok(c, k, part.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if post and c.role::text = 'teacher' then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select * into g from public.competition_categories gg where gg.id::text = p_category and gg.competition_id = k.id and gg.is_active;
  if g.id is null then return jsonb_build_object('ok', false, 'error', 'bad_category'); end if;
  used := public._comp_used(k, p_student, g.id, wk, null);
  if used + p_points > g.weekly_max_points then
    return jsonb_build_object('ok', false, 'error', 'cap', 'remaining', greatest(0, g.weekly_max_points - used));
  end if;
  if used + p_points < 0 then return jsonb_build_object('ok', false, 'error', 'below_zero', 'available', used); end if;
  insert into public.competition_scores (competition_id, student_id, category_id, points, entry_type, week_number, evaluation_date,
                                         reason, post_close, created_by, created_by_name)
  values (k.id, p_student, g.id, p_points, case when g.kind = 'bonus' then 'bonus' else 'adjust' end, wk, d,
          left(v_reason, 200), post, c.id::text, coalesce(c.full_name, c.username)) returning id into v_id;
  perform public._comp_audit(k, c, v_id, p_student, g.name, null, p_points, case when post then 'adjust_after_close' else 'adjust' end, v_reason);
  out := jsonb_build_object('ok', true, 'id', v_id, 'week_total', used + p_points, 'week', wk);
  perform public._comp_op_put(v_op, out);
  return out;
end $$;

create or replace function public.comp_score_update(p_token text, p_score text, p_points numeric, p_reason text, p_ver int default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions; s public.competition_scores; part public.competition_participants;
  g public.competition_categories; used numeric; gate text; v_reason text := btrim(coalesce(p_reason, ''));
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into s from public.competition_scores where id::text = p_score;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into k from public.competitions where id = s.competition_id;
  select * into part from public.competition_participants pp where pp.competition_id = k.id and pp.student_id = s.student_id;
  if not public._comp_view_ok(c, k) or not public._comp_score_ok(c, k, part.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  gate := public._comp_edit_gate(c, k);
  if gate is not null then return jsonb_build_object('ok', false, 'error', gate); end if;
  if s.voided then return jsonb_build_object('ok', false, 'error', 'voided'); end if;
  if length(v_reason) < 2 then return jsonb_build_object('ok', false, 'error', 'reason_required'); end if;
  if p_ver is not null and p_ver <> s.ver then return jsonb_build_object('ok', false, 'error', 'conflict', 'points', s.points, 'ver', s.ver); end if;
  if p_points is null or abs(p_points) > 100 or (s.entry_type = 'eval' and p_points < 0) then return jsonb_build_object('ok', false, 'error', 'bad_points'); end if;
  select * into g from public.competition_categories where id = s.category_id;
  used := public._comp_used(k, s.student_id, s.category_id, s.week_number, s.id);
  if used + p_points > g.weekly_max_points then return jsonb_build_object('ok', false, 'error', 'cap', 'remaining', greatest(0, g.weekly_max_points - used)); end if;
  if used + p_points < 0 then return jsonb_build_object('ok', false, 'error', 'below_zero', 'available', used); end if;
  update public.competition_scores set points = p_points, ver = ver + 1, updated_at = now(), reason = left(v_reason, 200),
         post_close = post_close or public._comp_state(k) = 'ended' where id = s.id;
  perform public._comp_audit(k, c, s.id, s.student_id, g.name, s.points, p_points,
                             case when public._comp_state(k) = 'ended' then 'update_after_close' else 'update' end, v_reason);
  return jsonb_build_object('ok', true, 'ver', s.ver + 1);
end $$;

create or replace function public.comp_score_void(p_token text, p_score text, p_reason text, p_restore boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions; s public.competition_scores; part public.competition_participants;
  g public.competition_categories; used numeric; gate text; v_reason text := btrim(coalesce(p_reason, ''));
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not public._comp_staff_ok(c) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into s from public.competition_scores where id::text = p_score;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into k from public.competitions where id = s.competition_id;
  select * into part from public.competition_participants pp where pp.competition_id = k.id and pp.student_id = s.student_id;
  if not public._comp_view_ok(c, k) or not public._comp_score_ok(c, k, part.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  gate := public._comp_edit_gate(c, k);
  if gate is not null then return jsonb_build_object('ok', false, 'error', gate); end if;
  if length(v_reason) < 2 then return jsonb_build_object('ok', false, 'error', 'reason_required'); end if;
  select * into g from public.competition_categories where id = s.category_id;
  if p_restore then
    if not s.voided then return jsonb_build_object('ok', false, 'error', 'not_voided'); end if;
    used := public._comp_used(k, s.student_id, s.category_id, s.week_number, null);
    if used + s.points > g.weekly_max_points then return jsonb_build_object('ok', false, 'error', 'cap', 'remaining', greatest(0, g.weekly_max_points - used)); end if;
    begin
      update public.competition_scores set voided = false, void_reason = null, ver = ver + 1, updated_at = now() where id = s.id;
    exception when unique_violation then return jsonb_build_object('ok', false, 'error', 'duplicate'); end;
    perform public._comp_audit(k, c, s.id, s.student_id, g.name, null, s.points, 'restore', v_reason);
    return jsonb_build_object('ok', true);
  end if;
  if s.voided then return jsonb_build_object('ok', false, 'error', 'voided'); end if;
  update public.competition_scores set voided = true, void_reason = left(v_reason, 200), ver = ver + 1, updated_at = now() where id = s.id;
  perform public._comp_audit(k, c, s.id, s.student_id, g.name, s.points, null,
                             case when public._comp_state(k) = 'ended' then 'void_after_close' else 'void' end, v_reason);
  return jsonb_build_object('ok', true);
end $$;

notify pgrst, 'reload schema';
select 'تم الجزء 3 من 6 بنجاح ✅' as status;
