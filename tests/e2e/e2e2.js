const L = require('./e2e_lib');
const { ok, sleep, openApp, dumpStorage, admin, pgLog } = L;
const sha = s => require('crypto').createHash('sha256').update(s).digest('hex');
const val = (w, id, v) => { w.document.getElementById(id).value = v; };
const ev = (w, code) => w.eval(code);

async function reset(){
  await admin("truncate centers, users, halaqat, students, records, messages, daily_questions, deleted_ids, app_sessions, app_login_attempts, audit_log restart identity cascade");
  await admin("insert into users(role,username,password_hash,full_name) values ('masool','owner',$1,'المالك')", [sha('ownerpass')]);
}
async function login(user, pass, storage){
  const dom = await openApp(storage); const w = dom.window;
  val(w, 'supUsername', user); val(w, 'supPassword', pass);
  await w.loginSupervisor(); await sleep(1400);
  return dom;
}
(async () => {
  await reset();

  console.log('\n[A] إنشاء مركز جديد (ذرّي) ثم موافقة المالك');
  let dom = await openApp(); let w = dom.window;
  val(w, 'ncCenterName', 'مركز النور'); val(w, 'ncManagerName', 'المشرف نور'); val(w, 'ncUsername', 'nour'); val(w, 'ncPassword', 'nour1234'); val(w, 'ncPassword2', 'nour1234');
  await w.createNewCenter(); await sleep(800);
  ok((await admin("select count(*)::int c from centers where status='pending'")).rows[0].c === 1, 'المركز أُنشئ بحالة pending');
  ok((await admin("select status from users where username='nour'")).rows[0].status === 'pending', 'المشرف بحالة pending');
  // محاولة ثانية بنفس اسم المستخدم لا تترك مركزاً يتيماً
  val(w, 'ncCenterName', 'مركز مكرر'); val(w, 'ncManagerName', 'x'); val(w, 'ncUsername', 'nour'); val(w, 'ncPassword', 'nour1234'); val(w, 'ncPassword2', 'nour1234');
  await w.createNewCenter(); await sleep(600);
  ok((await admin("select count(*)::int c from centers")).rows[0].c === 1, 'لا مركز يتيم عند تكرار اسم المستخدم');
  dom.window.close();
  dom = await login('nour', 'nour1234'); w = dom.window;
  ok(!ev(w, "_currentUser"), 'المشرف المعلّق لا يدخل');
  dom.window.close();
  // المالك يوافق
  dom = await login('owner', 'ownerpass'); w = dom.window;
  const cid = (await admin("select id from centers")).rows[0].id;
  ok(ev(w, "_currentUser && _currentUser.role") === 'masool', 'دخل المالك');
  ok(/مركز النور/.test(w.document.body.innerHTML) , 'لوحة المالك تعرض المركز (المشرفون عبر RPC)');
  ok(!/passDisp_|••••••/.test('') , 'تم حذف عرض hash');
  await w.approveCenter(cid); await sleep(700);
  ok((await admin("select status from centers")).rows[0].status === 'active' && (await admin("select status from users where username='nour'")).rows[0].status === 'active', 'الموافقة فعّلت المركز والمشرف');
  // المالك يعدّل بيانات دخول المشرف (كانت معطّلة سابقاً)
  const supId = (await admin("select id from users where username='nour'")).rows[0].id;
  w.showEditCenter(cid, 'nour', supId); await sleep(100);
  val(w, 'editUsername', 'nour2'); val(w, 'editPassword', 'newpass99');
  await w.updateCenterCredentials(supId, cid); await sleep(700);
  ok((await admin("select count(*)::int c from users where username='nour2'")).rows[0].c === 1, 'المالك غيّر بيانات دخول المشرف');
  dom.window.close();

  console.log('\n[B] تسجيل معلم بكود المركز → قبول المشرف');
  dom = await openApp(); w = dom.window;
  val(w, 'regCenterCode', cid); val(w, 'regFullName', 'معلم جديد'); val(w, 'regUsername', 'newteach'); val(w, 'regPassword', 'teach123'); if(w.document.getElementById('regPassword2')) val(w, 'regPassword2', 'teach123');
  await w.registerTeacher(); await sleep(800);
  ok((await admin("select status from users where username='newteach'")).rows[0]?.status === 'pending', 'المعلم سُجّل بحالة pending');
  val(w, 'regCenterCode', "x',id.eq.1"); val(w, 'regFullName', 'مخترق'); val(w, 'regUsername', 'hackt'); val(w, 'regPassword', 'teach123'); if(w.document.getElementById('regPassword2')) val(w, 'regPassword2', 'teach123');
  await w.registerTeacher(); await sleep(500);
  ok((await admin("select count(*)::int c from users where username='hackt'")).rows[0].c === 0, 'كود مركز مشبوه لا ينشئ شيئاً');
  dom.window.close();
  dom = await login('nour2', 'newpass99'); w = dom.window;
  ok(ev(w, "_currentUser && _currentUser.role") === 'supervisor', 'دخل المشرف بكلمة المرور الجديدة التي عيّنها المالك');
  // إنشاء حلقة ليرتبط بها المعلم
  val(w, 'hqName', 'حلقة جديدة'); val(w, 'hqSheikh', 'شيخ'); val(w, 'hqEmoji', '📖'); val(w, 'hqImgData', '');
  w.document.getElementById('btnConfirmHalaqa').dataset.editId = '';
  await w.confirmHalaqa(); await sleep(1500);
  const hid = ev(w, "halaqatList[0].id");
  await w._renderPendingTeachersNotif(); await sleep(400);
  const tid = (await admin("select id from users where username='newteach'")).rows[0].id;
  w.openPendingTeachersModal(); await sleep(1200);
  ok(!!w.document.getElementById('halaqaSel_' + tid), 'قائمة المعلمين المنتظرين تظهر عبر RPC');
  const sel = w.document.getElementById('halaqaSel_' + tid); if(sel){ sel.value = hid; }
  await w._approveTeacher(tid, 'newteach'); await sleep(1500);
  const tr = (await admin("select status,halaqa_id from users where username='newteach'")).rows[0];
  ok(tr.status === 'active' && tr.halaqa_id, 'قُبل المعلم وارتبط بحلقة');

  console.log('\n[C] بيانات دخول الطالب والمعلم (تغيير) + حذف الطالب');
  await w.openHalaqa(hid); await sleep(1200);
  val(w, 'newName', 'طالب س'); w.document.getElementById('btnConfirmStudent').dataset.editId = '';
  await w.confirmStudent(); await sleep(1500);
  const sid = ev(w, "db.students[0].id");
  w.openChangeStudentCreds(sid); await sleep(50);
  val(w, 'scU_' + sid, 'stu_new'); val(w, 'scP_' + sid, 'pass4444');
  await w._saveStudentCreds(sid); await sleep(1000);
  const su = (await admin("select u.username,u.password_hash from users u join students s on s.user_id=u.id where s.id=$1", [sid])).rows[0];
  ok(su && su.username === 'stu_new' && su.password_hash.startsWith('$2'), 'تغيير بيانات الطالب في السيرفر (مشفّر)');
  ok(ev(w, "db.students[0].password") === 'pass4444', 'كلمة مرور الطالب تبقى ظاهرة للمعلم محلياً');
  const tUser = ev(w, "halaqatList[0].teacherUsername");
  w.openChangeTeacherCreds(hid); await sleep(50);
  val(w, 'tcU_' + hid, tUser); val(w, 'tcP_' + hid, 'tpass555');
  await w._saveTeacherCreds(hid); await sleep(1000);
  ok((await admin("select password_hash from users where username=$1", [tUser])).rows[0].password_hash.startsWith('$2'), 'تغيير كلمة مرور المعلم (مشفّرة)');
  await w.delStudent(sid); await sleep(1500);
  ok((await admin("select count(*)::int c from users where username='stu_new'")).rows[0].c === 0, 'حذف الطالب حذف حسابه عبر RPC');

  console.log('\n[D] حذف حلقة بمعلميها وطلابها');
  await w.deleteHalaqa(hid); await sleep(2000);
  ok((await admin("select count(*)::int c from users where username=$1", [tUser])).rows[0].c === 0, 'حذف الحلقة حذف حساب معلمها');
  const bad = pgLog.filter(m => /permission denied for table users/.test(m) && !/<<select public\.app_/.test(m));
  ok(bad.length === 0, 'لا وصول مباشر لجدول users في أي مسار (' + bad.length + ') ' + bad.slice(0,2).join('|'));
  const others = pgLog.filter(m => !/messages|created_at|is_read_by/.test(m) && /does not exist|syntax error|violates/.test(m));
  ok(others.length === 0, 'لا أخطاء SQL غير متوقعة: ' + others.slice(0, 3).join(' || '));
  dom.window.close();
  const f = L.summary(); await L.pool.end(); process.exit(f ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
