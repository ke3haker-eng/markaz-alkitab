const L = require('./e2e_lib');
const { ok, sleep, openApp, dumpStorage, admin } = L;
const sha = s => require('crypto').createHash('sha256').update(s).digest('hex');
const val = (w, id, v) => { w.document.getElementById(id).value = v; };
const ev = (w, code) => w.eval(code);
(async () => {
  await admin("truncate centers, users, halaqat, students, records, messages, daily_questions, deleted_ids, app_sessions, app_login_attempts, audit_log restart identity cascade");
  const cid = (await admin("insert into centers(name,manager_name,status) values ('م','م','active') returning id")).rows[0].id;
  await admin("insert into users(center_id,role,username,password_hash,full_name) values ($1,'supervisor','sup',$2,'مشرف')", [cid, sha('suppass1')]);

  // مشرف ينشئ حلقة (معلمها يُنشأ تلقائياً)
  let dom = await openApp(); let w = dom.window;
  val(w, 'supUsername', 'sup'); val(w, 'supPassword', 'suppass1'); await w.loginSupervisor(); await sleep(1200);
  val(w, 'hqName', 'ح'); val(w, 'hqSheikh', 'ش'); val(w, 'hqEmoji', '📖'); val(w, 'hqImgData', '');
  w.document.getElementById('btnConfirmHalaqa').dataset.editId = ''; await w.confirmHalaqa(); await sleep(1500);
  const tUser = ev(w, "halaqatList[0].teacherUsername"), tPass = ev(w, "halaqatList[0].teacherPassword"), hid = ev(w, "halaqatList[0].id");
  const supStore = dumpStorage(w); dom.window.close();

  console.log('\n[E] المعلم: دخول عبر السيرفر ثم دخول بلا إنترنت من نفس الجهاز');
  dom = await openApp(supStore); w = dom.window;     // نفس الجهاز (يحتوي قائمة الحلقات وكلمة مرور المعلم محلياً)
  // نُسجّل خروج المشرف محلياً ونجعل الجهاز بلا إنترنت
  w.localStorage.removeItem('ridwan_session');
  let st = dumpStorage(w); dom.window.close();
  dom = await openApp(st); w = dom.window;
  Object.defineProperty(w.navigator, 'onLine', { get: () => false, configurable: true });
  val(w, 'supUsername', tUser); val(w, 'supPassword', tPass);
  await w.loginSupervisor(); await sleep(1500);
  ok(ev(w, "_currentUser && _currentUser.role") === 'teacher', 'دخل المعلم بلا إنترنت من الجهاز المعروف');
  val(w, 'supPassword', 'wrongpass');
  w.localStorage.removeItem('ridwan_session'); 
  dom.window.close();

  console.log('\n[F] كلمة مرور محلية قديمة لا تعمل بعد تغييرها في السيرفر (أونلاين)');
  await admin("update users set password_hash=$1 where username=$2", [sha('changed123'), tUser]);
  dom = await openApp(st); w = dom.window;
  val(w, 'supUsername', tUser); val(w, 'supPassword', tPass);
  await w.loginSupervisor(); await sleep(1200);
  ok(!ev(w, "_currentUser"), 'كلمة المرور القديمة المخزّنة محلياً لم تعد تدخل أونلاين');
  val(w, 'supPassword', 'changed123'); await w.loginSupervisor(); await sleep(1500);
  ok(ev(w, "_currentUser && _currentUser.role") === 'teacher', 'كلمة المرور الجديدة تدخل');
  dom.window.close();

  console.log('\n[G] تذكير النسخ الاحتياطي + تنبيه التحديث + الإصدار');
  dom = await openApp(supStore); w = dom.window;
  w.localStorage.setItem('ridwan_backup_first_seen', String(Date.now() - 10 * 864e5));
  w.localStorage.removeItem('ridwan_last_backup');
  w.localStorage.removeItem('ridwan_backup_snooze');
  ev(w, "_currentUser = {role:'supervisor', id:'x', username:'sup'}");
  w._checkBackupReminder();
  ok(!!w.document.getElementById('backupBanner') && /10/.test(w.document.getElementById('backupBanner').textContent), 'ظهر تذكير النسخ الاحتياطي بعد 10 أيام');
  w._snoozeBackup(); w._checkBackupReminder();
  ok(!w.document.getElementById('backupBanner'), 'تأجيل التذكير ليوم يعمل');
  w._markBackupDone(); w.localStorage.removeItem('ridwan_backup_snooze');
  w._checkBackupReminder();
  ok(!w.document.getElementById('backupBanner'), 'بعد النسخ لا يظهر التذكير');
  w._showUpdateBanner();
  ok(!!w.document.getElementById('updateBanner'), 'تنبيه التحديث يظهر');
  ok(ev(w, "APP_VERSION") === '2.0.0' && /2\.0\.0/.test(w.document.getElementById('appVersionAuth').textContent), 'رقم الإصدار ظاهر في شاشة الدخول');
  dom.window.close();
  const f = L.summary(); await L.pool.end(); process.exit(f ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
