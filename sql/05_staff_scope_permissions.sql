-- =====================================================================
--  نظام الرضوان — الإصدار 2.3.0
--  الخطوة 5: صلاحيات الموظفين — نطاق حلقة واحدة + منع تعديل السجلات اليومية
--  شغّله في Supabase ← SQL Editor بعد 04_part3. آمن ويمكن تكراره.
--  لا يغيّر بياناتك، بل يضيف دوال سيرفر ويوسّع بياض الصلاحيات.
-- =====================================================================
do $$ begin
  if to_regprocedure('public._app_auth(text)') is null then
    raise exception 'شغّل 01_security_setup.sql أولاً';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1) صلاحية جديدة: records_lock = الاطلاع على السجلات فقط (بلا إضافة/حذف/تعديل)
--    تُقرأ من perms في المتصفح، ويُوسَّع البياض هنا ليقبلها السيرفر ويحفظها.
-- ---------------------------------------------------------------------
create or replace function public._app_clean_perms(p jsonb) returns jsonb
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare k text; out jsonb := '{}'::jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return out; end if;
  foreach k in array array['students','records','halaqat','teachers','reports','messages','backup','competitions','records_lock'] loop
    if (p ->> k) in ('true','false') then out := out || jsonb_build_object(k, (p ->> k)::boolean); end if;
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- 2) نطاق عمل الموظف: الموظف المقيد بحلقة لا يدير إلا حسابات تلك الحلقة
--    (دفاع إضافي على مستوى السيرفر، إلى جانب منع الواجهة).
-- ---------------------------------------------------------------------
create or replace function public._app_can_manage(c public.users, t public.users) returns boolean
language plpgsql stable set search_path = public, extensions, pg_temp as $$
begin
  if c.id = t.id then return true; end if;
  if c.role::text = 'masool' then return t.role::text <> 'masool'; end if;
  if c.center_id::text is distinct from t.center_id::text then return false; end if;
  if c.role::text = 'supervisor' then return t.role::text in ('teacher','student','employee'); end if;
  if c.role::text = 'employee' then
    if c.halaqa_id is not null then
      return (t.role::text = 'student' and public._app_can(c, 'students')
              and exists (select 1 from public.students s
                           where s.user_id::text = t.id::text
                             and s.halaqa_id::text = c.halaqa_id::text))
          or (t.role::text = 'teacher' and public._app_can(c, 'halaqat')
              and t.halaqa_id::text = c.halaqa_id::text);
    end if;
    return (t.role::text = 'teacher' and public._app_can(c, 'halaqat'))
        or (t.role::text = 'student' and public._app_can(c, 'students'));
  end if;
  if c.role::text = 'teacher' then
    return t.role::text = 'student' and c.halaqa_id is not null
       and not exists (select 1 from public.students s
                        where s.user_id::text = t.id::text
                          and s.halaqa_id::text is distinct from c.halaqa_id::text);
  end if;
  return false;
end $$;

-- ---------------------------------------------------------------------
-- 3) قائمة الموظفين: نُعيد معهم نطاق الحلقة واسمها ليعرضه المشرف
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
             'halaqa_id', u.halaqa_id,
             'halaqa_name', (select h.name from public.halaqat h where h.id::text = u.halaqa_id::text),
             'last_login_at', u.last_login_at, 'created_at', u.created_at) order by u.created_at)
      from public.users u where u.center_id::text = c.center_id::text and u.role::text = 'employee'), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- 4) تعديل الموظف: نفس الدالة + مُعامل جديد p_halaqa_id
--    ('' أو null = كل الحلقات؛ معرّف حلقة = نطاق محدود)
-- ---------------------------------------------------------------------
drop function if exists public.app_update_staff(text, text, text, jsonb, text);
create or replace function public.app_update_staff(
  p_token text, p_user_id text, p_full_name text, p_perms jsonb, p_status text,
  p_halaqa_id text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.users; t public.users; v_status public.users.status%type; v_hid public.users.halaqa_id%type;
begin
  c := public._app_auth(p_token);
  if c.id is null or c.role::text <> 'supervisor' then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into t from public.users
   where id::text = p_user_id and role::text = 'employee' and center_id::text = c.center_id::text;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_status is not null and p_status not in ('active','disabled') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;

  -- p_halaqa_id = null يعني «لا تغيير»؛ '' يعني «كل الحلقات»
  if p_halaqa_id is null then
    v_hid := t.halaqa_id;
  else
    v_hid := nullif(btrim(p_halaqa_id), '');
    if v_hid is not null and not exists (
        select 1 from public.halaqat h where h.id::text = v_hid and h.center_id::text = c.center_id::text) then
      return jsonb_build_object('ok', false, 'error', 'no_halaqa');
    end if;
  end if;

  v_status := coalesce(p_status, t.status);
  update public.users
     set full_name = coalesce(nullif(btrim(coalesce(p_full_name, '')), ''), full_name),
         perms = case when p_perms is null then perms else public._app_clean_perms(p_perms) end,
         status = v_status,
         halaqa_id = v_hid
   where id = t.id;
  if p_status = 'disabled' then delete from public.app_sessions where user_id = t.id::text; end if;
  return jsonb_build_object('ok', true);
end $$;

-- الدالة الجديدة تحتاج إذن تنفيذ من المتصفح (كباقي دوال app_)
revoke all on function public.app_update_staff(text, text, text, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.app_update_staff(text, text, text, jsonb, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
select 'تم الجزء 1 من 1 بنجاح ✅ — صلاحيات الموظفين (2.3.0) جاهزة' as status;
