-- =====================================================================
--  الإصدار 2.2.0 — الجزء 2 من 3: المحادثة (النواة): جداول + قائمة المحادثات + القراءة + الإرسال
--  شغّله بعد الجزء 1. آمن ويمكن تكراره.
-- =====================================================================
do $$ begin
  if to_regclass('public.student_chat') is null then raise exception 'شغّل 03_competitions.sql أولاً'; end if;
end $$;

-- الرسائل: دعم الوسائط والردود والتعديل والحذف والمجموعات
do $$
declare r record;
begin
  for r in select c.conname from pg_constraint c
            where c.conrelid = 'public.student_chat'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) ~* 'body'
  loop execute format('alter table public.student_chat drop constraint %I', r.conname); end loop;
end $$;
alter table public.student_chat drop constraint if exists student_chat_body_len;
alter table public.student_chat add constraint student_chat_body_len check (length(body) <= 1500);
alter table public.student_chat alter column student_id drop not null;
alter table public.student_chat add column if not exists group_id uuid;
alter table public.student_chat add column if not exists kind text not null default 'text';
alter table public.student_chat add column if not exists media_id uuid;
alter table public.student_chat add column if not exists reply_to bigint;
alter table public.student_chat add column if not exists edited_at timestamptz;
alter table public.student_chat add column if not exists deleted_at timestamptz;
create index if not exists student_chat_group_idx on public.student_chat (group_id, id);

create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  center_id text not null,
  halaqa_id text,
  name text not null,
  allow_students boolean not null default true,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists chat_groups_center_idx on public.chat_groups (center_id, halaqa_id);
create table if not exists public.chat_reads (
  user_id text not null, thread_key text not null, last_id bigint not null default 0, cleared_at timestamptz,
  primary key (user_id, thread_key)
);
create table if not exists public.chat_prefs (user_id text primary key, order_keys jsonb not null default '[]'::jsonb);
create table if not exists public.chat_media (
  id uuid primary key default gen_random_uuid(),
  center_id text not null, owner_id text not null, thread_key text not null,
  kind text not null check (kind in ('image', 'video', 'audio')),
  mime text, name text, size int not null default 0, chunks int not null default 1,
  complete boolean not null default false, created_at timestamptz not null default now()
);
create index if not exists chat_media_thread_idx on public.chat_media (thread_key);
create table if not exists public.chat_media_chunks (
  media_id uuid not null references public.chat_media(id) on delete cascade,
  idx int not null, data text not null, primary key (media_id, idx)
);
do $$
declare t text;
begin
  foreach t in array array['chat_groups', 'chat_reads', 'chat_prefs', 'chat_media', 'chat_media_chunks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- سياق المحادثة: من يستطيع الدخول؟ هل يكتب؟ هل هو موظف؟ (المفتاح: s:<طالب> أو g:<مجموعة>)
create or replace function public._chat2_ctx(c public.users, p_key text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare st public.students; g public.chat_groups; k text := split_part(coalesce(p_key, ''), ':', 1); ident text := substr(coalesce(p_key, ''), 3);
begin
  if c.id is null then return null; end if;
  if k = 's' then
    if c.role::text = 'student' then
      st := public._app_student_of(c);
      if st.id is null or st.id::text <> ident then return null; end if;
    else
      select * into st from public.students s where s.id::text = ident;
      if not public._chat_staff_ok(c, st) then return null; end if;
    end if;
    return jsonb_build_object('kind', 's', 'student_id', st.id, 'halaqa_id', st.halaqa_id, 'can_post', true,
                              'staff', c.role::text <> 'student', 'title', st.name);
  elsif k = 'g' then
    select * into g from public.chat_groups x where x.id::text = ident;
    if g.id is null or g.center_id <> c.center_id::text then return null; end if;
    if c.role::text = 'student' then
      st := public._app_student_of(c);
      if st.id is null or (g.halaqa_id is not null and st.halaqa_id::text <> g.halaqa_id) then return null; end if;
      return jsonb_build_object('kind', 'g', 'group_id', g.id, 'halaqa_id', g.halaqa_id, 'can_post', g.allow_students, 'staff', false, 'title', g.name);
    end if;
    if not (c.role::text = 'supervisor' or (c.role::text = 'employee' and public._app_can(c, 'messages'))
            or (c.role::text = 'teacher' and g.halaqa_id is not null and c.halaqa_id::text = g.halaqa_id)) then return null; end if;
    return jsonb_build_object('kind', 'g', 'group_id', g.id, 'halaqa_id', g.halaqa_id, 'can_post', true, 'staff', true, 'title', g.name);
  end if;
  return null;
end $$;

create or replace function public._chat2_unread(me text, p_key text, p_sid text, p_gid uuid) returns int
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)::int from public.student_chat m
    left join public.chat_reads r on r.user_id = me and r.thread_key = p_key
   where m.deleted_at is null and m.sender_id is distinct from me and m.id > coalesce(r.last_id, 0)
     and (r.cleared_at is null or m.created_at > r.cleared_at)
     and ((p_gid is null and m.student_id = p_sid and m.group_id is null and m.read_at is null) or (p_gid is not null and m.group_id = p_gid))
$$;

create or replace function public._chat2_row(me text, p_key text, p_kind text, p_title text, p_sid text, p_gid uuid, p_post boolean, p_extra jsonb)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare l record; cl timestamptz;
begin
  select r.cleared_at into cl from public.chat_reads r where r.user_id = me and r.thread_key = p_key;
  select m.body, m.kind, m.created_at, m.sender_role into l from public.student_chat m
   where m.deleted_at is null and (cl is null or m.created_at > cl)
     and ((p_gid is null and m.student_id = p_sid and m.group_id is null) or (p_gid is not null and m.group_id = p_gid))
   order by m.id desc limit 1;
  return jsonb_build_object('key', p_key, 'kind', p_kind, 'title', p_title, 'last_body', left(coalesce(l.body, ''), 80), 'last_kind', l.kind,
           'last_at', l.created_at, 'last_role', l.sender_role, 'unread', public._chat2_unread(me, p_key, p_sid, p_gid),
           'pinned', p_kind = 'g', 'can_post', p_post) || coalesce(p_extra, '{}'::jsonb);
end $$;

create or replace function public._chat2_list(c public.users) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare st public.students; g public.chat_groups; s public.students; rows jsonb := '[]'::jsonb; me text := c.id::text; ord jsonb;
begin
  if c.role::text = 'student' then
    st := public._app_student_of(c);
    if st.id is not null then
      rows := rows || public._chat2_row(me, 's:' || st.id::text, 's', 'المعلم', st.id::text, null, true, null);
      for g in select * from public.chat_groups x where x.center_id = c.center_id::text and (x.halaqa_id is null or x.halaqa_id = st.halaqa_id::text) order by x.created_at loop
        rows := rows || public._chat2_row(me, 'g:' || g.id::text, 'g', g.name, null, g.id, g.allow_students, jsonb_build_object('group_id', g.id, 'halaqa_id', g.halaqa_id, 'allow_students', g.allow_students));
      end loop;
    end if;
  elsif c.role::text in ('teacher', 'supervisor', 'employee') then
    for s in select x.* from public.students x
              where public._chat_staff_ok(c, x)
                and exists (select 1 from public.student_chat m where m.student_id = x.id::text and m.group_id is null and m.deleted_at is null) loop
      rows := rows || public._chat2_row(me, 's:' || s.id::text, 's', s.name, s.id::text, null, true, jsonb_build_object('student_id', s.id, 'halaqa_id', s.halaqa_id));
    end loop;
    for g in select * from public.chat_groups x where x.center_id = c.center_id::text
               and (c.role::text = 'supervisor' or (c.role::text = 'employee' and public._app_can(c, 'messages'))
                    or (c.role::text = 'teacher' and x.halaqa_id = c.halaqa_id::text)) order by x.created_at loop
      rows := rows || public._chat2_row(me, 'g:' || g.id::text, 'g', g.name, null, g.id, true, jsonb_build_object('group_id', g.id, 'halaqa_id', g.halaqa_id, 'allow_students', g.allow_students));
    end loop;
  end if;
  select order_keys into ord from public.chat_prefs where user_id = me;
  return jsonb_build_object('rows', rows, 'order', coalesce(ord, '[]'::jsonb),
                            'unread', (select coalesce(sum((x ->> 'unread')::int), 0) from jsonb_array_elements(rows) x));
end $$;

create or replace function public.chat2_threads(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  return jsonb_build_object('ok', true) || public._chat2_list(c);
end $$;

create or replace function public.chat2_unread(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; l jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  l := public._chat2_list(c);
  return jsonb_build_object('ok', true, 'unread', l -> 'unread', 'threads',
    (select coalesce(jsonb_object_agg(x ->> 'key', (x ->> 'unread')::int) filter (where (x ->> 'unread')::int > 0), '{}'::jsonb) from jsonb_array_elements(l -> 'rows') x),
    'senders', (select coalesce(jsonb_agg(x ->> 'title') filter (where (x ->> 'unread')::int > 0), '[]'::jsonb) from jsonb_array_elements(l -> 'rows') x));
end $$;

create or replace function public.chat2_get(p_token text, p_key text, p_limit int default 150) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; ctx jsonb; me text; sid text; gid uuid; cl timestamptz; rows jsonb; mx bigint;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  ctx := public._chat2_ctx(c, p_key);
  if ctx is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  me := c.id::text; sid := ctx ->> 'student_id'; gid := nullif(ctx ->> 'group_id', '')::uuid;
  select r.cleared_at into cl from public.chat_reads r where r.user_id = me and r.thread_key = p_key;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id), '[]'::jsonb) into rows from (
    select m.id, m.sender_role, m.sender_name, (m.sender_id = me) as mine, m.kind,
           case when m.deleted_at is null then m.body else '' end as body,
           case when m.deleted_at is null then m.media_id else null end as media_id,
           m.reply_to, m.created_at, m.edited_at, (m.deleted_at is not null) as deleted,
           (select jsonb_build_object('id', r.id, 'sender_name', r.sender_name, 'kind', r.kind, 'deleted', r.deleted_at is not null,
                   'body', left(case when r.deleted_at is null then r.body else '' end, 80)) from public.student_chat r where r.id = m.reply_to) as reply,
           case when m.media_id is not null and m.deleted_at is null then
             (select jsonb_build_object('kind', x.kind, 'mime', x.mime, 'name', x.name, 'size', x.size, 'chunks', x.chunks) from public.chat_media x where x.id = m.media_id) end as media
      from public.student_chat m
     where ((gid is null and m.student_id = sid and m.group_id is null) or (gid is not null and m.group_id = gid))
       and (cl is null or m.created_at > cl)
     order by m.id desc limit least(greatest(coalesce(p_limit, 150), 1), 300)) q;
  select max(m.id) into mx from public.student_chat m
   where (gid is null and m.student_id = sid and m.group_id is null) or (gid is not null and m.group_id = gid);
  insert into public.chat_reads (user_id, thread_key, last_id) values (me, p_key, coalesce(mx, 0))
  on conflict (user_id, thread_key) do update set last_id = greatest(public.chat_reads.last_id, excluded.last_id);
  if gid is null then
    update public.student_chat set read_at = now() where student_id = sid and group_id is null and read_at is null and sender_id is distinct from me;
  end if;
  return jsonb_build_object('ok', true, 'rows', rows, 'title', ctx ->> 'title', 'can_post', (ctx ->> 'can_post')::boolean,
                            'kind', ctx ->> 'kind', 'staff', (ctx ->> 'staff')::boolean);
end $$;

create or replace function public.chat2_send(p_token text, p_key text, p_kind text, p_body text, p_media text default null,
                                             p_reply bigint default null, p_op text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  c public.users; ctx jsonb; v_op uuid; dup jsonb; v_body text := btrim(coalesce(p_body, '')); v_kind text := coalesce(nullif(p_kind, ''), 'text');
  mrow public.chat_media; rp public.student_chat; v_id bigint; v_at timestamptz; out jsonb; v_media uuid;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  ctx := public._chat2_ctx(c, p_key);
  if ctx is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if not (ctx ->> 'can_post')::boolean then return jsonb_build_object('ok', false, 'error', 'read_only'); end if;
  if v_kind not in ('text', 'image', 'video', 'audio') then return jsonb_build_object('ok', false, 'error', 'bad_body'); end if;
  begin v_op := nullif(p_op, '')::uuid; exception when others then v_op := null; end;
  dup := public._comp_op_get(v_op); if dup is not null then return dup; end if;
  if v_kind = 'text' then
    if length(v_body) < 1 or length(v_body) > 1500 then return jsonb_build_object('ok', false, 'error', 'bad_body'); end if;
  else
    select * into mrow from public.chat_media m where m.id::text = p_media and m.owner_id = c.id::text and m.complete and m.thread_key = p_key;
    if mrow.id is null or mrow.kind <> v_kind or length(v_body) > 500 then return jsonb_build_object('ok', false, 'error', 'bad_media'); end if;
    v_media := mrow.id;
  end if;
  if (select count(*) from public.student_chat m where m.sender_id = c.id::text and m.created_at > now() - interval '1 minute') >= 30 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  if p_reply is not null then
    select * into rp from public.student_chat r where r.id = p_reply
       and ((nullif(ctx ->> 'group_id', '') is null and r.student_id = ctx ->> 'student_id' and r.group_id is null) or r.group_id::text = ctx ->> 'group_id');
    if rp.id is null then return jsonb_build_object('ok', false, 'error', 'bad_reply'); end if;
  end if;
  insert into public.student_chat (center_id, halaqa_id, student_id, group_id, sender_role, sender_id, sender_name, body, kind, media_id, reply_to)
  values (c.center_id::text, nullif(ctx ->> 'halaqa_id', ''), nullif(ctx ->> 'student_id', ''), nullif(ctx ->> 'group_id', '')::uuid,
          c.role::text, c.id::text, coalesce(c.full_name, c.username), v_body, v_kind, v_media, p_reply)
  returning id, created_at into v_id, v_at;
  out := jsonb_build_object('ok', true, 'id', v_id, 'created_at', v_at);
  perform public._comp_op_put(v_op, out);
  return out;
end $$;

notify pgrst, 'reload schema';
select 'تم الجزء 2 من 3 بنجاح ✅' as status;
