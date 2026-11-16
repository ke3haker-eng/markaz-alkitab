-- =====================================================================
--  نظام الرضوان — الإصدار 2.1.0
--  الخطوة 3: «دوري فرسان القرآن» + الواجبات + محادثة الطالب والمعلم
--  شغّله في Supabase ← SQL Editor بعد 01_security_setup.sql. آمن ويمكن تكراره.
--  لا يغيّر أي جدول قديم. الجداول الجديدة مغلقة عن الوصول المباشر؛ كل شيء عبر
--  دوال سيرفر تتحقق من الرمز والدور والمركز والحلقة في كل عملية.
-- =====================================================================
do $$ begin
  if to_regprocedure('public._app_auth(text)') is null then
    raise exception 'شغّل 01_security_setup.sql أولاً';
  end if;
end $$;

-- صلاحية جديدة للموظفين: competitions (المسابقات والواجبات)
create or replace function public._app_clean_perms(p jsonb) returns jsonb
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare k text; out jsonb := '{}'::jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return out; end if;
  foreach k in array array['students','records','halaqat','teachers','reports','messages','backup','competitions'] loop
    if (p ->> k) in ('true','false') then out := out || jsonb_build_object(k, (p ->> k)::boolean); end if;
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- 1) الجداول
-- ---------------------------------------------------------------------
create table if not exists public.competitions (
  id uuid primary key default gen_random_uuid(),
  center_id text not null,
  name text not null,
  description text not null default '',
  start_date date not null,
  end_date date not null,
  status text not null default 'draft' check (status in ('draft','active','paused','ended')),
  halaqa_ids text[] not null default '{}',
  settings jsonb not null default '{}'::jsonb,
  created_by text, created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  ended_at timestamptz,
  constraint competitions_dates_ok check (end_date >= start_date)
);
create index if not exists competitions_center_idx on public.competitions (center_id, status);

create table if not exists public.competition_participants (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  student_id text not null,
  halaqa_id text,
  level text not null default 'متوسط',
  target_note text,
  status text not null default 'active',
  joined_at timestamptz not null default now(),
  unique (competition_id, student_id)
);
create index if not exists comp_part_student_idx on public.competition_participants (student_id);

create table if not exists public.competition_categories (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  key text not null default 'custom',
  name text not null,
  weekly_max_points numeric(7,2) not null default 10 check (weekly_max_points >= 0),
  sort_order int not null default 0,
  kind text not null default 'core' check (kind in ('core','bonus')),
  is_active boolean not null default true,
  unique (competition_id, name)
);

create table if not exists public.competition_scores (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  student_id text not null,
  category_id uuid not null references public.competition_categories(id) on delete restrict,
  points numeric(7,2) not null,
  entry_type text not null default 'eval' check (entry_type in ('eval','adjust','bonus')),
  week_number int not null,
  evaluation_date date not null,
  reason text not null default '',
  ver int not null default 1,
  voided boolean not null default false,
  void_reason text,
  post_close boolean not null default false,
  created_by text, created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- يمنع تكرار تقييم الطالب نفسه في المجال نفسه واليوم نفسه دون قصد
create unique index if not exists competition_scores_eval_uq
  on public.competition_scores (competition_id, student_id, category_id, evaluation_date)
  where entry_type = 'eval' and not voided;
create index if not exists competition_scores_cs_idx on public.competition_scores (competition_id, student_id);

create table if not exists public.competition_score_audit (
  id bigint generated always as identity primary key,
  score_id uuid,
  competition_id uuid references public.competitions(id) on delete cascade,
  student_id text, category_name text,
  old_points numeric, new_points numeric,
  action_type text not null, reason text,
  performed_by text, performed_by_name text,
  created_at timestamptz not null default now()
);
create index if not exists comp_audit_idx on public.competition_score_audit (competition_id, id desc);

create table if not exists public.app_ops (
  op_id uuid primary key,
  result jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  center_id text not null,
  halaqa_id text not null,
  title text not null,
  description text not null default '',
  due_at timestamptz,
  status text not null default 'draft' check (status in ('draft','published','closed')),
  student_ids text[] not null default '{}',
  settings jsonb not null default '{}'::jsonb,
  created_by text, created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists assignments_center_idx on public.assignments (center_id, halaqa_id, status);

create table if not exists public.assignment_questions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  position int not null default 0,
  qtype text not null check (qtype in ('mcq','truefalse','text')),
  prompt text not null,
  options jsonb not null default '[]'::jsonb,
  correct jsonb,
  points numeric(6,2) not null default 1 check (points >= 0)
);
create index if not exists asg_q_idx on public.assignment_questions (assignment_id, position);

create table if not exists public.assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  student_id text not null,
  answers jsonb not null default '{}'::jsonb,
  grades jsonb not null default '{}'::jsonb,
  score numeric(7,2) not null default 0,
  max_score numeric(7,2) not null default 0,
  pending_manual boolean not null default false,
  feedback text,
  late boolean not null default false,
  submitted_at timestamptz not null default now(),
  graded_at timestamptz, graded_by text,
  unique (assignment_id, student_id)
);

create table if not exists public.student_chat (
  id bigint generated always as identity primary key,
  center_id text not null,
  halaqa_id text,
  student_id text not null,
  sender_role text not null,
  sender_id text, sender_name text,
  body text not null check (length(body) between 1 and 1500),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists student_chat_thread_idx on public.student_chat (student_id, id);
create index if not exists student_chat_center_idx on public.student_chat (center_id, halaqa_id);

-- مغلقة عن الوصول المباشر
do $$
declare t text;
begin
  foreach t in array array['competitions','competition_participants','competition_categories','competition_scores',
                           'competition_score_audit','app_ops','assignments','assignment_questions',
                           'assignment_submissions','student_chat'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2) دوال مساعدة داخلية
-- ---------------------------------------------------------------------
create or replace function public._comp_today(p_settings jsonb) returns date
language plpgsql stable set search_path = public, extensions, pg_temp as $$
begin
  return (now() at time zone coalesce(nullif(p_settings ->> 'tz', ''), 'Asia/Gaza'))::date;
exception when others then
  return (now() at time zone 'Asia/Gaza')::date;
end $$;

create or replace function public._comp_state(c public.competitions) returns text
language sql stable set search_path = public, extensions, pg_temp as $$
  select case
    when c.status = 'draft' then 'draft'
    when c.status = 'ended' or public._comp_today(c.settings) > c.end_date then 'ended'
    when c.status = 'paused' then 'paused'
    when public._comp_today(c.settings) < c.start_date then 'upcoming'
    else 'running' end
$$;

create or replace function public._comp_week(c public.competitions, d date) returns int
language sql immutable set search_path = public, extensions, pg_temp as $$
  select ((d - c.start_date) / 7) + 1
$$;
create or replace function public._comp_total_weeks(c public.competitions) returns int
language sql immutable set search_path = public, extensions, pg_temp as $$
  select greatest(1, ceil(((c.end_date - c.start_date) + 1) / 7.0)::int)
$$;
create or replace function public._comp_elapsed_weeks(c public.competitions) returns int
language sql stable set search_path = public, extensions, pg_temp as $$
  select case when public._comp_today(c.settings) < c.start_date then 0
    else least(public._comp_total_weeks(c),
               greatest(1, ceil(((least(public._comp_today(c.settings), c.end_date) - c.start_date) + 1) / 7.0)::int)) end
$$;

create or replace function public._comp_staff_ok(c public.users) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select c.id is not null and (
    c.role::text = 'supervisor'
    or (c.role::text = 'employee' and public._app_can(c, 'competitions'))
    or (c.role::text = 'teacher' and c.halaqa_id is not null))
$$;

create or replace function public._comp_halaqa_in_center(c public.users, hid text) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select exists (select 1 from public.halaqat h where h.id::text = hid and h.center_id::text = c.center_id::text)
$$;

-- عرض المسابقة (للموظفين): المشرف/الموظف: مسابقات المركز، المعلم: ما يضم حلقته
create or replace function public._comp_view_ok(c public.users, k public.competitions) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select public._comp_staff_ok(c) and k.center_id = c.center_id::text
     and (c.role::text <> 'teacher' or c.halaqa_id::text = any (k.halaqa_ids))
$$;
-- إدارة إعدادات المسابقة وحالتها: المشرف/الموظف، أو المعلم إذا كانت لحلقته وحدها
create or replace function public._comp_manage_ok(c public.users, k public.competitions) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select public._comp_staff_ok(c) and k.center_id = c.center_id::text
     and (c.role::text <> 'teacher' or k.halaqa_ids = array[c.halaqa_id::text])
$$;
-- تقييم طالب: من يدير المسابقة، أو معلم حلقة الطالب
create or replace function public._comp_score_ok(c public.users, k public.competitions, p_halaqa text) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select public._comp_manage_ok(c, k)
      or (c.role::text = 'teacher' and k.center_id = c.center_id::text
          and c.halaqa_id::text = p_halaqa and p_halaqa = any (k.halaqa_ids))
$$;

create or replace function public._comp_default_cats() returns jsonb
language sql immutable as $$
  select '[
    {"key":"hifz","name":"التسميع والحفظ الجديد","weekly_max_points":25,"kind":"core"},
    {"key":"itqan","name":"إتقان الحفظ وقلة الأخطاء","weekly_max_points":15,"kind":"core"},
    {"key":"review","name":"المراجعة والتثبيت","weekly_max_points":10,"kind":"core"},
    {"key":"attendance","name":"الحضور والالتزام","weekly_max_points":10,"kind":"core"},
    {"key":"early","name":"الحضور المبكر","weekly_max_points":5,"kind":"core"},
    {"key":"prayer","name":"المحافظة على الصلاة","weekly_max_points":15,"kind":"core"},
    {"key":"adab","name":"الأدب وحسن التعامل","weekly_max_points":10,"kind":"core"},
    {"key":"participation","name":"المشاركة والمبادرة","weekly_max_points":5,"kind":"core"},
    {"key":"azkar","name":"الأذكار والورد اليومي","weekly_max_points":5,"kind":"core"},
    {"key":"bonus","name":"مكافآت إضافية","weekly_max_points":10,"kind":"bonus"}
  ]'::jsonb
$$;

create or replace function public._comp_default_settings() returns jsonb
language sql immutable as $$
  select '{"show_ranking":true,"show_scores":true,"levels":true,"bonus_weekly_cap":10,"tz":"Asia/Gaza",
           "bonus_items":[{"name":"صيام تطوع اختياري","points":2},{"name":"مساعدة زميل في الحفظ","points":2},
                          {"name":"تسميع إضافي متقن","points":2},{"name":"تقديم فائدة قرآنية صحيحة","points":2},
                          {"name":"مبادرة خيرية أو خدمة الحلقة","points":2}]}'::jsonb
$$;

create or replace function public._comp_clean_settings(p jsonb) returns jsonb
language plpgsql stable set search_path = public, extensions, pg_temp as $$
declare d jsonb := public._comp_default_settings(); o jsonb; items jsonb := '[]'::jsonb; it jsonb; tz text;
begin
  o := d;
  if p is null or jsonb_typeof(p) <> 'object' then return o; end if;
  if (p ->> 'show_ranking') in ('true','false') then o := o || jsonb_build_object('show_ranking', (p ->> 'show_ranking')::boolean); end if;
  if (p ->> 'show_scores')  in ('true','false') then o := o || jsonb_build_object('show_scores',  (p ->> 'show_scores')::boolean); end if;
  if (p ->> 'levels')       in ('true','false') then o := o || jsonb_build_object('levels',       (p ->> 'levels')::boolean); end if;
  if (p ->> 'bonus_weekly_cap') ~ '^[0-9]+(\.[0-9]+)?$' then
    o := o || jsonb_build_object('bonus_weekly_cap', least((p ->> 'bonus_weekly_cap')::numeric, 100));
  end if;
  tz := nullif(p ->> 'tz', '');
  if tz is not null then
    begin perform now() at time zone tz; o := o || jsonb_build_object('tz', tz);
    exception when others then null; end;
  end if;
  if jsonb_typeof(p -> 'bonus_items') = 'array' then
    for it in select * from jsonb_array_elements(p -> 'bonus_items') loop
      if length(btrim(coalesce(it ->> 'name', ''))) > 0 and (it ->> 'points') ~ '^[0-9]+(\.[0-9]+)?$' then
        items := items || jsonb_build_object('name', left(btrim(it ->> 'name'), 60), 'points', least((it ->> 'points')::numeric, 20));
      end if;
    end loop;
    o := o || jsonb_build_object('bonus_items', items);
  end if;
  return o;
end $$;

-- منع تكرار العملية نفسها (نقر مزدوج / إعادة اتصال)
create or replace function public._comp_op_get(p_op uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r jsonb;
begin
  if p_op is null then return null; end if;
  select result into r from public.app_ops where op_id = p_op;
  if found then return coalesce(r, jsonb_build_object('ok', true)) || jsonb_build_object('duplicate', true); end if;
  return null;
end $$;
create or replace function public._comp_op_put(p_op uuid, p_res jsonb) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_op is null then return; end if;
  insert into public.app_ops (op_id, result) values (p_op, p_res) on conflict (op_id) do nothing;
  if random() < 0.02 then delete from public.app_ops where created_at < now() - interval '7 days'; end if;
end $$;

create or replace function public._comp_audit(k public.competitions, c public.users, p_score uuid, p_student text, p_cat text,
                                              p_old numeric, p_new numeric, p_action text, p_reason text) returns void
language sql security definer set search_path = public, extensions, pg_temp as $$
  insert into public.competition_score_audit (score_id, competition_id, student_id, category_name, old_points, new_points,
                                              action_type, reason, performed_by, performed_by_name)
  values (p_score, k.id, p_student, p_cat, p_old, p_new, p_action, p_reason, c.id::text, coalesce(c.full_name, c.username))
$$;

create or replace function public._app_student_of(c public.users) returns public.students
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select s.* from public.students s where s.user_id::text = c.id::text order by s.id limit 1
$$;

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
