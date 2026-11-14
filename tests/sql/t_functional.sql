\set ON_ERROR_STOP on
set client_min_messages = notice;
set search_path = public, extensions;
create or replace function pg_temp.j(x jsonb, k text) returns text language sql as $$ select x ->> k $$;
do $$
declare
  cA uuid; cB uuid; r jsonb; tokM text; tokS text; tokE text; tokT text; tokB text; v_h text; sid uuid; tid uuid; empid uuid; n int; stuid uuid; stuB uuid;
begin
  insert into centers(name, manager_name, status) values ('مركز أ','مشرف أ','active') returning id into cA;
  insert into centers(name, manager_name, status) values ('مركز ب','مشرف ب','active') returning id into cB;
  insert into users(role, username, password_hash, full_name) values ('masool','owner', encode(digest('ownerpass','sha256'),'hex'), 'المالك');
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'supervisor','supA', encode(digest('suppass1','sha256'),'hex'), 'مشرف أ') returning id into sid;
  insert into users(center_id, role, username, password_hash, full_name) values (cB,'supervisor','supB', encode(digest('suppass2','sha256'),'hex'), 'مشرف ب');
  insert into halaqat(id, center_id, name, teacher_username) values ('hq_1', cA, 'حلقة 1', 'teachA'), ('hq_2', cA, 'حلقة 2', 'teachA2');
  insert into users(center_id, role, username, password_hash, full_name, halaqa_id) values (cA,'teacher','teachA', encode(digest('teachpw','sha256'),'hex'), 'معلم', 'hq_1') returning id into tid;
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'student','stuA', encode(digest('stupw','sha256'),'hex'), 'طالب') returning id into stuid;
  insert into students(id, halaqa_id, user_id, name) values ('s1','hq_1', stuid, 'طالب');
  insert into users(center_id, role, username, password_hash, full_name) values (cB,'student','stuB', encode(digest('stupw','sha256'),'hex'), 'طالب ب') returning id into stuB;

  -- 1) دخول المالك بهاش قديم + ترقية الهاش
  r := app_login('owner','ownerpass','staff'); assert (r->>'ok')::boolean, 'owner login: '||r::text; tokM := r->>'token';
  select password_hash into v_h from users where username='owner'; assert v_h like '$2%', 'hash upgraded to bcrypt';
  r := app_login('owner','ownerpass','staff'); assert (r->>'ok')::boolean, 'owner login after upgrade';
  -- طالب لا يدخل من نموذج الموظفين والعكس
  r := app_login('stuA','stupw','staff'); assert not (r->>'ok')::boolean, 'student cannot use staff form';
  r := app_login('stuA','stupw','student'); assert (r->>'ok')::boolean, 'student login'; 
  r := app_login('supA','suppass1','student'); assert not (r->>'ok')::boolean, 'staff cannot use student form';

  -- 2) القفل المؤقت
  delete from app_login_attempts;
  for i in 1..4 loop r := app_login('supA','wrong','staff'); assert r->>'error'='invalid', 'invalid #'||i; end loop;
  r := app_login('supA','wrong','staff'); assert r->>'error'='locked' and (r->>'retry_after')::int = 600, 'locked after 5: '||r::text;
  r := app_login('supA','suppass1','staff'); assert r->>'error'='locked', 'correct pw still locked';
  update app_login_attempts set locked_until = now() - interval '1 second' where uname='supa';
  r := app_login('supA','suppass1','staff'); assert (r->>'ok')::boolean, 'login after lock expiry'; tokS := r->>'token';
  assert not exists(select 1 from app_login_attempts where uname='supa'), 'attempts reset on success';

  -- 3) الجلسة
  r := app_session_check(tokS); assert (r->>'ok')::boolean and r->'user'->>'role'='supervisor', 'session ok';
  assert not (app_session_check('x'||tokS)->>'ok')::boolean, 'bad token rejected';
  assert not (r->'user' ? 'password_hash'), 'no hash in user json';
  r := app_login('teachA','teachpw','staff'); tokT := r->>'token'; assert (r->>'ok')::boolean, 'teacher login';
  r := app_login('supB','suppass2','staff'); tokB := r->>'token';

  -- 4) إنشاء موظف وصلاحياته
  r := app_create_user(tokS,'employee','emp1','emppass1','موظف',null,null,'{"students":true,"hack":true,"reports":"yes"}'::jsonb);
  assert (r->>'ok')::boolean, 'create employee '||r::text; empid := (r->>'id')::uuid;
  assert (select perms from users where id=empid) = '{"students": true}'::jsonb, 'perms sanitized: '||(select perms::text from users where id=empid);
  r := app_create_user(tokT,'employee','emp2','emppass1','x'); assert r->>'error'='forbidden', 'teacher cannot create employee';
  r := app_login('emp1','emppass1','staff'); assert (r->>'ok')::boolean, 'employee login'; tokE := r->>'token';
  r := app_create_user(tokE,'student','stuNew','pw1234','طالب جديد'); assert (r->>'ok')::boolean, 'employee with students perm creates student';
  r := app_create_user(tokE,'teacher','tNew','pw1234','معلم جديد'); assert r->>'error'='forbidden', 'employee without halaqat perm cannot create teacher';
  r := app_create_user(tokE,'student','stuNew','pw1234','طالب جديد'); assert r->>'error'='username_taken', 'dup username';
  r := app_create_user(tokE,'student','stuNew','pw1234','طالب جديد',null,null,null,true); assert (r->>'ok')::boolean and (r->>'existed')::boolean, 'reuse';
  r := app_create_user(tokS,'supervisor','supX','pw1234','x'); assert r->>'error'='forbidden', 'supervisor cannot create supervisor';
  r := app_create_user(tokS,'student','ab','pw1234','x'); assert r->>'error'='bad_username';
  r := app_create_user(tokS,'student','okname','12','x'); assert r->>'error'='weak_password';
  r := app_update_staff(tokS, empid::text, 'موظف معدّل', '{"students":true,"halaqat":true}', 'active'); assert (r->>'ok')::boolean, 'update staff';
  r := app_create_user(tokE,'teacher','tNew','pw1234','معلم جديد'); assert (r->>'ok')::boolean, 'employee now creates teacher';
  r := app_list_staff(tokS); assert jsonb_array_length(r->'rows')=1, 'list staff';
  r := app_list_staff(tokE); assert r->>'error'='forbidden', 'employee cannot list staff';
  r := app_update_staff(tokS, empid::text, null, null, 'disabled');
  assert not (app_session_check(tokE)->>'ok')::boolean, 'disabled employee session dies';
  r := app_login('emp1','emppass1','staff'); assert r->>'error'='disabled', 'disabled employee cannot login';
  r := app_update_staff(tokS, empid::text, null, null, 'active');
  r := app_login('emp1','emppass1','staff'); assert (r->>'ok')::boolean; tokE := r->>'token';

  -- 5) تغيير بيانات الدخول
  r := app_save_credentials(tokS,'teacher',tid::text,null,'teachA','newpass99'); assert (r->>'ok')::boolean, 'supervisor sets teacher pw '||r::text;
  assert not (app_session_check(tokT)->>'ok')::boolean, 'teacher old sessions killed after pw change';
  r := app_login('teachA','teachpw','staff'); assert r->>'error'='invalid', 'old teacher pw rejected';
  r := app_login('teachA','newpass99','staff'); assert (r->>'ok')::boolean; tokT := r->>'token';
  r := app_save_credentials(tokB,'student',stuid::text,null,null,'hacked12'); assert r->>'error'='forbidden', 'other center supervisor blocked';
  r := app_save_credentials(tokT,'student',stuid::text,null,null,'stupw22'); assert (r->>'ok')::boolean, 'teacher sets own student pw';
  r := app_save_credentials(tokT,'student',stuB::text,null,null,'hacked12'); assert r->>'error'='forbidden', 'teacher blocked from other center student';
  insert into halaqat(id, center_id, name) values ('hq_9', cA, 'x');
  r := app_save_credentials(tokT,'teacher',tid::text,null,'teachA','x'); assert r->>'error'='weak_password';
  r := app_save_credentials(tokT,'student',null,'stuA','stuA2',null); assert (r->>'ok')::boolean, 'upsert by old username (rename)';
  assert exists(select 1 from users where username='stuA2'), 'renamed';
  r := app_save_credentials(tokT,'student',null,'nobody','stuC','pw1234','طالب ج'); assert (r->>'ok')::boolean and (r->>'created')::boolean, 'upsert creates';
  r := app_save_credentials(tokS,'supervisor',sid::text,null,'supB','pw1234'); assert r->>'error'='username_taken', 'rename collision';
  r := app_username_taken(tokS,'STUC',null); assert (r->>'taken')::boolean, 'taken case-insens';
  r := app_username_taken(tokS,'stuC','stuC'); assert not (r->>'taken')::boolean, 'excluded own';
  r := app_username_taken(tokB,'stuC',null); assert not (r->>'taken')::boolean, 'other center cannot see';

  -- 6) تسجيل ذاتي ذرّي + موافقة المعلمين
  r := app_register_center('مركز ج','مشرف ج','supC','secret1'); assert (r->>'ok')::boolean, 'register center';
  assert (select status from centers where name='مركز ج')='pending' and (select status from users where username='supC')='pending';
  r := app_login('supC','secret1','staff'); assert r->>'error'='pending', 'pending supervisor blocked';
  r := app_register_center('مركز د','مشرف د','supC','secret1'); assert r->>'error'='username_taken';
  assert not exists(select 1 from centers where name='مركز د'), 'no orphan center on failure';
  r := app_register_center('مركز د','مشرف د','supD','123'); assert r->>'error'='weak_password';
  assert not exists(select 1 from centers where name='مركز د'), 'no orphan center on weak pw';
  r := app_register_teacher(cA::text,'newT','secret1','معلم جديد'); assert (r->>'ok')::boolean, 'register teacher by id: '||r::text; 
  r := app_register_teacher('مركز أ','newT2','secret1','معلم 2'); assert (r->>'ok')::boolean, 'register teacher by name';
  r := app_register_teacher('x'',id.eq.1','newT3','secret1','معلم 3'); assert r->>'error'='no_center', 'injection-like code harmless';
  r := app_pending_teachers(tokS); assert jsonb_array_length(r->'rows')=2, 'pending 2: '||r::text;
  r := app_pending_teachers(tokT); assert r->>'error'='forbidden', 'teacher cannot list pending';
  r := app_approve_teacher(tokS, (select id::text from users where username='newT'), 'hq_9'); assert (r->>'ok')::boolean, 'approve';
  r := app_approve_teacher(tokB, (select id::text from users where username='newT2'), 'hq_9'); assert r->>'error'='forbidden' or r->>'error'='not_found', 'other center cannot approve';
  r := app_reject_teacher(tokS, (select id::text from users where username='newT2')); assert (r->>'ok')::boolean, 'reject';
  assert not exists(select 1 from users where username='newT2'), 'rejected deleted';
  r := app_login('newT','secret1','staff'); assert (r->>'ok')::boolean, 'approved teacher logs in';
  r := app_link_my_halaqa(tokT,'hq_2'); assert r->>'error'='not_yours', 'cannot link foreign halaqa';
  r := app_link_my_halaqa(tokT,'hq_1'); assert (r->>'ok')::boolean, 'link own halaqa';

  -- 7) حذف حسابات
  r := app_delete_users(tokT, array[stuB::text]); assert r->>'error'='forbidden', 'teacher cannot delete other center student';
  r := app_delete_users(tokB, array[stuid::text]); assert r->>'error'='forbidden', 'other supervisor cannot delete';
  delete from students where id='s1';
  r := app_delete_users(tokT, array[stuid::text]); assert (r->>'ok')::boolean and (r->>'deleted')::int=1, 'teacher deletes own student account';
  r := app_delete_users(tokS, array[sid::text]); assert (r->>'deleted')::int=0, 'cannot delete self';

  -- 8) المالك
  r := app_masool_supervisors(tokS); assert r->>'error'='forbidden';
  r := app_masool_supervisors(tokM); assert jsonb_array_length(r->'rows')>=3, 'masool lists supervisors';
  r := app_masool_set_center_status(tokM, (select id::text from centers where name='مركز ج'), 'active'); assert (r->>'ok')::boolean;
  r := app_login('supC','secret1','staff'); assert (r->>'ok')::boolean, 'approved center supervisor logs in';
  r := app_masool_set_center_status(tokS, cA::text, 'rejected'); assert r->>'error'='forbidden', 'supervisor cannot change center status';
  insert into halaqat(id, center_id, name) values ('hq_B1', cB, 'ب'); insert into records(id, center_id) values ('r1', cB);
  r := app_masool_delete_center(tokS, cB::text); assert r->>'error'='forbidden';
  r := app_masool_delete_center(tokM, cB::text); assert (r->>'ok')::boolean, 'masool deletes center '||r::text;
  assert not exists(select 1 from users where center_id=cB) and not exists(select 1 from halaqat where center_id=cB) and not exists(select 1 from centers where id=cB), 'cascade clean';
  assert not (app_session_check(tokB)->>'ok')::boolean, 'deleted center sessions gone';
  r := app_save_credentials(tokM,'supervisor',sid::text,null,null,'ownerset1',null,null,false); assert (r->>'ok')::boolean, 'masool resets supervisor pw';

  assert not (app_session_check(tokS)->>'ok')::boolean, 'supervisor sessions killed after masool reset';
  r := app_login('supA','ownerset1','staff'); assert (r->>'ok')::boolean, 'new pw works'; tokS := r->>'token';
  -- 9) سجل التعديلات
  r := app_audit_add(tokT,'student.delete','student','s1','طالب',jsonb_build_object('x',1)); assert (r->>'ok')::boolean;
  r := app_audit_add(tokE,'student.add','student','s2','طالب 2'); assert (r->>'ok')::boolean;
  r := app_audit_list(tokS,50,null); assert jsonb_array_length(r->'rows')=2, 'audit list: '||r::text;
  r := app_audit_list(tokT,50,null); assert r->>'error'='forbidden', 'teacher cannot read audit';
  r := app_audit_list(tokM,50,null); assert r->>'error'='forbidden', 'masool has no center audit';


  -- 11) قراءة حسابات + حذف معلمي حلقة
  r := app_login('supA','ownerset1','staff'); tokS := r->>'token';
  r := app_accounts_by_ids(tokS, array[tid::text, stuB::text]); assert (r->>'ok')::boolean and jsonb_array_length(r->'rows')=1, 'accounts_by_ids same-center only: '||r::text;
  assert not (r->'rows'->0 ? 'password_hash'), 'no hash in accounts';
  r := app_accounts_by_ids(tokE, array[tid::text]); assert (r->>'ok')::boolean, 'employee can read accounts';
  r := app_teacher_accounts(tokS); assert (r->>'ok')::boolean and jsonb_array_length(r->'rows')>=1, 'teacher accounts: '||r::text;
  r := app_teacher_accounts('bad-token-bad-token-bad'); assert r->>'error'='auth';
  r := app_delete_halaqa_teachers(tokT,'hq_1',array[]::text[],'teachA'); assert r->>'error'='forbidden', 'teacher cannot delete teachers';
  r := app_delete_halaqa_teachers(tokS,'hq_1',array[]::text[],'teachA'); assert (r->>'ok')::boolean and (r->>'deleted')::int=1, 'delete halaqa teacher: '||r::text;
  assert not exists(select 1 from users where username='teachA'), 'teacher gone';
  r := app_center_teachers(tokS, array['hq_9']); assert (r->>'ok')::boolean and jsonb_array_length(r->'rows')=1, 'teachers by halaqa: '||r::text;
  r := app_center_teachers(tokB, array['hq_9']); assert r->>'error'='forbidden' or r->>'error'='auth' or jsonb_array_length(r->'rows')=0, 'other center sees none';
  -- 10) خروج
  r := app_logout(tokS); assert not (app_session_check(tokS)->>'ok')::boolean, 'logout kills session';
  raise notice 'ALL FUNCTIONAL TESTS PASSED';
end $$;
