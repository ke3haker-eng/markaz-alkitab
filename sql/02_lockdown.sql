-- =====================================================================
--  نظام الرضوان — الإصدار 2.0
--  الخطوة 2 من 2: إغلاق الوصول المباشر (شغّله بعد نشر التطبيق الجديد واختبار الدخول)
--  بعد هذه الخطوة: لا أحد يستطيع قراءة/كتابة جدول users مباشرة،
--  ولا تغيير حالة المركز أو حذفه — كل ذلك يمر عبر دوال السيرفر المفحوصة.
--  ⚠️ النسخة القديمة من التطبيق ستتوقف عن الدخول بعد هذه الخطوة (المقصود).
-- =====================================================================

-- 1) جدول المستخدمين وجداول الحماية: لا وصول مباشر إطلاقاً
revoke all on public.users               from anon, authenticated;
revoke all on public.app_sessions        from anon, authenticated;
revoke all on public.app_login_attempts  from anon, authenticated;
revoke all on public.audit_log           from anon, authenticated;
alter table public.users enable row level security;

-- 2) جدول المراكز: القراءة وتعديل بيانات المركز (الاسم/الأيقونة..) كما هو،
--    أما الإضافة والحذف وتغيير الحالة (status) فعبر دوال السيرفر فقط
revoke insert, delete, update on public.centers from anon, authenticated;
do $$
declare cols text;
begin
  select string_agg(quote_ident(column_name), ', ') into cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'centers'
     and column_name not in ('id', 'status', 'created_at');
  if cols is not null then
    execute format('grant update (%s) on public.centers to anon, authenticated', cols);
  end if;
end $$;

notify pgrst, 'reload schema';
