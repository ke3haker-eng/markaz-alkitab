const L = require('./e2e_lib');
const { ok, sleep, openApp, dumpStorage, admin, pgLog } = L;
const sha = s => require('crypto').createHash('sha256').update(s).digest('hex');

async function reset(){
  await admin("truncate centers, users, halaqat, students, records, messages, daily_questions, deleted_ids, app_sessions, app_login_attempts, audit_log restart identity cascade");
  const c = (await admin("insert into centers(name,manager_name,status) values ('مركز الاختبار','مشرف','active') returning id")).rows[0].id;
  await admin("insert into users(role,username,password_hash,full_name) values ('masool','owner',$1,'المالك')", [sha('ownerpass')]);
  await admin("insert into users(center_id,role,username,password_hash,full_name) values ($1,'supervisor','supA',$2,'مشرف أ')", [c, sha('suppass1')]);
  return c;
}
const val = (w, id, v) => { w.document.getElementById(id).value = v; };
const S = (dom) => dom.window; // alias
const ev = (w, code) => w.eval(code);

(async () => {
  const cid = await reset();

  console.log('\n[1] كل واجهات Google اختفت');
  let dom = await openApp();
  let w = dom.window;
  const html = w.document.getElementById('auth').innerHTML;
  ok(!/google/i.test(html), 'لا ذكر لـ Google في شاشة الدخول');
  ok(typeof w.loginWithGoogle === 'undefined' && typeof w.loginStudentWithGoogle === 'undefined', 'دوال Google محذوفة');
  ok(w.__errors.length === 0 && dom.jerr.length === 0, 'لا أخطاء عند التحميل: ' + [...w.__errors, ...dom.jerr].join(' | '));

  console.log('\n[2] دخول المالك (هاش قديم → bcrypt) + حفظ الجلسة بلا hash');
  val(w, 'supUsername', 'owner'); val(w, 'supPassword', 'wrong');
  await w.loginSupervisor(); await sleep(200);
  ok(!ev(w, "_currentUser"), 'كلمة مرور خاطئة لا تدخل');
  val(w, 'supPassword', 'ownerpass');
  await w.loginSupervisor(); await sleep(900);
  ok(ev(w, "_currentUser && _currentUser.role") === 'masool', 'دخل المالك');
  const sess = JSON.parse(w.localStorage.getItem('ridwan_session'));
  ok(sess && sess.token && !('password_hash' in sess), 'الجلسة فيها رمز ولا تحتوي hash');
  ok((await admin("select password_hash from users where username='owner'")).rows[0].password_hash.startsWith('$2'), 'تمت ترقية هاش المالك إلى bcrypt');
  ok(w.localStorage.getItem('ridwan_masool_creds') === null, 'لا hash للمالك مخزّن محلياً');
  let st = dumpStorage(w);
  // إعادة فتح التطبيق بنفس الجلسة
  dom.window.close();
  dom = await openApp(st); w = dom.window; await sleep(800);
  ok(ev(w, "_currentUser && _currentUser.role") === 'masool', 'استعادة جلسة المالك بعد إعادة الفتح');
  // إبطال الجلسة من السيرفر → يُطرد
  await admin("delete from app_sessions");
  st = dumpStorage(w); dom.window.close();
  dom = await openApp(st); w = dom.window; await sleep(800);
  ok(!ev(w, "_currentUser") && w.localStorage.getItem('ridwan_session') === null, 'جلسة مُلغاة من السيرفر تُنهى فوراً');
  dom.window.close();

  console.log('\n[3] دخول المشرف وإنشاء حلقة (حساب المعلم عبر السيرفر)');
  dom = await openApp(); w = dom.window;
  val(w, 'supUsername', 'supA'); val(w, 'supPassword', 'suppass1');
  await w.loginSupervisor(); await sleep(1200);
  ok(ev(w, "_currentUser && _currentUser.role") === 'supervisor', 'دخل المشرف');
  ok(ev(w, "centerCfg.supabase_center_id") === cid, 'حُمّلت بيانات المركز');
  val(w, 'hqName', 'حلقة الاختبار'); val(w, 'hqSheikh', 'الشيخ أحمد'); val(w, 'hqEmoji', '📖'); val(w, 'hqImgData', '');
  w.document.getElementById('btnConfirmHalaqa').dataset.editId = '';
  await w.confirmHalaqa(); await sleep(1500);
  const hq = ev(w, "JSON.parse(JSON.stringify(halaqatList[0]))");
  ok(hq && hq.teacherUsername && hq.teacherPassword, 'حُفظت بيانات المعلم محلياً (تبقى ظاهرة للمشرف)');
  const tRow = (await admin("select username,role,password_hash,halaqa_id from users where role='teacher'")).rows[0];
  ok(tRow && tRow.username === hq.teacherUsername && tRow.password_hash.startsWith('$2') && tRow.halaqa_id === hq.id, 'حساب المعلم أُنشئ بـ bcrypt ومرتبط بالحلقة');
  ok((await admin("select count(*)::int c from halaqat")).rows[0].c === 1, 'الحلقة في السيرفر');

  console.log('\n[4] إضافة طالب + تعديله (اسم المستخدم لا يتغير)');
  await w.openHalaqa(hq.id); await sleep(1200);
  val(w, 'newName', 'طالب تجريبي'); val(w, 'newPhone', '0599'); 
  w.document.getElementById('btnConfirmStudent').dataset.editId = '';
  await w.confirmStudent(); await sleep(1500);
  const stu = ev(w, "JSON.parse(JSON.stringify(db.students[0]))");
  ok(stu && stu.username && stu.password, 'الطالب أُضيف محلياً مع بيانات الدخول');
  const sRow = (await admin("select u.username,u.password_hash,s.user_id from students s join users u on u.id=s.user_id where s.id=$1", [stu.id])).rows[0];
  ok(sRow && sRow.username === stu.username && sRow.password_hash.startsWith('$2'), 'حساب الطالب مربوط وbcrypt');
  val(w, 'newName', 'طالب تجريبي معدّل'); val(w, 'newPhone', '0588');
  w.document.getElementById('btnConfirmStudent').dataset.editId = stu.id;
  await w.confirmStudent(); await sleep(1000);
  const stu2 = ev(w, "JSON.parse(JSON.stringify(db.students[0]))");
  ok(stu2.name === 'طالب تجريبي معدّل' && stu2.username === stu.username, 'تعديل الطالب لا يغيّر اسم المستخدم');
  ok((await admin("select username from users where id=(select user_id from students where id=$1)", [stu.id])).rows[0].username === stu.username, 'اسم المستخدم في السيرفر لم يتغيّر');

  console.log('\n[5] المزامنة التفاضلية');
  await admin("delete from records");
  ev(w, `db.students[0].records.push({id:'e1',date:'١٢‏/١١‏/٢٠٢٦',day:'الخميس',type:'حفظ',att:'حضور',sura:['البقرة'],from:'1',to:'5',errors:0,notes:''}); persist();`);
  await sleep(1500);
  ok((await admin("select count(*)::int c from records")).rows[0].c === 1, 'السجل الجديد رُفع');
  await admin("delete from records");   // نحذفه من السيرفر ونعيد الحفظ دون تعديل: لا يجب إعادة رفعه
  ev(w, "persist()"); await sleep(1500);
  ok((await admin("select count(*)::int c from records")).rows[0].c === 0, 'المتغيّر فقط يُرفع (لا إحياء لسجل محذوف من جهاز آخر)');
  ev(w, "db.students[0].records[0].notes='معدّل'; persist()"); await sleep(1500);
  ok((await admin("select count(*)::int c from records")).rows[0].c === 1, 'السجل المعدّل يُرفع');

  console.log('\n[6] توحيد مفتاح الشهر');
  const k1 = ev(w, "_mkOf('١٢‏/١١‏/٢٠٢٦')"), k2 = ev(w, "_mkOf('12/11/2026')"), k3 = ev(w, "_mkOf('2026-11-12')");
  ok(k1 === k2 && k2 === k3, 'مفتاح الشهر موحّد لثلاث صيغ تاريخ: ' + [k1, k2, k3].join(' | '));

  console.log('\n[7] دخول المعلم والطالب بحسابيهما');
  const stHq = dumpStorage(w); const tUser = hq.teacherUsername, tPass = hq.teacherPassword;
  dom.window.close();
  dom = await openApp(); w = dom.window;
  val(w, 'supUsername', tUser); val(w, 'supPassword', tPass);
  await w.loginSupervisor(); await sleep(1500);
  ok(ev(w, "_currentUser && _currentUser.role") === 'teacher' && ev(w, "!!_authToken"), 'دخل المعلم (عبر السيرفر) وحصل على رمز جلسة');
  dom.window.close();
  dom = await openApp(); w = dom.window;
  val(w, 'stuUsername', stu.username); val(w, 'stuPassword', 'WRONGPASS');
  await w.loginStudent(); await sleep(400);
  ok(!ev(w, "_currentUser"), 'كلمة مرور طالب خاطئة مرفوضة');
  val(w, 'stuPassword', stu.password);
  await w.loginStudent(); await sleep(1500);
  ok(ev(w, "_currentUser && _currentUser.role") === 'student', 'دخل الطالب');
  dom.window.close();

  console.log('\n[8] القفل المؤقت بعد محاولات فاشلة');
  dom = await openApp(); w = dom.window;
  let msg = '';
  for(let i = 0; i < 5; i++){ val(w, 'supUsername', 'supA'); val(w, 'supPassword', 'bad' + i); await w.loginSupervisor(); await sleep(150); msg = w.document.getElementById('supError').textContent; }
  ok(/إيقاف الدخول مؤقتاً/.test(msg), 'رسالة القفل: ' + msg);
  val(w, 'supPassword', 'suppass1'); await w.loginSupervisor(); await sleep(300);
  ok(!ev(w, "_currentUser"), 'الدخول الصحيح مرفوض أثناء القفل');
  await admin("delete from app_login_attempts");
  dom.window.close();

  console.log('\n[9] الموظفون والصلاحيات + سجل التعديلات');
  dom = await openApp(); w = dom.window;
  val(w, 'supUsername', 'supA'); val(w, 'supPassword', 'suppass1'); await w.loginSupervisor(); await sleep(1200);
  w._openStaffForm(null); await sleep(100);
  val(w, 'sfName', 'موظف اختبار'); val(w, 'sfUser', 'emp_test'); val(w, 'sfPass', 'emppass1');
  w.document.querySelectorAll('.sf-perm').forEach(c => { c.checked = (c.value === 'reports' || c.value === 'records'); });
  await w._saveStaffForm(null); await sleep(800);
  const emp = (await admin("select role,perms,password_hash from users where username='emp_test'")).rows[0];
  ok(emp && emp.role === 'employee' && emp.perms.reports === true && emp.perms.students === false, 'حساب الموظف بصلاحياته أُنشئ');
  await w.openAuditLog(); await sleep(800);
  ok(w.document.querySelectorAll('#auditList > div').length >= 1, 'سجل التعديلات يعرض إدخالات');
  dom.window.close();
  dom = await openApp(); w = dom.window;
  val(w, 'supUsername', 'emp_test'); val(w, 'supPassword', 'emppass1'); await w.loginSupervisor(); await sleep(1500);
  ok(ev(w, "_currentUser && _currentUser.role") === 'employee', 'دخل الموظف من شاشة الدخول نفسها');
  ok(ev(w, "can('reports')") === true && ev(w, "can('students')") === false, 'صلاحيات الموظف تُقرأ من السيرفر');
  ok(ev(w, "_guard('students')") === false && ev(w, "_guard('records')") === true, 'الحارس يمنع غير المسموح ويسمح بالمسموح');
  w.showCenterSettings();
  ok(w.document.getElementById('centerInfoCard').style.display === 'none' && w.document.getElementById('supervisorToolsCard').style.display === 'none', 'إعدادات المركز وأدوات المشرف مخفية عن الموظف');
  const denied = await w._rpcT('app_list_staff');
  ok(denied && denied.error === 'forbidden', 'السيرفر يرفض الموظف من قائمة الموظفين');
  dom.window.close();

  console.log('\n[10] لا وصول مباشر لجدول المستخدمين من المتصفح');
  const direct = pgLog.filter(m => /permission denied for table users/.test(m) && !/<<select public\.app_/.test(m));
  ok(direct.length === 0, 'لم يحاول التطبيق أي وصول مباشر لجدول users (' + direct.length + ')');
  const bad = pgLog.filter(m => !/messages|created_at|is_read_by/.test(m) && /does not exist|syntax error|violates/.test(m));
  ok(bad.length === 0, 'لا أخطاء SQL غير متوقعة: ' + bad.slice(0, 3).join(' || '));

  const f = L.summary(); await L.pool.end(); process.exit(f ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
