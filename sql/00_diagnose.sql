-- =====================================================================
--  تشخيص (اختياري ولا يغيّر شيئاً) — شغّله وأرسل لي النتائج إن أردت مراجعة
--  سياسات الحماية (RLS) على باقي الجداول: students / records / halaqat / messages
-- =====================================================================

-- 1) سياسات RLS الحالية
select tablename, policyname, cmd, roles, qual as using_expr, with_check
  from pg_policies where schemaname = 'public' order by tablename, policyname;

-- 2) ماذا يستطيع anon أن يفعل مباشرة على كل جدول؟
select table_name, string_agg(privilege_type, ', ' order by privilege_type) as anon_privileges
  from information_schema.role_table_grants
 where table_schema = 'public' and grantee = 'anon'
 group by table_name order by table_name;

-- 3) هل RLS مفعّل على كل جدول؟
select c.relname as table_name, c.relrowsecurity as rls_enabled
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' order by c.relname;

-- 4) حسابات بلا كلمة مرور (غالباً أُنشئت سابقاً عبر Google) — هؤلاء يحتاجون تعيين كلمة مرور
select role, username, full_name, status, center_id
  from public.users where coalesce(password_hash, '') = '' order by role, username;
