\set ON_ERROR_STOP on
set client_min_messages = notice;
set search_path = public, extensions;
do $$
declare
  cA uuid; cB uuid; uS1 uuid; uS2 uuid; uS3 uuid; tokSup text; tokTA text; tokTB text; tokS1 text; tokS2 text; tokS3 text; tokEmpY text; tokEmpN text; tokM text;
  today date := (now() at time zone 'Asia/Gaza')::date; h text := encode(digest('pw1234','sha256'),'hex');
  r jsonb; k text; catH text; catI text; catB text; mid text; gid text; m1 bigint; m2 bigint; m3 bigint; n int; i int; v_op text := gen_random_uuid()::text; bad text;
begin
  insert into centers(name, manager_name, status) values ('مركز أ','م','active') returning id into cA;
  insert into centers(name, manager_name, status) values ('مركز ب','م','active') returning id into cB;
  insert into halaqat(id, center_id, name) values ('hA1', cA, 'حلقة 1'), ('hA2', cA, 'حلقة 2');
  insert into users(role, username, password_hash, full_name) values ('masool','owner',h,'المالك');
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'supervisor','supA',h,'مشرف'), (cB,'supervisor','supB',h,'مشرف ب');
  insert into users(center_id, role, username, password_hash, full_name, halaqa_id) values (cA,'teacher','tA',h,'معلم 1','hA1'), (cA,'teacher','tB',h,'معلم 2','hA2');
  insert into users(center_id, role, username, password_hash, full_name, perms) values (cA,'employee','empY',h,'موظف',' {"messages":true}'::jsonb), (cA,'employee','empN',h,'موظف2','{"reports":true}');
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'student','stu1',h,'طالب 1') returning id into uS1;
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'student','stu2',h,'طالب 2') returning id into uS2;
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'student','stu3',h,'طالب 3') returning id into uS3;
  insert into students(id, halaqa_id, user_id, name) values ('s1','hA1',uS1,'أحمد'),('s2','hA1',uS2,'بلال'),('s3','hA2',uS3,'جاسم');
  tokSup := app_login('supA','pw1234','staff')->>'token'; tokTA := app_login('tA','pw1234','staff')->>'token'; tokTB := app_login('tB','pw1234','staff')->>'token';
  tokEmpY := app_login('empY','pw1234','staff')->>'token'; tokEmpN := app_login('empN','pw1234','staff')->>'token'; tokM := app_login('owner','pw1234','staff')->>'token';
  tokS1 := app_login('stu1','pw1234','student')->>'token'; tokS2 := app_login('stu2','pw1234','student')->>'token'; tokS3 := app_login('stu3','pw1234','student')->>'token';

  -- ===== الحد اليومي =====
  r := comp_save(tokTA, jsonb_build_object('name','مسابقة الحد اليومي','start_date',today-6,'end_date',today+20,'halaqa_ids',jsonb_build_array('hA1'),
        'participants',jsonb_build_array(jsonb_build_object('student_id','s1'),jsonb_build_object('student_id','s2')))); k := r->>'id';
  assert (r->>'ok')::boolean, 'create'; assert (comp_set_status(tokTA,k,'active')->>'ok')::boolean, 'activate';
  select (c->>'id') into catH from jsonb_array_elements(comp_get(tokTA,k)->'categories') c where c->>'key'='hifz';
  select (c->>'id') into catI from jsonb_array_elements(comp_get(tokTA,k)->'categories') c where c->>'key'='itqan';
  select (c->>'id') into catB from jsonb_array_elements(comp_get(tokTA,k)->'categories') c where c->>'key'='bonus';
  r := comp_get(tokTA,k); assert (select (c->>'daily_max')::numeric from jsonb_array_elements(r->'categories') c where c->>'key'='hifz') = 5, 'default daily = weekly/5';
  assert (select (c->>'daily_max')::numeric from jsonb_array_elements(comp_grid(tokTA,k,null)->'categories') c where c->>'key'='hifz') = 5, 'grid exposes daily_max';
  r := comp_eval_save(tokTA,k,(today-1)::text,jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',6)));
  assert r->'results'->0->>'status'='daily_cap' and (r->'results'->0->>'daily_max')::numeric=5, 'daily cap enforced: '||r::text;
  r := comp_eval_save(tokTA,k,(today-1)::text,jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',5)));
  assert r->'results'->0->>'status'='saved', 'within daily limit saved';
  r := comp_save(tokTA, jsonb_build_object('id',k,'name','مسابقة الحد اليومي','start_date',today-6,'end_date',today+20,'halaqa_ids',jsonb_build_array('hA1'),
        'categories',(select jsonb_agg(case when c->>'key'='hifz' then c || jsonb_build_object('daily_max_points',8) else c end) from jsonb_array_elements(comp_get(tokTA,k)->'categories') c)));
  assert (r->>'ok')::boolean, 'custom daily saved: '||r::text;
  assert (select (c->>'daily_max')::numeric from jsonb_array_elements(comp_get(tokTA,k)->'categories') c where c->>'key'='hifz') = 8, 'custom daily 8';
  r := comp_eval_save(tokTA,k,(today-2)::text,jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',8)));
  assert r->'results'->0->>'status'='saved', 'custom daily limit allows 8';
  r := comp_save(tokTA, jsonb_build_object('id',k,'name','مسابقة الحد اليومي','start_date',today-6,'end_date',today+20,'halaqa_ids',jsonb_build_array('hA1'),
        'categories',(select jsonb_agg(case when c->>'key'='hifz' then c || jsonb_build_object('daily_max_points',99) else c end) from jsonb_array_elements(comp_get(tokTA,k)->'categories') c)));
  assert r->>'error'='bad_points', 'daily above weekly rejected';

  -- ===== تعديل لعدة طلاب ومجالات =====
  r := comp_adjust_many(tokTA,k,array['s1','s2'],array[catI,catB],2,'مكافأة جماعية',null,gen_random_uuid()::text);
  assert (r->>'ok')::boolean and (r->>'saved')::int = 4 and jsonb_array_length(r->'results') = 4, 'adjust_many 2x2: '||r::text;
  assert (select count(*) from competition_score_audit where competition_id::text=k and action_type='adjust') = 4, 'adjust_many audited';
  r := comp_adjust_many(tokTA,k,array['s1','s3'],array[catI],1,'اختبار',null,null);
  assert (select count(*) from jsonb_array_elements(r->'results') x where x->>'status'='not_participant') = 1 and (r->>'saved')::int = 1, 'non participant skipped';
  r := comp_adjust_many(tokTA,k,array['s1'],array[catI],-50,'خصم كبير',null,null); assert r->'results'->0->>'status'='below_zero', 'below zero';
  r := comp_adjust_many(tokS1,k,array['s1'],array[catI],5,'غش',null,null); assert r->>'error'='forbidden', 'student cannot adjust_many';
  r := comp_adjust_many(tokTB,k,array['s1'],array[catI],5,'خارج',null,null); assert r->>'error'='forbidden', 'other teacher cannot';
  r := comp_adjust_many(tokTA,k,array['s1'],array[catI],1,'',null,null); assert r->>'error'='reason_required';
  v_op := gen_random_uuid()::text; r := comp_adjust_many(tokTA,k,array['s2'],array[catI],1,'مرتين',null,v_op); n := (select count(*) from competition_scores);
  r := comp_adjust_many(tokTA,k,array['s2'],array[catI],1,'مرتين',null,v_op); assert (r->>'duplicate')::boolean and (select count(*) from competition_scores) = n, 'adjust_many idempotent';

  -- ===== المحادثة: رسائل نصية وردود وتعديل وحذف =====
  r := chat2_send(tokS1,'s:s1','text','السلام عليكم',null,null,gen_random_uuid()::text); assert (r->>'ok')::boolean, 'student sends'; m1 := (r->>'id')::bigint;
  r := chat2_send(tokS1,'s:s2','text','x',null,null,null); assert r->>'error'='forbidden', 'student cannot post in other thread';
  r := chat2_threads(tokTA); assert (r->>'unread')::int = 1 and jsonb_array_length(r->'rows') = 1, 'teacher sees 1 unread: '||r::text;
  assert (chat2_unread(tokTA)->>'unread')::int = 1 and (chat2_unread(tokTB)->>'unread')::int = 0, 'unread counts per user';
  r := chat2_get(tokTB,'s:s1'); assert r->>'error'='forbidden', 'other teacher cannot read';
  r := chat2_get(tokTA,'s:s1'); assert jsonb_array_length(r->'rows') = 1 and (chat2_unread(tokTA)->>'unread')::int = 0, 'read clears unread';
  r := chat2_send(tokTA,'s:s1','text','وعليكم السلام',null,m1); assert (r->>'ok')::boolean, 'teacher replies with reply_to'; m2 := (r->>'id')::bigint;
  r := chat2_get(tokS1,'s:s1'); assert r->'rows'->1->'reply'->>'id' = m1::text and r->'rows'->1->'reply'->>'body' like 'السلام%', 'reply preview returned';
  assert (chat2_unread(tokS1)->>'unread')::int = 0, 'student unread cleared after get';
  r := chat2_send(tokTA,'s:s1','text','سؤال',null,999999); assert r->>'error'='bad_reply', 'invalid reply target';
  r := chat2_edit(tokS1, m1, 'السلام عليكم ورحمة الله'); assert (r->>'ok')::boolean, 'edit own';
  assert (chat2_get(tokTA,'s:s1')->'rows'->0->>'edited_at') is not null, 'edited flag';
  r := chat2_edit(tokS1, m2, 'تعديل رسالة غيري'); assert r->>'error'='forbidden', 'cannot edit others';
  r := chat2_edit(tokTB, m1, 'x'); assert r->>'error'='forbidden', 'outsider cannot edit';
  r := chat2_delete(tokS1, m2); assert r->>'error'='forbidden', 'student cannot delete teacher message';
  r := chat2_delete(tokTA, m1); assert (r->>'ok')::boolean, 'teacher moderates student message';
  r := chat2_get(tokS1,'s:s1'); assert (r->'rows'->0->>'deleted')::boolean and r->'rows'->0->>'body' = '', 'deleted shown as tombstone without body';
  r := chat2_clear(tokS1,'s:s1',true); assert r->>'error'='forbidden', 'student cannot delete for everyone';
  r := chat2_clear(tokS1,'s:s1',false); assert (r->>'ok')::boolean, 'student clears own view';
  assert jsonb_array_length(chat2_get(tokS1,'s:s1')->'rows') = 0, 'cleared view empty for student';
  assert jsonb_array_length(chat2_get(tokTA,'s:s1')->'rows') = 2, 'teacher still sees conversation';
  r := chat2_clear(tokTA,'s:s1',true); assert (r->>'deleted')::int = 2, 'teacher deletes conversation for everyone';
  assert (select count(*) from student_chat where student_id='s1') = 0, 'hard deleted';

  -- ===== مجموعة لجميع الطلاب =====
  r := chat2_group_save(tokTA, null, 'مجموعة الحلقة', null, true); assert (r->>'ok')::boolean, 'teacher creates group: '||r::text; gid := r->>'id';
  assert (select halaqa_id from chat_groups where id::text = gid) = 'hA1', 'teacher group scoped to own halaqa';
  r := chat2_group_save(tokS1, null, 'اختراق', null, true); assert r->>'error'='forbidden', 'student cannot create group';
  r := chat2_group_save(tokEmpN, null, 'اختراق', null, true); assert r->>'error'='forbidden', 'employee without messages perm cannot';
  r := chat2_group_save(tokEmpY, null, 'مجموعة المركز', 'hA2', true); assert (r->>'ok')::boolean, 'employee with perm creates group';
  r := chat2_threads(tokS1); assert r->'rows'->0->>'key' = 's:s1' and (select count(*) from jsonb_array_elements(r->'rows') x where x->>'kind'='g') = 1 and (select (x->>'pinned')::boolean from jsonb_array_elements(r->'rows') x where x->>'kind'='g'), 'student sees own halaqa group pinned';
  r := chat2_threads(tokS3); assert (select count(*) from jsonb_array_elements(r->'rows') x where x->>'kind'='g') = 1, 'other halaqa student sees only its group';
  r := chat2_get(tokS3,'g:'||gid); assert r->>'error'='forbidden', 'other halaqa cannot read group';
  r := chat2_send(tokTA,'g:'||gid,'text','أهلاً بكم في المجموعة'); assert (r->>'ok')::boolean, 'teacher posts to group';
  r := chat2_send(tokS2,'g:'||gid,'text','شكراً يا شيخ'); assert (r->>'ok')::boolean, 'student posts when allowed'; m3 := (r->>'id')::bigint;
  assert (chat2_unread(tokS1)->'threads'->>('g:'||gid))::int = 2, 'group unread for another student';
  r := chat2_get(tokS1,'g:'||gid); assert jsonb_array_length(r->'rows') = 2 and (chat2_unread(tokS1)->>'unread')::int = 0, 'group read clears for me only';
  assert (chat2_unread(tokS2)->>'unread')::int = 1, 'other member still has unread (teacher msg)';
  r := chat2_group_save(tokTA, gid, 'مجموعة الحلقة', null, false); assert (r->>'ok')::boolean, 'lock group';
  r := chat2_send(tokS2,'g:'||gid,'text','x'); assert r->>'error'='read_only', 'students cannot post when locked';
  r := chat2_send(tokTA,'g:'||gid,'text','إعلان'); assert (r->>'ok')::boolean, 'teacher can still post';
  r := chat2_delete(tokTA, m3); assert (r->>'ok')::boolean, 'teacher moderates group message';
  r := chat2_group_save(tokTB, gid, 'سرقة', null, true); assert r->>'error' in ('forbidden','not_found'), 'other teacher cannot edit group';
  r := chat2_group_delete(tokS1, gid); assert r->>'error'='forbidden', 'student cannot delete group';

  -- ===== ترتيب المحادثات =====
  r := chat2_prefs_set(tokS1, jsonb_build_array('g:'||gid,'s:s1')); assert (r->>'ok')::boolean;
  assert chat2_threads(tokS1)->'order'->>0 = 'g:'||gid, 'prefs order returned';
  r := chat2_prefs_set(tokS1, '{"a":1}'::jsonb); assert r->>'error'='bad_items';

  -- ===== الوسائط (رفع مجزّأ) =====
  r := chat2_media_start(tokS1,'s:s1','image','image/jpeg','a.jpg',300,2); assert (r->>'ok')::boolean, 'media start: '||r::text; mid := r->>'id';
  r := chat2_media_finish(tokS1, mid); assert r->>'error'='incomplete', 'finish needs all chunks';
  assert (chat2_media_chunk(tokS1, mid, 0, 'AAAA')->>'ok')::boolean and (chat2_media_chunk(tokS1, mid, 1, 'BBBB')->>'ok')::boolean, 'chunks stored';
  r := chat2_media_chunk(tokS1, mid, 5, 'CCCC'); assert r->>'error'='bad_media', 'chunk index validated';
  r := chat2_media_chunk(tokS2, mid, 0, 'ZZZZ'); assert r->>'error'='not_found', 'other user cannot write chunks';
  r := chat2_send(tokS1,'s:s1','image','',mid); assert r->>'error'='bad_media', 'cannot send before complete';
  assert (chat2_media_finish(tokS1, mid)->>'ok')::boolean, 'finish ok';
  r := chat2_send(tokS2,'s:s2','image','',mid); assert r->>'error'='bad_media', 'cannot reuse another owner media';
  r := chat2_send(tokS1,'s:s1','video','',mid); assert r->>'error'='bad_media', 'kind must match';
  r := chat2_send(tokS1,'s:s1','image','صورة',mid); assert (r->>'ok')::boolean, 'media message sent';
  r := chat2_get(tokTA,'s:s1'); assert r->'rows'->0->'media'->>'kind'='image' and r->'rows'->0->>'media_id' = mid, 'teacher sees media meta';
  r := chat2_media_get(tokTA, mid, 1); assert (r->>'ok')::boolean and r->>'data'='BBBB', 'teacher downloads chunk';
  r := chat2_media_get(tokTB, mid, 0); assert r->>'error'='forbidden', 'other teacher cannot download';
  r := chat2_media_get(tokS3, mid, 0); assert r->>'error'='forbidden', 'other student cannot download';
  r := chat2_media_start(tokS1,'s:s1','video','video/mp4','v.mp4',30000000,10); assert r->>'error'='too_big', 'video size limit';
  r := chat2_media_start(tokS1,'s:s1','audio','audio/webm','a.webm',0,1); assert r->>'error'='too_big', 'empty size rejected';
  r := chat2_media_start(tokS1,'g:'||gid,'audio','audio/webm','a.webm',100,1); assert r->>'error'='read_only', 'media blocked in locked group';
  r := chat2_media_start(tokS1,'s:s2','audio','audio/webm','a.webm',100,1); assert r->>'error'='forbidden', 'media to other thread forbidden';
  r := chat2_get(tokS1,'s:s1'); m1 := (r->'rows'->0->>'id')::bigint;
  r := chat2_delete(tokS1, m1); assert (r->>'ok')::boolean and not exists(select 1 from chat_media where id::text = mid), 'deleting a media message removes the media';
  r := chat2_media_start(tokS2,'s:s2','audio','audio/webm','a.webm',100,1); mid := r->>'id'; perform chat2_media_chunk(tokS2, mid, 0, 'QQ'); perform chat2_media_finish(tokS2, mid);
  r := chat2_send(tokS2,'s:s2','audio','',mid); assert (r->>'ok')::boolean, 'voice message';
  r := chat2_clear(tokTA,'s:s2',true); assert (r->>'ok')::boolean and not exists(select 1 from chat_media where thread_key = 's:s2'), 'conversation delete removes media';

  -- ===== الأمان =====
  foreach bad in array array['chat_groups','chat_reads','chat_prefs','chat_media','chat_media_chunks','student_chat'] loop
    assert not has_table_privilege('anon','public.'||bad,'select') and not has_table_privilege('anon','public.'||bad,'insert')
       and not has_table_privilege('anon','public.'||bad,'update') and not has_table_privilege('anon','public.'||bad,'delete'), 'anon locked: '||bad;
  end loop;
  assert not has_function_privilege('anon','public._chat2_ctx(public.users,text)','execute') and has_function_privilege('anon','public.chat2_get(text,text,integer)','execute'), 'rpc exposure';
  assert not exists(select 1 from pg_proc p where p.proname = 'comp_adjust_many' and has_function_privilege('public', p.oid, 'execute')), 'adjust_many not public-executable';
  r := chat2_group_save(tokSup, null, 'مجموعة كل المركز', null, true); assert (r->>'ok')::boolean and (select halaqa_id from chat_groups where id::text = r->>'id') is null, 'supervisor center-wide group';
  r := chat2_send(tokS3,'g:'||(r->>'id'),'text','أنا من حلقة أخرى'); assert (r->>'ok')::boolean, 'center-wide group reachable by all students';
  r := comp_save(tokSup, jsonb_build_object('name','مسابقة ب','start_date',today,'end_date',today+9,'halaqa_ids',jsonb_build_array('hA1'))); 
  r := app_masool_delete_center(tokM, cA::text); assert (r->>'ok')::boolean, 'masool deletes center';
  assert not exists(select 1 from chat_groups where center_id = cA::text) and not exists(select 1 from student_chat where center_id = cA::text) and not exists(select 1 from competitions where center_id = cA::text), 'cascade clean incl. chat groups';
  raise notice 'ALL CHAT2 / DAILY-LIMIT TESTS PASSED';
end $$;
