-- =====================================================================
--  الإصدار 2.2.0 — الجزء 3 من 3: المحادثة: تعديل/حذف/مسح، المجموعات، ترتيب المحادثات، الصور والفيديو والصوت
--  شغّله بعد الجزء 2. آمن ويمكن تكراره.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.chat2_send(text,text,text,text,text,bigint,text)') is null then raise exception 'شغّل الجزء 2 أولاً'; end if;
end $$;

create or replace function public._chat2_key_of(m public.student_chat) returns text
language sql immutable as $$ select case when m.group_id is null then 's:' || m.student_id else 'g:' || m.group_id::text end $$;

create or replace function public.chat2_edit(p_token text, p_id bigint, p_body text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; m public.student_chat; v_body text := btrim(coalesce(p_body, ''));
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into m from public.student_chat where id = p_id;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if m.sender_id is distinct from c.id::text or m.kind <> 'text' or m.deleted_at is not null
     or public._chat2_ctx(c, public._chat2_key_of(m)) is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if length(v_body) < 1 or length(v_body) > 1500 then return jsonb_build_object('ok', false, 'error', 'bad_body'); end if;
  update public.student_chat set body = v_body, edited_at = now() where id = m.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.chat2_delete(p_token text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; m public.student_chat; ctx jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into m from public.student_chat where id = p_id;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  ctx := public._chat2_ctx(c, public._chat2_key_of(m));
  if ctx is null or not (m.sender_id = c.id::text or (ctx ->> 'staff')::boolean) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  update public.student_chat set deleted_at = now(), body = '', media_id = null where id = m.id;
  if m.media_id is not null then delete from public.chat_media where id = m.media_id; end if;
  return jsonb_build_object('ok', true);
end $$;

-- مسح المحادثة: p_everyone=false يخفيها عن صاحب الطلب فقط؛ true (للمعلم/المشرف) يحذفها نهائياً للجميع
create or replace function public.chat2_clear(p_token text, p_key text, p_everyone boolean default false) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; ctx jsonb; sid text; gid uuid; n int := 0;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  ctx := public._chat2_ctx(c, p_key);
  if ctx is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  sid := ctx ->> 'student_id'; gid := nullif(ctx ->> 'group_id', '')::uuid;
  if p_everyone then
    if not (ctx ->> 'staff')::boolean then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    delete from public.chat_media where thread_key = p_key;
    delete from public.student_chat m where (gid is null and m.student_id = sid and m.group_id is null) or (gid is not null and m.group_id = gid);
    get diagnostics n = row_count;
    delete from public.chat_reads where thread_key = p_key;
  else
    insert into public.chat_reads (user_id, thread_key, last_id, cleared_at) values (c.id::text, p_key, 0, now())
    on conflict (user_id, thread_key) do update set cleared_at = now();
  end if;
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;

create or replace function public.chat2_group_save(p_token text, p_id text, p_name text, p_halaqa text default null, p_allow boolean default true) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; g public.chat_groups; v_name text := btrim(coalesce(p_name, '')); v_h text := nullif(btrim(coalesce(p_halaqa, '')), '');
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if not (c.role::text in ('supervisor', 'teacher') or (c.role::text = 'employee' and public._app_can(c, 'messages'))) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if length(v_name) < 2 or length(v_name) > 60 then return jsonb_build_object('ok', false, 'error', 'bad_title'); end if;
  if c.role::text = 'teacher' then v_h := c.halaqa_id::text; end if;
  if v_h is not null and not exists (select 1 from public.halaqat h where h.id::text = v_h and h.center_id::text = c.center_id::text) then
    return jsonb_build_object('ok', false, 'error', 'bad_halaqa');
  end if;
  if v_h is null and c.role::text = 'teacher' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if coalesce(p_id, '') <> '' then
    select * into g from public.chat_groups x where x.id::text = p_id and x.center_id = c.center_id::text;
    if g.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if c.role::text = 'teacher' and g.halaqa_id is distinct from c.halaqa_id::text then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    update public.chat_groups set name = v_name, allow_students = coalesce(p_allow, true) where id = g.id;
    return jsonb_build_object('ok', true, 'id', g.id);
  end if;
  insert into public.chat_groups (center_id, halaqa_id, name, allow_students, created_by)
  values (c.center_id::text, v_h, v_name, coalesce(p_allow, true), c.id::text) returning * into g;
  return jsonb_build_object('ok', true, 'id', g.id);
end $$;

create or replace function public.chat2_group_delete(p_token text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; g public.chat_groups; ctx jsonb;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into g from public.chat_groups x where x.id::text = p_id;
  if g.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  ctx := public._chat2_ctx(c, 'g:' || g.id::text);
  if ctx is null or not (ctx ->> 'staff')::boolean then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  delete from public.chat_media where thread_key = 'g:' || g.id::text;
  delete from public.student_chat where group_id = g.id;
  delete from public.chat_reads where thread_key = 'g:' || g.id::text;
  delete from public.chat_groups where id = g.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.chat2_prefs_set(p_token text, p_order jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if jsonb_typeof(p_order) <> 'array' or jsonb_array_length(p_order) > 300 then return jsonb_build_object('ok', false, 'error', 'bad_items'); end if;
  insert into public.chat_prefs (user_id, order_keys) values (c.id::text, p_order)
  on conflict (user_id) do update set order_keys = excluded.order_keys;
  return jsonb_build_object('ok', true);
end $$;

-- الوسائط: رفع مجزّأ (قطع base64) واسترجاع مجزّأ. الحدود: صورة 6MB، صوت 12MB، فيديو 25MB، وحصة يومية 120MB لكل مرسل
create or replace function public.chat2_media_start(p_token text, p_key text, p_kind text, p_mime text, p_name text, p_size int, p_chunks int) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; ctx jsonb; lim int; v_id uuid;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  ctx := public._chat2_ctx(c, p_key);
  if ctx is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if not (ctx ->> 'can_post')::boolean then return jsonb_build_object('ok', false, 'error', 'read_only'); end if;
  if p_kind not in ('image', 'video', 'audio') then return jsonb_build_object('ok', false, 'error', 'bad_media'); end if;
  lim := case p_kind when 'image' then 6291456 when 'audio' then 12582912 else 26214400 end;
  if coalesce(p_size, 0) <= 0 or p_size > lim or coalesce(p_chunks, 0) < 1 or p_chunks > 70 then return jsonb_build_object('ok', false, 'error', 'too_big', 'limit', lim); end if;
  if (select coalesce(sum(m.size), 0) from public.chat_media m where m.owner_id = c.id::text and m.created_at > now() - interval '1 day') + p_size > 125829120 then
    return jsonb_build_object('ok', false, 'error', 'quota');
  end if;
  if random() < 0.02 then delete from public.chat_media where created_at < now() - interval '120 days' or (not complete and created_at < now() - interval '1 day'); end if;
  insert into public.chat_media (center_id, owner_id, thread_key, kind, mime, name, size, chunks)
  values (c.center_id::text, c.id::text, p_key, p_kind, left(coalesce(p_mime, ''), 80), left(coalesce(p_name, ''), 120), p_size, p_chunks) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.chat2_media_chunk(p_token text, p_id text, p_idx int, p_data text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; m public.chat_media;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into m from public.chat_media x where x.id::text = p_id and x.owner_id = c.id::text and not x.complete;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_idx < 0 or p_idx >= m.chunks or length(coalesce(p_data, '')) = 0 or length(p_data) > 900000 then return jsonb_build_object('ok', false, 'error', 'bad_media'); end if;
  insert into public.chat_media_chunks (media_id, idx, data) values (m.id, p_idx, p_data)
  on conflict (media_id, idx) do update set data = excluded.data;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.chat2_media_finish(p_token text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; m public.chat_media;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into m from public.chat_media x where x.id::text = p_id and x.owner_id = c.id::text;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if (select count(*) from public.chat_media_chunks k where k.media_id = m.id) <> m.chunks then return jsonb_build_object('ok', false, 'error', 'incomplete'); end if;
  update public.chat_media set complete = true where id = m.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.chat2_media_get(p_token text, p_id text, p_idx int default 0) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; m public.chat_media; d text;
begin
  c := public._app_auth(p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  select * into m from public.chat_media x where x.id::text = p_id and x.complete;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if public._chat2_ctx(c, m.thread_key) is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select k.data into d from public.chat_media_chunks k where k.media_id = m.id and k.idx = p_idx;
  if d is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'kind', m.kind, 'mime', m.mime, 'name', m.name, 'size', m.size, 'chunks', m.chunks, 'data', d);
end $$;

-- حذف مركز (للمالك) يشمل المجموعات والوسائط الجديدة
create or replace function public.app_masool_delete_center(p_token text, p_center_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t text;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'masool' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  delete from public.app_sessions where user_id in (select id::text from public.users where center_id::text = p_center_id);
  foreach t in array array['records', 'students'] loop
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = t and column_name = 'halaqa_id') then
      execute format('delete from public.%I where halaqa_id::text in (select id::text from public.halaqat where center_id::text = $1)', t) using p_center_id;
    end if;
  end loop;
  foreach t in array array['records', 'students', 'halaqat', 'messages', 'daily_questions', 'deleted_ids', 'competitions', 'assignments',
                           'student_chat', 'chat_groups', 'chat_media', 'users'] loop
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = t and column_name = 'center_id') then
      execute format('delete from public.%I where center_id::text = $1', t) using p_center_id;
    end if;
  end loop;
  delete from public.audit_log where center_id = p_center_id;
  delete from public.centers where id::text = p_center_id;
  return jsonb_build_object('ok', true);
end $$;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname ~ '^chat2_' or p.proname ~ '^_chat2_' or p.proname = 'app_masool_delete_center')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if r.proname ~ '^chat2_' or r.proname = 'app_masool_delete_center' then
      execute format('grant execute on function %s to anon, authenticated', r.sig);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
select 'تم الجزء 3 من 3 بنجاح ✅ — الإصدار 2.2.0 جاهز في قاعدة البيانات' as status;
