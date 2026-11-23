-- =====================================================================
--  دوري فرسان القرآن — الجزء 4 من 6: الترتيب والتفاصيل والتقارير
--  شغّله بعد الجزء 3 بالترتيب. آمن ويمكن تكراره. الملف صغير ليُلصق كاملاً من الجوال.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.comp_eval_save(text, text, text, jsonb, text)') is null then raise exception 'شغّل الجزء 3 أولاً (الترتيب مهم)'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 5) الترتيب والتفاصيل والتقارير وسجل التدقيق
-- ---------------------------------------------------------------------
create or replace function public._comp_totals(p_comp uuid)
returns table (student_id text, name text, halaqa_id text, level text, total numeric, prev_total numeric,
               last_update timestamptz, rk bigint, prk bigint, has_prev boolean, gap numeric)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with parts as (
    select p.student_id, p.halaqa_id, p.level, coalesce(s.name, '—') as name
      from public.competition_participants p left join public.students s on s.id::text = p.student_id
     where p.competition_id = p_comp and p.status = 'active'),
  sc as (select s.student_id, s.points, s.evaluation_date, s.updated_at from public.competition_scores s
          where s.competition_id = p_comp and not s.voided),
  ld as (select max(evaluation_date) as d from sc),
  tot as (
    select pa.student_id, pa.name, pa.halaqa_id, pa.level,
           coalesce(sum(sc.points), 0)::numeric as total,
           coalesce(sum(sc.points) filter (where sc.evaluation_date < (select d from ld)), 0)::numeric as prev_total,
           max(sc.updated_at) as last_update
      from parts pa left join sc on sc.student_id = pa.student_id
     group by pa.student_id, pa.name, pa.halaqa_id, pa.level)
  select t.student_id, t.name, t.halaqa_id, t.level, t.total, t.prev_total, t.last_update,
         rank() over (order by t.total desc), rank() over (order by t.prev_total desc),
         exists (select 1 from sc where sc.evaluation_date < (select d from ld)),
         lag(t.total) over (order by t.total desc, t.name) - t.total
    from tot t
$$;

create or replace function public._comp_access(c public.users, k public.competitions) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare st public.students;
begin
  if c.role::text = 'student' then
    st := public._app_student_of(c);
    if st.id is null or k.status = 'draft' or k.center_id <> c.center_id::text
       or not exists (select 1 from public.competition_participants p where p.competition_id = k.id and p.student_id = st.id::text and p.status = 'active') then
      return null;
    end if;
    return 'student';
  end if;
  if public._comp_view_ok(c, k) then return 'staff'; end if;
  return null;
end $$;

create or replace function public.comp_leaderboard(p_token text, p_comp text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions; acc text; me text; rows jsonb; n int; show boolean;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into k from public.competitions where id::text = p_comp;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  acc := public._comp_access(c, k);
  if acc is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if acc = 'student' then me := (public._app_student_of(c)).id::text; end if;
  -- الترتيب الحي يمكن إخفاؤه عن الطلاب؛ أما النتائج النهائية بعد الانتهاء فتظهر دائماً
  show := acc = 'staff' or coalesce((k.settings ->> 'show_ranking')::boolean, true) or public._comp_state(k) = 'ended';
  select count(*) into n from public.competition_participants where competition_id = k.id and status = 'active';
  select coalesce(jsonb_agg(jsonb_build_object(
      'student_id', t.student_id, 'name', t.name, 'halaqa_id', t.halaqa_id, 'level', t.level,
      'total', t.total, 'rank', t.rk,
      'prev_rank', case when t.has_prev then t.prk else null end,
      'delta', case when t.has_prev then t.prk - t.rk else null end,
      'gap', t.gap, 'last_update', t.last_update, 'me', (t.student_id = me),
      'weeks', (select coalesce(jsonb_object_agg(w.week_number::text, w.s), '{}'::jsonb)
                  from (select s.week_number, sum(s.points) as s from public.competition_scores s
                         where s.competition_id = k.id and s.student_id = t.student_id and not s.voided group by s.week_number) w))
      order by t.rk, t.name), '[]'::jsonb)
    into rows
    from public._comp_totals(k.id) t
   where show or t.student_id = me;
  return jsonb_build_object('ok', true, 'rows', rows, 'participants', n, 'state', public._comp_state(k),
                            'weeks_total', public._comp_total_weeks(k), 'elapsed_weeks', public._comp_elapsed_weeks(k),
                            'ranking_hidden', not show);
end $$;

create or replace function public.comp_student_detail(p_token text, p_comp text, p_student text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; k public.competitions; acc text; sid text; part public.competition_participants; staff boolean;
  tw int; ew int; core_week numeric; tot numeric; rk bigint; gap numeric; cnt int; cats jsonb; weeks jsonb; ents jsonb; badges jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into k from public.competitions where id::text = p_comp;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  acc := public._comp_access(c, k);
  if acc is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  staff := acc = 'staff';
  if staff then sid := p_student; else sid := (public._app_student_of(c)).id::text; end if;
  select * into part from public.competition_participants pp where pp.competition_id = k.id and pp.student_id = sid;
  if part.id is null then return jsonb_build_object('ok', false, 'error', 'not_participant'); end if;
  if staff and c.role::text = 'teacher' and part.halaqa_id <> c.halaqa_id::text then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  tw := public._comp_total_weeks(k); ew := public._comp_elapsed_weeks(k);
  select coalesce(sum(weekly_max_points), 0) into core_week from public.competition_categories where competition_id = k.id and is_active and kind = 'core';
  select coalesce(sum(points), 0) into tot from public.competition_scores where competition_id = k.id and student_id = sid and not voided;
  select t.rk, t.gap into rk, gap from public._comp_totals(k.id) t where t.student_id = sid;
  select count(*) into cnt from public.competition_participants where competition_id = k.id and status = 'active';
  if not staff and not (coalesce((k.settings ->> 'show_ranking')::boolean, true) or public._comp_state(k) = 'ended') then rk := null; gap := null; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'kind', g.kind, 'weekly_max', g.weekly_max_points,
           'total', coalesce(x.total, 0), 'possible', g.weekly_max_points * ew,
           'weeks', coalesce(x.weeks, '{}'::jsonb)) order by g.sort_order, g.name), '[]'::jsonb)
    into cats
    from public.competition_categories g
    left join lateral (
      select sum(w.s) as total, jsonb_object_agg(w.week_number::text, w.s) as weeks
        from (select s.week_number, sum(s.points) as s from public.competition_scores s
               where s.competition_id = k.id and s.student_id = sid and s.category_id = g.id and not s.voided group by s.week_number) w) x on true
   where g.competition_id = k.id and g.is_active;

  select coalesce(jsonb_agg(jsonb_build_object('week', gs.w, 'points', coalesce(w.s, 0), 'max', core_week,
           'start', k.start_date + (gs.w - 1) * 7, 'end', least(k.end_date, k.start_date + gs.w * 7 - 1)) order by gs.w), '[]'::jsonb)
    into weeks
    from generate_series(1, tw) as gs(w)
    left join (select s.week_number, sum(s.points) as s from public.competition_scores s
                where s.competition_id = k.id and s.student_id = sid and not s.voided group by s.week_number) w on w.week_number = gs.w;

  select coalesce(jsonb_agg(e order by (e ->> 'date') desc, (e ->> 'created_at') desc), '[]'::jsonb) into ents from (
    select jsonb_build_object('id', s.id, 'category', g.name, 'category_id', g.id, 'points', s.points, 'date', s.evaluation_date, 'week', s.week_number,
             'reason', s.reason, 'type', s.entry_type, 'ver', s.ver, 'voided', s.voided, 'void_reason', s.void_reason,
             'by', s.created_by_name, 'post_close', s.post_close, 'created_at', s.created_at) as e
      from public.competition_scores s join public.competition_categories g on g.id = s.category_id
     where s.competition_id = k.id and s.student_id = sid and (staff or not s.voided)
     order by s.evaluation_date desc, s.created_at desc limit 300) q;

  -- شارات المسابقة: تُمنح عند بلوغ 80٪ من الحد الأقصى للمجال خلال الأسابيع المنقضية
  select coalesce(jsonb_agg(b order by (b ->> 'sort')::int), '[]'::jsonb) into badges from (
    select jsonb_build_object('key', d.bkey, 'name', d.bname, 'icon', d.icon, 'sort', d.srt,
             'progress', case when sum(g.weekly_max_points) * ew > 0 then round(100 * coalesce(sum(x.t), 0) / (sum(g.weekly_max_points) * ew)) else 0 end,
             'earned', ew >= 1 and sum(g.weekly_max_points) * ew > 0 and coalesce(sum(x.t), 0) >= 0.8 * sum(g.weekly_max_points) * ew) as b
      from (values ('hifz','فارس الحفظ','📖',1,'hifz'), ('itqan','نجم الإتقان','⭐',2,'itqan'), ('review','بطل المراجعة','🔁',3,'review'),
                   ('discipline','فارس الانضباط','⏰',4,'attendance'), ('discipline','فارس الانضباط','⏰',4,'early'),
                   ('adab','صاحب الخلق الحسن','🤝',5,'adab'),
                   ('himma','صاحب الهمة','🔥',6,'participation'), ('himma','صاحب الهمة','🔥',6,'azkar')) as d(bkey, bname, icon, srt, ckey)
      join public.competition_categories g on g.competition_id = k.id and g.is_active and g.kind = 'core' and g.key = d.ckey
      left join lateral (select sum(s.points) as t from public.competition_scores s
                          where s.competition_id = k.id and s.student_id = sid and s.category_id = g.id and not s.voided) x on true
     group by d.bkey, d.bname, d.icon, d.srt) z;

  return jsonb_build_object('ok', true, 'student_id', sid, 'level', part.level, 'target_note', part.target_note,
    'name', (select s.name from public.students s where s.id::text = sid),
    'total', tot, 'rank', rk, 'participants', cnt, 'gap', gap, 'weeks_total', tw, 'elapsed_weeks', ew, 'weekly_core_max', core_week,
    'categories', cats, 'weeks', weeks, 'entries', ents, 'badges', badges, 'state', public._comp_state(k));
end $$;

create or replace function public.comp_audit_list(p_token text, p_comp text, p_limit int default 100, p_before bigint default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into k from public.competitions where id::text = p_comp;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._comp_view_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(to_jsonb(q) order by q.id desc) from (
      select a.id, a.created_at, a.student_id, coalesce(s.name, '—') as student_name, a.category_name, a.old_points, a.new_points,
             a.action_type, a.reason, a.performed_by_name
        from public.competition_score_audit a
        left join public.students s on s.id::text = a.student_id
       where a.competition_id = k.id and (p_before is null or a.id < p_before)
         and (c.role::text <> 'teacher' or exists (select 1 from public.competition_participants pp
                where pp.competition_id = k.id and pp.student_id = a.student_id and pp.halaqa_id = c.halaqa_id::text))
       order by a.id desc limit least(greatest(coalesce(p_limit, 100), 1), 300)) q), '[]'::jsonb));
end $$;

create or replace function public.comp_report(p_token text, p_comp text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; k public.competitions; studs jsonb; cats jsonb; wk jsonb; lead jsonb; impr jsonb; lastw int; prevw int;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into k from public.competitions where id::text = p_comp;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._comp_view_ok(c, k) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'kind', g.kind, 'weekly_max', g.weekly_max_points)
                           order by g.sort_order, g.name), '[]'::jsonb) into cats
    from public.competition_categories g where g.competition_id = k.id and g.is_active;

  select coalesce(jsonb_agg(jsonb_build_object('student_id', t.student_id, 'name', t.name, 'halaqa_id', t.halaqa_id, 'level', t.level,
      'total', t.total, 'rank', t.rk,
      'by_category', (select coalesce(jsonb_object_agg(x.category_id::text, x.s), '{}'::jsonb)
                        from (select s.category_id, sum(s.points) as s from public.competition_scores s
                               where s.competition_id = k.id and s.student_id = t.student_id and not s.voided group by s.category_id) x),
      'by_week', (select coalesce(jsonb_object_agg(x.week_number::text, x.s), '{}'::jsonb)
                    from (select s.week_number, sum(s.points) as s from public.competition_scores s
                           where s.competition_id = k.id and s.student_id = t.student_id and not s.voided group by s.week_number) x))
      order by t.rk, t.name), '[]'::jsonb) into studs
    from public._comp_totals(k.id) t
   where c.role::text <> 'teacher' or t.halaqa_id = c.halaqa_id::text;

  select coalesce(jsonb_agg(jsonb_build_object('week', w.week_number, 'total', w.tot, 'average', round(w.tot / nullif(w.n, 0), 2)) order by w.week_number), '[]'::jsonb) into wk
    from (select s.week_number, sum(s.points) as tot, count(distinct s.student_id) as n from public.competition_scores s
           where s.competition_id = k.id and not s.voided
             and (c.role::text <> 'teacher' or s.student_id in (select pp.student_id from public.competition_participants pp
                    where pp.competition_id = k.id and pp.halaqa_id = c.halaqa_id::text))
           group by s.week_number) w;

  select coalesce(jsonb_agg(jsonb_build_object('category_id', q.cid, 'category', q.cname,
           'top', (select jsonb_agg(jsonb_build_object('student_id', r.student_id, 'name', r.name, 'points', r.p) order by r.p desc)
                     from (select s.student_id, coalesce(st.name, '—') as name, sum(s.points) as p
                             from public.competition_scores s left join public.students st on st.id::text = s.student_id
                            where s.competition_id = k.id and s.category_id = q.cid and not s.voided
                              and (c.role::text <> 'teacher' or s.student_id in (select pp.student_id from public.competition_participants pp
                                     where pp.competition_id = k.id and pp.halaqa_id = c.halaqa_id::text))
                            group by s.student_id, st.name having sum(s.points) > 0 order by sum(s.points) desc limit 3) r))
           order by q.srt), '[]'::jsonb) into lead
    from (select g.id as cid, g.name as cname, g.sort_order as srt from public.competition_categories g
           where g.competition_id = k.id and g.is_active) q
   where exists (select 1 from public.competition_scores s where s.competition_id = k.id and s.category_id = q.cid and not s.voided and s.points > 0);

  select max(week_number) into lastw from public.competition_scores where competition_id = k.id and not voided;
  prevw := lastw - 1;
  select coalesce(jsonb_agg(jsonb_build_object('student_id', x.student_id, 'name', x.name, 'last_week', x.lw, 'prev_week', x.pw, 'improvement', x.lw - x.pw)
                            order by x.lw - x.pw desc), '[]'::jsonb) into impr
    from (select t.student_id, t.name,
                 coalesce((select sum(s.points) from public.competition_scores s where s.competition_id = k.id and s.student_id = t.student_id and not s.voided and s.week_number = lastw), 0) as lw,
                 coalesce((select sum(s.points) from public.competition_scores s where s.competition_id = k.id and s.student_id = t.student_id and not s.voided and s.week_number = prevw), 0) as pw
            from public._comp_totals(k.id) t
           where lastw is not null and prevw >= 1 and (c.role::text <> 'teacher' or t.halaqa_id = c.halaqa_id::text)) x
   where x.lw - x.pw > 0 limit 5;

  return jsonb_build_object('ok', true, 'competition', public._comp_row_json(k, c), 'categories', cats, 'students', studs,
                            'weeks', wk, 'leaders', lead, 'improved', impr, 'last_week', lastw);
end $$;

notify pgrst, 'reload schema';
select 'تم الجزء 4 من 6 بنجاح ✅' as status;
