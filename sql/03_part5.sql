-- =====================================================================
--  دوري فرسان القرآن — الجزء 5 من 6: الواجبات
--  شغّله بعد الجزء 4 بالترتيب. آمن ويمكن تكراره. الملف صغير ليُلصق كاملاً من الجوال.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.comp_leaderboard(text, text)') is null then raise exception 'شغّل الجزء 4 أولاً (الترتيب مهم)'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 6) الواجبات (يحلّها الطالب وتظهر نتائجها للمعلم)
-- ---------------------------------------------------------------------
create or replace function public._asg_scope_ok(c public.users, hid text) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select c.id is not null and exists (select 1 from public.halaqat h where h.id::text = hid and h.center_id::text = c.center_id::text)
     and (c.role::text = 'supervisor'
          or (c.role::text = 'employee' and public._app_can(c, 'competitions'))
          or (c.role::text = 'teacher' and c.halaqa_id::text = hid))
$$;

create or replace function public._asg_student_ok(c public.users, a public.assignments, st public.students) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select st.id is not null and a.center_id = c.center_id::text and a.halaqa_id = st.halaqa_id::text
     and (cardinality(a.student_ids) = 0 or st.id::text = any (a.student_ids))
$$;

create or replace function public._asg_row_json(a public.assignments) returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object('id', a.id, 'halaqa_id', a.halaqa_id,
    'halaqa_name', (select h.name from public.halaqat h where h.id::text = a.halaqa_id),
    'title', a.title, 'description', a.description, 'due_at', a.due_at, 'status', a.status, 'student_ids', to_jsonb(a.student_ids),
    'settings', a.settings, 'updated_at', a.updated_at,
    'questions', (select count(*) from public.assignment_questions q where q.assignment_id = a.id),
    'max_score', (select coalesce(sum(q.points), 0) from public.assignment_questions q where q.assignment_id = a.id))
$$;

create or replace function public.asg_save(p_token text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; a public.assignments; v_new boolean := false; hid text := p ->> 'halaqa_id'; v_title text := btrim(coalesce(p ->> 'title', ''));
  v_due timestamptz; sids text[]; v_set jsonb; q jsonb; i int := 0; qt text; opts jsonb; cor jsonb; pts numeric; missing text[];
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if c.role::text not in ('teacher', 'supervisor', 'employee') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if length(v_title) < 2 or length(v_title) > 120 then return jsonb_build_object('ok', false, 'error', 'bad_title'); end if;
  if not public._asg_scope_ok(c, hid) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  begin v_due := nullif(p ->> 'due_at', '')::timestamptz; exception when others then return jsonb_build_object('ok', false, 'error', 'bad_date'); end;
  select coalesce(array_agg(distinct x), '{}') into sids from jsonb_array_elements_text(coalesce(p -> 'student_ids', '[]'::jsonb)) x;
  select coalesce(array_agg(x), '{}') into missing from unnest(sids) x
   where not exists (select 1 from public.students s where s.id::text = x and s.halaqa_id::text = hid);
  if cardinality(missing) > 0 then return jsonb_build_object('ok', false, 'error', 'student_not_found', 'ids', to_jsonb(missing)); end if;
  v_set := jsonb_build_object('reveal_answers', coalesce((p -> 'settings' ->> 'reveal_answers')::boolean, true),
                              'allow_late', coalesce((p -> 'settings' ->> 'allow_late')::boolean, false));

  if coalesce(p ->> 'id', '') <> '' then
    select * into a from public.assignments where id::text = p ->> 'id';
    if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if a.halaqa_id <> hid or not public._asg_scope_ok(c, a.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if jsonb_typeof(p -> 'questions') = 'array' and exists (select 1 from public.assignment_submissions s where s.assignment_id = a.id) then
      return jsonb_build_object('ok', false, 'error', 'has_submissions');
    end if;
    update public.assignments set title = v_title, description = left(coalesce(p ->> 'description', ''), 1000), due_at = v_due,
           student_ids = sids, settings = v_set, updated_at = now() where id = a.id returning * into a;
  else
    v_new := true;
    insert into public.assignments (center_id, halaqa_id, title, description, due_at, status, student_ids, settings, created_by, created_by_name)
    values (c.center_id::text, hid, v_title, left(coalesce(p ->> 'description', ''), 1000), v_due, 'draft', sids, v_set, c.id::text, coalesce(c.full_name, c.username))
    returning * into a;
  end if;

  if jsonb_typeof(p -> 'questions') = 'array' then
    if jsonb_array_length(p -> 'questions') > 40 then raise exception 'asg_save:%', '{"ok":false,"error":"too_many"}' using errcode = 'P0001'; end if;
    delete from public.assignment_questions where assignment_id = a.id;
    for q in select * from jsonb_array_elements(p -> 'questions') loop
      i := i + 1; qt := q ->> 'qtype';
      if qt not in ('mcq', 'truefalse', 'text') or length(btrim(coalesce(q ->> 'prompt', ''))) < 2 then
        raise exception 'asg_save:%', '{"ok":false,"error":"bad_question"}' using errcode = 'P0001';
      end if;
      pts := case when (q ->> 'points') ~ '^[0-9]+(\.[0-9]+)?$' then least((q ->> 'points')::numeric, 100) else 1 end;
      opts := '[]'::jsonb; cor := null;
      if qt = 'mcq' then
        select coalesce(jsonb_agg(left(btrim(x), 200)), '[]'::jsonb) into opts from jsonb_array_elements_text(coalesce(q -> 'options', '[]'::jsonb)) x where btrim(x) <> '';
        if jsonb_array_length(opts) < 2 or jsonb_array_length(opts) > 6 or (q ->> 'correct') !~ '^[0-9]+$'
           or (q ->> 'correct')::int >= jsonb_array_length(opts) then
          raise exception 'asg_save:%', '{"ok":false,"error":"bad_question"}' using errcode = 'P0001';
        end if;
        cor := to_jsonb((q ->> 'correct')::int);
      elsif qt = 'truefalse' then
        if (q ->> 'correct') not in ('true', 'false') then raise exception 'asg_save:%', '{"ok":false,"error":"bad_question"}' using errcode = 'P0001'; end if;
        cor := to_jsonb((q ->> 'correct')::boolean);
      elsif nullif(btrim(coalesce(q ->> 'correct', '')), '') is not null then
        cor := to_jsonb(left(btrim(q ->> 'correct'), 500));
      end if;
      insert into public.assignment_questions (assignment_id, position, qtype, prompt, options, correct, points)
      values (a.id, i, qt, left(btrim(q ->> 'prompt'), 500), opts, cor, pts);
    end loop;
  end if;
  if v_new and p ->> 'status' = 'published' and i > 0 then update public.assignments set status = 'published' where id = a.id; end if;
  return jsonb_build_object('ok', true, 'id', a.id, 'created', v_new);
exception when sqlstate 'P0001' then
  if sqlerrm like 'asg_save:%' then return substr(sqlerrm, 10)::jsonb; end if;
  raise;
end $$;

create or replace function public.asg_set_status(p_token text, p_id text, p_status text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; a public.assignments;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into a from public.assignments where id::text = p_id;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._asg_scope_ok(c, a.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_status not in ('draft', 'published', 'closed') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  if p_status = 'published' and not exists (select 1 from public.assignment_questions q where q.assignment_id = a.id) then
    return jsonb_build_object('ok', false, 'error', 'no_questions');
  end if;
  if p_status = 'draft' and exists (select 1 from public.assignment_submissions s where s.assignment_id = a.id) then
    return jsonb_build_object('ok', false, 'error', 'has_submissions');
  end if;
  update public.assignments set status = p_status, updated_at = now() where id = a.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.asg_delete(p_token text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; a public.assignments;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into a from public.assignments where id::text = p_id;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._asg_scope_ok(c, a.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  delete from public.assignments where id = a.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.asg_list(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; st public.students; rows jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if c.role::text = 'student' then
    st := public._app_student_of(c);
    if st.id is null then return jsonb_build_object('ok', true, 'rows', '[]'::jsonb); end if;
    select coalesce(jsonb_agg((public._asg_row_json(a) - 'student_ids') || jsonb_build_object(
             'my', (select jsonb_build_object('submitted', true, 'score', s.score, 'max', s.max_score, 'pending_manual', s.pending_manual, 'late', s.late, 'submitted_at', s.submitted_at)
                      from public.assignment_submissions s where s.assignment_id = a.id and s.student_id = st.id::text))
             order by a.due_at nulls last, a.created_at desc), '[]'::jsonb) into rows
      from public.assignments a where a.status <> 'draft' and public._asg_student_ok(c, a, st);
    return jsonb_build_object('ok', true, 'rows', rows);
  end if;
  if c.role::text not in ('teacher', 'supervisor', 'employee') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select coalesce(jsonb_agg(public._asg_row_json(a) || jsonb_build_object(
           'targets', case when cardinality(a.student_ids) > 0 then cardinality(a.student_ids)
                           else (select count(*) from public.students s where s.halaqa_id::text = a.halaqa_id) end,
           'submitted', (select count(*) from public.assignment_submissions s where s.assignment_id = a.id),
           'pending', (select count(*) from public.assignment_submissions s where s.assignment_id = a.id and s.pending_manual),
           'avg_pct', (select round(avg(100 * s.score / nullif(s.max_score, 0)), 1) from public.assignment_submissions s where s.assignment_id = a.id))
           order by a.created_at desc), '[]'::jsonb) into rows
    from public.assignments a where a.center_id = c.center_id::text and public._asg_scope_ok(c, a.halaqa_id);
  return jsonb_build_object('ok', true, 'rows', rows);
end $$;

create or replace function public.asg_get(p_token text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; a public.assignments; st public.students; sub public.assignment_submissions; qs jsonb; reveal boolean;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into a from public.assignments where id::text = p_id;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if c.role::text = 'student' then
    st := public._app_student_of(c);
    if a.status = 'draft' or not public._asg_student_ok(c, a, st) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    select * into sub from public.assignment_submissions s where s.assignment_id = a.id and s.student_id = st.id::text;
    reveal := coalesce((a.settings ->> 'reveal_answers')::boolean, true) and sub.id is not null;
    select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'position', q.position, 'qtype', q.qtype, 'prompt', q.prompt, 'options', q.options, 'points', q.points)
             || case when reveal and q.qtype <> 'text' then jsonb_build_object('correct', q.correct) else '{}'::jsonb end order by q.position), '[]'::jsonb)
      into qs from public.assignment_questions q where q.assignment_id = a.id;
    return jsonb_build_object('ok', true, 'assignment', public._asg_row_json(a) - 'student_ids', 'questions', qs,
      'submission', case when sub.id is null then null else jsonb_build_object('answers', sub.answers, 'grades', sub.grades, 'score', sub.score,
         'max', sub.max_score, 'pending_manual', sub.pending_manual, 'feedback', sub.feedback, 'late', sub.late, 'submitted_at', sub.submitted_at) end);
  end if;
  if not public._asg_scope_ok(c, a.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'position', q.position, 'qtype', q.qtype, 'prompt', q.prompt, 'options', q.options,
           'correct', q.correct, 'points', q.points) order by q.position), '[]'::jsonb) into qs from public.assignment_questions q where q.assignment_id = a.id;
  return jsonb_build_object('ok', true, 'assignment', public._asg_row_json(a), 'questions', qs,
    'has_submissions', exists (select 1 from public.assignment_submissions s where s.assignment_id = a.id));
end $$;

create or replace function public.asg_submit(p_token text, p_id text, p_answers jsonb, p_op text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; a public.assignments; st public.students; q public.assignment_questions; v_op uuid; dup jsonb; v_late boolean := false;
  grades jsonb := '{}'::jsonb; score numeric := 0; mx numeric := 0; pend boolean := false; ans text; ok boolean; clean jsonb := '{}'::jsonb;
  res jsonb := '[]'::jsonb; reveal boolean; out jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if c.role::text <> 'student' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  begin v_op := nullif(p_op, '')::uuid; exception when others then v_op := null; end;
  dup := public._comp_op_get(v_op); if dup is not null then return dup; end if;
  st := public._app_student_of(c);
  select * into a from public.assignments where id::text = p_id;
  if a.id is null or a.status = 'draft' or not public._asg_student_ok(c, a, st) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if a.status = 'closed' then return jsonb_build_object('ok', false, 'error', 'closed'); end if;
  if exists (select 1 from public.assignment_submissions s where s.assignment_id = a.id and s.student_id = st.id::text) then
    return jsonb_build_object('ok', false, 'error', 'already_submitted');
  end if;
  if a.due_at is not null and now() > a.due_at then
    if coalesce((a.settings ->> 'allow_late')::boolean, false) then v_late := true; else return jsonb_build_object('ok', false, 'error', 'past_due'); end if;
  end if;
  if jsonb_typeof(p_answers) <> 'object' then return jsonb_build_object('ok', false, 'error', 'bad_answers'); end if;
  reveal := coalesce((a.settings ->> 'reveal_answers')::boolean, true);
  for q in select * from public.assignment_questions where assignment_id = a.id order by position loop
    mx := mx + q.points; ans := p_answers ->> q.id::text; ok := null;
    if q.qtype = 'text' then
      pend := true;
      if ans is not null then clean := clean || jsonb_build_object(q.id::text, left(ans, 2000)); end if;
    elsif ans is not null then
      if q.qtype = 'mcq' and ans ~ '^[0-9]+$' then
        clean := clean || jsonb_build_object(q.id::text, ans::int); ok := (ans::int = (q.correct #>> '{}')::int);
      elsif q.qtype = 'truefalse' and ans in ('true', 'false') then
        clean := clean || jsonb_build_object(q.id::text, ans::boolean); ok := (ans::boolean = (q.correct #>> '{}')::boolean);
      else ok := false; end if;
      if ok then score := score + q.points; grades := grades || jsonb_build_object(q.id::text, q.points);
      else grades := grades || jsonb_build_object(q.id::text, 0); end if;
    elsif q.qtype <> 'text' then grades := grades || jsonb_build_object(q.id::text, 0); end if;
    if reveal and q.qtype <> 'text' then res := res || jsonb_build_object('id', q.id, 'ok', ok, 'correct', q.correct); end if;
  end loop;
  insert into public.assignment_submissions (assignment_id, student_id, answers, grades, score, max_score, pending_manual, late)
  values (a.id, st.id::text, clean, grades, score, mx, pend, v_late);
  out := jsonb_build_object('ok', true, 'score', score, 'max', mx, 'pending_manual', pend, 'late', v_late, 'review', res);
  perform public._comp_op_put(v_op, out);
  return out;
exception when unique_violation then
  return jsonb_build_object('ok', false, 'error', 'already_submitted');
end $$;

create or replace function public.asg_results(p_token text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; a public.assignments; rows jsonb; stats jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into a from public.assignments where id::text = p_id;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._asg_scope_ok(c, a.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'name', s.name, 'submitted', sub.id is not null,
           'score', sub.score, 'max', sub.max_score, 'pct', round(100 * sub.score / nullif(sub.max_score, 0), 1),
           'late', sub.late, 'pending_manual', sub.pending_manual, 'submitted_at', sub.submitted_at) order by s.name), '[]'::jsonb) into rows
    from public.students s
    left join public.assignment_submissions sub on sub.assignment_id = a.id and sub.student_id = s.id::text
   where s.halaqa_id::text = a.halaqa_id and (cardinality(a.student_ids) = 0 or s.id::text = any (a.student_ids));
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'position', q.position, 'prompt', q.prompt, 'qtype', q.qtype,
           'answered', (select count(*) from public.assignment_submissions sb where sb.assignment_id = a.id and sb.answers ? q.id::text),
           'correct_count', (select count(*) from public.assignment_submissions sb where sb.assignment_id = a.id and q.qtype <> 'text'
                               and coalesce((sb.grades ->> q.id::text)::numeric, 0) >= q.points and q.points > 0)) order by q.position), '[]'::jsonb) into stats
    from public.assignment_questions q where q.assignment_id = a.id;
  return jsonb_build_object('ok', true, 'assignment', public._asg_row_json(a), 'rows', rows, 'questions', stats);
end $$;

create or replace function public.asg_submission(p_token text, p_id text, p_student text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; a public.assignments; sub public.assignment_submissions; qs jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into a from public.assignments where id::text = p_id;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._asg_scope_ok(c, a.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into sub from public.assignment_submissions s where s.assignment_id = a.id and s.student_id = p_student;
  if sub.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'position', q.position, 'qtype', q.qtype, 'prompt', q.prompt, 'options', q.options,
           'correct', q.correct, 'points', q.points, 'answer', sub.answers -> q.id::text, 'grade', sub.grades -> q.id::text) order by q.position), '[]'::jsonb)
    into qs from public.assignment_questions q where q.assignment_id = a.id;
  return jsonb_build_object('ok', true, 'student_id', p_student, 'name', (select s.name from public.students s where s.id::text = p_student),
    'score', sub.score, 'max', sub.max_score, 'pending_manual', sub.pending_manual, 'feedback', sub.feedback, 'late', sub.late,
    'submitted_at', sub.submitted_at, 'questions', qs);
end $$;

create or replace function public.asg_grade(p_token text, p_id text, p_student text, p_grades jsonb, p_feedback text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; a public.assignments; sub public.assignment_submissions; q public.assignment_questions; g jsonb; v numeric; tot numeric := 0; pend boolean := false;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into a from public.assignments where id::text = p_id;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not public._asg_scope_ok(c, a.halaqa_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into sub from public.assignment_submissions s where s.assignment_id = a.id and s.student_id = p_student;
  if sub.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  g := sub.grades;
  for q in select * from public.assignment_questions where assignment_id = a.id and qtype = 'text' loop
    if jsonb_typeof(p_grades) = 'object' and (p_grades ->> q.id::text) is not null then
      if (p_grades ->> q.id::text) !~ '^[0-9]+(\.[0-9]+)?$' or (p_grades ->> q.id::text)::numeric > q.points then
        return jsonb_build_object('ok', false, 'error', 'bad_points', 'question', q.id);
      end if;
      g := g || jsonb_build_object(q.id::text, (p_grades ->> q.id::text)::numeric);
    end if;
    if g -> q.id::text is null then pend := true; end if;
  end loop;
  select coalesce(sum((e.value)::numeric), 0) into tot from jsonb_each_text(g) e;
  update public.assignment_submissions set grades = g, score = tot, pending_manual = pend, feedback = coalesce(left(p_feedback, 1000), feedback),
         graded_at = now(), graded_by = c.id::text where id = sub.id;
  return jsonb_build_object('ok', true, 'score', tot, 'pending_manual', pend);
end $$;

notify pgrst, 'reload schema';
select 'تم الجزء 5 من 6 بنجاح ✅' as status;
