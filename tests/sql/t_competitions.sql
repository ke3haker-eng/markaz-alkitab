\set ON_ERROR_STOP on
set client_min_messages = notice;
set search_path = public, extensions;
do $$
declare
  cA uuid; cB uuid; uS1 uuid; uS2 uuid; uS3 uuid; uSB uuid;
  tokSup text; tokTA text; tokTB text; tokEmp text; tokEmp2 text; tokS1 text; tokS2 text; tokS3 text; tokSupB text; tokM text;
  today date := (now() at time zone 'Asia/Gaza')::date;
  r jsonb; k1 text; k2 text; k3 text; cats jsonb; catH text; catI text; catB text; catA text; n int; v_op text := gen_random_uuid()::text;
  sc1 text; ver1 int; asg text; q1 text; q2 text; q3 text; bad text;
  h text := encode(digest('pw1234','sha256'),'hex');
begin
  -- ===== الإعداد =====
  insert into centers(name, manager_name, status) values ('مركز أ','م','active') returning id into cA;
  insert into centers(name, manager_name, status) values ('مركز ب','م','active') returning id into cB;
  insert into halaqat(id, center_id, name) values ('hA1', cA, 'حلقة 1'), ('hA2', cA, 'حلقة 2'), ('hB1', cB, 'حلقة ب');
  insert into users(role, username, password_hash, full_name) values ('masool','owner',h,'المالك');
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'supervisor','supA',h,'مشرف أ');
  insert into users(center_id, role, username, password_hash, full_name) values (cB,'supervisor','supB',h,'مشرف ب');
  insert into users(center_id, role, username, password_hash, full_name, halaqa_id) values (cA,'teacher','tA',h,'معلم 1','hA1'), (cA,'teacher','tB',h,'معلم 2','hA2');
  insert into users(center_id, role, username, password_hash, full_name, perms) values (cA,'employee','empYes',h,'موظف نعم','{"competitions":true,"messages":true}'), (cA,'employee','empNo',h,'موظف لا','{"reports":true}');
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'student','stu1',h,'طالب 1') returning id into uS1;
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'student','stu2',h,'طالب 2') returning id into uS2;
  insert into users(center_id, role, username, password_hash, full_name) values (cA,'student','stu3',h,'طالب 3') returning id into uS3;
  insert into users(center_id, role, username, password_hash, full_name) values (cB,'student','stuB',h,'طالب ب') returning id into uSB;
  insert into students(id, halaqa_id, user_id, name) values ('s1','hA1',uS1,'أحمد'), ('s2','hA1',uS2,'بلال'), ('s3','hA2',uS3,'جاسم'), ('sB','hB1',uSB,'طالب ب');
  tokSup := app_login('supA','pw1234','staff')->>'token'; tokTA := app_login('tA','pw1234','staff')->>'token'; tokTB := app_login('tB','pw1234','staff')->>'token';
  tokEmp := app_login('empYes','pw1234','staff')->>'token'; tokEmp2 := app_login('empNo','pw1234','staff')->>'token';
  tokS1 := app_login('stu1','pw1234','student')->>'token'; tokS2 := app_login('stu2','pw1234','student')->>'token'; tokS3 := app_login('stu3','pw1234','student')->>'token';
  tokSupB := app_login('supB','pw1234','staff')->>'token'; tokM := app_login('owner','pw1234','staff')->>'token';

  -- ===== 1) إنشاء مسابقة =====
  r := comp_defaults(tokTA); assert jsonb_array_length(r->'categories') = 10, 'defaults 10 cats';
  r := comp_save(tokTA, jsonb_build_object('name','دوري فرسان القرآن','description','30 يوماً','start_date',today-10,'end_date',today+19,
        'halaqa_ids',jsonb_build_array('hA1'),'participants',jsonb_build_array(jsonb_build_object('student_id','s1','level','متقدم'),jsonb_build_object('student_id','s2'))));
  assert (r->>'ok')::boolean, 'teacher creates for own halaqa: '||r::text; k1 := r->>'id';
  r := comp_get(tokTA, k1); assert jsonb_array_length(r->'categories') = 10 and jsonb_array_length(r->'participants') = 2, 'default cats + 2 participants';
  assert (select count(*) from competition_categories where competition_id::text = k1 and kind='core') = 9, '9 core cats';
  assert (select sum(weekly_max_points) from competition_categories where competition_id::text = k1 and kind='core') = 100, 'core total 100';
  r := comp_save(tokTA, jsonb_build_object('name','xy','start_date',today,'end_date',today+5,'halaqa_ids',jsonb_build_array('hA2'))); assert r->>'error'='forbidden', 'teacher cannot create for other halaqa';
  r := comp_save(tokTA, jsonb_build_object('name','xx','start_date',today,'end_date',today+5,'halaqa_ids',jsonb_build_array('hA1','hA2'))); assert r->>'error'='forbidden', 'teacher cannot create multi-halaqa';
  r := comp_save(tokTA, jsonb_build_object('name','xx','start_date',today+5,'end_date',today,'halaqa_ids',jsonb_build_array('hA1'))); assert r->>'error'='bad_dates';
  r := comp_save(tokTA, jsonb_build_object('name','xx','start_date',today,'end_date',today+5,'halaqa_ids',jsonb_build_array('hB1'))); assert r->>'error'='bad_halaqa', 'foreign center halaqa rejected';
  r := comp_save(tokTA, jsonb_build_object('name','xx','start_date',today,'end_date',today+5,'halaqa_ids',jsonb_build_array('hA1'),'participants',jsonb_build_array(jsonb_build_object('student_id','s3'))));
  assert r->>'error'='student_not_found', 'student of another halaqa rejected: '||r::text;
  assert (select count(*) from competitions where name='xx') = 0, 'failed create left nothing';
  r := comp_save(tokS1, jsonb_build_object('name','hack','start_date',today,'end_date',today+5,'halaqa_ids',jsonb_build_array('hA1'))); assert r->>'error'='forbidden', 'student cannot create';
  r := comp_save(tokEmp2, jsonb_build_object('name','hack','start_date',today,'end_date',today+5,'halaqa_ids',jsonb_build_array('hA1'))); assert r->>'error'='forbidden', 'employee without perm cannot';
  r := comp_save(tokEmp, jsonb_build_object('name','مسابقة موظف','start_date',today+60,'end_date',today+80,'halaqa_ids',jsonb_build_array('hA1','hA2'))); assert (r->>'ok')::boolean, 'employee with perm can'; k3 := r->>'id';

  -- ===== 2) الطالب لا يرى المسودة، التفعيل =====
  r := comp_list(tokS1); assert jsonb_array_length(r->'rows') = 0, 'student sees no draft';
  r := comp_get(tokS1, k1); assert r->>'error'='forbidden', 'student cannot get draft';
  r := comp_set_status(tokTB, k1, 'active'); assert r->>'error'='forbidden', 'other teacher cannot activate';
  r := comp_set_status(tokTA, k1, 'active'); assert (r->>'ok')::boolean, 'activate: '||r::text;
  r := comp_save(tokTA, jsonb_build_object('name','تداخل','start_date',today,'end_date',today+10,'halaqa_ids',jsonb_build_array('hA1'),'participants',jsonb_build_array(jsonb_build_object('student_id','s1'))));
  k2 := r->>'id'; r := comp_set_status(tokTA, k2, 'active'); assert r->>'error'='overlap', 'overlap blocked: '||r::text;
  r := comp_list(tokS1); assert jsonb_array_length(r->'rows') = 1 and r->'rows'->0->>'state' = 'running', 'student sees running competition';
  r := comp_list(tokS3); assert jsonb_array_length(r->'rows') = 0, 'non participant sees nothing';
  r := comp_list(tokTB); assert not exists(select 1 from jsonb_array_elements(r->'rows') x where x->>'id' = k1), 'other halaqa teacher does not see it';
  r := comp_delete(tokTA, k2); assert (r->>'ok')::boolean, 'delete draft';

  select (jsonb_path_query_first(comp_get(tokTA,k1)->'categories', '$[*] ? (@.key == "hifz")')->>'id'),
         (jsonb_path_query_first(comp_get(tokTA,k1)->'categories', '$[*] ? (@.key == "itqan")')->>'id'),
         (jsonb_path_query_first(comp_get(tokTA,k1)->'categories', '$[*] ? (@.key == "bonus")')->>'id'),
         (jsonb_path_query_first(comp_get(tokTA,k1)->'categories', '$[*] ? (@.key == "attendance")')->>'id') into catH, catI, catB, catA;

  -- ===== 3) التقييم اليومي =====
  r := comp_eval_save(tokTA, k1, (today-2)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',20),
         jsonb_build_object('student_id','s1','category_id',catI,'points',10),jsonb_build_object('student_id','s2','category_id',catH,'points',12)));
  assert (r->>'ok')::boolean and (r->>'saved')::int = 3, 'eval saved 3: '||r::text;
  assert (select week_number from competition_scores where student_id='s1' limit 1) = ((10-2)/7)+1, 'week number computed';
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',10)));
  assert r->'results'->0->>'status' = 'cap' and (r->'results'->0->>'remaining')::numeric = 5, 'weekly cap enforced: '||r::text;
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',5)));
  assert r->'results'->0->>'status' = 'saved', 'within cap saved';
  r := comp_eval_save(tokTA, k1, (today-2)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',15)));
  assert r->'results'->0->>'status' = 'saved', 'same day/cat updates not duplicates: '||r::text;
  assert (select count(*) from competition_scores where student_id='s1' and category_id::text=catH and evaluation_date=today-2 and not voided) = 1, 'single eval row per day/cat';
  select ver into ver1 from competition_scores where student_id='s1' and category_id::text=catH and evaluation_date=today-2;
  r := comp_eval_save(tokTA, k1, (today-2)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',14,'ver',ver1-1)));
  assert r->'results'->0->>'status' = 'conflict', 'stale version rejected';
  r := comp_eval_save(tokTA, k1, (today+3)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',1))); assert r->>'error'='out_of_window', 'future date rejected';
  r := comp_eval_save(tokTA, k1, (today-20)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catH,'points',1))); assert r->>'error'='out_of_window', 'before start rejected';
  r := comp_eval_save(tokTB, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catI,'points',1))); assert r->>'error'='forbidden', 'other halaqa teacher cannot score';
  r := comp_eval_save(tokS1, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catI,'points',1))); assert r->>'error'='forbidden', 'student cannot score';
  r := comp_eval_save(tokEmp2, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catI,'points',1))); assert r->>'error'='forbidden', 'employee without perm cannot score';
  r := comp_eval_save(tokEmp, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s2','category_id',catI,'points',3))); assert (r->>'saved')::int = 1, 'employee with perm can score';
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s3','category_id',catI,'points',3))); assert r->'results'->0->>'status'='not_participant', 'non participant rejected';
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catB,'points',3))); assert r->'results'->0->>'status'='bad_category', 'bonus category not usable in eval';
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s1','category_id',catI,'points',-2))); assert r->'results'->0->>'status'='bad_points', 'negative eval rejected';

  r := comp_grid(tokTA, k1, (today-2)::text); assert (r->>'ok')::boolean and jsonb_array_length(r->'rows') = 2 and jsonb_array_length(r->'categories') = 9, 'grid rows/cats: '||left(r::text,200);
  assert (r->'rows'->0->'cells'->catH->>'points')::numeric = 15 and (r->'rows'->0->'cells'->catH->>'used')::numeric = 20, 'grid cell points 15 used 20: '||(r->'rows'->0->'cells'->catH)::text;
  r := comp_grid(tokTB, k1, null); assert r->>'error'='forbidden', 'other teacher grid forbidden';
  r := comp_grid(tokS1, k1, null); assert r->>'error'='forbidden', 'student grid forbidden';
  -- منع التكرار بالنقر المزدوج
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s2','category_id',catA,'points',4)), v_op);
  n := (select count(*) from competition_scores); r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s2','category_id',catA,'points',4)), v_op);
  assert (r->>'duplicate')::boolean and (select count(*) from competition_scores) = n, 'idempotent op id';

  -- ===== 4) التعديل اليدوي: زيادة/خصم =====
  r := comp_adjust(tokTA, k1, 's1', catB, 2, 'صيام تطوع اختياري', null, null); assert (r->>'ok')::boolean, 'bonus +2: '||r::text;
  r := comp_adjust(tokTA, k1, 's1', catB, 2, '', null, null); assert r->>'error'='reason_required', 'reason required';
  r := comp_adjust(tokTA, k1, 's1', catB, 20, 'كثير', null, null); assert r->>'error'='cap', 'bonus weekly cap';
  r := comp_adjust(tokTA, k1, 's1', catI, -3, 'خصم لمخالفة', null, null); assert (r->>'ok')::boolean, 'deduct ok: '||r::text; sc1 := r->>'id';
  r := comp_adjust(tokTA, k1, 's1', catI, -50, 'خصم كبير', null, null); assert r->>'error'='below_zero', 'cannot go below zero';
  r := comp_adjust(tokS1, k1, 's1', catI, 5, 'تعديل ذاتي', null, null); assert r->>'error'='forbidden', 'student cannot adjust own points';
  r := comp_score_update(tokTA, sc1, -1, 'تصحيح الخصم', 1); assert (r->>'ok')::boolean, 'update score: '||r::text;
  r := comp_score_update(tokTA, sc1, -2, 'نسخة قديمة', 1); assert r->>'error'='conflict', 'optimistic conflict';
  r := comp_score_update(tokTA, sc1, -2, '', 2); assert r->>'error'='reason_required';
  r := comp_score_void(tokTB, sc1, 'محاولة'); assert r->>'error'='forbidden', 'other teacher cannot void';
  r := comp_score_void(tokTA, sc1, 'عملية خاطئة'); assert (r->>'ok')::boolean, 'void';
  r := comp_score_void(tokTA, sc1, 'عملية خاطئة'); assert r->>'error'='voided';
  r := comp_score_void(tokTA, sc1, 'استرجاع', true); assert (r->>'ok')::boolean, 'restore';
  assert (select count(*) from competition_score_audit where competition_id::text = k1 and action_type in ('create','update','void','restore','adjust')) >= 8, 'audit rows exist';
  assert exists(select 1 from competition_score_audit where score_id::text = sc1 and action_type='void' and reason='عملية خاطئة'), 'void reason audited';
  r := comp_audit_list(tokTA, k1); assert jsonb_array_length(r->'rows') >= 8, 'audit list visible to teacher';
  r := comp_audit_list(tokS1, k1); assert r->>'error'='forbidden', 'student cannot read audit';
  r := comp_audit_list(tokTB, k1); assert r->>'error'='forbidden', 'other halaqa teacher cannot read audit';

  -- ===== 5) الترتيب والتفاصيل =====
  r := comp_leaderboard(tokTA, k1);
  assert r->'rows'->0->>'name' = 'أحمد' and (r->'rows'->0->>'rank')::int = 1, 'rank 1 = أحمد: '||r::text;
  assert (r->'rows'->0->>'total')::numeric = 15+10+5+2-1, 'total points exact (15+10+5+2-1=31) got '||(r->'rows'->0->>'total');
  r := comp_leaderboard(tokS2, k1); assert jsonb_array_length(r->'rows') = 2 and (select count(*) from jsonb_array_elements(r->'rows') x where (x->>'me')::boolean) = 1, 'student sees ranking incl. self';
  r := comp_leaderboard(tokS3, k1); assert r->>'error'='forbidden', 'non participant cannot see ranking';
  r := comp_student_detail(tokS1, k1, 's2'); assert r->>'student_id'='s1', 'student detail ignores other student id';
  assert jsonb_array_length(r->'badges') >= 4 and jsonb_array_length(r->'categories') = 10 and jsonb_array_length(r->'weeks') = 5, 'detail has badges/cats/5 weeks';
  assert (select count(*) from jsonb_array_elements(r->'entries') e where (e->>'voided')::boolean) = 0, 'student sees no voided';
  r := comp_student_detail(tokTA, k1, 's3'); assert r->>'error' = 'not_participant', 'teacher detail of non participant';
  r := comp_student_detail(tokTB, k1, 's1'); assert r->>'error'='forbidden', 'other teacher cannot view detail';
  r := comp_student_detail(tokTA, k1, 's1'); assert (r->>'total')::numeric = 31 and jsonb_array_length(r->'entries') >= 5, 'teacher detail total 31';
  r := comp_report(tokTA, k1); assert jsonb_array_length(r->'students') = 2 and jsonb_array_length(r->'leaders') >= 2, 'report students+leaders';
  r := comp_report(tokTB, k1); assert r->>'error'='forbidden', 'other teacher no report';
  -- إخفاء الترتيب عن الطلاب
  r := comp_save(tokTA, jsonb_build_object('id',k1,'name','دوري فرسان القرآن','start_date',today-10,'end_date',today+19,'halaqa_ids',jsonb_build_array('hA1'),'settings',jsonb_build_object('show_ranking',false)));
  assert (r->>'ok')::boolean, 'update settings: '||r::text;
  r := comp_leaderboard(tokS2, k1); assert jsonb_array_length(r->'rows') = 1 and (r->>'ranking_hidden')::boolean, 'ranking hidden for students';
  r := comp_save(tokTA, jsonb_build_object('id',k1,'name','دوري فرسان القرآن','start_date',today-9,'end_date',today+19,'halaqa_ids',jsonb_build_array('hA1'))); assert r->>'error'='start_locked', 'start date locked after scores';
  r := comp_save(tokTA, jsonb_build_object('id',k1,'name','دوري فرسان القرآن','start_date',today-10,'end_date',today+19,'halaqa_ids',jsonb_build_array('hA1'),'settings',jsonb_build_object('show_ranking',true),'expected_updated_at','2000-01-01T00:00:00Z'));
  assert r->>'error'='conflict', 'stale competition edit rejected';

  -- تخصيص الشبكة: إضافة/إعادة تسمية/حذف مجال
  cats := comp_get(tokTA,k1)->'categories';
  r := comp_save(tokTA, jsonb_build_object('id',k1,'name','دوري فرسان القرآن','start_date',today-10,'end_date',today+19,'halaqa_ids',jsonb_build_array('hA1'),
        'categories', cats || jsonb_build_array(jsonb_build_object('name','مجال مخصص','weekly_max_points',7,'kind','core','key','custom'))));
  assert (r->>'ok')::boolean and (select count(*) from competition_categories where competition_id::text=k1) = 11, 'custom category added: '||r::text;
  r := comp_save(tokTA, jsonb_build_object('id',k1,'name','دوري فرسان القرآن','start_date',today-10,'end_date',today+19,'halaqa_ids',jsonb_build_array('hA1'),
        'categories', (select jsonb_agg(c) from jsonb_array_elements(comp_get(tokTA,k1)->'categories') c where c->>'name' <> 'الأذكار والورد اليومي')));
  assert (r->>'ok')::boolean and not exists(select 1 from competition_categories where competition_id::text=k1 and name='الأذكار والورد اليومي'), 'unused category deleted';
  r := comp_save(tokTA, jsonb_build_object('id',k1,'name','دوري فرسان القرآن','start_date',today-10,'end_date',today+19,'halaqa_ids',jsonb_build_array('hA1'),
        'categories', (select jsonb_agg(c) from jsonb_array_elements(comp_get(tokTA,k1)->'categories') c where c->>'key' <> 'itqan')));
  assert exists(select 1 from competition_categories where competition_id::text=k1 and key='itqan' and not is_active), 'used category deactivated (scores preserved)';
  assert (select sum(points) from competition_scores where competition_id::text=k1 and student_id='s1' and not voided) = 31, 'scores preserved after category deactivate';

  -- ===== 6) مسابقة متعددة الحلقات (للمشرف) =====
  r := comp_save(tokSup, jsonb_build_object('name','دوري المركز','start_date',today+30,'end_date',today+50,'halaqa_ids',jsonb_build_array('hA1','hA2'),
        'participants',jsonb_build_array(jsonb_build_object('student_id','s1'),jsonb_build_object('student_id','s3'))));
  assert (r->>'ok')::boolean, 'supervisor multi-halaqa'; k2 := r->>'id';
  r := comp_save(tokTA, jsonb_build_object('id',k2,'name','تعديل','start_date',today+30,'end_date',today+50,'halaqa_ids',jsonb_build_array('hA1'))); assert r->>'error'='forbidden', 'teacher cannot edit multi-halaqa competition';
  r := comp_get(tokTA, k2); assert (r->>'ok')::boolean and jsonb_array_length(r->'participants') = 1 and not (r->>'can_manage')::boolean, 'teacher sees only own students, cannot manage';
  r := comp_set_status(tokSupB, k2, 'active'); assert r->>'error' in ('forbidden','not_found'), 'other center supervisor blocked';
  r := comp_get(tokSupB, k1); assert r->>'error'='forbidden', 'other center cannot get';
  r := comp_save(tokSupB, jsonb_build_object('id',k1,'name','اختراق','start_date',today,'end_date',today+3,'halaqa_ids',jsonb_build_array('hB1'))); assert r->>'error'='forbidden', 'other center cannot edit';

  -- ===== 7) الإيقاف والإنهاء والنتائج النهائية =====
  r := comp_set_status(tokTA, k1, 'paused'); assert (r->>'ok')::boolean;
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s2','category_id',catH,'points',1))); assert r->>'error'='not_active', 'paused competition rejects scores';
  r := comp_set_status(tokTA, k1, 'active'); assert (r->>'ok')::boolean;
  r := comp_set_status(tokTA, k1, 'ended'); assert (r->>'ok')::boolean, 'end';
  assert (select ended_at from competitions where id::text=k1) is not null, 'ended_at set';
  r := comp_eval_save(tokTA, k1, (today-1)::text, jsonb_build_array(jsonb_build_object('student_id','s2','category_id',catH,'points',1))); assert r->>'error'='locked', 'ended: eval locked';
  r := comp_adjust(tokTA, k1, 's2', catH, 1, 'محاولة بعد الإغلاق', null, null); assert r->>'error'='locked', 'ended: teacher cannot adjust';
  r := comp_score_void(tokTA, sc1, 'بعد الإغلاق'); assert r->>'error'='locked', 'ended: teacher cannot void';
  r := comp_adjust(tokSup, k1, 's2', catH, 1, 'تصحيح إداري موثق بعد الإغلاق', null, null); assert (r->>'ok')::boolean, 'ended: supervisor correction allowed: '||r::text;
  assert exists(select 1 from competition_scores where competition_id::text=k1 and post_close), 'post_close flagged';
  assert exists(select 1 from competition_score_audit where competition_id::text=k1 and action_type='adjust_after_close'), 'after-close audited';
  r := comp_leaderboard(tokS1, k1); assert r->>'state'='ended' and jsonb_array_length(r->'rows') = 2, 'student sees final results';
  r := comp_save(tokTA, jsonb_build_object('id',k1,'name','xy','start_date',today-10,'end_date',today+19,'halaqa_ids',jsonb_build_array('hA1'))); assert r->>'error'='locked', 'ended competition cannot be edited';
  r := comp_set_status(tokTA, k1, 'reopen'); assert r->>'error'='forbidden', 'teacher cannot reopen';
  r := comp_delete(tokTA, k1); assert r->>'error'='not_deletable', 'cannot delete competition with scores';

  -- ===== 8) مسابقة ثانية مستقلة =====
  r := comp_save(tokTA, jsonb_build_object('name','الدوري الثاني','start_date',today,'end_date',today+29,'halaqa_ids',jsonb_build_array('hA1'),
        'participants',jsonb_build_array(jsonb_build_object('student_id','s1'),jsonb_build_object('student_id','s2')))); k3 := r->>'id';
  r := comp_set_status(tokTA, k3, 'active'); assert (r->>'ok')::boolean, 'second competition activates after first ended: '||r::text;
  r := comp_leaderboard(tokTA, k3); assert (select sum((x->>'total')::numeric) from jsonb_array_elements(r->'rows') x) = 0, 'second competition scores independent';
  r := comp_leaderboard(tokTA, k1); assert (r->'rows'->0->>'total')::numeric > 0, 'first competition results preserved';
  r := comp_list(tokS1); assert jsonb_array_length(r->'rows') = 2 and r->'rows'->0->>'state' = 'running', 'student list: running first, ended after';

  -- ===== 9) الواجبات =====
  r := asg_save(tokTA, jsonb_build_object('halaqa_id','hA1','title','واجب سورة الملك','description','حل الأسئلة','due_at',(now()+interval '2 days')::text,
        'questions', jsonb_build_array(
          jsonb_build_object('qtype','mcq','prompt','كم عدد آيات سورة الملك؟','options',jsonb_build_array('20','30','40'),'correct',1,'points',2),
          jsonb_build_object('qtype','truefalse','prompt','سورة الملك مكية','correct',true,'points',1),
          jsonb_build_object('qtype','text','prompt','اكتب آية تعجبك','points',3)), 'status','published'));
  assert (r->>'ok')::boolean, 'assignment saved: '||r::text; asg := r->>'id';
  assert (select status from assignments where id::text = asg) = 'published', 'published on create';
  r := asg_save(tokTB, jsonb_build_object('halaqa_id','hA1','title','اختراق','questions','[]'::jsonb)); assert r->>'error'='forbidden', 'other teacher cannot create for halaqa';
  r := asg_list(tokS1); assert jsonb_array_length(r->'rows') = 1, 'student sees assignment';
  r := asg_list(tokS3); assert jsonb_array_length(r->'rows') = 0, 'other halaqa student does not';
  r := asg_get(tokS1, asg); assert (r->>'ok')::boolean and not (r->'questions'->0 ? 'correct'), 'student gets questions without answers: '||r::text;
  r := asg_get(tokS3, asg); assert r->>'error'='forbidden', 'other halaqa student forbidden';
  select (q->>'id') into q1 from jsonb_array_elements(asg_get(tokTA, asg)->'questions') q where q->>'qtype'='mcq';
  select (q->>'id') into q2 from jsonb_array_elements(asg_get(tokTA, asg)->'questions') q where q->>'qtype'='truefalse';
  select (q->>'id') into q3 from jsonb_array_elements(asg_get(tokTA, asg)->'questions') q where q->>'qtype'='text';
  r := asg_submit(tokS1, asg, jsonb_build_object(q1,1,q2,true,q3,'تبارك الذي بيده الملك'), gen_random_uuid()::text);
  assert (r->>'ok')::boolean and (r->>'score')::numeric = 3 and (r->>'max')::numeric = 6 and (r->>'pending_manual')::boolean, 'auto grade 3/6 pending text: '||r::text;
  r := asg_submit(tokS1, asg, jsonb_build_object(q1,1), gen_random_uuid()::text); assert r->>'error'='already_submitted', 'single submission';
  r := asg_submit(tokS3, asg, jsonb_build_object(q1,1)); assert r->>'error'='forbidden', 'other halaqa cannot submit';
  r := asg_submit(tokTA, asg, jsonb_build_object(q1,1)); assert r->>'error'='forbidden', 'teacher cannot submit';
  r := asg_submit(tokS2, asg, jsonb_build_object(q1,0,q2,false), gen_random_uuid()::text); assert (r->>'score')::numeric = 0, 'wrong answers score 0';
  r := asg_results(tokTA, asg); assert jsonb_array_length(r->'rows') = 2 and (select count(*) from jsonb_array_elements(r->'rows') x where (x->>'submitted')::boolean) = 2, 'results show both submitted';
  r := asg_results(tokS1, asg); assert r->>'error'='forbidden', 'student cannot see results';
  r := asg_results(tokTB, asg); assert r->>'error'='forbidden', 'other teacher cannot see results';
  r := asg_submission(tokTA, asg, 's1'); assert (r->'questions'->2->>'answer') is not null, 'teacher sees text answer';
  r := asg_grade(tokTA, asg, 's1', jsonb_build_object(q3, 2.5), 'أحسنت'); assert (r->>'ok')::boolean and (r->>'score')::numeric = 5.5 and not (r->>'pending_manual')::boolean, 'manual grade: '||r::text;
  r := asg_grade(tokTA, asg, 's1', jsonb_build_object(q3, 9), 'x'); assert r->>'error'='bad_points', 'grade above max rejected';
  r := asg_grade(tokS1, asg, 's1', jsonb_build_object(q3, 3), 'x'); assert r->>'error'='forbidden', 'student cannot grade';
  r := asg_get(tokS1, asg); assert (r->'submission'->>'score')::numeric = 5.5 and (r->'questions'->0 ? 'correct'), 'student sees result + revealed answers';
  r := asg_save(tokTA, jsonb_build_object('id',asg,'halaqa_id','hA1','title','عنوان جديد','questions','[]'::jsonb)); assert r->>'error'='has_submissions', 'cannot change questions after submissions';
  r := asg_set_status(tokTA, asg, 'closed'); assert (r->>'ok')::boolean;
  r := asg_set_status(tokTA, asg, 'draft'); assert r->>'error'='has_submissions';
  r := asg_set_status(tokTB, asg, 'published'); assert r->>'error'='forbidden';
  r := asg_save(tokTA, jsonb_build_object('halaqa_id','hA1','title','واجب متأخر','due_at',(now()-interval '1 day')::text,'status','published',
        'questions', jsonb_build_array(jsonb_build_object('qtype','truefalse','prompt','سؤال سريع','correct',true))));
  r := asg_submit(tokS2, r->>'id', jsonb_build_object()); assert r->>'error'='past_due', 'past due rejected';

  -- ===== 10) المحادثة =====
  r := chat_send(tokS1, null, 'السلام عليكم يا شيخ', gen_random_uuid()::text); assert (r->>'ok')::boolean, 'student sends';
  r := chat_threads(tokTA); assert jsonb_array_length(r->'rows') = 1 and (r->>'unread')::int = 1, 'teacher sees 1 unread thread: '||r::text;
  r := chat_threads(tokTB); assert jsonb_array_length(r->'rows') = 0, 'other teacher sees nothing';
  r := chat_get(tokTB, 's1'); assert r->>'error'='forbidden', 'other teacher cannot read thread';
  r := chat_get(tokSupB, 's1'); assert r->>'error'='forbidden', 'other center cannot read thread';
  r := chat_get(tokTA, 's1'); assert jsonb_array_length(r->'rows') = 1, 'teacher reads thread';
  assert (chat_threads(tokTA)->>'unread')::int = 0, 'read marks messages';
  r := chat_send(tokTA, 's1', 'وعليكم السلام ورحمة الله'); assert (r->>'ok')::boolean, 'teacher replies';
  r := chat_send(tokTA, 's3', 'x'); assert r->>'error'='forbidden', 'teacher cannot message other halaqa student';
  assert (chat_threads(tokS1)->>'unread')::int = 1, 'student has 1 unread';
  r := chat_get(tokS1); assert jsonb_array_length(r->'rows') = 2 and (chat_threads(tokS1)->>'unread')::int = 0, 'student reads both';
  r := chat_send(tokS1, 's2', 'مرحبا'); assert (select student_id from student_chat order by id desc limit 1) = 's1', 'student chat always goes to own thread (target ignored)';
  r := chat_get(tokS2, 's1'); assert jsonb_array_length(r->'rows') = 0, 'student cannot read other thread';
  r := chat_send(tokS1, null, repeat('x', 1501)); assert r->>'error'='bad_body';
  r := chat_send(tokEmp2, 's1', 'x'); assert r->>'error'='forbidden', 'employee without messages perm blocked';
  r := chat_send(tokEmp, 's1', 'رسالة من موظف'); assert (r->>'ok')::boolean, 'employee with messages perm ok';

  -- ===== 11) الحماية: الجداول مغلقة + حذف المركز =====
  foreach bad in array array['competitions','competition_scores','competition_score_audit','assignments','assignment_submissions','student_chat','competition_participants','competition_categories','assignment_questions','app_ops'] loop
    assert not has_table_privilege('anon', 'public.'||bad, 'select') and not has_table_privilege('anon', 'public.'||bad, 'insert')
       and not has_table_privilege('anon', 'public.'||bad, 'update') and not has_table_privilege('anon', 'public.'||bad, 'delete'), 'anon has no access to '||bad;
  end loop;
  assert not has_function_privilege('anon', 'public._comp_totals(uuid)', 'execute'), 'internal totals not callable by anon';
  assert has_function_privilege('anon', 'public.comp_list(text)', 'execute'), 'public rpc callable';
  r := comp_save(tokSupB, jsonb_build_object('name','مسابقة ب','start_date',today,'end_date',today+9,'halaqa_ids',jsonb_build_array('hB1'),'participants',jsonb_build_array(jsonb_build_object('student_id','sB'))));
  assert (r->>'ok')::boolean, 'center B competition';
  r := app_masool_delete_center(tokM, cB::text); assert (r->>'ok')::boolean, 'masool deletes center B';
  assert not exists(select 1 from competitions where center_id = cB::text), 'center B competitions removed';
  assert exists(select 1 from competitions where center_id = cA::text), 'center A untouched';
  raise notice 'ALL COMPETITION TESTS PASSED';
end $$;
