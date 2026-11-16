const L = require('./e2e_lib');
const { ok, sleep, openApp, dumpStorage, admin, pgLog } = L;
const sha = s => require('crypto').createHash('sha256').update(s).digest('hex');
const val = (w, id, v) => { w.document.getElementById(id).value = v; };
const ev = (w, code) => w.eval(code);
const fire = (w, el, type) => el.dispatchEvent(new w.Event(type, {bubbles: true}));
const setV = (w, el, v, type = 'input') => { el.value = v; fire(w, el, type); };
const q = (w, sel) => w.document.querySelector(sel);
const qa = (w, sel) => [...w.document.querySelectorAll(sel)];
async function waitFor(fn, ms = 7000){ const t = Date.now(); while(Date.now() - t < ms){ try { const r = await fn(); if(r) return r; } catch(e){} await sleep(120); } return false; }
const N = async (sql, p) => (await admin(sql, p)).rows;

async function login(user, pass, storage){
  const dom = await openApp(storage); const w = dom.window;
  val(w, 'supUsername', user); val(w, 'supPassword', pass); await w.loginSupervisor(); await sleep(1500); return dom;
}
async function loginStu(user, pass){
  const dom = await openApp(); const w = dom.window;
  val(w, 'stuUsername', user); val(w, 'stuPassword', pass); await w.loginStudent(); await sleep(1800); return dom;
}

(async () => {
  await admin("truncate centers, users, halaqat, students, records, competitions, assignments, student_chat, app_ops, app_sessions, app_login_attempts, audit_log restart identity cascade");
  const today = (await N("select (now() at time zone 'Asia/Gaza')::date::text d"))[0].d;
  const cid = (await N("insert into centers(name,manager_name,status) values ('مركز','م','active') returning id"))[0].id;
  const h = sha('pw1234');
  await admin("insert into halaqat(id, center_id, name, teacher_username) values ('hA1',$1,'حلقة الفرسان','tA'),('hA2',$1,'حلقة ثانية','tB')", [cid]);
  await admin("insert into users(center_id,role,username,password_hash,full_name) values ($1,'supervisor','supA',$2,'مشرف')", [cid, h]);
  await admin("insert into users(center_id,role,username,password_hash,full_name,halaqa_id) values ($1,'teacher','tA',$2,'المعلم أحمد','hA1'),($1,'teacher','tB',$2,'المعلم بلال','hA2')", [cid, h]);
  for(const [u, n] of [['stu1', 'سعد'], ['stu2', 'ياسر'], ['stu3', 'عمر']]){
    const uid = (await N("insert into users(center_id,role,username,password_hash,full_name) values ($1,'student',$2,$3,$4) returning id", [cid, u, h, n]))[0].id;
    await admin("insert into students(id,halaqa_id,user_id,name,username_cache) values ($1,$2,$3,$4,$5)", ['s' + u.slice(3), u === 'stu3' ? 'hA2' : 'hA1', uid, n, u]);
  }

  console.log('\n[1] المشرف: زر الكأس + لوحة المسابقة + إنشاء ونشر مسابقة من الواجهة');
  let dom = await login('supA', 'pw1234'); let w = dom.window;
  w.CompUI.syncNav();
  ok(q(w, '#hqCompBtn').style.display !== 'none', 'زر 🏆 ظاهر في رأس المشرف');
  ok(q(w, '#nt-comp') !== null, 'أيقونة الكأس في شريط التنقل السفلي موجودة');
  await w.CompUI.open(); await sleep(800);
  ok(!!q(w, '#cuOverlay') && qa(w, '#cuTabs button').length === 7, 'لوحة المسابقة مفتوحة بسبعة تبويبات');
  q(w, '#cuOverlay [data-act="new"]').click(); await sleep(900);
  ok(!!q(w, '.cu-modal [data-f="name"]'), 'نموذج مسابقة جديدة ظهر');
  setV(w, q(w, '.cu-modal [data-f="name"]'), 'دوري فرسان القرآن');
  setV(w, q(w, '#fStart'), addD(today, -6), 'change'); setV(w, q(w, '#fEnd'), addD(today, 23), 'change');
  const hqBox = q(w, '.cu-modal [data-h="hA1"]'); hqBox.checked = true; fire(w, hqBox, 'change'); await sleep(200);
  ok(qa(w, '.cu-modal [data-sid]:checked').length === 2, 'طلاب الحلقة أُضيفوا تلقائياً كمشاركين');
  ok(qa(w, '.cu-modal [data-cn]').length === 10, 'شبكة التقييم الافتراضية: 10 مجالات');
  // تخصيص الشبكة: إضافة مجال
  q(w, '.cu-modal [data-act="f_catadd"]').click(); await sleep(100);
  const cn = qa(w, '.cu-modal [data-cn]'); setV(w, cn[cn.length - 1], 'مجال مخصص'); 
  q(w, '.cu-modal [data-act="f_preview"]').click(); await sleep(300);
  ok(/مجال مخصص/.test(w.document.body.innerHTML) && /معاينة المسابقة/.test(w.document.body.innerHTML), 'المعاينة تعرض المجال المضاف');
  qa(w, '.cu-modal').pop().remove();
  q(w, '.cu-modal [data-act="f_pub"]').click();
  const comp = await waitFor(async () => (await N("select id,status from competitions"))[0]);
  ok(comp && comp.status === 'active', 'المسابقة حُفظت ونُشرت في Supabase');
  ok((await N("select count(*)::int c from competition_participants where competition_id=$1", [comp.id]))[0].c === 2, 'المشاركان في قاعدة البيانات');
  ok((await N("select count(*)::int c from competition_categories where competition_id=$1", [comp.id]))[0].c === 11, '11 مجالاً (10 + المخصص)');
  const cats = await N("select id,key,name from competition_categories where competition_id=$1", [comp.id]);
  const catH = cats.find(c => c.key === 'hifz').id, catB = cats.find(c => c.key === 'bonus').id, catI = cats.find(c => c.key === 'itqan').id;

  console.log('\n[2] شبكة التقييم اليومي لعدة طلاب دفعة واحدة');
  await sleep(600);
  q(w, '[data-act="tab"][data-t="grid"]').click(); await sleep(1200);
  ok(qa(w, '[data-g]').length >= 2 * 10, 'الشبكة تعرض الطلاب × المجالات');
  const c1 = q(w, `[data-g="s1|${catH}"]`), c2 = q(w, `[data-g="s2|${catH}"]`), c3 = q(w, `[data-g="s1|${catI}"]`);
  setV(w, c1, '20'); setV(w, c2, '12'); setV(w, c3, '10');
  setV(w, c1, '30');
  ok(c1.classList.contains('bad'), 'قيمة تتجاوز الحد الأسبوعي تُعلَّم خاطئة فوراً');
  setV(w, c1, '20');
  q(w, '[data-act="g_save"]').click();
  await waitFor(async () => (await N("select count(*)::int c from competition_scores"))[0].c === 3);
  ok((await N("select count(*)::int c from competition_scores"))[0].c === 3, 'حُفظت 3 تقييمات في خطوة واحدة');
  ok((await N("select count(*)::int c from competition_score_audit"))[0].c === 3, 'سُجلت في سجل التدقيق');
  await sleep(600);
  ok(q(w, `[data-g="s1|${catH}"]`).value === '20', 'الشبكة تعرض القيمة المحفوظة بعد إعادة التحميل');

  console.log('\n[3] لوحة النقاط: إضافة وخصم بسبب إلزامي + تصحيح');
  q(w, '[data-act="tab"][data-t="pts"]').click(); await sleep(1200);
  const sel = q(w, '#pStu'); setV(w, sel, 's2', 'change'); setV(w, q(w, '#pCat'), catB, 'change'); await sleep(300);
  ok(qa(w, '[data-act="p_item"]').length === 5, 'خيارات المكافآت الجاهزة الخمسة ظاهرة لمجال المكافآت');
  q(w, '[data-act="p_item"]').click(); await sleep(100);
  q(w, '[data-act="p_apply"]').click();
  await waitFor(async () => (await N("select count(*)::int c from competition_scores where entry_type='bonus'"))[0].c === 1);
  ok((await N("select points,reason from competition_scores where entry_type='bonus'"))[0].reason === 'صيام تطوع اختياري', 'مكافأة بسبب مسجل');
  setV(w, q(w, '#pCat'), catH, 'change'); q(w, '[data-act="p_amt"][data-a="-2"]').click(); setV(w, q(w, '#pReason'), 'مخالفة سلوكية');
  q(w, '[data-act="p_apply"]').click(); await sleep(400);
  const conf = q(w, '.cu-modal [data-r="1"]'); ok(!!conf, 'تأكيد قبل الخصم'); if(conf) conf.click();
  await waitFor(async () => (await N("select count(*)::int c from competition_scores where entry_type='adjust'"))[0].c === 1);
  ok((await N("select points from competition_scores where entry_type='adjust'"))[0].points === '-2.00', 'خصم -2 مسجل');
  // بدون سبب
  q(w, '[data-act="p_amt"][data-a="1"]').click(); setV(w, q(w, '#pReason'), ''); q(w, '[data-act="p_apply"]').click(); await sleep(400);
  ok((await N("select count(*)::int c from competition_scores where entry_type='adjust'"))[0].c === 1, 'بدون سبب: لا تُسجَّل العملية');

  console.log('\n[4] الترتيب + تفاصيل الطالب + حذف عملية خاطئة بسبب');
  q(w, '[data-act="tab"][data-t="board"]').click(); await sleep(1200);
  ok(/سعد/.test(q(w, '#cuMain').textContent) && /ياسر/.test(q(w, '#cuMain').textContent), 'جدول الترتيب يعرض الطلاب');
  ok(q(w, '#cuMain table tr.clk td.nm').textContent.includes('سعد'), 'سعد في المركز الأول (30 نقطة)');
  q(w, '#cuMain tr.clk').click(); await sleep(900);
  ok(!!q(w, '.cu-modal [data-act="d_void"]'), 'نافذة تفاصيل الطالب فيها أزرار التصحيح');
  q(w, '.cu-modal [data-act="d_void"]').click(); await sleep(300);
  setV(w, q(w, '#cuf_r'), 'تم إدخالها بالخطأ'); q(w, '.cu-modal [data-r="1"]').click();
  await waitFor(async () => (await N("select count(*)::int c from competition_scores where voided"))[0].c === 1);
  ok((await N("select void_reason from competition_scores where voided"))[0].void_reason === 'تم إدخالها بالخطأ', 'الحذف سُجّل بالسبب (إلغاء لا حذف نهائي)');
  ok((await N("select count(*)::int c from competition_score_audit where action_type='void'"))[0].c === 1, 'سجل التدقيق يحوي الحذف');
  const st1 = dumpStorage(w); dom.window.close();

  console.log('\n[5] الطالب: واجهة «فرسان القرآن» مكان «إنجازاتي»');
  dom = await loginStu('stu1', 'pw1234'); w = dom.window;
  ok(ev(w, "_currentUser && _currentUser.role") === 'student', 'دخل الطالب');
  ok(/فرسان القرآن/.test(q(w, '.sp-tab[data-tab="badges"]').textContent) && !/إنجازاتي/.test(q(w, '.sp-tab[data-tab="badges"]').textContent), 'اسم التبويب تغيّر وبقيت أربعة تبويبات');
  ok(qa(w, '.sp-tab').length === 4, 'عدد تبويبات الطالب 4');
  w.spSwitchTab('badges'); await sleep(2200);
  const html = q(w, '#sp-panel-badges').textContent;
  ok(/دوري فرسان القرآن/.test(html) && /مجموع نقاطك/.test(html), 'بطاقة المسابقة ظاهرة');
  ok(/مركزك/.test(html) || /ترتيبي/.test(html), 'قسم الترتيب ظاهر');
  ok(/تقدمي الأسبوعي/.test(html) && /شارات المسابقة/.test(html) && /تفاصيل نقاطي/.test(html), 'التقدم الأسبوعي والشارات والتفاصيل ظاهرة');
  ok(/الأسبوع ١/.test(html), 'أسابيع المسابقة ظاهرة');
  ok(!q(w, '#sp-panel-badges [data-act="g_save"]') && !q(w, '#sp-panel-badges [data-act="p_apply"]'), 'لا أدوات تعديل نقاط في واجهة الطالب');
  const myTotal = (await N("select coalesce(sum(points),0)::numeric t from competition_scores where student_id='s1' and not voided"))[0].t;
  ok(q(w, '#sp-panel-badges .cu-hero .big').textContent.replace(/[٠-٩]/g, d => '٠١٢٣٤٥٦٧٨٩'.indexOf(d)) == String(Number(myTotal)), 'نقاط الطالب في الواجهة = قاعدة البيانات (' + myTotal + ')');
  // محاولة الطالب تعديل نقاطه عبر الواجهة البرمجية
  const bad = await w._rpcT('comp_adjust', {p_comp: comp.id, p_student: 's1', p_category: catH, p_points: 50, p_reason: 'غش', p_date: null, p_op: null});
  ok(bad && bad.ok === false && bad.error === 'forbidden', 'محاولة الطالب تعديل نقاطه رُفضت من السيرفر');
  const bad2 = await w._rpcT('comp_score_void', {p_score: (await N("select id from competition_scores limit 1"))[0].id, p_reason: 'غش', p_restore: false});
  ok(bad2 && bad2.ok === false && bad2.error === 'forbidden', 'محاولة الطالب حذف نقاط رُفضت');
  w.eval("document.documentElement.setAttribute('data-x','1')");
  const stuStore = dumpStorage(w); dom.window.close();

  console.log('\n[6] الواجب: المعلم ينشئ، الطالب يحل، النتيجة تظهر للمعلم');
  dom = await login('supA', 'pw1234'); w = dom.window; await w.CompUI.open('asg'); await sleep(900);
  q(w, '[data-act="a_new"]').click(); await sleep(900);
  setV(w, q(w, '[data-a="title"]'), 'واجب سورة الملك');
  const qp = q(w, '[data-qp="0"]'); setV(w, qp, 'كم آيات سورة الملك؟');
  const opts = qa(w, '[data-qo]'); setV(w, opts[0], '20'); setV(w, opts[1], '30');
  const rad = qa(w, '[data-qc]')[1]; rad.checked = true; fire(w, rad, 'change');
  q(w, '.cu-modal [data-act="a_q"][data-t="truefalse"]').click(); await sleep(100);
  setV(w, q(w, '[data-qp="1"]'), 'سورة الملك مكية'); 
  q(w, '.cu-modal [data-act="a_q"][data-t="text"]').click(); await sleep(100);
  setV(w, q(w, '[data-qp="2"]'), 'اكتب آية تعجبك');
  q(w, '.cu-modal [data-act="a_pub"]').click();
  const asg = await waitFor(async () => (await N("select id,status from assignments"))[0]);
  ok(asg && asg.status === 'published', 'الواجب نُشر');
  ok((await N("select count(*)::int c from assignment_questions where assignment_id=$1", [asg.id]))[0].c === 3, 'ثلاثة أسئلة (متعدد/صح-خطأ/مقالي)');
  dom.window.close();
  dom = await loginStu('stu1', 'pw1234'); w = dom.window; w.spSwitchTab('badges'); await sleep(1500);
  q(w, '[data-act="seg"][data-seg="asg"]').click(); await sleep(1200);
  ok(/واجب سورة الملك/.test(q(w, '#cuBody').textContent) && /لم تُحلّ/.test(q(w, '#cuBody').textContent), 'الواجب ظاهر للطالب كغير محلول');
  q(w, '#cuBody [data-act="asgOpen"]').click(); await sleep(1000);
  ok(qa(w, '[data-act="opt"]').length === 2 && !/correct/.test(q(w, '#cuBody').innerHTML), 'الأسئلة بلا الإجابات الصحيحة');
  qa(w, '[data-act="opt"]')[1].click(); await sleep(100);
  q(w, '[data-act="tf"][data-v="1"]').click(); await sleep(100);
  setV(w, q(w, '#cuBody textarea[data-q]'), 'تبارك الذي بيده الملك');
  q(w, '[data-act="asgSubmit"]').click(); await sleep(400); q(w, '.cu-modal [data-r="1"]').click();
  const sub = await waitFor(async () => (await N("select score,max_score,pending_manual from assignment_submissions"))[0]);
  ok(sub && Number(sub.score) === 2 && Number(sub.max_score) === 4 && sub.pending_manual, 'تصحيح تلقائي 2/4 والمقالي بانتظار المعلم');
  await sleep(1200);
  ok(/بانتظار تصحيح/.test(q(w, '#cuBody').textContent) || /تصحيح/.test(q(w, '#cuBody').textContent), 'الطالب يرى حالة التسليم');
  dom.window.close();
  dom = await login('supA', 'pw1234'); w = dom.window; await w.CompUI.open('asg'); await sleep(1000);
  q(w, '[data-act="a_res"]').click(); await sleep(1000);
  ok(/سعد/.test(q(w, '.cu-modal').textContent) && /بانتظار التصحيح/.test(q(w, '.cu-modal').textContent), 'نتائج الواجب تظهر للمعلم');
  q(w, '.cu-modal [data-act="a_sub"]').click(); await sleep(900);
  const gin = q(w, '[data-gr]'); setV(w, gin, '1.5', 'input'); q(w, '[data-act="a_grade"]').click();
  await waitFor(async () => Number((await N("select score from assignment_submissions"))[0].score) === 3.5);
  ok(Number((await N("select score from assignment_submissions"))[0].score) === 3.5, 'المعلم صحّح المقالي: 3.5/4');
  dom.window.close();

  console.log('\n[7] المحادثة بين الطالب والمعلم');
  dom = await loginStu('stu1', 'pw1234'); w = dom.window; w.spSwitchTab('badges'); await sleep(1300);
  q(w, '[data-act="seg"][data-seg="chat"]').click(); await sleep(1200);
  setV(w, q(w, '#cuChatIn'), 'السلام عليكم يا شيخ، سؤال في الحفظ'); q(w, '[data-act="chatSend"]').click();
  await waitFor(async () => (await N("select count(*)::int c from student_chat"))[0].c === 1);
  ok((await N("select sender_role from student_chat"))[0].sender_role === 'student', 'رسالة الطالب في قاعدة البيانات');
  dom.window.close();
  dom = await login('supA', 'pw1234'); w = dom.window; await w.CompUI.open('chat'); await sleep(1000);
  ok(/سعد/.test(q(w, '#cuMain').textContent) && /جديدة/.test(q(w, '#cuMain').textContent), 'المعلم يرى المحادثة برسالة جديدة');
  q(w, '[data-act="c_open"]').click(); await sleep(1000);
  setV(w, q(w, '#cuTIn'), 'وعليكم السلام ورحمة الله'); q(w, '[data-act="c_send"]').click();
  await waitFor(async () => (await N("select count(*)::int c from student_chat"))[0].c === 2);
  ok((await N("select sender_role from student_chat order by id desc limit 1"))[0].sender_role === 'supervisor', 'رد المعلم مسجل');
  dom.window.close();

  console.log('\n[8] انقطاع الإنترنت: التقييم يُحفظ كمعلّق ولا يظهر كمحفوظ ثم يُزامَن');
  dom = await login('supA', 'pw1234'); w = dom.window; await w.CompUI.open('grid'); await sleep(1500);
  const cell = q(w, `[data-g="s2|${catI}"]`); const before = (await N("select count(*)::int c from competition_scores"))[0].c;
  w.__offline = true; Object.defineProperty(w.navigator, 'onLine', {get: () => false, configurable: true});
  setV(w, cell, '4'); q(w, '[data-act="g_save"]').click(); await sleep(900);
  ok((await N("select count(*)::int c from competition_scores"))[0].c === before, 'لم يُحفظ في السيرفر أثناء الانقطاع');
  ok(JSON.parse(w.localStorage.getItem('ridwan_comp_outbox') || '[]').length === 1, 'العملية في الطابور المحلي');
  ok(q(w, '#cuSync').classList.contains('warn') && /لم تُزامن/.test(q(w, '#cuSync').textContent), 'المؤشر يقول «لم تُزامن» بوضوح');
  ok(q(w, `[data-g="s2|${catI}"]`).classList.contains('pend'), 'الخانة معلّمة ⏳ (ليست محفوظة)');
  w.__offline = false; Object.defineProperty(w.navigator, 'onLine', {get: () => true, configurable: true});
  w.dispatchEvent(new w.Event('online')); 
  await waitFor(async () => (await N("select count(*)::int c from competition_scores"))[0].c === before + 1, 9000);
  ok((await N("select count(*)::int c from competition_scores"))[0].c === before + 1, 'بعد عودة الاتصال زُوملت العملية تلقائياً');
  ok(JSON.parse(w.localStorage.getItem('ridwan_comp_outbox') || '[]').length === 0, 'الطابور فرغ');
  // منع التكرار: إرسال العملية نفسها مرتين
  const opId = '11111111-1111-4111-8111-111111111111';
  const r1 = await w._rpcT('comp_adjust', {p_comp: comp.id, p_student: 's1', p_category: catB, p_points: 1, p_reason: 'اختبار', p_date: null, p_op: opId});
  const r2 = await w._rpcT('comp_adjust', {p_comp: comp.id, p_student: 's1', p_category: catB, p_points: 1, p_reason: 'اختبار', p_date: null, p_op: opId});
  ok(r1.ok && r2.duplicate === true && (await N("select count(*)::int c from competition_scores where reason='اختبار'"))[0].c === 1, 'النقر المزدوج/إعادة الاتصال لا يكرر العملية');
  dom.window.close();

  console.log('\n[9] المعلم: صلاحيته على حلقته فقط، وانتهاء المسابقة ثم مسابقة ثانية مستقلة');
  dom = await login('tA', 'pw1234'); w = dom.window;
  ok(ev(w, "_currentUser && _currentUser.role") === 'teacher', 'دخل المعلم');
  w.CompUI.syncNav(); ok(q(w, '#nt-comp').style.display !== 'none', 'الكأس ظاهرة للمعلم');
  await w.CompUI.open('board'); await sleep(1500);
  ok(/سعد/.test(q(w, '#cuMain').textContent), 'المعلم يرى ترتيب حلقته');
  const forb = await w._rpcT('comp_adjust', {p_comp: comp.id, p_student: 's3', p_category: catH, p_points: 3, p_reason: 'خارج الصلاحية', p_date: null, p_op: null});
  ok(forb.ok === false, 'لا يستطيع تقييم طالب خارج حلقته: ' + forb.error);
  // المعلم ينهي المسابقة (مسابقة حلقته)
  await w.CompUI.open('comps'); await sleep(1000);
  q(w, '[data-act="status"][data-s="ended"]').click(); await sleep(400); q(w, '.cu-modal [data-r="1"]').click();
  await waitFor(async () => (await N("select status from competitions"))[0].status === 'ended');
  ok((await N("select status from competitions"))[0].status === 'ended', 'المسابقة انتهت');
  const afterEnd = await w._rpcT('comp_adjust', {p_comp: comp.id, p_student: 's1', p_category: catH, p_points: 1, p_reason: 'بعد الانتهاء', p_date: null, p_op: null});
  ok(afterEnd.ok === false && afterEnd.error === 'locked', 'المعلم لا يعدّل نتائج مسابقة منتهية');
  dom.window.close();
  dom = await loginStu('stu1', 'pw1234'); w = dom.window; w.spSwitchTab('badges'); await sleep(2000);
  ok(/انتهت المسابقة/.test(q(w, '#sp-panel-badges').textContent) && /النهائ/.test(q(w, '#sp-panel-badges').textContent), 'الطالب يرى النتائج النهائية بعد الانتهاء');
  dom.window.close();
  dom = await login('supA', 'pw1234'); w = dom.window; await w.CompUI.open('comps'); await sleep(900);
  q(w, '[data-act="new"]').click(); await sleep(900);
  setV(w, q(w, '[data-f="name"]'), 'الدوري الثاني'); setV(w, q(w, '#fStart'), today, 'change'); setV(w, q(w, '#fEnd'), addD(today, 29), 'change');
  const hb = q(w, '.cu-modal [data-h="hA1"]'); hb.checked = true; fire(w, hb, 'change'); await sleep(150);
  q(w, '.cu-modal [data-act="f_pub"]').click();
  await waitFor(async () => (await N("select count(*)::int c from competitions"))[0].c === 2);
  const comp2 = (await N("select id,status from competitions where name='الدوري الثاني'"))[0];
  ok(comp2 && comp2.status === 'active', 'مسابقة ثانية نُشرت بعد انتهاء الأولى');
  ok((await N("select count(*)::int c from competition_scores where competition_id=$1", [comp2.id]))[0].c === 0, 'نتائج المسابقة الثانية مستقلة (صفر)');
  ok((await N("select count(*)::int c from competition_scores where competition_id=$1", [comp.id]))[0].c >= 6, 'نتائج الأولى محفوظة');
  dom.window.close();

  console.log('\n[10] سلامة التشغيل');
  const errs = pgLog.filter(m => !/messages|created_at|is_read_by|violates|duplicate key/.test(m) && /does not exist|syntax error|permission denied for table (competition|assignment|student_chat)/.test(m));
  ok(errs.length === 0, 'لا أخطاء SQL أو وصول مباشر للجداول المغلقة (' + errs.length + ') ' + errs.slice(0, 2).join(' | '));
  const f = L.summary(); await L.pool.end(); process.exit(f ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
function addD(s, n){ const d = new Date(s + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); }
