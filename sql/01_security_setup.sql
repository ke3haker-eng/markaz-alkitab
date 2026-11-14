-- =====================================================================
--  نظام الرضوان — الإصدار 2.0
--  الخطوة 1 من 2: إعداد طبقة الحماية (آمنة — لا تكسر النسخة القديمة)
--  الشغل: Supabase ← SQL Editor ← New query ← الصق الملف كاملاً ← Run
--  يمكن تشغيله أكثر من مرة بلا ضرر.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1) أعمدة جديدة + السماح بدور "موظف" وحالة "معطّل"
-- ---------------------------------------------------------------------
alter table public.users add column if not exists perms jsonb not null default '{}'::jsonb;
alter table public.users add column if not exists last_login_at timestamptz;

do $$
declare r record; t oid;
begin
  -- نحذف قيود CHECK القديمة على role / status حتى يُقبل الدور والحالة الجديدان
  for r in
    select c.conname from pg_constraint c
    where c.conrelid = 'public.users'::regclass and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ~* '\m(role|status)\M'
  loop
    execute format('alter table public.users drop constraint %I', r.conname);
  end loop;

  -- إن كان role من نوع ENUM نضيف القيمة الجديدة
  select a.atttypid into t from pg_attribute a
   where a.attrelid = 'public.users'::regclass and a.attname = 'role' and not a.attisdropped;
  if exists (select 1 from pg_type where oid = t and typtype = 'e') then
    execute format('alter type %s add value if not exists %L', t::regtype, 'employee');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2) جداول الجلسات ومحاولات الدخول وسجل التعديلات (لا وصول مباشر لها)
-- ---------------------------------------------------------------------
create table if not exists public.app_sessions (
  token_hash text primary key,
  user_id    text not null,
  created_at timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists app_sessions_user_idx on public.app_sessions (user_id);

create table if not exists public.app_login_attempts (
  uname        text primary key,
  fails        int  not null default 0,
  first_fail   timestamptz,
  locked_until timestamptz,
  lock_count   int  not null default 0,
  updated_at   timestamptz not null default now()
);

create table if not exists public.audit_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  center_id   text,
  actor_id    text,
  actor_name  text,
  actor_role  text,
  action      text not null,
  entity      text,
  entity_id   text,
  entity_name text,
  details     jsonb not null default '{}'::jsonb
);
create index if not exists audit_log_center_at on public.audit_log (center_id, at desc);

alter table public.app_sessions       enable row level security;
alter table public.app_login_attempts enable row level security;
alter table public.audit_log          enable row level security;

-- ---------------------------------------------------------------------
-- 3) دوال مساعدة داخلية (لا تُستدعى من المتصفح)
-- ---------------------------------------------------------------------
create or replace function public._app_pw_ok(p_pw text, p_hash text) returns boolean
language plpgsql stable set search_path = public, extensions, pg_temp as $$
begin
  if p_hash is null or p_pw is null then return false; end if;
  if p_hash like '$2%' then
    return crypt(p_pw, p_hash) = p_hash;                       -- bcrypt (الجديد)
  elsif p_hash ~ '^[0-9a-f]{64}$' then
    return encode(digest(convert_to(p_pw, 'UTF8'), 'sha256'), 'hex') = p_hash;  -- SHA-256 القديم
  end if;
  return false;
end $$;

create or replace function public._app_hash(p_pw text) returns text
language sql volatile set search_path = public, extensions, pg_temp as $$
  select crypt(p_pw, gen_salt('bf', 10))
$$;

create or replace function public._app_user_json(u public.users) returns jsonb
language sql stable set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object(
    'id', u.id, 'role', u.role::text, 'username', u.username, 'full_name', u.full_name,
    'center_id', u.center_id, 'halaqa_id', u.halaqa_id, 'status', u.status,
    'perms', coalesce(u.perms, '{}'::jsonb))
$$;

create or replace function public._app_clean_perms(p jsonb) returns jsonb
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare k text; out jsonb := '{}'::jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return out; end if;
  foreach k in array array['students','records','halaqat','teachers','reports','messages','backup'] loop
    if (p ->> k) in ('true','false') then out := out || jsonb_build_object(k, (p ->> k)::boolean); end if;
  end loop;
  return out;
end $$;

create or replace function public._app_auth(p_token text) returns public.users
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_u public.users; v_s public.app_sessions; v_h text;
begin
  if p_token is null or length(p_token) < 20 then return null; end if;
  v_h := encode(digest(p_token, 'sha256'), 'hex');
  select * into v_s from public.app_sessions where token_hash = v_h and expires_at > now();
  if not found then return null; end if;
  select * into v_u from public.users where id::text = v_s.user_id;
  if not found then
    delete from public.app_sessions where token_hash = v_h;
    return null;
  end if;
  if coalesce(v_u.status, 'active') in ('disabled', 'rejected') then return null; end if;
  if v_s.last_seen < now() - interval '1 hour' then
    update public.app_sessions set last_seen = now(), expires_at = now() + interval '90 days'
     where token_hash = v_h;
  end if;
  return v_u;
end $$;

-- هل يملك المستخدم صلاحية معينة؟ (المشرف والمالك: دائماً نعم)
create or replace function public._app_can(u public.users, p_perm text) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select case u.role::text
    when 'masool'     then true
    when 'supervisor' then true
    when 'employee'   then coalesce((u.perms ->> p_perm)::boolean, false)
    else false end
$$;

-- هل يحق للمستخدم c إدارة حساب t (تغيير بيانات الدخول / الحذف)؟
create or replace function public._app_can_manage(c public.users, t public.users) returns boolean
language plpgsql stable set search_path = public, extensions, pg_temp as $$
begin
  if c.id = t.id then return true; end if;
  if c.role::text = 'masool' then return t.role::text <> 'masool'; end if;
  if c.center_id::text is distinct from t.center_id::text then return false; end if;
  if c.role::text = 'supervisor' then return t.role::text in ('teacher','student','employee'); end if;
  if c.role::text = 'employee' then
    return (t.role::text = 'teacher' and public._app_can(c, 'halaqat'))
        or (t.role::text = 'student' and public._app_can(c, 'students'));
  end if;
  if c.role::text = 'teacher' then
    -- المعلم يدير طلاب حلقته فقط (لا طالباً مربوطاً بحلقة أخرى)
    return t.role::text = 'student' and c.halaqa_id is not null
       and not exists (select 1 from public.students s
                        where s.user_id::text = t.id::text
                          and s.halaqa_id::text is distinct from c.halaqa_id::text);
  end if;
  return false;
end $$;

-- ---------------------------------------------------------------------
-- 4) الدخول والجلسات
-- ---------------------------------------------------------------------
create or replace function public.app_login(p_username text, p_password text, p_kind text default 'staff')
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_name text := btrim(coalesce(p_username, ''));
  v_key  text := lower(btrim(coalesce(p_username, '')));
  v_att  public.app_login_attempts;
  v_u    public.users;
  v_ok   public.users;
  v_roles text[];
  v_token text;
  v_lock_min int;
begin
  if v_key = '' or coalesce(p_password, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  v_roles := case when p_kind = 'student' then array['student']
                  else array['masool','supervisor','employee','teacher'] end;

  -- تنظيف دوري خفيف
  if random() < 0.05 then
    delete from public.app_sessions where expires_at < now();
    delete from public.app_login_attempts where updated_at < now() - interval '1 day' and (locked_until is null or locked_until < now());
  end if;

  -- هل الحساب مقفل مؤقتاً؟
  select * into v_att from public.app_login_attempts where uname = v_key;
  if found and v_att.locked_until is not null and v_att.locked_until > now() then
    return jsonb_build_object('ok', false, 'error', 'locked',
      'retry_after', ceil(extract(epoch from (v_att.locked_until - now())))::int);
  end if;

  -- نبحث بين كل الحسابات بهذا الاسم (قد يتكرر الاسم في مراكز مختلفة)
  for v_u in select * from public.users where username = v_name and role::text = any (v_roles) loop
    if public._app_pw_ok(p_password, v_u.password_hash) then v_ok := v_u; exit; end if;
  end loop;

  if v_ok.id is null then
    insert into public.app_login_attempts (uname, fails, first_fail, updated_at)
    values (v_key, 1, now(), now())
    on conflict (uname) do update set
      fails = case when public.app_login_attempts.first_fail is null
                     or public.app_login_attempts.first_fail < now() - interval '15 minutes'
                   then 1 else public.app_login_attempts.fails + 1 end,
      first_fail = case when public.app_login_attempts.first_fail is null
                          or public.app_login_attempts.first_fail < now() - interval '15 minutes'
                        then now() else public.app_login_attempts.first_fail end,
      updated_at = now();
    select * into v_att from public.app_login_attempts where uname = v_key;
    if v_att.fails >= 5 then
      v_lock_min := least((10 * (2 ^ least(v_att.lock_count, 3)))::int, 120);
      update public.app_login_attempts
         set locked_until = now() + make_interval(mins => v_lock_min),
             lock_count = lock_count + 1, fails = 0, first_fail = null, updated_at = now()
       where uname = v_key;
      return jsonb_build_object('ok', false, 'error', 'locked', 'retry_after', v_lock_min * 60);
    end if;
    return jsonb_build_object('ok', false, 'error', 'invalid', 'remaining', 5 - v_att.fails);
  end if;

  -- كلمة المرور صحيحة
  delete from public.app_login_attempts where uname = v_key;
  if v_ok.role::text <> 'student' and coalesce(v_ok.status, 'active') = 'pending' then
    return jsonb_build_object('ok', false, 'error', 'pending');
  end if;
  if coalesce(v_ok.status, 'active') in ('disabled', 'rejected') then
    return jsonb_build_object('ok', false, 'error', 'disabled');
  end if;

  -- ترقية الهاش القديم (SHA-256) إلى bcrypt بشكل تلقائي
  if v_ok.password_hash !~ '^\$2' then
    update public.users set password_hash = public._app_hash(p_password) where id = v_ok.id;
  end if;
  update public.users set last_login_at = now() where id = v_ok.id;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.app_sessions (token_hash, user_id, expires_at)
  values (encode(digest(v_token, 'sha256'), 'hex'), v_ok.id::text, now() + interval '90 days');

  return jsonb_build_object('ok', true, 'token', v_token, 'user', public._app_user_json(v_ok));
end $$;

create or replace function public.app_session_check(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_u public.users;
begin
  v_u := public._app_auth(p_token);
  if v_u.id is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'user', public._app_user_json(v_u));
end $$;

create or replace function public.app_logout(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_token is not null and length(p_token) >= 20 then
    delete from public.app_sessions where token_hash = encode(digest(p_token, 'sha256'), 'hex');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5) التسجيل الذاتي (إنشاء مركز / تسجيل معلم) — ذرّي بلا بيانات يتيمة
-- ---------------------------------------------------------------------
create or replace function public.app_register_center(p_center_name text, p_manager_name text, p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_cname text := btrim(coalesce(p_center_name, ''));
  v_mname text := btrim(coalesce(p_manager_name, ''));
  v_uname text := btrim(coalesce(p_username, ''));
  v_cid public.centers.id%type;
  v_role public.users.role%type;
  v_status public.users.status%type;
begin
  if v_cname = '' or v_mname = '' or length(v_uname) < 3 then
    return jsonb_build_object('ok', false, 'error', 'missing');
  end if;
  if coalesce(length(p_password), 0) < 6 then
    return jsonb_build_object('ok', false, 'error', 'weak_password');
  end if;
  if exists (select 1 from public.users where lower(username) = lower(v_uname)) then
    return jsonb_build_object('ok', false, 'error', 'username_taken');
  end if;
  insert into public.centers (name, manager_name, status) values (v_cname, v_mname, 'pending') returning id into v_cid;
  v_role := 'supervisor'; v_status := 'pending';
  insert into public.users (center_id, role, username, password_hash, full_name, status)
  values (v_cid, v_role, v_uname, public._app_hash(p_password), v_mname, v_status);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.app_register_teacher(p_center_code text, p_username text, p_password text, p_full_name text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_code  text := btrim(coalesce(p_center_code, ''));
  v_uname text := btrim(coalesce(p_username, ''));
  v_cid public.centers.id%type;
  v_cname text;
  v_role public.users.role%type;
  v_status public.users.status%type;
  v_new public.users.id%type;
begin
  if v_code = '' or length(v_uname) < 3 or btrim(coalesce(p_full_name, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'missing');
  end if;
  if coalesce(length(p_password), 0) < 6 then
    return jsonb_build_object('ok', false, 'error', 'weak_password');
  end if;
  select c.id, c.name into v_cid, v_cname from public.centers c
   where c.id::text = v_code or c.name = v_code order by (c.id::text = v_code) desc limit 1;
  if v_cid is null then return jsonb_build_object('ok', false, 'error', 'no_center'); end if;
  if exists (select 1 from public.users where lower(username) = lower(v_uname) and center_id::text = v_cid::text) then
    return jsonb_build_object('ok', false, 'error', 'username_taken');
  end if;
  v_role := 'teacher'; v_status := 'pending';
  insert into public.users (center_id, role, username, password_hash, full_name, status, halaqa_id)
  values (v_cid, v_role, v_uname, public._app_hash(p_password), btrim(p_full_name), v_status, null)
  returning id into v_new;
  return jsonb_build_object('ok', true, 'user_id', v_new, 'center_name', v_cname);
end $$;

-- ---------------------------------------------------------------------
-- 6) إنشاء الحسابات وتغيير بيانات الدخول
-- ---------------------------------------------------------------------
create or replace function public.app_create_user(
  p_token text, p_role text, p_username text, p_password text, p_full_name text,
  p_halaqa_id text default null, p_center_id text default null, p_perms jsonb default null,
  p_reuse boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users;
  v_cid public.centers.id%type;
  v_ex public.users;
  v_uname text := btrim(coalesce(p_username, ''));
  v_role public.users.role%type;
  v_status public.users.status%type;
  v_hid public.users.halaqa_id%type;
  v_new public.users.id%type;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if p_role not in ('supervisor','teacher','student','employee') then
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;

  if c.role::text = 'masool' then
    select id into v_cid from public.centers where id::text = p_center_id;
  else
    select id into v_cid from public.centers where id::text = c.center_id::text;
  end if;
  if v_cid is null then return jsonb_build_object('ok', false, 'error', 'no_center'); end if;

  if c.role::text <> 'masool' then
    if p_role = 'supervisor' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if p_role = 'employee' and c.role::text <> 'supervisor' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if p_role = 'teacher' and not public._app_can(c, 'halaqat') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if p_role = 'student' and not (public._app_can(c, 'students') or c.role::text = 'teacher') then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
  end if;

  if length(v_uname) < 3 then return jsonb_build_object('ok', false, 'error', 'bad_username'); end if;
  if coalesce(length(p_password), 0) < 4 then return jsonb_build_object('ok', false, 'error', 'weak_password'); end if;

  select * into v_ex from public.users
   where lower(username) = lower(v_uname) and center_id::text = v_cid::text limit 1;
  if found then
    if p_reuse and v_ex.role::text = p_role then
      return jsonb_build_object('ok', true, 'id', v_ex.id, 'existed', true);
    end if;
    return jsonb_build_object('ok', false, 'error', 'username_taken');
  end if;
  if p_role = 'supervisor' and exists (select 1 from public.users where lower(username) = lower(v_uname)) then
    return jsonb_build_object('ok', false, 'error', 'username_taken');
  end if;

  v_role := p_role; v_status := 'active'; v_hid := nullif(btrim(coalesce(p_halaqa_id, '')), '');
  insert into public.users (center_id, role, username, password_hash, full_name, status, halaqa_id, perms)
  values (v_cid, v_role, v_uname, public._app_hash(p_password), nullif(btrim(coalesce(p_full_name, '')), ''),
          v_status, v_hid, case when p_role = 'employee' then public._app_clean_perms(p_perms) else '{}'::jsonb end)
  returning id into v_new;
  return jsonb_build_object('ok', true, 'id', v_new, 'existed', false);
end $$;

-- تعديل بيانات دخول حساب (أو إنشاؤه إن لم يوجد وكان p_create = true)
create or replace function public.app_save_credentials(
  p_token text, p_role text, p_user_id text, p_old_username text,
  p_new_username text, p_password text, p_full_name text default null,
  p_halaqa_id text default null, p_create boolean default true)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; t public.users;
  v_new text := btrim(coalesce(p_new_username, ''));
  v_res jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;

  if nullif(p_user_id, '') is not null then
    select * into t from public.users where id::text = p_user_id;
  elsif nullif(p_old_username, '') is not null and p_role is not null then
    select * into t from public.users
     where username = btrim(p_old_username) and role::text = p_role
       and center_id::text = c.center_id::text limit 1;
  end if;

  if t.id is null then
    if not p_create then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    v_res := public.app_create_user(p_token, p_role, v_new, p_password, p_full_name, p_halaqa_id, null, null, false);
    if (v_res ->> 'ok')::boolean then v_res := v_res || jsonb_build_object('created', true); end if;
    return v_res;
  end if;

  if not public._app_can_manage(c, t) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  if v_new <> '' and v_new <> t.username then
    if length(v_new) < 3 then return jsonb_build_object('ok', false, 'error', 'bad_username'); end if;
    if exists (select 1 from public.users
                where lower(username) = lower(v_new) and id <> t.id
                  and (t.role::text in ('supervisor','masool') or center_id::text = t.center_id::text)) then
      return jsonb_build_object('ok', false, 'error', 'username_taken');
    end if;
    update public.users set username = v_new where id = t.id;
  end if;

  if coalesce(p_password, '') <> '' then
    if length(p_password) < 4 then return jsonb_build_object('ok', false, 'error', 'weak_password'); end if;
    update public.users set password_hash = public._app_hash(p_password) where id = t.id;
    -- نُنهي جلسات الحساب الأخرى بعد تغيير كلمة المرور (نُبقي جلسة صاحب الطلب)
    delete from public.app_sessions
     where user_id = t.id::text
       and token_hash <> encode(digest(p_token, 'sha256'), 'hex');
  end if;

  return jsonb_build_object('ok', true, 'id', t.id, 'created', false);
end $$;

create or replace function public.app_username_taken(p_token text, p_username text, p_exclude_username text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; v_u text := lower(btrim(coalesce(p_username, '')));
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  return jsonb_build_object('ok', true, 'taken', exists (
    select 1 from public.users u
     where lower(u.username) = v_u
       and lower(u.username) <> lower(btrim(coalesce(p_exclude_username, '')))
       and (c.role::text = 'masool' or u.center_id::text = c.center_id::text)));
end $$;

create or replace function public.app_delete_users(p_token text, p_ids text[])
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t public.users; n int := 0;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  for t in select * from public.users where id::text = any (coalesce(p_ids, array[]::text[])) loop
    if t.id = c.id then continue; end if;
    if not public._app_can_manage(c, t) then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    delete from public.app_sessions where user_id = t.id::text;
    delete from public.users where id = t.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;

-- ---------------------------------------------------------------------
-- 7) المعلمون الجدد (طلبات الانضمام) وربط المعلم بحلقته
-- ---------------------------------------------------------------------
create or replace function public.app_pending_teachers(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text not in ('supervisor','employee') or not public._app_can(c, 'teachers') then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', u.id, 'username', u.username, 'full_name', u.full_name, 'created_at', u.created_at) order by u.created_at)
      from public.users u
     where u.center_id::text = c.center_id::text and u.role::text = 'teacher'
       and u.status = 'pending'), '[]'::jsonb));
end $$;

create or replace function public.app_approve_teacher(p_token text, p_user_id text, p_halaqa_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t public.users; v_hid public.users.halaqa_id%type; v_status public.users.status%type;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text not in ('supervisor','employee') or not public._app_can(c, 'teachers') then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  select * into t from public.users
   where id::text = p_user_id and role::text = 'teacher' and center_id::text = c.center_id::text;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not exists (select 1 from public.halaqat h where h.id::text = p_halaqa_id and h.center_id::text = c.center_id::text) then
    return jsonb_build_object('ok', false, 'error', 'no_halaqa');
  end if;
  v_hid := p_halaqa_id; v_status := 'active';
  update public.users set halaqa_id = v_hid, status = v_status where id = t.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.app_reject_teacher(p_token text, p_user_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text not in ('supervisor','employee') or not public._app_can(c, 'teachers') then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  select * into t from public.users
   where id::text = p_user_id and role::text = 'teacher' and center_id::text = c.center_id::text and status = 'pending';
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  delete from public.app_sessions where user_id = t.id::text;
  delete from public.users where id = t.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.app_link_my_halaqa(p_token text, p_halaqa_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; v_hid public.users.halaqa_id%type;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'teacher' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if not exists (select 1 from public.halaqat h
                  where h.id::text = p_halaqa_id and h.center_id::text = c.center_id::text
                    and h.teacher_username = c.username) then
    return jsonb_build_object('ok', false, 'error', 'not_yours');
  end if;
  v_hid := p_halaqa_id;
  update public.users set halaqa_id = v_hid where id = c.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.app_activate_self(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; v_status public.users.status%type;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'student' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  v_status := 'active';
  update public.users set status = v_status where id = c.id;
  return jsonb_build_object('ok', true);
end $$;

drop function if exists public.app_center_teachers(text, text[]);
create or replace function public.app_center_teachers(p_token text, p_halaqa_ids text[])
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text not in ('supervisor','employee','teacher') then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('full_name', u.full_name, 'username', u.username))
      from public.users u
     where u.center_id::text = c.center_id::text and u.role::text = 'teacher'
       and u.halaqa_id::text = any (coalesce(p_halaqa_ids, array[]::text[]))), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- 8) مالك التطبيق
-- ---------------------------------------------------------------------
create or replace function public.app_masool_supervisors(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'masool' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', u.id, 'center_id', u.center_id, 'username', u.username))
      from public.users u where u.role::text = 'supervisor'), '[]'::jsonb));
end $$;

create or replace function public.app_masool_set_center_status(p_token text, p_center_id text, p_status text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; v_ustatus public.users.status%type;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'masool' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_status not in ('active','rejected','pending') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  update public.centers set status = p_status where id::text = p_center_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_status = 'active' then
    v_ustatus := 'active';
    update public.users set status = v_ustatus where center_id::text = p_center_id and role::text = 'supervisor';
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.app_masool_delete_center(p_token text, p_center_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t text;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'masool' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  delete from public.app_sessions where user_id in (select id::text from public.users where center_id::text = p_center_id);
  foreach t in array array['records','students','halaqat','messages','daily_questions','deleted_ids','users'] loop
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
-- 9) الموظفون والصلاحيات (للمشرف فقط)
-- ---------------------------------------------------------------------
create or replace function public.app_list_staff(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'supervisor' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', u.id, 'username', u.username, 'full_name', u.full_name,
             'status', coalesce(u.status, 'active'), 'perms', coalesce(u.perms, '{}'::jsonb),
             'last_login_at', u.last_login_at, 'created_at', u.created_at) order by u.created_at)
      from public.users u where u.center_id::text = c.center_id::text and u.role::text = 'employee'), '[]'::jsonb));
end $$;

create or replace function public.app_update_staff(p_token text, p_user_id text, p_full_name text, p_perms jsonb, p_status text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t public.users; v_status public.users.status%type;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'supervisor' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into t from public.users
   where id::text = p_user_id and role::text = 'employee' and center_id::text = c.center_id::text;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_status is not null and p_status not in ('active','disabled') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  v_status := coalesce(p_status, t.status);
  update public.users
     set full_name = coalesce(nullif(btrim(coalesce(p_full_name, '')), ''), full_name),
         perms = case when p_perms is null then perms else public._app_clean_perms(p_perms) end,
         status = v_status
   where id = t.id;
  if p_status = 'disabled' then delete from public.app_sessions where user_id = t.id::text; end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 10) سجل التعديلات
-- ---------------------------------------------------------------------
create or replace function public.app_audit_add(p_token text, p_action text, p_entity text, p_entity_id text, p_entity_name text, p_details jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; d jsonb := coalesce(p_details, '{}'::jsonb);
begin
  c := public._app_auth(p_token);
  if c.id is null or c.center_id is null then return jsonb_build_object('ok', false); end if;
  if length(d::text) > 4000 then d := jsonb_build_object('truncated', true); end if;
  insert into public.audit_log (center_id, actor_id, actor_name, actor_role, action, entity, entity_id, entity_name, details)
  values (c.center_id::text, c.id::text, coalesce(c.full_name, c.username), c.role::text,
          left(coalesce(p_action, ''), 60), left(p_entity, 40), left(p_entity_id, 80), left(p_entity_name, 120), d);
  if random() < 0.01 then delete from public.audit_log where at < now() - interval '400 days'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.app_audit_list(p_token text, p_limit int default 100, p_before timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'supervisor' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(to_jsonb(x) order by x.at desc) from (
      select a.id, a.at, a.actor_name, a.actor_role, a.action, a.entity, a.entity_id, a.entity_name, a.details
        from public.audit_log a
       where a.center_id = c.center_id::text and (p_before is null or a.at < p_before)
       order by a.at desc limit least(greatest(coalesce(p_limit, 100), 1), 300)) x), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- 10b) قراءة آمنة لأسماء الحسابات (بلا أي hash) + حذف حساب معلم الحلقة
-- ---------------------------------------------------------------------
create or replace function public.app_accounts_by_ids(p_token text, p_ids text[]) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text not in ('supervisor','employee','teacher') then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', u.id, 'username', u.username, 'full_name', u.full_name))
      from public.users u
     where u.id::text = any (coalesce(p_ids, array[]::text[]))
       and u.center_id::text = c.center_id::text
       and u.role::text in ('student','teacher')), '[]'::jsonb));
end $$;

create or replace function public.app_teacher_accounts(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.center_id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('username', u.username, 'halaqa_id', u.halaqa_id, 'status', u.status))
      from public.users u
     where u.center_id::text = c.center_id::text and u.role::text = 'teacher' and u.status = 'active'), '[]'::jsonb));
end $$;

create or replace function public.app_delete_halaqa_teachers(p_token text, p_halaqa_id text, p_ids text[], p_teacher_username text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; n int := 0; v_ids text[];
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text not in ('supervisor','employee') or not public._app_can(c, 'halaqat') then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  select coalesce(array_agg(u.id::text), array[]::text[]) into v_ids from public.users u
   where u.role::text = 'teacher' and u.center_id::text = c.center_id::text
     and ( u.halaqa_id::text = p_halaqa_id
        or u.id::text = any (coalesce(p_ids, array[]::text[]))
        or (coalesce(p_teacher_username, '') <> '' and u.username = p_teacher_username) );
  delete from public.app_sessions where user_id = any (v_ids);
  delete from public.users where id::text = any (v_ids);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;

-- ---------------------------------------------------------------------
-- 11) صلاحيات التنفيذ: الدوال العامة فقط تُستدعى من المتصفح
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname like '\_app\_%' or p.proname like 'app\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if r.proname like 'app\_%' then
      execute format('grant execute on function %s to anon, authenticated', r.sig);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
