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

notify pgrst, 'reload schema';
select 'تم الجزء 1 من 6 بنجاح ✅' as status;
