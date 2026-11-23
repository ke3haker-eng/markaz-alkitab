const L = require('./e2e_lib');
const { ok, sleep, openApp, dumpStorage, admin, pgLog } = L;
const sha = s => require('crypto').createHash('sha256').update(s).digest('hex');
const val = (w, id, v) => { w.document.getElementById(id).value = v; };
const ev = (w, code) => w.eval(code);
const fire = (w, el, type) => el.dispatchEvent(new w.Event(type, {bubbles: true}));
const setV = (w, el, v, type = 'input') => { el.value = v; fire(w, el, type); };
const q = (w, sel) => w.document.querySelector(sel);
const qa = (w, sel) => [...w.document.querySelectorAll(sel)];
async function waitFor(fn, ms = 8000){ const t = Date.now(); while(Date.now() - t < ms){ try { const r = await fn(); if(r) return r; } catch(e){} await sleep(120); } return false; }
const N = async (sql, p) => (await admin(sql, p)).rows;
const addD = (s, n) => { const d = new Date(s + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
async function login(user, pass, storage){ const dom = await openApp(storage); const w = dom.window; val(w, 'supUsername', user); val(w, 'supPassword', pass); await w.loginSupervisor(); await sleep(1500); stubEnv(w); return dom; }
async function loginStu(user, pass){ const dom = await openApp(); const w = dom.window; val(w, 'stuUsername', user); val(w, 'stuPassword', pass); await w.loginStudent(); await sleep(1800); stubEnv(w); return dom; }
function stubEnv(w){ w.URL.createObjectURL = () => 'blob:test'; w.URL.revokeObjectURL = () => {}; }
const click = async (w, sel, ms = 350) => { const e = q(w, sel); if(!e) throw new Error('missing ' + sel); e.click(); await sleep(ms); };

(async () => {
  await admin("truncate centers, users, halaqat, students, records, competitions, assignments, student_chat, chat_groups, chat_reads, chat_prefs, chat_media, chat_media_chunks, app_ops, app_sessions, app_login_attempts, audit_log restart identity cascade");
  const today = (await N("select (now() at time zone 'Asia/Gaza')::date::text d"))[0].d;
  const cid = (await N("insert into centers(name,manager_name,status) values ('مركز','م','active') returning id"))[0].id;
  const h = sha('pw1234');
  await admin("insert into halaqat(id, center_id, name, teacher_username) values ('hA1',$1,'حلقة الفرسان','tA'),('hA2',$1,'حلقة ثانية','tB')", [cid]);
  await admin("insert into users(center_id,role,username,password_hash,full_name) values ($1,'supervisor','supA',$2,'مشرف')", [cid, h]);
  await admin("insert into users(center_id,role,username,password_hash,full_name,halaqa_id) values ($1,'teacher','tA',$2,'المعلم أحمد','hA1')", [cid, h]);
  for(const [u, n, hq] of [['stu1', 'سعد', 'hA1'], ['stu2', 'ياسر', 'hA1'], ['stu3', 'عمر', 'hA2']]){
    const uid = (await N("insert into users(center_id,role,username,password_hash,full_name) values ($1,'student',$2,$3,$4) returning id", [cid, u, h, n]))[0].id;
    await admin("insert into students(id,halaqa_id,user_id,name,username_cache) values ($1,$2,$3,$4,$5)", ['s' + u.slice(3), hq, uid, n, u]);
  }

  console.log('\n[1] الحد اليومي + اسم اليوم + الأرقام الباهتة');
  let dom = await login('supA', 'pw1234'); let w = dom.window;
  const mk = await w._rpcT('comp_save', {p: {name: 'دوري الاختبار', start_date: addD(today, -9), end_date: addD(today, 20), halaqa_ids: ['hA1'], participants: [{student_id: 's1', level: 'متقدم'}, {student_id: 's2'}]}});
  await w._rpcT('comp_set_status', {p_id: mk.id, p_status: 'active'});
  const cats = await N("select id,key from competition_categories where competition_id=$1", [mk.id]);
  const catH = cats.find(c => c.key === 'hifz').id, catI = cats.find(c => c.key === 'itqan').id, catA = cats.find(c => c.key === 'attendance').id;
  await w.CompUI.open('grid'); await sleep(1500);
  const dateVal = q(w, '#gDate').value;
  const expDay = new Date(dateVal + 'T12:00:00').toLocaleDateString('ar', {weekday: 'long'});
  ok(q(w, '#cuMain .cu-st.green').textContent.trim() === expDay, 'اسم اليوم بجانب التاريخ: ' + expDay);
  const c1 = q(w, `[data-g="s1|${catH}"]`);
  ok(c1.placeholder === '٥', 'الرقم الباهت في الخانة = الحد اليومي (٥)');
  ok(/يومي ٥/.test(q(w, '#cuMain table.cu-g').textContent) && /أسبوعي ٢٥/.test(q(w, '#cuMain table.cu-g').textContent), 'الرأس يبيّن الحد اليومي والأسبوعي');
  setV(w, c1, '6'); ok(c1.classList.contains('bad') && /اليومي/.test(c1.title), 'تجاوز الحد اليومي يُعلَّم فوراً: ' + c1.title);
  setV(w, c1, '5'); ok(!c1.classList.contains('bad'), '٥ مقبولة');
  await click(w, '[data-act="g_save"]', 100);
  await waitFor(async () => (await N("select count(*)::int c from competition_scores"))[0].c === 1);
  ok(Number((await N("select points from competition_scores"))[0].points) === 5, 'حُفظ ٥ في السيرفر');
  const srv = await w._rpcT('comp_eval_save', {p_comp: mk.id, p_date: addD(today, -1), p_items: [{student_id: 's2', category_id: catH, points: 6}], p_op: null});
  ok(srv.results[0].status === 'daily_cap', 'السيرفر يرفض تجاوز الحد اليومي حتى لو تجاوزت الواجهة: ' + srv.results[0].status);
  await w.CompUI.open('comps'); await sleep(900);
  await click(w, '[data-act="edit"]', 1200);
  ok(qa(w, '.cu-modal [data-cd]').length >= 9, 'خانة الحد اليومي لكل مجال في نموذج الشبكة');
  const cd = qa(w, '.cu-modal [data-cd]')[0]; setV(w, cd, '8', 'change');
  await click(w, '.cu-modal [data-act="f_save"]', 100);
  await waitFor(async () => (await N("select daily_max_points d from competition_categories where id=$1", [catH]))[0].d !== null);
  ok(Number((await N("select daily_max_points d from competition_categories where id=$1", [catH]))[0].d) === 8, 'الحد اليومي المخصص (٨) حُفظ');
  await w.CompUI.open('grid'); await sleep(1300);
  ok(q(w, `[data-g="s1|${catH}"]`).placeholder === '٨', 'الرقم الباهت تغيّر إلى ٨ بعد التخصيص');

  console.log('\n[2] لوحة النقاط: اختيار متعدد للطلاب والمجالات');
  await click(w, '[data-act="tab"][data-t="pts"]', 1400);
  setV(w, q(w, '#pSearch'), 'ياسر'); ok(qa(w, '[data-ps]').length === 1, 'البحث يفلتر الطلاب');
  setV(w, q(w, '#pSearch'), '');
  await click(w, '[data-act="p_all"]', 200); ok(qa(w, '[data-ps]:checked').length === 2, 'تحديد كل الطلاب');
  await click(w, `[data-act="p_cat"][data-c="${catI}"]`, 100); await click(w, `[data-act="p_cat"][data-c="${catA}"]`, 100);
  ok(/٤ عملية/.test(q(w, '#pSummary').textContent), 'ملخص: ٢ طالب × ٢ مجال = ٤ عملية');
  await click(w, '[data-act="p_amt"][data-a="2"]', 100); setV(w, q(w, '#pReason'), 'تميز جماعي');
  await click(w, '[data-act="p_apply"]', 400); await click(w, '.cu-modal [data-r="1"]', 100);
  await waitFor(async () => (await N("select count(*)::int c from competition_scores where entry_type='adjust'"))[0].c === 4);
  ok((await N("select count(*)::int c from competition_scores where entry_type='adjust' and reason='تميز جماعي'"))[0].c === 4, 'طُبّقت ٤ عمليات بسبب واحد على طالبين ومجالين');

  console.log('\n[3] العمل دون إنترنت: نسخ محفوظة + طابور + رفع تلقائي');
  for(const t of ['comps', 'board', 'grid', 'pts']){ await click(w, `[data-act="tab"][data-t="${t}"]`, 1200); }
  w.__offline = true; Object.defineProperty(w.navigator, 'onLine', {get: () => false, configurable: true});
  await w.CompUI.open('grid'); await sleep(1500);
  ok(!!q(w, '#cuMain') && qa(w, '[data-g]').length >= 18 && /نسخة محفوظة|دون اتصال/.test(q(w, '#cuMain').textContent), 'الشبكة تعمل دون إنترنت من النسخة المحفوظة');
  const o1 = q(w, `[data-g="s2|${catH}"]`); setV(w, o1, '3'); await click(w, '[data-act="g_save"]', 800);
  ok(JSON.parse(w.localStorage.getItem('ridwan_comp_outbox') || '[]').length === 1 && q(w, `[data-g="s2|${catH}"]`).classList.contains('pend'), 'التقييم حُفظ محلياً بعلامة ⏳');
  const prev = addD(dateVal, -1);
  setV(w, q(w, '#gDate'), prev, 'change'); await sleep(1200);
  ok(qa(w, '[data-g]').length >= 18, 'يوم غير محفوظ مسبقاً: الشبكة تُبنى دون إنترنت من بيانات المسابقة');
  setV(w, q(w, `[data-g="s1|${catI}"]`), '2'); await click(w, '[data-act="g_save"]', 800);
  await click(w, '[data-act="tab"][data-t="pts"]', 1200);
  await click(w, '[data-act="p_none"]', 100); q(w, '[data-ps="s1"]').checked = true; fire(w, q(w, '[data-ps="s1"]'), 'change');
  await click(w, `[data-act="p_cat"][data-c="${catI}"]`, 100); await click(w, '[data-act="p_amt"][data-a="1"]', 100); setV(w, q(w, '#pReason'), 'التزام دون إنترنت');
  await click(w, '[data-act="p_apply"]', 900);
  const ob = JSON.parse(w.localStorage.getItem('ridwan_comp_outbox') || '[]');
  ok(ob.length === 3 && ob.some(x => x.type === 'adjust_many'), 'ثلاث عمليات معلّقة (تقييمان + نقاط): ' + ob.map(x => x.type).join(','));
  ok(/معلّقة/.test(q(w, '#cuMain').textContent) && /لم تُزامن/.test(q(w, '#cuSync').textContent), 'اللوحة والمؤشر يوضحان أن العمليات لم تُزامن');
  ok((await N("select count(*)::int c from competition_scores"))[0].c === 5, 'لا شيء وصل للسيرفر أثناء الانقطاع (١ + ٤ سابقة)');
  w.__offline = false; Object.defineProperty(w.navigator, 'onLine', {get: () => true, configurable: true}); w.dispatchEvent(new w.Event('online'));
  await waitFor(async () => (await N("select count(*)::int c from competition_scores"))[0].c === 8, 10000);
  ok((await N("select count(*)::int c from competition_scores"))[0].c === 8, 'عند عودة الإنترنت رُفعت العمليات الثلاث تلقائياً إلى السيرفر');
  ok(JSON.parse(w.localStorage.getItem('ridwan_comp_outbox') || '[]').length === 0, 'الطابور فرغ');
  dom.window.close();

  console.log('\n[4] جلسة الطالب بعد تحديث الصفحة');
  dom = await loginStu('stu1', 'pw1234'); w = dom.window; w.spSwitchTab('badges'); await sleep(2200);
  ok(!!q(w, '#sp-panel-badges .cu-hero'), 'واجهة المسابقة تعمل بعد الدخول');
  let st = dumpStorage(w); dom.window.close();
  ok(!!JSON.parse(st.ridwan_session).token, 'رمز الجلسة محفوظ بعد تحميل بيانات الطالب (كان يضيع سابقاً)');
  dom = await openApp(st); w = dom.window; await sleep(1500); w.spSwitchTab('badges'); await sleep(2200);
  ok(!!q(w, '#sp-panel-badges .cu-hero') && !/انتهت الجلسة/.test(q(w, '#sp-panel-badges').textContent), 'بعد تحديث الصفحة لا يظهر خطأ «انتهت الجلسة» وتعمل المسابقة');
  dom.window.close();
  const bad = JSON.parse(st.ridwan_session); delete bad.token; const st2 = {...st, ridwan_session: JSON.stringify(bad)};
  Object.keys(st2).filter(k => k.startsWith('ridwan_hq_')).forEach(k => delete st2[k]);
  dom = await openApp(st2); w = dom.window; await sleep(1500); w.spSwitchTab('badges'); await sleep(2000);
  ok(!!q(w, '#sp-panel-badges [data-act="relogin"]') || !!q(w, '#sp-panel-badges .cu-hero'), 'جلسة قديمة بلا رمز: تُستعاد تلقائياً أو يظهر زر «تسجيل الدخول من جديد»');
  const rb = q(w, '#sp-panel-badges [data-act="relogin"]'); if(rb){ rb.click(); await sleep(900); ok(!ev(w, '_currentUser') && w.localStorage.getItem('ridwan_session') === null, 'الزر يُخرج الطالب لشاشة الدخول'); }
  dom.window.close();

  console.log('\n[5] المحادثة: ردود وتعديل وحذف ومجموعة مثبّتة وترتيب ووسائط وصوت ونقطة حمراء');
  dom = await loginStu('stu1', 'pw1234'); w = dom.window; w.spSwitchTab('badges'); await sleep(1500);
  await click(w, '[data-act="seg"][data-seg="chat"]', 1300); await click(w, '#cuBody [data-act="c_open"]', 1200);
  setV(w, q(w, '#cuChatIn'), 'السلام عليكم يا شيخ'); await click(w, '[data-act="c_send"]', 1200);
  dom.window.close();
  dom = await login('supA', 'pw1234'); w = dom.window;
  await w.CompUI.notify(true);
  const dot = q(w, '#hqCompBtn .cu-reddot'); ok(!!dot && /١/.test(dot.textContent), 'نقطة حمراء على 🏆 عند وصول رسالة جديدة');
  await w.CompUI.open('chat'); await sleep(1200);
  ok(!!q(w, '#cuMain .cu-reddot') && !!q(w, '#cuTabs [data-t="chat"] .cu-reddot'), 'نقطة حمراء على تبويب المحادثات وعلى المحادثة');
  await click(w, '#cuMain [data-act="c_open"]', 1200);
  await click(w, '#cuChatList [data-act="c_msg"]', 300); await click(w, '.cu-modal [data-act="c_reply"]', 200);
  setV(w, q(w, '#cuChatIn'), 'وعليكم السلام ورحمة الله'); await click(w, '[data-act="c_send"]', 1300);
  const rep = (await N("select id,reply_to from student_chat where sender_role='supervisor'"))[0];
  const first = (await N("select id from student_chat where sender_role='student' order by id limit 1"))[0];
  ok(rep && String(rep.reply_to) === String(first.id), 'رد على رسالة محددة (reply_to)');
  ok(/وعليكم/.test(q(w, '#cuChatList').textContent) && !!q(w, '#cuChatList .cu-quote'), 'الاقتباس يظهر داخل الرسالة');
  await click(w, '#cuChatList .cu-bub.me [data-act="c_msg"]', 300); await click(w, '.cu-modal [data-act="c_edit"]', 200);
  ok(q(w, '#cuChatIn').value === 'وعليكم السلام ورحمة الله' && q(w, '#cuSendBtn').textContent === 'حفظ', 'وضع التعديل يعبّئ النص');
  setV(w, q(w, '#cuChatIn'), 'وعليكم السلام ورحمة الله وبركاته'); await click(w, '[data-act="c_send"]', 1300);
  ok((await N("select body,edited_at from student_chat where sender_role='supervisor'"))[0].body.endsWith('وبركاته') && (await N("select edited_at from student_chat where sender_role='supervisor'"))[0].edited_at !== null, 'تعديل الرسالة محفوظ مع علامة «معدّلة»');
  setV(w, q(w, '#cuChatIn'), 'رسالة للحذف'); await click(w, '[data-act="c_send"]', 1300);
  await click(w, '#cuChatList .cu-bub.me:last-of-type [data-act="c_msg"]', 300); await click(w, '.cu-modal [data-act="c_del"]', 300); await click(w, '.cu-modal [data-r="1"]', 1300);
  ok((await N("select count(*)::int c from student_chat where deleted_at is not null"))[0].c === 1 && /تم حذف هذه الرسالة/.test(q(w, '#cuChatList').textContent), 'حذف رسالة: تبقى علامة «تم حذف هذه الرسالة»');
  await click(w, '[data-act="c_back"]', 1000);
  await click(w, '[data-act="c_group"]', 800);
  setV(w, q(w, '#cuf_name'), 'مجموعة فرسان الحلقة'); setV(w, q(w, '#cuf_h'), 'hA1', 'change'); await click(w, '.cu-modal [data-r="1"]', 1500);
  const grp = (await N("select id,halaqa_id,allow_students from chat_groups"))[0];
  ok(grp && grp.halaqa_id === 'hA1' && grp.allow_students === true, 'مجموعة لجميع طلاب الحلقة أُنشئت');
  const firstRow = q(w, '#cuMain [data-act="c_open"]'); ok(/📌/.test(firstRow.textContent) && /مجموعة فرسان/.test(firstRow.textContent), 'المجموعة مثبّتة في أول قائمة المحادثات');
  await click(w, '[data-act="c_order"]', 300); await click(w, '#cuMain [data-act="c_dn"]', 800);
  ok((await N("select jsonb_array_length(order_keys)::int n from chat_prefs"))[0].n >= 2, 'تغيير ترتيب المحادثات محفوظ');
  ok(!/📌/.test(q(w, '#cuMain [data-act="c_open"]').textContent), 'المجموعة انتقلت من أول القائمة بعد تغيير الترتيب');
  await click(w, '[data-act="c_order"]', 300);
  const gRow = qa(w, '#cuMain [data-act="c_open"]').find(e => /مجموعة فرسان/.test(e.textContent)); gRow.click(); await sleep(1300);
  // إرسال صورة
  const fi = q(w, '#cuFImg'); const file = new w.File([new Uint8Array(1500).fill(7)], 'a.png', {type: 'image/png'});
  Object.defineProperty(fi, 'files', {value: [file], configurable: true}); fire(w, fi, 'change');
  await waitFor(async () => (await N("select count(*)::int c from student_chat where kind='image'"))[0].c === 1);
  ok((await N("select count(*)::int c from chat_media where complete and kind='image'"))[0].c === 1, 'صورة رُفعت (مجزّأة) وأُرسلت في المجموعة');
  await sleep(1200); ok(!!q(w, '#cuChatList .cu-media img'), 'الصورة تظهر داخل المحادثة');
  // تسجيل صوتي مباشر (محاكاة MediaRecorder)
  w.MediaRecorder = class { constructor(){ this.mimeType = 'audio/webm'; } static isTypeSupported(){ return true; } start(){ setTimeout(() => this.ondataavailable && this.ondataavailable({data: new w.Blob([new Uint8Array(3000).fill(3)])}), 80); } stop(){ setTimeout(() => this.onstop && this.onstop(), 30); } };
  Object.defineProperty(w.navigator, 'mediaDevices', {value: {getUserMedia: async () => ({getTracks: () => [{stop(){}}]})}, configurable: true});
  await click(w, '[data-act="c_rec"]', 500); ok(!!q(w, '[data-act="c_recs"]'), 'شريط التسجيل الصوتي المباشر يظهر');
  await click(w, '[data-act="c_recs"]', 100);
  await waitFor(async () => (await N("select count(*)::int c from student_chat where kind='audio'"))[0].c === 1);
  ok((await N("select count(*)::int c from student_chat where kind='audio'"))[0].c === 1, 'رسالة صوتية مباشرة أُرسلت');
  ok((await N("select count(*)::int c from chat_media where kind='audio' and complete"))[0].c === 1, 'الوسائط الصوتية مخزنة');
  const urlsB4 = 0; await click(w, '#cuChatList [data-act="c_play"]', 900);
  ok(!!q(w, '#cuChatList .cu-media audio'), 'تشغيل الصوت يحمّله ويعرض المشغّل');
  dom.window.close();
  dom = await loginStu('stu1', 'pw1234'); w = dom.window; w.spSwitchTab('badges'); await sleep(1200);
  await w.CompUI.notify(true);
  ok(!!q(w, '.sp-tab[data-tab="badges"] .cu-reddot'), 'نقطة حمراء على تبويب «فرسان القرآن» عند الطالب');
  await click(w, '[data-act="seg"][data-seg="chat"]', 1400);
  const rows = qa(w, '#cuBody [data-act="c_open"]'); ok(/📌/.test(rows[0].textContent) && /مجموعة فرسان/.test(rows[0].textContent), 'عند الطالب: المجموعة مثبّتة أولاً');
  rows[0].click(); await sleep(1300); ok(qa(w, '#cuChatList .cu-bub').length >= 2, 'الطالب يرى رسائل المجموعة');
  setV(w, q(w, '#cuChatIn'), 'جزاك الله خيراً'); await click(w, '[data-act="c_send"]', 1300);
  ok((await N("select count(*)::int c from student_chat where group_id is not null and sender_role='student'"))[0].c === 1, 'الطالب يكتب في المجموعة عندما يسمح المعلم');
  dom.window.close();

  console.log('\n[6] سلامة التشغيل');
  const errs = pgLog.filter(m => !/messages|created_at|is_read_by|violates|duplicate key/.test(m) && /does not exist|syntax error|permission denied for table (competition|assignment|student_chat|chat_)/.test(m));
  ok(errs.length === 0, 'لا أخطاء SQL أو وصول مباشر للجداول المغلقة (' + errs.length + ') ' + errs.slice(0, 2).join(' | '));
  const f = L.summary(); await L.pool.end(); process.exit(f ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
