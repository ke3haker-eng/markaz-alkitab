-- =====================================================================
--  دوري فرسان القرآن — الجزء 6 من 6: المحادثة الأساسية + حذف مركز + الصلاحيات
--  شغّله بعد الجزء 5 بالترتيب. آمن ويمكن تكراره. الملف صغير ليُلصق كاملاً من الجوال.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.asg_save(text, jsonb)') is null then raise exception 'شغّل الجزء 5 أولاً (الترتيب مهم)'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 7) محادثة الطالب والمعلم
-- ---------------------------------------------------------------------
create or replace function public._chat_staff_ok(c public.users, st public.students) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select st.id is not null and exists (select 1 from public.halaqat h where h.id::text = st.halaqa_id::text and h.center_id::text = c.center_id::text)
     and (c.role::text = 'supervisor'
          or (c.role::text = 'employee' and public._app_can(c, 'messages'))
          or (c.role::text = 'teacher' and c.halaqa_id::text = st.halaqa_id::text))
$$;

create or replace function public.chat_send(p_token text, p_student text, p_body text, p_op text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; st public.students; v_op uuid; dup jsonb; v_body text := btrim(coalesce(p_body, '')); v_id bigint; v_at timestamptz; out jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if length(v_body) < 1 or length(v_body) > 1500 then return jsonb_build_object('ok', false, 'error', 'bad_body'); end if;
  begin v_op := nullif(p_op, '')::uuid; exception when others then v_op := null; end;
  dup := public._comp_op_get(v_op); if dup is not null then return dup; end if;
  if (select count(*) from public.student_chat m where m.sender_id = c.id::text and m.created_at > now() - interval '1 minute') >= 20 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  if c.role::text = 'student' then st := public._app_student_of(c);
    if st.id is null or c.center_id is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  else
    select * into st from public.students s where s.id::text = p_student;
    if not public._chat_staff_ok(c, st) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  end if;
  insert into public.student_chat (center_id, halaqa_id, student_id, sender_role, sender_id, sender_name, body)
  values (c.center_id::text, st.halaqa_id::text, st.id::text, c.role::text, c.id::text, coalesce(c.full_name, c.username), v_body)
  returning id, created_at into v_id, v_at;
  out := jsonb_build_object('ok', true, 'id', v_id, 'created_at', v_at);
  perform public._comp_op_put(v_op, out);
  return out;
end $$;

create or replace function public.chat_get(p_token text, p_student text default null, p_after bigint default 0, p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; st public.students; rows jsonb; is_student boolean;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  is_student := c.role::text = 'student';
  if is_student then st := public._app_student_of(c);
    if st.id is null then return jsonb_build_object('ok', true, 'rows', '[]'::jsonb); end if;
  else
    select * into st from public.students s where s.id::text = p_student;
    if not public._chat_staff_ok(c, st) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.id), '[]'::jsonb) into rows from (
    select x.id, x.sender_role, x.sender_name, x.body, x.created_at, x.read_at, (x.sender_id = c.id::text) as mine
      from public.student_chat x where x.student_id = st.id::text and x.id > coalesce(p_after, 0)
     order by x.id desc limit least(greatest(coalesce(p_limit, 200), 1), 500)) m;
  update public.student_chat set read_at = now()
   where student_id = st.id::text and read_at is null and ((is_student and sender_role <> 'student') or (not is_student and sender_role = 'student'));
  return jsonb_build_object('ok', true, 'rows', rows, 'student', jsonb_build_object('id', st.id, 'name', st.name));
end $$;

create or replace function public.chat_threads(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; st public.students; rows jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if c.role::text = 'student' then
    st := public._app_student_of(c);
    return jsonb_build_object('ok', true, 'unread', case when st.id is null then 0 else
      (select count(*) from public.student_chat m where m.student_id = st.id::text and m.read_at is null and m.sender_role <> 'student') end);
  end if;
  if c.role::text not in ('teacher', 'supervisor', 'employee') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select coalesce(jsonb_agg(t order by (t ->> 'last_at') desc), '[]'::jsonb) into rows from (
    select jsonb_build_object('student_id', s.id, 'name', s.name, 'halaqa_id', s.halaqa_id,
             'last_body', l.body, 'last_at', l.created_at, 'last_role', l.sender_role,
             'unread', (select count(*) from public.student_chat m where m.student_id = s.id::text and m.read_at is null and m.sender_role = 'student')) as t
      from public.students s
      join lateral (select m.body, m.created_at, m.sender_role from public.student_chat m where m.student_id = s.id::text order by m.id desc limit 1) l on true
     where public._chat_staff_ok(c, s)) q;
  return jsonb_build_object('ok', true, 'rows', rows,
    'unread', (select coalesce(sum((r ->> 'unread')::int), 0) from jsonb_array_elements(rows) r));
end $$;

-- شبكة التقييم اليومي: الطلاب × المجالات لتاريخ محدد (استدعاء واحد خفيف)
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
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'key', g.key, 'name', g.name, 'weekly_max', g.weekly_max_points) order by g.sort_order, g.name), '[]'::jsonb)
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

-- ---------------------------------------------------------------------
-- 8) حذف مركز: يشمل جداول المسابقات/الواجبات/المحادثة الجديدة
-- ---------------------------------------------------------------------
create or replace function public.app_masool_delete_center(p_token text, p_center_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t text;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'masool' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  delete from public.app_sessions where user_id in (select id::text from public.users where center_id::text = p_center_id);
  -- الطلاب والسجلات عبر الحلقات (يعمل حتى لو لم يكن لهذه الجداول عمود center_id)
  foreach t in array array['records','students'] loop
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = t and column_name = 'halaqa_id') then
      execute format('delete from public.%I where halaqa_id::text in (select id::text from public.halaqat where center_id::text = $1)', t) using p_center_id;
    end if;
  end loop;
  foreach t in array array['records','students','halaqat','messages','daily_questions','deleted_ids',
                           'competitions','assignments','student_chat','users'] loop
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = t and column_name = 'center_id') then
      execute format('delete from public.%I where center_id::text = $1', t) using p_center_id;
    end if;
  end loop;
  delete from public.audit_log where center_id = p_center_id;
  delete from public.centers where id::text = p_center_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 9) صلاحيات التنفيذ: الدوال العامة فقط تُستدعى من المتصفح
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and (p.proname ~ '^(comp|asg|chat)_' or p.proname ~ '^_(comp|asg|chat)_' or p.proname = '_app_student_of'
            or p.proname = 'app_masool_delete_center' or p.proname = '_app_clean_perms')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if r.proname ~ '^(comp|asg|chat)_' or r.proname = 'app_masool_delete_center' then
      execute format('grant execute on function %s to anon, authenticated', r.sig);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';

notify pgrst, 'reload schema';
select 'تم الجزء 6 من 6 بنجاح ✅' as status;
