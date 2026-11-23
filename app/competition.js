/* ═══════════════════════════════════════════════════════════════════════
   دوري فرسان القرآن + الواجبات + محادثة الطالب والمعلم
   وحدة مستقلة داخل تطبيق مركز الكتاب (v2.1.0)
   - كل البيانات والصلاحيات في Supabase عبر دوال RPC تتحقق من الرمز والدور والمركز والحلقة.
   - لا تُحفظ النقاط محلياً؛ ما لم يُزامَن يظهر بوضوح بعلامة «⏳ لم تُزامن».
═══════════════════════════════════════════════════════════════════════ */
(function(){
'use strict';
const CU = window.CompUI = {};

/* ───────── أدوات عامة ───────── */
const $ = id => document.getElementById(id);
const E = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const AD = n => String(n).replace(/\d/g, d => '٠١٢٣٤٥٦٧٨٩'[d]);
const NF = n => { if(n == null || n === '') return '—'; const v = Math.round(Number(n) * 100) / 100; return AD(String(v)); };
const SG = n => (Number(n) > 0 ? '+' : '') + NF(n);
const UID = () => (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
  : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
const wait = ms => new Promise(r => setTimeout(r, ms));
const ymd = d => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
const addDays = (s, n) => { const d = new Date(String(s).slice(0, 10) + 'T12:00:00'); d.setDate(d.getDate() + n); return ymd(d); };
const fmtD = d => { if(!d) return '—'; const p = String(d).slice(0, 10).split('-'); return AD(p[2] + '/' + p[1] + '/' + p[0]); };
const fmtT = ts => { try { return new Date(ts).toLocaleString('ar-EG', {dateStyle: 'medium', timeStyle: 'short'}); } catch(e){ return ''; } };
const toast2 = m => { try { toast(m); } catch(e){} };
const online = () => navigator.onLine !== false;
const role = () => (typeof _currentUser !== 'undefined' && _currentUser) ? _currentUser.role : null;
const STATE = {
  draft:    ['مسودة', 'gray'], upcoming: ['لم تبدأ', 'blue'], running: ['جارية', 'green'],
  paused:   ['متوقفة مؤقتاً', 'amber'], ended: ['انتهت', 'slate']
};
const LEVELS = ['مبتدئ', 'متوسط', 'متقدم'];
const ERR = {
  forbidden: 'ليست لديك صلاحية لهذا الإجراء', auth: 'انتهت الجلسة — سجّل الدخول من جديد', not_found: 'العنصر غير موجود',
  locked: 'المسابقة منتهية ومقفلة — التعديل بعد الإغلاق للمشرف فقط وبسبب موثق', not_active: 'المسابقة غير نشطة الآن (متوقفة أو لم تُنشر)',
  out_of_window: 'التاريخ خارج فترة المسابقة أو في المستقبل', bad_date: 'تاريخ غير صالح', bad_dates: 'تواريخ المسابقة غير صالحة',
  bad_name: 'اسم المسابقة قصير جداً', no_halaqa: 'اختر حلقة واحدة على الأقل', bad_halaqa: 'حلقة غير تابعة لمركزك',
  no_participants: 'أضف طالباً واحداً على الأقل قبل النشر', student_not_found: 'بعض الطلاب غير موجودين في هذه الحلقات (تأكد من مزامنتهم)',
  dup_category: 'اسم مجال مكرر', no_core_category: 'يلزم مجال تقييم واحد على الأقل', bad_categories: 'مجالات التقييم غير صالحة',
  bad_points: 'قيمة النقاط غير صالحة', bad_category: 'مجال غير صالح', not_participant: 'الطالب غير مشارك في المسابقة',
  reason_required: 'اكتب سبب العملية (حرفان على الأقل)', conflict: 'تم تعديل هذه البيانات من جهاز آخر — حدّث الصفحة ثم أعد المحاولة',
  start_locked: 'لا يمكن تغيير تاريخ البداية بعد تسجيل نقاط', end_before_scores: 'تاريخ النهاية قبل تقييمات مسجلة',
  not_deletable: 'يمكن حذف المسودات الخالية من النقاط فقط', voided: 'هذه العملية ملغاة بالفعل', not_voided: 'العملية غير ملغاة',
  duplicate: 'يوجد تقييم لنفس الطالب والمجال واليوم', past_end: 'انتهت المدة — لا يمكن إعادة الفتح', bad_status: 'حالة غير صالحة',
  already_submitted: 'سبق أن سلّمت هذا الواجب', past_due: 'انتهى موعد تسليم الواجب', closed: 'الواجب مغلق', has_submissions: 'لا يمكن تغيير الأسئلة بعد وصول إجابات',
  no_questions: 'أضف سؤالاً واحداً على الأقل', bad_title: 'عنوان قصير جداً', bad_question: 'سؤال غير صالح (تحقق من الخيارات والإجابة الصحيحة)',
  too_many: 'عدد الأسئلة كبير جداً', bad_body: 'الرسالة فارغة أو طويلة جداً', rate_limited: 'رسائل كثيرة — انتظر قليلاً', bad_answers: 'إجابات غير صالحة',
  bad_items: 'لا توجد تقييمات للحفظ'
};
function errMsg(r){
  if(!r) return 'تعذّر تنفيذ العملية';
  if(r.error === 'cap') return 'تجاوز الحد الأسبوعي — المتبقي ' + NF(r.remaining);
  if(r.error === 'below_zero') return 'لا يمكن أن ينزل مجموع المجال عن صفر (المتاح ' + NF(r.available) + ')';
  if(r.error === 'overlap') return 'توجد مسابقة نشطة متداخلة: «' + (r.name || '') + '» — أنهِها أو أوقفها أولاً';
  return ERR[r.error] || ('تعذّر تنفيذ العملية (' + (r.error || '؟') + ')');
}
function netMsg(e){
  if(typeof _isSqlMissing === 'function' && _isSqlMissing(e)) return 'قاعدة البيانات تحتاج تحديثاً — شغّل ملف 03_competitions.sql في Supabase';
  if(!online() || (typeof _isNetErr === 'function' && _isNetErr(e))) return 'لا يوجد اتصال بالإنترنت';
  return (e && e.message) || 'خطأ غير متوقع';
}
/* ذاكرة قراءة محلية: عند انقطاع الإنترنت تُعرض آخر نسخة محفوظة (للقراءة فقط) */
const LAST = {stale: null};
const CACHE_READS = new Set(['comp_list', 'comp_get', 'comp_leaderboard', 'comp_student_detail', 'comp_grid', 'comp_roster', 'comp_defaults', 'comp_report', 'asg_list', 'asg_get', 'chat2_threads', 'chat2_get']);
const myUid = () => (typeof _currentUser !== 'undefined' && _currentUser && _currentUser.id) || '';
const ckey = (n, a) => 'ridwan_cc:' + myUid() + ':' + n + ':' + JSON.stringify(a || {}, Object.keys(a || {}).sort());
function cacheSet(n, a, r){
  try {
    const body = JSON.stringify({t: Date.now(), r}); if(body.length > 220000) return;
    localStorage.setItem(ckey(n, a), body);
    let tot = 0; const ks = [];
    for(let i = 0; i < localStorage.length; i++){ const k = localStorage.key(i); if(k && k.startsWith('ridwan_cc:')){ const v = localStorage.getItem(k) || ''; tot += v.length; let t = 0; try { t = JSON.parse(v).t; } catch(e){} ks.push([k, t, v.length]); } }
    if(tot > 2000000){ ks.sort((x, y) => x[1] - y[1]); for(const k of ks){ localStorage.removeItem(k[0]); tot -= k[2]; if(tot < 1400000) break; } }
  } catch(e){ /* الذاكرة ممتلئة: نتجاهل */ }
}
function cacheGet(n, a){ try { return JSON.parse(localStorage.getItem(ckey(n, a)) || 'null'); } catch(e){ return null; } }
const staleHtml = () => LAST.stale ? `<div class="cu-warn">📴 تعرض نسخة محفوظة من ${fmtT(LAST.stale)} — ستتحدث تلقائياً عند عودة الاتصال، ويمكنك متابعة التقييم وسيُرفع لاحقاً.</div>` : '';
/* استدعاء دالة سيرفر برمز الجلسة؛ يرمي خطأ بنص عربي واضح */
async function api(name, args){
  let r;
  try { r = await _rpcT(name, args || {}, true); }
  catch(e){
    const net = !online() || (typeof _isNetErr === 'function' && _isNetErr(e));
    if(net && CACHE_READS.has(name)){ const c = cacheGet(name, args); if(c){ LAST.stale = c.t; return Object.assign({}, c.r, {_cached: c.t}); } }
    const x = new Error(netMsg(e)); x.net = net; throw x;
  }
  if(!r || r.ok === false){ const x = new Error(errMsg(r)); x.r = r; x.auth = !!(r && r.error === 'auth'); throw x; }
  if(CACHE_READS.has(name)) cacheSet(name, args, r);
  return r;
}

/* ───────── التنسيق ───────── */
const CSS = `
.cu-root{--g:#0e9f6e;--g2:#10b981;--b:#2563eb;--bg:#f3f6fb;--card:#fff;--ink:#0f172a;--mut:#64748b;--bd:#e2e8f0;--soft:#f1f5f9;--amber:#f59e0b;--red:#ef4444;--ok-bg:#dcfce7;--ok-ink:#166534;--shadow:0 6px 20px rgba(15,23,42,.07);
  font-family:inherit;color:var(--ink);direction:rtl;text-align:right}
#studentPortal[data-dark="1"] .cu-root{--bg:#0b1220;--card:#141c2e;--ink:#e8edf7;--mut:#94a3b8;--bd:#24304a;--soft:#1b2540;--ok-bg:#12372a;--ok-ink:#86efac;--shadow:0 6px 20px rgba(0,0,0,.35)}
.cu-root *{box-sizing:border-box}
.cu-card{background:var(--card);border:1px solid var(--bd);border-radius:18px;padding:14px;margin-bottom:12px;box-shadow:var(--shadow)}
.cu-h{font-size:14px;font-weight:900;margin:0 0 10px;display:flex;align-items:center;gap:8px}
.cu-h .dot{width:5px;height:16px;border-radius:4px;background:linear-gradient(var(--g2),var(--b))}
.cu-mut{color:var(--mut);font-size:11.5px;line-height:1.7}
.cu-hero{border-radius:22px;padding:18px;color:#fff;background:linear-gradient(135deg,#0e9f6e 0%,#0d9488 45%,#2563eb 100%);box-shadow:0 10px 28px rgba(14,159,110,.28);margin-bottom:12px;position:relative;overflow:hidden}
.cu-hero:after{content:"🏆";position:absolute;left:-6px;bottom:-18px;font-size:92px;opacity:.13}
.cu-hero h2{margin:0 0 3px;font-size:18px;font-weight:900}
.cu-hero .sub{font-size:12px;opacity:.92;margin-bottom:10px;line-height:1.6}
.cu-hero .big{font-size:38px;font-weight:900;line-height:1}
.cu-hero .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
.cu-chip{display:inline-flex;align-items:center;gap:4px;padding:4px 10px;border-radius:99px;font-size:11px;font-weight:800;background:rgba(255,255,255,.2);color:#fff;border:1px solid rgba(255,255,255,.25)}
.cu-st{display:inline-block;padding:3px 10px;border-radius:99px;font-size:10.5px;font-weight:900}
.cu-st.green{background:#dcfce7;color:#166534}.cu-st.blue{background:#dbeafe;color:#1e40af}.cu-st.amber{background:#fef3c7;color:#92400e}
.cu-st.gray{background:#e2e8f0;color:#334155}.cu-st.slate{background:#e2e8f0;color:#475569}
.cu-grid2{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.cu-stat{background:var(--soft);border-radius:14px;padding:11px;text-align:center}
.cu-stat b{display:block;font-size:20px;font-weight:900}
.cu-stat span{font-size:10.5px;color:var(--mut);font-weight:700}
.cu-seg{display:flex;gap:4px;background:var(--soft);padding:4px;border-radius:14px;margin-bottom:12px}
.cu-seg button{flex:1;border:0;background:transparent;color:var(--mut);font:inherit;font-size:12px;font-weight:800;padding:9px 4px;border-radius:11px;cursor:pointer;position:relative}
.cu-seg button.on{background:var(--card);color:var(--ink);box-shadow:0 2px 8px rgba(15,23,42,.1)}
.cu-dotb{position:absolute;top:3px;left:8px;min-width:16px;height:16px;border-radius:99px;background:var(--red);color:#fff;font-size:9px;font-weight:900;display:flex;align-items:center;justify-content:center;padding:0 4px}
.cu-btn{border:0;font:inherit;font-weight:800;font-size:12.5px;border-radius:12px;padding:10px 14px;cursor:pointer;background:linear-gradient(135deg,var(--g),var(--b));color:#fff}
.cu-btn.sec{background:var(--soft);color:var(--ink)}.cu-btn.red{background:#fee2e2;color:#b91c1c}.cu-btn.amb{background:#fef3c7;color:#92400e}
.cu-btn.sm{padding:6px 10px;font-size:11px;border-radius:10px}.cu-btn.full{width:100%}.cu-btn[disabled]{opacity:.5;pointer-events:none}
.cu-in,.cu-sel,.cu-ta{width:100%;border:1.5px solid var(--bd);background:var(--card);color:var(--ink);border-radius:12px;padding:10px 12px;font:inherit;font-size:13px;outline:none}
.cu-in:focus,.cu-sel:focus,.cu-ta:focus{border-color:var(--g2)}
.cu-ta{min-height:72px;resize:vertical}
.cu-lbl{display:block;font-size:11px;font-weight:800;color:var(--mut);margin:10px 0 4px}
.cu-podium{display:flex;align-items:flex-end;justify-content:center;gap:8px;margin:4px 0 6px}
.cu-pod{flex:1;max-width:110px;text-align:center;border-radius:14px 14px 0 0;padding:10px 4px 8px;background:var(--soft)}
.cu-pod .m{font-size:24px}.cu-pod .n{font-size:11.5px;font-weight:900;margin:2px 0;word-break:break-word}.cu-pod .p{font-size:13px;font-weight:900;color:var(--g)}
.cu-pod.p1{min-height:118px;background:linear-gradient(#fef9c3,var(--soft))}.cu-pod.p2{min-height:96px}.cu-pod.p3{min-height:82px}
#studentPortal[data-dark="1"] .cu-pod.p1{background:linear-gradient(#4a3f10,var(--soft))}
.cu-tbl{width:100%;border-collapse:collapse;font-size:12px}
.cu-tbl th{color:var(--mut);font-size:10.5px;font-weight:800;padding:7px 5px;text-align:center;border-bottom:1px solid var(--bd);white-space:nowrap}
.cu-tbl td{padding:8px 5px;text-align:center;border-bottom:1px solid var(--bd)}
.cu-tbl td.nm,.cu-tbl th.nm{text-align:right}
.cu-tbl tr.me td{background:rgba(16,185,129,.12);font-weight:900}
.cu-tbl tr.clk{cursor:pointer}
.cu-scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
.cu-bar{height:9px;border-radius:99px;background:var(--soft);overflow:hidden}
.cu-bar i{display:block;height:100%;border-radius:99px;background:linear-gradient(90deg,var(--g2),var(--b))}
.cu-wk{margin-bottom:10px}.cu-wk .t{display:flex;justify-content:space-between;font-size:12px;font-weight:800;margin-bottom:4px}
.cu-wk.cur .t{color:var(--g)}
.cu-badges{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
.cu-bdg{text-align:center;padding:10px 4px;border-radius:14px;background:var(--soft);opacity:.55}
.cu-bdg.on{opacity:1;background:linear-gradient(#fef3c7,#fde68a);color:#78350f}
.cu-bdg .i{font-size:26px}.cu-bdg .n{font-size:10.5px;font-weight:900;margin-top:2px}.cu-bdg .pr{font-size:9.5px;margin-top:2px}
.cu-msg{background:linear-gradient(135deg,rgba(16,185,129,.12),rgba(37,99,235,.1));border:1px solid var(--bd);border-radius:16px;padding:13px;font-size:13px;font-weight:800;line-height:1.8;text-align:center}
.cu-empty{text-align:center;padding:34px 14px;color:var(--mut)}.cu-empty .i{font-size:46px;margin-bottom:8px}.cu-empty b{display:block;color:var(--ink);font-size:14px;margin-bottom:4px}
.cu-skel{height:70px;border-radius:16px;margin-bottom:10px;background:linear-gradient(90deg,var(--soft) 25%,var(--bd) 50%,var(--soft) 75%);background-size:200% 100%;animation:cusk 1.2s infinite}
@keyframes cusk{to{background-position:-200% 0}}
.cu-err{background:#fef2f2;border:1px solid #fecaca;color:#991b1b;border-radius:14px;padding:12px;font-size:12.5px;font-weight:700;margin-bottom:10px;line-height:1.7}
.cu-ent{display:flex;justify-content:space-between;gap:8px;padding:8px 0;border-bottom:1px solid var(--bd);font-size:12px}
.cu-ent .pt{font-weight:900;white-space:nowrap}.cu-ent .pt.pos{color:#059669}.cu-ent .pt.neg{color:#dc2626}.cu-ent.void{opacity:.5;text-decoration:line-through}
.cu-q{border:1.5px solid var(--bd);border-radius:14px;padding:12px;margin-bottom:10px}
.cu-opt{display:flex;gap:8px;align-items:center;padding:9px 10px;border:1.5px solid var(--bd);border-radius:11px;margin-top:6px;cursor:pointer;font-size:13px}
.cu-opt.on{border-color:var(--g2);background:rgba(16,185,129,.12)}.cu-opt.right{border-color:#10b981;background:rgba(16,185,129,.18)}.cu-opt.wrong{border-color:#ef4444;background:rgba(239,68,68,.12)}
.cu-chat{display:flex;flex-direction:column;gap:8px;max-height:52vh;overflow-y:auto;padding:4px 2px 8px}
.cu-bub{max-width:82%;padding:9px 12px;border-radius:15px;font-size:13px;line-height:1.7;word-break:break-word}
.cu-bub.me{align-self:flex-start;background:linear-gradient(135deg,var(--g),var(--b));color:#fff;border-bottom-right-radius:4px}
.cu-bub.th{align-self:flex-end;background:var(--soft);border-bottom-left-radius:4px}
.cu-bub small{display:block;opacity:.7;font-size:9.5px;margin-top:3px}
.cu-bub.pend{opacity:.6}
.cu-send{display:flex;gap:8px;margin-top:8px}.cu-send .cu-in{flex:1}
.cu-quote{border-right:3px solid var(--g2);padding:5px 9px;margin-bottom:6px;font-size:11px;background:rgba(15,23,42,.07);border-radius:9px;cursor:pointer;line-height:1.6}
.cu-bub.me .cu-quote{background:rgba(255,255,255,.2)}
.cu-media img,.cu-media video{display:block;margin-bottom:4px}.cu-media audio{max-width:210px;height:38px}
.cu-reddot{position:absolute;top:1px;left:4px;min-width:17px;height:17px;border-radius:99px;background:#ef4444;color:#fff;font-size:9.5px;font-weight:900;font-style:normal;display:flex;align-items:center;justify-content:center;padding:0 4px;box-shadow:0 0 0 2px rgba(255,255,255,.9);z-index:5;line-height:1}
/* ===== واجهة المعلم (ملء الشاشة) ===== */
.cu-overlay{position:fixed;inset:0;z-index:9000;background:var(--bg);display:flex;flex-direction:column}
.cu-top{display:flex;align-items:center;gap:8px;padding:12px 12px 8px;background:linear-gradient(135deg,#0e9f6e,#2563eb);color:#fff}
.cu-top .tt{flex:1;font-size:15px;font-weight:900}.cu-top button{background:rgba(255,255,255,.2);color:#fff;border:0;border-radius:10px;padding:7px 11px;font:inherit;font-weight:800;font-size:13px;cursor:pointer}
.cu-sync{font-size:10px;font-weight:800;background:rgba(255,255,255,.2);padding:4px 9px;border-radius:99px}
.cu-sync.warn{background:#fbbf24;color:#451a03}
.cu-tabs{display:flex;gap:4px;padding:8px 10px;overflow-x:auto;background:var(--card);border-bottom:1px solid var(--bd);-webkit-overflow-scrolling:touch}
.cu-tabs button{flex:0 0 auto;border:0;background:var(--soft);color:var(--mut);font:inherit;font-size:12px;font-weight:800;padding:8px 12px;border-radius:12px;cursor:pointer;white-space:nowrap;position:relative}
.cu-tabs button.on{background:linear-gradient(135deg,var(--g),var(--b));color:#fff}
.cu-cbar{display:flex;gap:8px;align-items:center;padding:8px 10px;background:var(--card);border-bottom:1px solid var(--bd)}
.cu-cbar .cu-sel{flex:1;padding:8px 10px;font-size:12.5px}
.cu-main{flex:1;overflow-y:auto;padding:12px 12px 90px;-webkit-overflow-scrolling:touch}
.cu-modal{position:fixed;inset:0;z-index:9500;background:rgba(10,15,30,.66);backdrop-filter:blur(6px);display:flex;align-items:flex-end;justify-content:center}
.cu-sheet{background:var(--bg);width:100%;max-width:520px;max-height:94vh;overflow-y:auto;border-radius:22px 22px 0 0;padding:16px 14px 22px;animation:cuup .22s ease}
@keyframes cuup{from{transform:translateY(30px);opacity:0}}
.cu-sheet h3{margin:0 0 10px;font-size:15px;font-weight:900}
.cu-row{display:flex;gap:8px;align-items:center}.cu-row.wrap{flex-wrap:wrap}.cu-grow{flex:1}
.cu-chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}
.cu-pill{border:1.5px solid var(--bd);background:var(--card);color:var(--ink);font:inherit;font-size:12px;font-weight:800;padding:7px 12px;border-radius:99px;cursor:pointer}
.cu-pill.on{background:linear-gradient(135deg,var(--g),var(--b));color:#fff;border-color:transparent}
.cu-pill.neg{color:#b91c1c;border-color:#fecaca}.cu-pill.neg.on{background:#ef4444;color:#fff}
.cu-g{border-collapse:separate;border-spacing:0;font-size:12px;min-width:100%}
.cu-g th{position:sticky;top:0;background:var(--card);z-index:2;padding:7px 4px;font-size:10px;color:var(--mut);font-weight:800;border-bottom:1px solid var(--bd);min-width:64px;vertical-align:bottom}
.cu-g td{padding:5px 3px;border-bottom:1px solid var(--bd);text-align:center}
.cu-g td.nm,.cu-g th.nm{position:sticky;right:0;background:var(--card);z-index:3;text-align:right;min-width:104px;max-width:120px;padding:6px 8px;font-weight:800;font-size:12px;box-shadow:-3px 0 6px rgba(15,23,42,.06)}
.cu-g input{width:58px;text-align:center;border:1.5px solid var(--bd);border-radius:9px;padding:7px 2px;font:inherit;font-size:13px;font-weight:800;background:var(--card);color:var(--ink)}
.cu-g input.dirty{border-color:var(--amber);background:#fffbeb;color:#78350f}.cu-g input.ok{border-color:#10b981;background:#ecfdf5}
.cu-g input.bad{border-color:#ef4444;background:#fef2f2}.cu-g input.pend{border-style:dashed;border-color:#f59e0b}
.cu-g input:disabled{opacity:.55}
.cu-g input::placeholder{color:var(--mut);opacity:.38;font-weight:700}
.cu-g .rem{display:block;font-size:9px;color:var(--mut);margin-top:2px}
.cu-bar2{position:fixed;left:0;right:0;bottom:0;z-index:9100;padding:10px 12px 14px;background:var(--card);border-top:1px solid var(--bd);box-shadow:0 -6px 20px rgba(15,23,42,.1)}
.cu-qk{display:flex;gap:6px;overflow-x:auto;margin-bottom:8px}
.cu-warn{background:#fffbeb;border:1px solid #fde68a;color:#92400e;border-radius:12px;padding:10px;font-size:12px;font-weight:700;margin-bottom:10px;line-height:1.7}
.cu-delta.up{color:#059669}.cu-delta.dn{color:#dc2626}.cu-delta.eq{color:var(--mut)}
@media print{body.cu-printing>*:not(#cuPrintArea){display:none!important}#cuPrintArea{display:block!important;direction:rtl;font-family:inherit;color:#000;background:#fff;padding:12px}
 #cuPrintArea table{width:100%;border-collapse:collapse}#cuPrintArea th,#cuPrintArea td{border:1px solid #999;padding:5px;font-size:11px;text-align:center}#cuPrintArea h2{margin:0 0 6px}}
#cuPrintArea{display:none}
`;
function injectCss(){
  if($('cuCss')) return;
  const s = document.createElement('style'); s.id = 'cuCss'; s.textContent = CSS; document.head.appendChild(s);
}

/* ───────── مكوّنات واجهة عامة ───────── */
const skel = (n = 3) => Array.from({length: n}, () => '<div class="cu-skel"></div>').join('');
const emptyBox = (icon, title, sub) => `<div class="cu-empty"><div class="i">${icon}</div><b>${E(title)}</b>${sub ? `<div>${E(sub)}</div>` : ''}</div>`;
const errBox = (msg, act, label) => `<div class="cu-err">⚠️ ${E(msg)}${act ? `<div style="margin-top:8px"><button class="cu-btn sm" data-act="${act}">${E(label || 'إعادة المحاولة')}</button></div>` : ''}</div>`;
const eb = (e, act) => (e && e.auth) ? errBox(e.message, 'relogin', 'تسجيل الدخول من جديد') : errBox((e && e.message) || e, act);
const reLogin = () => { if(role() === 'student'){ if(typeof logoutStudent === 'function') logoutStudent(); } else if(typeof _doLogout === 'function') _doLogout(); };
const stChip = st => { const s = STATE[st] || [st, 'gray']; return `<span class="cu-st ${s[1]}">${s[0]}</span>`; };
const bar = pct => `<div class="cu-bar"><i style="width:${Math.max(0, Math.min(100, pct || 0))}%"></i></div>`;

function modal(html, opts){
  injectCss();
  const m = document.createElement('div');
  m.className = 'cu-modal cu-root'; m.innerHTML = `<div class="cu-sheet">${html}</div>`;
  m.addEventListener('mousedown', e => { if(e.target === m && !(opts && opts.sticky)) m.remove(); });
  document.body.appendChild(m);
  return m;
}
function ask(msg, o){
  o = o || {};
  return new Promise(res => {
    const m = modal(`<h3>${E(o.title || 'تأكيد')}</h3><div class="cu-mut" style="font-size:13px;color:var(--ink);line-height:1.8;margin-bottom:14px">${E(msg)}</div>
      <div class="cu-grid2"><button class="cu-btn sec" data-r="0">إلغاء</button><button class="cu-btn ${o.danger ? 'red' : ''}" data-r="1">${E(o.ok || 'تأكيد')}</button></div>`, {sticky: true});
    m.addEventListener('click', e => { const b = e.target.closest('[data-r]'); if(b){ m.remove(); res(b.dataset.r === '1'); } });
  });
}
/* نموذج صغير: fields = [{k,label,type,value,required,options,ph}] ← يعيد القيم أو null */
function formModal(title, fields, o){
  o = o || {};
  return new Promise(res => {
    const body = fields.map(f => {
      const id = 'cuf_' + f.k;
      if(f.type === 'select') return `<label class="cu-lbl">${E(f.label)}</label><select class="cu-sel" id="${id}">${f.options.map(op => `<option value="${E(op[0])}" ${String(op[0]) === String(f.value) ? 'selected' : ''}>${E(op[1])}</option>`).join('')}</select>`;
      if(f.type === 'textarea') return `<label class="cu-lbl">${E(f.label)}</label><textarea class="cu-ta" id="${id}" placeholder="${E(f.ph || '')}">${E(f.value || '')}</textarea>`;
      return `<label class="cu-lbl">${E(f.label)}</label><input class="cu-in" id="${id}" type="${f.type || 'text'}" value="${E(f.value == null ? '' : f.value)}" placeholder="${E(f.ph || '')}" ${f.step ? `step="${f.step}"` : ''} ${f.min != null ? `min="${f.min}"` : ''} ${f.max != null ? `max="${f.max}"` : ''} inputmode="${f.type === 'number' ? 'decimal' : 'text'}">`;
    }).join('');
    const m = modal(`<h3>${E(title)}</h3>${o.note ? `<div class="cu-mut" style="margin-bottom:6px">${E(o.note)}</div>` : ''}${body}<div id="cuFErr" class="cu-err" style="display:none;margin-top:10px"></div>
      <div class="cu-grid2" style="margin-top:14px"><button class="cu-btn sec" data-r="0">إلغاء</button><button class="cu-btn ${o.danger ? 'red' : ''}" data-r="1">${E(o.ok || 'حفظ')}</button></div>`, {sticky: true});
    m.addEventListener('click', e => {
      const b = e.target.closest('[data-r]'); if(!b) return;
      if(b.dataset.r === '0'){ m.remove(); return res(null); }
      const vals = {};
      for(const f of fields){
        const v = ($('cuf_' + f.k).value || '').trim();
        if(f.required && !v){ const er = $('cuFErr'); er.textContent = 'أكمل الحقل: ' + f.label; er.style.display = 'block'; return; }
        vals[f.k] = v;
      }
      m.remove(); res(vals);
    });
  });
}
function bindClicks(root, map){
  root.addEventListener('click', async e => {
    const t = e.target.closest('[data-act]'); if(!t || !root.contains(t)) return;
    const fn = map[t.dataset.act]; if(!fn) return;
    try { await fn(t, e); } catch(err){ toast2('❌ ' + (err && err.message || err)); console.warn('[comp]', err); }
  });
}
function lvlChip(l){ return l ? `<span class="cu-st ${l === 'متقدم' ? 'blue' : l === 'مبتدئ' ? 'amber' : 'gray'}" style="font-size:9.5px">${E(l)}</span>` : ''; }
const MOTIV = [
  'استمر، فكل آية تحفظها ترفع مقام همتك.', 'لا تقارن بدايتك بإنجاز غيرك.', 'الإتقان خير من كثرة الحفظ دون تثبيت.',
  'قليلٌ دائمٌ خيرٌ من كثيرٍ منقطع.', 'خيركم من تعلّم القرآن وعلّمه.', 'اجعل لك وِرداً يومياً ولو كان يسيراً.',
  'من جدّ وجد، ومن زرع حصد — واصل بثبات.', 'حسن الخلق مع الحفظ نورٌ على نور.', 'كل يوم جديد فرصة لتقترب من كتاب الله.'
];
const dayOfYear = () => { const d = new Date(); return Math.floor((d - new Date(d.getFullYear(), 0, 0)) / 864e5); };
function csvDownload(name, rows){
  const csv = '\uFEFF' + rows.map(r => r.map(c => '"' + String(c == null ? '' : c).replace(/"/g, '""') + '"').join(',')).join('\r\n');
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], {type: 'text/csv;charset=utf-8'}));
  a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
}
function printHtml(html){
  let p = $('cuPrintArea'); if(!p){ p = document.createElement('div'); p.id = 'cuPrintArea'; document.body.appendChild(p); }
  p.innerHTML = html; document.body.classList.add('cu-printing');
  const done = () => { document.body.classList.remove('cu-printing'); window.removeEventListener('afterprint', done); };
  window.addEventListener('afterprint', done); setTimeout(() => window.print(), 80);
}

/* ═══════════════════════════════════════════════════════════════════════
   واجهة الطالب: المسابقة | الواجبات | التواصل مع المعلم
═══════════════════════════════════════════════════════════════════════ */
const S = {host: null, seg: 'comp', comps: null, cid: null, d: null, lvl: '', showAll: false, showEnt: false,
           asg: null, asgOpen: null, ans: {}, asgOp: {}, chat: {rows: [], last: 0, pend: []}, timer: null, chatTimer: null, stamp: null};

CU.renderStudent = function(host){
  injectCss();
  S.host = host;
  if(!/\bcu-root\b/.test(host.className)) host.className += ' cu-root';
  if(!host.dataset.cuBound){
    host.dataset.cuBound = '1';
    bindClicks(host, SH);
    host.addEventListener('input', e => { const t = e.target; if(t.dataset && t.dataset.q){ S.ans[t.dataset.q] = t.value; } });
  }
  host.innerHTML = `<div class="cu-seg" id="cuSeg">
    <button data-act="seg" data-seg="comp">🏆 المسابقة</button>
    <button data-act="seg" data-seg="asg">📝 الواجبات</button>
    <button data-act="seg" data-seg="chat">💬 المعلم<span class="cu-dotb" id="cuUnread" style="display:none"></span></button>
  </div><div id="cuBody"></div>`;
  sGo(S.seg || 'comp');
  clearInterval(S.timer);
  S.timer = setInterval(sTick, 30000);
};

function sPanelVisible(){ return S.host && S.host.isConnected && S.host.classList.contains('on') && document.visibilityState === 'visible'; }
async function sTick(){
  if(!sPanelVisible() || !online()) return;
  try {
    if(S.seg === 'comp' && S.comps && S.comps.length) await sComp(true, true);
    sUnread();
  } catch(e){}
}
async function sUnread(){ notifyTick(true); }
function sMark(){ S.host.querySelectorAll('#cuSeg button').forEach(b => b.classList.toggle('on', b.dataset.seg === S.seg)); }
function sGo(seg){
  S.seg = seg; sMark(); clearInterval(S.chatTimer); S.chatTimer = null; chReset();
  if(seg === 'comp') sComp(false); else if(seg === 'asg'){ S.asgOpen = null; sAsg(); } else sChat();
}

const SH = {
  seg: t => sGo(t.dataset.seg),
  relogin: () => reLogin(),
  retryComp: () => sComp(true),
  refresh: () => sComp(true),
  pick: t => { S.cid = t.dataset.id; S.d = null; S.showAll = false; S.showEnt = false; sComp(false); },
  lvl: t => { S.lvl = t.dataset.l || ''; sRenderComp(); },
  toggleAll: () => { S.showAll = !S.showAll; sRenderComp(); },
  toggleEnt: () => { S.showEnt = !S.showEnt; sRenderComp(); },
  asgOpen: t => sAsgOpen(t.dataset.id),
  asgBack: () => { S.asgOpen = null; sAsg(); },
  opt: t => { S.ans[t.dataset.q] = Number(t.dataset.i); sAsgForm(); },
  tf: t => { S.ans[t.dataset.q] = t.dataset.v === '1'; sAsgForm(); },
  asgSubmit: () => sAsgSubmit(),
  _x: 0
};

/* ── المسابقة ── */
async function sComp(force, soft){
  const body = $('cuBody'); if(!body || S.seg !== 'comp') return;
  LAST.stale = null;
  if(!S.comps || force){
    if(!soft) body.innerHTML = skel(4);
    try { S.comps = (await api('comp_list')).rows; }
    catch(e){ if(!soft) body.innerHTML = eb(e, 'retryComp'); return; }
  }
  if(!S.comps.length){
    body.innerHTML = `<div class="cu-hero" style="opacity:.92"><h2>🏆 دوري فرسان القرآن</h2><div class="sub">30 يوماً من القرآن والعبادة والأخلاق</div></div>`
      + emptyBox('🌙', 'المسابقة غير متاحة حالياً', 'لا توجد مسابقة نشطة لك الآن. سيُعلمك معلمك عند بدء مسابقة جديدة بإذن الله.');
    return;
  }
  const cur = S.comps.find(c => c.id === S.cid) || S.comps[0]; S.cid = cur.id;
  if(!S.d || S.d.id !== cur.id || force){
    if(!soft && !S.d) body.innerHTML = skel(4);
    try {
      const [g, lb, dt] = await Promise.all([api('comp_get', {p_id: cur.id}), api('comp_leaderboard', {p_comp: cur.id}), api('comp_student_detail', {p_comp: cur.id})]);
      S.d = {id: cur.id, comp: g.competition, cats: g.categories, lb, det: dt}; S.stamp = new Date();
    } catch(e){ if(!soft) body.innerHTML = eb(e, 'retryComp'); return; }
  }
  sRenderComp();
}

function sRenderComp(){
  const body = $('cuBody'); if(!body || !S.d || S.seg !== 'comp') return;
  const {comp: c, lb, det} = S.d;
  const rows = lb.rows || [];
  const me = rows.find(r => r.me) || null;
  const days = Math.round((new Date(c.end_date) - new Date(c.start_date)) / 864e5) + 1;
  const todayS = ymd(new Date());
  let when = '';
  if(c.state === 'running') when = `⏳ المتبقي ${AD(c.days_left)} ${c.days_left === 1 ? 'يوم' : 'أيام'}`;
  else if(c.state === 'upcoming') { const n = Math.max(1, Math.ceil((new Date(c.start_date) - new Date(todayS)) / 864e5)); when = `🚀 تبدأ بعد ${AD(n)} ${n === 1 ? 'يوم' : 'أيام'}`; }
  else if(c.state === 'paused') when = '⏸ متوقفة مؤقتاً';
  else when = '🏁 انتهت';
  const hidden = lb.ranking_hidden;
  let h = '';
  if(S.comps.length > 1) h += `<div class="cu-chips" style="margin:0 0 10px">${S.comps.map(x => `<button class="cu-pill ${x.id === c.id ? 'on' : ''}" data-act="pick" data-id="${x.id}">${E(x.name)}</button>`).join('')}</div>`;
  h += `<div class="cu-hero"><h2>🏆 ${E(c.name)}</h2><div class="sub">${E(c.description || (AD(days) + ' يوماً من القرآن والعبادة والأخلاق'))}</div>
    <div style="display:flex;justify-content:space-between;align-items:flex-end;gap:8px"><div><div class="big">${NF(det.total)}</div><div style="font-size:11px;opacity:.92;margin-top:2px">مجموع نقاطك</div></div>
    <div style="text-align:left"><span class="cu-chip">${STATE[c.state] ? STATE[c.state][0] : ''}</span></div></div>
    <div class="row"><span class="cu-chip">📅 ${fmtD(c.start_date)} ← ${fmtD(c.end_date)}</span><span class="cu-chip">${when}</span>${det.level && c.settings && c.settings.levels !== false ? `<span class="cu-chip">المستوى: ${E(det.level)}</span>` : ''}${det.target_note ? `<span class="cu-chip">🎯 ${E(det.target_note)}</span>` : ''}</div></div>`;
  if(c.state === 'ended') h += `<div class="cu-warn" style="background:#ecfdf5;border-color:#6ee7b7;color:#065f46">🏁 انتهت المسابقة — هذه نتائجك النهائية${det.rank ? ' ومركزك النهائي <b>' + AD(det.rank) + '</b> من ' + AD(det.participants) : ''}.</div>`;
  if(c.state === 'upcoming') h += `<div class="cu-warn">المسابقة لم تبدأ بعد؛ تبدأ بتاريخ ${fmtD(c.start_date)} — استعد! 💪</div>`;

  /* الترتيب */
  h += `<div class="cu-card"><div class="cu-h"><span class="dot"></span>ترتيبي</div>`;
  if(hidden || det.rank == null) h += `<div class="cu-mut">أخفى المعلم الترتيب الحي أثناء المسابقة، وسيظهر الترتيب النهائي عند انتهائها. نقاطك: <b>${NF(det.total)}</b></div>`;
  else {
    const dl = me && me.delta != null ? (me.delta > 0 ? `<span class="cu-delta up">▲ تقدّمت ${AD(me.delta)} ${me.delta === 1 ? 'مركز' : 'مراكز'}</span>` : me.delta < 0 ? `<span class="cu-delta dn">▼ تراجعت ${AD(-me.delta)}</span>` : `<span class="cu-delta eq">● ثابت</span>`) : '';
    h += `<div class="cu-grid2"><div class="cu-stat"><b>#${AD(det.rank)}</b><span>مركزك من ${AD(det.participants)} مشارك</span></div><div class="cu-stat"><b>${NF(det.total)}</b><span>نقطة</span></div></div>
      <div class="cu-mut" style="margin-top:8px">${det.rank > 1 && det.gap != null ? 'يفصلك <b>' + NF(det.gap) + '</b> نقطة عن المركز الذي يسبقك. ' : det.rank === 1 ? '🥇 أنت في الصدارة — حافظ عليها! ' : ''}${dl}</div>`;
    const top = rows.slice(0, 3);
    if(top.length){
      const order = [top[1], top[0], top[2]].filter(Boolean); const cls = x => 'p' + Math.min(3, x.rank);
      h += `<div class="cu-podium" style="margin-top:12px">${order.map(x => `<div class="cu-pod ${cls(x)}"><div class="m">${x.rank === 1 ? '🥇' : x.rank === 2 ? '🥈' : '🥉'}</div><div class="n">${E(x.name)}${x.me ? ' (أنت)' : ''}</div><div class="p">${NF(x.total)}</div></div>`).join('')}</div>`;
    }
    const levels = [...new Set(rows.map(r => r.level).filter(Boolean))];
    const showLv = c.settings && c.settings.levels !== false && levels.length > 1;
    const list = S.lvl ? rows.filter(r => r.level === S.lvl) : rows;
    h += `<button class="cu-btn sec full" style="margin-top:10px" data-act="toggleAll">${S.showAll ? 'إخفاء' : 'عرض'} الترتيب الكامل (${AD(rows.length)})</button>`;
    if(S.showAll){
      if(showLv) h += `<div class="cu-chips"><button class="cu-pill ${S.lvl ? '' : 'on'}" data-act="lvl" data-l="">الكل</button>${LEVELS.filter(l => levels.includes(l)).map(l => `<button class="cu-pill ${S.lvl === l ? 'on' : ''}" data-act="lvl" data-l="${l}">${l}</button>`).join('')}</div>`;
      h += `<div class="cu-scroll" style="margin-top:8px"><table class="cu-tbl"><tr><th>#</th><th class="nm">الطالب</th><th>النقاط</th></tr>${list.map(r => `<tr class="${r.me ? 'me' : ''}"><td>${AD(r.rank)}</td><td class="nm">${E(r.name)} ${showLv ? lvlChip(r.level) : ''}</td><td>${NF(r.total)}</td></tr>`).join('')}</table></div>`;
    }
  }
  h += `</div>`;

  /* تفاصيل النقاط */
  h += `<div class="cu-card"><div class="cu-h"><span class="dot"></span>تفاصيل نقاطي</div>${(det.categories || []).map(g => {
    const pct = g.possible > 0 ? Math.round(100 * g.total / g.possible) : 0;
    return `<div style="margin-bottom:9px"><div class="cu-row" style="justify-content:space-between;font-size:12px;font-weight:800;margin-bottom:3px"><span>${g.kind === 'bonus' ? '⭐ ' : ''}${E(g.name)}</span><span>${NF(g.total)} <span class="cu-mut">/ ${NF(g.possible)}</span></span></div>${bar(pct)}</div>`;
  }).join('') || '<div class="cu-mut">لا توجد مجالات.</div>'}
    <button class="cu-btn sec full" data-act="toggleEnt">${S.showEnt ? 'إخفاء' : 'عرض'} سجل نقاطي وأسبابها (${AD((det.entries || []).length)})</button>
    ${S.showEnt ? ((det.entries || []).length ? (det.entries || []).map(e => `<div class="cu-ent"><div><b>${E(e.category)}</b>${e.reason ? '<div class="cu-mut">' + E(e.reason) + '</div>' : ''}<div class="cu-mut">${fmtD(e.date)} · الأسبوع ${AD(e.week)}${e.type !== 'eval' ? ' · تعديل من المعلم' : ''}</div></div><div class="pt ${e.points < 0 ? 'neg' : 'pos'}">${SG(e.points)}</div></div>`).join('') : '<div class="cu-mut" style="margin-top:8px">لا توجد نقاط مسجلة بعد.</div>') : ''}</div>`;

  /* التقدم الأسبوعي */
  const ew = det.elapsed_weeks;
  h += `<div class="cu-card"><div class="cu-h"><span class="dot"></span>تقدمي الأسبوعي</div>${(det.weeks || []).map(w => {
    const cur = w.week === ew && c.state === 'running';
    const pct = w.max > 0 ? Math.round(100 * w.points / w.max) : 0;
    return `<div class="cu-wk ${cur ? 'cur' : ''}"><div class="t"><span>الأسبوع ${AD(w.week)}${cur ? ' · الحالي' : ''} <span class="cu-mut">(${fmtD(w.start)} – ${fmtD(w.end)})</span></span><span>${NF(w.points)} / ${NF(w.max)}</span></div>${bar(pct)}</div>`;
  }).join('')}<div class="cu-mut" style="margin-top:6px">المجموع الكلي: <b>${NF(det.total)}</b> نقطة</div></div>`;

  /* الشارات */
  if((det.badges || []).length) h += `<div class="cu-card"><div class="cu-h"><span class="dot"></span>شارات المسابقة</div><div class="cu-badges">${det.badges.map(b => `<div class="cu-bdg ${b.earned ? 'on' : ''}"><div class="i">${b.icon}</div><div class="n">${E(b.name)}</div><div class="pr">${b.earned ? '✅ حصلت عليها' : AD(b.progress) + '٪'}</div></div>`).join('')}</div><div class="cu-mut" style="margin-top:8px">تُمنح الشارة عند بلوغ ٨٠٪ من نقاط مجالها خلال الأسابيع المنقضية.</div></div>`;

  /* تحفيز */
  h += `<div class="cu-msg">${E(MOTIV[(dayOfYear() + (det.student_id ? String(det.student_id).length : 0)) % MOTIV.length])}</div>
    <div class="cu-mut" style="text-align:center;margin-top:10px">آخر تحديث ${S.stamp ? AD(S.stamp.toLocaleTimeString('ar-EG', {hour: '2-digit', minute: '2-digit'})) : ''} · <a href="#" data-act="refresh" style="color:var(--g);font-weight:800">تحديث 🔄</a></div>`;
  body.innerHTML = staleHtml() + h;
}

/* ── الواجبات ── */
async function sAsg(){
  const body = $('cuBody'); if(!body) return;
  body.innerHTML = skel(3);
  try { S.asg = (await api('asg_list')).rows; } catch(e){ body.innerHTML = eb(e, 'asgBack'); return; }
  if(!S.asg.length){ body.innerHTML = emptyBox('📝', 'لا توجد واجبات حالياً', 'ستظهر هنا الواجبات التي ينشرها معلمك.'); return; }
  body.innerHTML = S.asg.map(a => {
    const my = a.my, due = a.due_at ? new Date(a.due_at) : null, late = due && due < new Date();
    const st = my ? (my.pending_manual ? `<span class="cu-st amber">بانتظار تصحيح المعلم</span>` : `<span class="cu-st green">الدرجة ${NF(my.score)} / ${NF(my.max)}</span>`)
      : (a.status === 'closed' ? `<span class="cu-st slate">مغلق</span>` : late && !(a.settings && a.settings.allow_late) ? `<span class="cu-st slate">انتهى الموعد</span>` : `<span class="cu-st blue">لم تُحلّ بعد</span>`);
    return `<div class="cu-card" data-act="asgOpen" data-id="${a.id}" style="cursor:pointer"><div class="cu-row" style="justify-content:space-between"><b style="font-size:14px">📝 ${E(a.title)}</b>${st}</div>
      ${a.description ? `<div class="cu-mut" style="margin-top:4px">${E(a.description)}</div>` : ''}
      <div class="cu-mut" style="margin-top:6px">${AD(a.questions)} أسئلة · ${NF(a.max_score)} درجة${due ? ' · آخر موعد ' + fmtT(a.due_at) : ''}</div></div>`;
  }).join('');
}
async function sAsgOpen(id){
  const body = $('cuBody'); body.innerHTML = skel(3);
  try { const r = await api('asg_get', {p_id: id}); S.asgOpen = r; S.ans = {}; sAsgForm(); }
  catch(e){ body.innerHTML = eb(e, 'asgBack'); }
}
function sAsgForm(){
  const body = $('cuBody'), r = S.asgOpen; if(!r) return;
  const a = r.assignment, sub = r.submission;
  let h = `<button class="cu-btn sec sm" data-act="asgBack" style="margin-bottom:10px">→ رجوع للواجبات</button><div class="cu-card"><div class="cu-h">📝 ${E(a.title)}</div>${a.description ? `<div class="cu-mut">${E(a.description)}</div>` : ''}
    <div class="cu-mut" style="margin-top:6px">${a.due_at ? 'آخر موعد: ' + fmtT(a.due_at) : 'بدون موعد محدد'} · ${NF(a.max_score)} درجة</div></div>`;
  if(sub){
    h += `<div class="cu-hero" style="padding:14px"><div class="sub" style="margin:0">${sub.pending_manual ? 'تم التسليم — بانتظار تصحيح الأسئلة المقالية' : 'نتيجتك'}</div><div class="big">${NF(sub.score)} <span style="font-size:15px">/ ${NF(sub.max)}</span></div>${sub.late ? '<div class="cu-chip" style="margin-top:8px">سُلّم متأخراً</div>' : ''}</div>`;
    if(sub.feedback) h += `<div class="cu-card"><div class="cu-h">💬 ملاحظة المعلم</div><div style="font-size:13px;line-height:1.8">${E(sub.feedback)}</div></div>`;
  }
  h += r.questions.map((q, i) => {
    const mine = sub ? (sub.answers || {})[q.id] : S.ans[q.id];
    const g = sub ? (sub.grades || {})[q.id] : null;
    let inner = '';
    if(q.qtype === 'mcq') inner = q.options.map((o, k) => {
      const picked = mine === k; const rev = sub && q.correct !== undefined && q.correct !== null;
      const cls = sub ? (rev && k === q.correct ? 'right' : picked && rev && k !== q.correct ? 'wrong' : picked ? 'on' : '') : (picked ? 'on' : '');
      return `<div class="cu-opt ${cls}" ${sub ? '' : `data-act="opt" data-q="${q.id}" data-i="${k}"`}>${picked ? '●' : '○'} ${E(o)}</div>`;
    }).join('');
    else if(q.qtype === 'truefalse') inner = `<div class="cu-grid2">${[[1, '✅ صحيح', true], [0, '❌ خطأ', false]].map(o => {
      const picked = mine === o[2]; const rev = sub && q.correct !== undefined && q.correct !== null;
      const cls = sub ? (rev && o[2] === q.correct ? 'right' : picked && rev ? 'wrong' : picked ? 'on' : '') : (picked ? 'on' : '');
      return `<div class="cu-opt ${cls}" style="justify-content:center" ${sub ? '' : `data-act="tf" data-q="${q.id}" data-v="${o[0]}"`}>${o[1]}</div>`; }).join('')}</div>`;
    else inner = sub ? `<div class="cu-opt" style="cursor:default;white-space:pre-wrap">${E(mine || '— لم تُجب —')}</div>`
      : `<textarea class="cu-ta" data-q="${q.id}" placeholder="اكتب إجابتك هنا">${E(S.ans[q.id] || '')}</textarea>`;
    return `<div class="cu-q"><div class="cu-row" style="justify-content:space-between;font-size:13px;font-weight:900"><span>${AD(i + 1)}. ${E(q.prompt)}</span><span class="cu-mut">${NF(q.points)} د${sub && g != null ? ' · نلت ' + NF(g) : ''}</span></div>${inner}</div>`;
  }).join('');
  if(!sub){
    const closed = a.status === 'closed';
    h += closed ? errBox('الواجب مغلق ولا يقبل إجابات.') : `<button class="cu-btn full" data-act="asgSubmit">📤 تسليم الواجب</button><div class="cu-mut" style="text-align:center;margin-top:8px">لا يمكن تعديل الإجابات بعد التسليم.</div>`;
  }
  body.innerHTML = h;
}
async function sAsgSubmit(){
  const r = S.asgOpen; if(!r) return;
  const unanswered = r.questions.filter(q => S.ans[q.id] === undefined || S.ans[q.id] === '').length;
  if(!(await ask(unanswered ? `لم تجب عن ${AD(unanswered)} من الأسئلة. هل تريد التسليم؟` : 'تأكيد تسليم الواجب؟ لن تستطيع تعديل الإجابات بعد ذلك.', {ok: 'تسليم'}))) return;
  const key = r.assignment.id; S.asgOp[key] = S.asgOp[key] || UID();
  const btn = S.host.querySelector('[data-act="asgSubmit"]'); if(btn) btn.disabled = true;
  try {
    const res = await api('asg_submit', {p_id: key, p_answers: S.ans, p_op: S.asgOp[key]});
    delete S.asgOp[key];
    toast2(res.pending_manual ? '✅ تم تسليم الواجب — بانتظار تصحيح المعلم' : '✅ تم التسليم — درجتك ' + NF(res.score) + ' من ' + NF(res.max));
    await sAsgOpen(key);
  } catch(e){
    if(btn) btn.disabled = false;
    toast2('❌ لم يُسلَّم الواجب: ' + e.message);
  }
}

/* ═══════════════════════════════════════════════════════════════════════
   واجهة المعلم / المشرف / الموظف: لوحة إدارة المسابقة (ملء الشاشة)
═══════════════════════════════════════════════════════════════════════ */
const T = {el: null, tab: 'comps', comps: null, cid: null, comp: null, roster: null, defaults: null, today: null, lb: null,
           G: {date: null, data: null, orig: {}, edits: {}, state: {}, focus: null}, P: {sids: new Set(), cats: new Set(), amt: '', reason: '', date: '', q: ''},
           pts: null, outbox: [], flushing: false, timer: null, chat: {sid: null, name: '', rows: [], last: 0, pend: []}, rep: null, repMode: 'all', repWeek: 1, repSid: ''};
const TABS = [['comps', '🏆 المسابقات'], ['board', '📊 الترتيب'], ['grid', '📝 التقييم'], ['pts', '➕ النقاط'], ['asg', '📋 الواجبات'], ['chat', '💬 المحادثات'], ['rep', '📈 التقارير']];
const NEEDS_COMP = ['board', 'grid', 'pts', 'rep'];
const OB_KEY = 'ridwan_comp_outbox';
function obLoad(){ try { return JSON.parse(localStorage.getItem(OB_KEY) || '[]'); } catch(e){ return []; } }
function obSave(){ try { localStorage.setItem(OB_KEY, JSON.stringify(T.outbox)); } catch(e){} syncBadge(); }
const myId = () => (typeof _currentUser !== 'undefined' && _currentUser && _currentUser.id) || '';
const canComp = () => { const r = role(); return r === 'teacher' || r === 'supervisor' || (r === 'employee' && typeof can === 'function' && can('competitions')); };
const canAsg = canComp;

CU.syncNav = function(){
  const ok = canComp();
  ['nt-comp', 'hqCompBtn'].forEach(id => { const e = $(id); if(e) e.style.display = ok ? '' : 'none'; });
};
function syncBadge(){
  const s = $('cuSync'); if(!s) return;
  const n = T.outbox.filter(x => x.uid === myId()).length;
  s.className = 'cu-sync' + (n || !online() ? ' warn' : '');
  s.textContent = !online() ? (n ? '📴 بلا اتصال · ' + AD(n) + ' لم تُزامن' : '📴 بلا اتصال') : n ? '⏳ ' + AD(n) + ' لم تُزامن — اضغط للمزامنة' : '✅ متزامن';
}

CU.open = async function(tab){
  injectCss();
  if(!canComp()){ toast2('🚫 ليست لديك صلاحية لإدارة المسابقات'); return; }
  if(T.el) T.el.remove();
  T.outbox = obLoad();
  const el = document.createElement('div'); el.className = 'cu-overlay cu-root'; el.id = 'cuOverlay';
  el.innerHTML = `<div class="cu-top"><button data-act="close">✕</button><div class="tt">🏆 دوري فرسان القرآن</div><span class="cu-sync" id="cuSync" data-act="flush" style="cursor:pointer"></span><button data-act="reload">🔄</button></div>
    <div class="cu-tabs" id="cuTabs">${TABS.map(t => `<button data-act="tab" data-t="${t[0]}">${t[1]}</button>`).join('')}</div>
    <div class="cu-cbar" id="cuCbar" style="display:none"></div><div class="cu-main" id="cuMain"></div>`;
  document.body.appendChild(el); T.el = el;
  bindClicks(el, TH);
  el.addEventListener('input', tInput); el.addEventListener('change', tInput);
  T.G = {date: null, data: null, orig: {}, edits: {}, state: {}, focus: null};
  syncBadge();
  const main = $('cuMain'); main.innerHTML = skel(4);
  try { await tLoadComps(); } catch(e){ main.innerHTML = eb(e, 'reload'); return; }
  tGo(tab || 'comps');
  flushOutbox(); notifyTick(true);
};
function tClose(){ if(T.el){ T.el.remove(); T.el = null; } clearInterval(T.timer); clearInterval(T.chatTimer); chReset(); }
async function tDefaults(){
  if(!T.defaults){ const r = await api('comp_defaults'); T.defaults = r; T.today = r.today; }
  return T.defaults;
}
async function tRoster(force){
  if(!T.roster || force) T.roster = await api('comp_roster');
  return T.roster;
}
const hqName = id => { const h = T.roster && T.roster.halaqat.find(x => String(x.id) === String(id)); return h ? h.name : id; };
async function tLoadComps(){
  await tDefaults();
  const r = await api('comp_list'); T.comps = r.rows;
  if(!T.comps.find(c => c.id === T.cid)){
    const pick = T.comps.find(c => c.state === 'running') || T.comps.find(c => c.state === 'upcoming') || T.comps.find(c => c.state === 'paused') || T.comps[0];
    T.cid = pick ? pick.id : null; T.comp = null;
  }
  if(T.cid && (!T.comp || T.comp.competition.id !== T.cid)){
    try { T.comp = await api('comp_get', {p_id: T.cid}); } catch(e){ T.comp = null; }
  }
  try { await tRoster(); } catch(e){}
  tCbar();
}
async function tReloadComp(){
  if(!T.cid) return;
  T.comp = await api('comp_get', {p_id: T.cid});
  const i = T.comps.findIndex(c => c.id === T.cid); if(i >= 0) T.comps[i] = T.comp.competition;
}
function tCbar(){
  const b = $('cuCbar'); if(!b) return;
  const show = NEEDS_COMP.includes(T.tab) && T.comps && T.comps.length;
  b.style.display = show ? 'flex' : 'none';
  if(!show) return;
  b.innerHTML = `<select class="cu-sel" data-act="cmp" id="cuCmpSel">${T.comps.map(c => `<option value="${c.id}" ${c.id === T.cid ? 'selected' : ''}>${E(c.name)}</option>`).join('')}</select>${T.comp ? stChip(T.comp.competition.state) : ''}`;
}
function tMarkTabs(){ T.el.querySelectorAll('#cuTabs button').forEach(b => b.classList.toggle('on', b.dataset.t === T.tab)); }
function tNeedComp(){
  if(T.cid && T.comp) return true;
  $('cuMain').innerHTML = emptyBox('🏆', 'لا توجد مسابقة بعد', 'أنشئ مسابقة جديدة من تبويب «المسابقات» أولاً.') + `<button class="cu-btn full" data-act="tab" data-t="comps">إلى المسابقات</button>`;
  return false;
}
async function tGo(tab){
  T.tab = tab; clearInterval(T.timer); clearInterval(T.chatTimer); chReset(); tMarkTabs(); tCbar();
  const main = $('cuMain'); if(!main) return; main.scrollTop = 0;
  if(NEEDS_COMP.includes(tab) && !tNeedComp()) return;
  main.innerHTML = skel(4); LAST.stale = null;
  try {
    if(tab === 'comps') await tComps(); else if(tab === 'board') await tBoard(); else if(tab === 'grid') await tGrid();
    else if(tab === 'pts') await tPts(); else if(tab === 'asg') await tAsg(); else if(tab === 'chat') await tChatList(); else if(tab === 'rep') await tRep();
    if(LAST.stale && T.el && tab !== 'grid' && tab !== 'pts') main.insertAdjacentHTML('afterbegin', staleHtml());
  } catch(e){ main.innerHTML = eb(e, 'reload'); }
}

const TH = {
  close: () => tClose(),
  relogin: () => reLogin(),
  reload: async () => { T.roster = null; try { await tLoadComps(); } catch(e){ toast2('❌ ' + e.message); } tGo(T.tab); },
  tab: t => tGo(t.dataset.t),
  flush: () => { if(!online()) toast2('📴 لا يوجد اتصال'); else flushOutbox(true); },
  cmp: async t => { T.cid = t.value; T.comp = null; T.lb = null; T.G = {date: null, data: null, orig: {}, edits: {}, state: {}, focus: null}; T.pts = null; T.rep = null;
    try { T.comp = await api('comp_get', {p_id: T.cid}); } catch(e){ toast2('❌ ' + e.message); } tGo(T.tab); },
  /* المسابقات */
  new: () => tForm(null), edit: t => tForm(t.dataset.id),
  open: async t => { T.cid = t.dataset.id; T.comp = await api('comp_get', {p_id: T.cid}); tGo('board'); },
  status: t => tStatus(t.dataset.id, t.dataset.s), del: t => tDelete(t.dataset.id),
  /* نموذج المسابقة */
  f_close: t => t.closest('.cu-modal').remove(), f_preview: t => fPreview(t.closest('.cu-modal')), f_save: t => fSave(t.closest('.cu-modal'), false), f_pub: t => fSave(t.closest('.cu-modal'), true),
  f_dur: t => { F.end = addDays(F.start, Number(t.dataset.n) - 1); const e = $('fEnd'); if(e) e.value = F.end; },
  f_partall: t => { const h = t.dataset.h; const list = (T.roster.students || []).filter(s => String(s.halaqa_id) === h); const allOn = list.every(s => F.parts.has(s.id));
    list.forEach(s => { if(allOn) F.parts.delete(s.id); else if(!F.parts.has(s.id)) F.parts.set(s.id, {level: 'متوسط', note: ''}); }); fParts(); },
  f_catadd: () => { F.cats.push({key: 'custom', name: '', weekly_max_points: 5, kind: 'core', is_active: true}); fCats(); },
  f_catdel: t => { F.cats.splice(Number(t.dataset.i), 1); fCats(); },
  f_catup: t => { const i = Number(t.dataset.i); if(i > 0){ [F.cats[i - 1], F.cats[i]] = [F.cats[i], F.cats[i - 1]]; fCats(); } },
  f_catdn: t => { const i = Number(t.dataset.i); if(i < F.cats.length - 1){ [F.cats[i + 1], F.cats[i]] = [F.cats[i], F.cats[i + 1]]; fCats(); } },
  f_catreset: () => { F.cats = JSON.parse(JSON.stringify(T.defaults.categories)).map(c => ({...c, daily_max_points: null, is_active: true})); fCats(); },
  f_itemadd: () => { F.settings.bonus_items.push({name: '', points: 2}); fItems(); },
  f_itemdel: t => { F.settings.bonus_items.splice(Number(t.dataset.i), 1); fItems(); },
  /* التقييم اليومي */
  g_prev: () => gShift(-1), g_next: () => gShift(1), g_save: () => gSave(), g_q: t => gQuick(t.dataset.q), g_col: t => gColFill(t.dataset.c),
  /* الترتيب */
  b_lvl: t => { T.bLvl = t.dataset.l || ''; tBoardRender(); }, b_hq: t => { T.bHq = t.dataset.h || ''; tBoardRender(); }, detail: t => tDetail(t.dataset.s),
  d_edit: t => entEdit(t.dataset.id, t.dataset.p, t.dataset.v), d_void: t => entVoid(t.dataset.id, false), d_restore: t => entVoid(t.dataset.id, true),
  d_pts: t => { T.P.sids = new Set([t.dataset.s]); t.closest('.cu-modal').remove(); tGo('pts'); }, d_print: t => repStudentPrint(t.dataset.s),
  /* النقاط */
  p_amt: t => { T.P.amt = t.dataset.a; const i = $('pAmt'); if(i) i.value = T.P.amt; pMark(); }, p_item: t => { T.P.reason = t.dataset.n; T.P.amt = t.dataset.a; const r = $('pReason'); if(r) r.value = T.P.reason; const i = $('pAmt'); if(i) i.value = T.P.amt; pMark(); },
  p_reason: t => { T.P.reason = t.dataset.n; const r = $('pReason'); if(r) r.value = T.P.reason; }, p_apply: () => pApply(), p_audit: () => auditView(),
  p_cat: t => { const id = t.dataset.c; T.P.cats.has(id) ? T.P.cats.delete(id) : T.P.cats.add(id); t.classList.toggle('on'); pChips(); pSum(); },
  p_all: () => { T.pts.rows.forEach(r => T.P.sids.add(r.student_id)); pStuList(); pSum(); pRecent(); },
  p_none: () => { T.P.sids.clear(); pStuList(); pSum(); pRecent(); },
  p_more: () => auditView(true),
  /* الواجبات */
  a_new: () => aForm(null), a_edit: t => aForm(t.dataset.id), a_res: t => aResults(t.dataset.id), a_stat: t => aStatus(t.dataset.id, t.dataset.s), a_del: t => aDelete(t.dataset.id),
  a_q: t => aQAdd(t.dataset.t), a_qdel: t => { A.qs.splice(Number(t.dataset.i), 1); aQRender(); }, a_qup: t => { const i = Number(t.dataset.i); if(i > 0){ [A.qs[i - 1], A.qs[i]] = [A.qs[i], A.qs[i - 1]]; aQRender(); } },
  a_qdn: t => { const i = Number(t.dataset.i); if(i < A.qs.length - 1){ [A.qs[i + 1], A.qs[i]] = [A.qs[i], A.qs[i + 1]]; aQRender(); } },
  a_optadd: t => { A.qs[Number(t.dataset.i)].options.push(''); aQRender(); }, a_optdel: t => { const q = A.qs[Number(t.dataset.i)]; q.options.splice(Number(t.dataset.o), 1); if(q.correct >= q.options.length) q.correct = 0; aQRender(); },
  a_save: t => aSave(t.closest('.cu-modal'), false), a_pub: t => aSave(t.closest('.cu-modal'), true), a_sub: t => aSubmission(t.dataset.id, t.dataset.s), a_grade: t => aGrade(t.dataset.id, t.dataset.s),
  a_stud: t => { const m = t.closest('.cu-modal'); const on = t.value === 'sel'; m.querySelector('#aStuBox').style.display = on ? 'block' : 'none'; },
  /* المحادثات */
  /* التقارير */
  r_mode: t => { T.repMode = t.dataset.m; tRepRender(); }, r_print: () => repPrint(), r_csv: () => repCsv()
};

/* ───── قائمة المسابقات ───── */
async function tComps(){
  await tLoadComps();
  const main = $('cuMain'); const rows = T.comps;
  let h = `<button class="cu-btn full" data-act="new" style="margin-bottom:12px">＋ مسابقة جديدة</button>`;
  if(!rows.length) h += emptyBox('🏆', 'لا توجد مسابقات بعد', 'أنشئ أول مسابقة، حدّد طلابها ومجالات التقييم ثم انشرها.');
  h += rows.map(c => {
    const hq = c.halaqa_ids.map(hqName).join('، ');
    const acts = [];
    acts.push(`<button class="cu-btn sm" data-act="open" data-id="${c.id}">فتح</button>`);
    if(c.can_manage){
      if(c.state !== 'ended') acts.push(`<button class="cu-btn sec sm" data-act="edit" data-id="${c.id}">✏️ تعديل</button>`);
      if(c.state === 'draft') acts.push(`<button class="cu-btn sm" data-act="status" data-id="${c.id}" data-s="active">🚀 نشر</button>`, `<button class="cu-btn red sm" data-act="del" data-id="${c.id}">🗑</button>`);
      if(c.state === 'running' || c.state === 'upcoming') acts.push(`<button class="cu-btn amb sm" data-act="status" data-id="${c.id}" data-s="paused">⏸ إيقاف</button>`);
      if(c.state === 'paused') acts.push(`<button class="cu-btn sm" data-act="status" data-id="${c.id}" data-s="active">▶ استئناف</button>`);
      if(['running', 'upcoming', 'paused'].includes(c.state)) acts.push(`<button class="cu-btn red sm" data-act="status" data-id="${c.id}" data-s="ended">🏁 إنهاء</button>`);
      if(c.state === 'ended' && role() !== 'teacher') acts.push(`<button class="cu-btn amb sm" data-act="status" data-id="${c.id}" data-s="reopen">↩ إعادة فتح</button>`);
    }
    return `<div class="cu-card"><div class="cu-row" style="justify-content:space-between"><b style="font-size:14.5px">${E(c.name)}</b>${stChip(c.state)}</div>
      ${c.description ? `<div class="cu-mut" style="margin-top:3px">${E(c.description)}</div>` : ''}
      <div class="cu-mut" style="margin-top:6px">📅 ${fmtD(c.start_date)} ← ${fmtD(c.end_date)} · ${AD(c.weeks_total)} أسابيع<br>👥 ${AD(c.participants)} مشارك · 📖 ${E(hq)}${!c.can_manage ? '<br>🔒 للعرض والتقييم فقط (مسابقة متعددة الحلقات)' : ''}</div>
      <div class="cu-row wrap" style="margin-top:10px">${acts.join('')}</div></div>`;
  }).join('');
  main.innerHTML = h;
}
async function tStatus(id, s){
  const c = T.comps.find(x => x.id === id);
  const msg = {active: 'نشر المسابقة وبدء التقييم؟ ستظهر للطلاب المشاركين فوراً.', paused: 'إيقاف المسابقة مؤقتاً؟ لن يمكن تسجيل نقاط حتى تستأنفها.',
    ended: 'إنهاء المسابقة؟ ستظهر النتائج النهائية للطلاب ويُقفل التعديل (التصحيح بعد الإغلاق للمشرف فقط وبسبب موثق).', reopen: 'إعادة فتح المسابقة (ستصبح متوقفة مؤقتاً لتراجعها)؟'}[s];
  if(!(await ask(msg + (c ? '\n«' + c.name + '»' : ''), {danger: s === 'ended', ok: s === 'ended' ? 'إنهاء المسابقة' : 'تأكيد'}))) return;
  await api('comp_set_status', {p_id: id, p_status: s});
  toast2('✅ تم تحديث حالة المسابقة'); T.comp = null; await tLoadComps(); tGo('comps');
}
async function tDelete(id){
  if(!(await ask('حذف هذه المسودة نهائياً؟', {danger: true, ok: 'حذف'}))) return;
  await api('comp_delete', {p_id: id}); toast2('🗑 تم حذف المسودة'); T.cid = null; T.comp = null; await tLoadComps(); tGo('comps');
}

/* ───── نموذج إنشاء/تعديل المسابقة ───── */
let F = null;
async function tForm(id){
  const m = modal(`<div style="padding:10px 0">${skel(3)}</div>`, {sticky: true}); bindClicks(m, TH);
  try {
    const [ro, dfl] = await Promise.all([tRoster(true), tDefaults()]);
    let comp = null, cats = null, parts = [];
    if(id){ const g = await api('comp_get', {p_id: id}); comp = g.competition; cats = g.categories; parts = g.participants; }
    const s0 = Object.assign({}, dfl.settings, comp ? comp.settings : {});
    const own = role() === 'teacher' ? [String(_currentUser.halaqa_id)] : [];
    const hqs = comp ? comp.halaqa_ids.map(String) : (own.length ? own : (ro.halaqat.length === 1 ? [String(ro.halaqat[0].id)] : []));
    F = {id: id || null, expected: comp ? comp.updated_at : null, name: comp ? comp.name : '', desc: comp ? comp.description : '', start: comp ? String(comp.start_date).slice(0, 10) : dfl.today,
         end: comp ? String(comp.end_date).slice(0, 10) : addDays(dfl.today, 29), halaqas: new Set(hqs), parts: new Map(), status: comp ? comp.status : 'draft',
         cats: cats ? cats.map(c => ({id: c.id, key: c.key, name: c.name, weekly_max_points: c.weekly_max_points, daily_max_points: c.daily_max_points == null ? null : c.daily_max_points, kind: c.kind, is_active: c.is_active})) : JSON.parse(JSON.stringify(dfl.categories)).map(c => ({...c, is_active: true})),
         settings: {show_ranking: s0.show_ranking !== false, levels: s0.levels !== false, bonus_weekly_cap: s0.bonus_weekly_cap, tz: s0.tz, bonus_items: JSON.parse(JSON.stringify(s0.bonus_items || []))}};
    parts.filter(p => p.status === 'active').forEach(p => F.parts.set(p.student_id, {level: p.level || 'متوسط', note: p.target_note || ''}));
    if(!id && F.halaqas.size) (ro.students || []).filter(s => F.halaqas.has(String(s.halaqa_id))).forEach(s => F.parts.set(s.id, {level: 'متوسط', note: ''}));
  } catch(e){ m.remove(); toast2('❌ ' + e.message); return; }
  fRender(m);
}
function fRender(m){
  const ro = T.roster, isT = role() === 'teacher', locked = F.id && T.comp && T.comp.competition.state !== 'draft' && T.comp.competition.state !== 'upcoming';
  m.querySelector('.cu-sheet').innerHTML = `<h3>${F.id ? '✏️ تعديل المسابقة' : '🏆 مسابقة جديدة'}</h3>
    <div class="cu-card"><div class="cu-h">المعلومات الأساسية</div>
      <label class="cu-lbl">اسم المسابقة</label><input class="cu-in" data-f="name" value="${E(F.name)}" placeholder="مثال: دوري فرسان القرآن" maxlength="80">
      <label class="cu-lbl">وصف (اختياري)</label><textarea class="cu-ta" data-f="desc" placeholder="30 يوماً من القرآن والعبادة والأخلاق" maxlength="500">${E(F.desc)}</textarea>
      <div class="cu-grid2"><div><label class="cu-lbl">تاريخ البداية</label><input class="cu-in" type="date" id="fStart" data-f="start" value="${F.start}" ${F.id && locked ? 'disabled' : ''}></div>
      <div><label class="cu-lbl">تاريخ النهاية</label><input class="cu-in" type="date" id="fEnd" data-f="end" value="${F.end}"></div></div>
      <div class="cu-chips"><span class="cu-mut" style="align-self:center">المدة:</span>${[14, 30, 60].map(n => `<button class="cu-pill" data-act="f_dur" data-n="${n}">${AD(n)} يوماً</button>`).join('')}<span class="cu-mut" id="fDays" style="align-self:center"></span></div></div>
    <div class="cu-card"><div class="cu-h">النطاق: الحلقات المشمولة</div><div id="fHq"></div></div>
    <div class="cu-card"><div class="cu-h">الطلاب المشاركون <span class="cu-mut" id="fPc"></span></div><div id="fParts"></div></div>
    <div class="cu-card"><div class="cu-h">شبكة التقييم (المجالات)</div><div class="cu-mut" style="margin-bottom:8px">لكل مجال: الاسم، ثم <b>الحد الأسبوعي</b>، ثم <b>الحد اليومي</b> (إن تركته فارغاً يُحسب تلقائياً = الأسبوعي ÷ ٥). المجموع الأسبوعي الافتراضي ١٠٠ نقطة.</div><div id="fCats"></div></div>
    <div class="cu-card"><div class="cu-h">الإعدادات</div>
      <label class="cu-row" style="margin-bottom:8px"><input type="checkbox" data-s="show_ranking" ${F.settings.show_ranking ? 'checked' : ''}> <span style="font-size:12.5px;font-weight:700">إظهار الترتيب الحي للطلاب (النتائج النهائية تظهر دائماً بعد الانتهاء)</span></label>
      <label class="cu-row" style="margin-bottom:8px"><input type="checkbox" data-s="levels" ${F.settings.levels ? 'checked' : ''}> <span style="font-size:12.5px;font-weight:700">تفعيل مستويات الطلاب (مبتدئ / متوسط / متقدم) للمقارنة العادلة</span></label>
      <label class="cu-lbl">الحد الأقصى للمكافآت الإضافية أسبوعياً</label><input class="cu-in" type="number" min="0" max="100" data-s="bonus_weekly_cap" value="${F.settings.bonus_weekly_cap}">
      <div class="cu-lbl">خيارات المكافآت الجاهزة (للتسريع)</div><div id="fItems"></div></div>
    <div id="fErr" class="cu-err" style="display:none"></div>
    <div class="cu-grid2"><button class="cu-btn sec" data-act="f_preview">👁 معاينة</button><button class="cu-btn sec" data-act="f_close">إلغاء</button></div>
    <div class="cu-grid2" style="margin-top:8px"><button class="cu-btn" data-act="f_save">💾 ${F.id ? 'حفظ التعديلات' : 'حفظ كمسودة'}</button>${F.status === 'draft' ? '<button class="cu-btn" data-act="f_pub" style="background:linear-gradient(135deg,#d97706,#ea580c)">🚀 حفظ ونشر</button>' : '<span></span>'}</div>`;
  if(!m.dataset.fb){ m.dataset.fb = '1'; m.addEventListener('input', fInput); m.addEventListener('change', fInput); }
  fHq(isT); fParts(); fCats(); fItems(); fDays();
}
function fDays(){ const e = $('fDays'); if(!e) return; const n = Math.round((new Date(F.end) - new Date(F.start)) / 864e5) + 1; e.textContent = n > 0 ? '= ' + AD(n) + ' يوماً (' + AD(Math.ceil(n / 7)) + ' أسابيع)' : ''; }
function fHq(isT){
  const ro = T.roster; const box = $('fHq'); if(!box) return;
  box.innerHTML = ro.halaqat.length ? ro.halaqat.map(h => `<label class="cu-row" style="padding:6px 0"><input type="checkbox" data-h="${E(h.id)}" ${F.halaqas.has(String(h.id)) ? 'checked' : ''} ${isT || (F.id && T.comp && T.comp.competition.state === 'running') ? 'disabled' : ''}> <span style="font-weight:800;font-size:13px">📖 ${E(h.name)}</span></label>`).join('')
    : '<div class="cu-mut">لا توجد حلقات.</div>';
  if(isT) box.insertAdjacentHTML('beforeend', '<div class="cu-mut">المعلم ينشئ مسابقات لحلقته فقط. المسابقات متعددة الحلقات للمشرف.</div>');
}
function fParts(){
  const box = $('fParts'); if(!box) return; const ro = T.roster;
  const groups = [...F.halaqas].map(hid => ({hid, name: hqName(hid), list: (ro.students || []).filter(s => String(s.halaqa_id) === hid)}));
  box.innerHTML = groups.length ? groups.map(g => `<div style="margin-bottom:10px"><div class="cu-row" style="justify-content:space-between"><b style="font-size:12.5px">📖 ${E(g.name)}</b><button class="cu-pill" data-act="f_partall" data-h="${E(g.hid)}">تحديد/إلغاء الكل</button></div>
    ${g.list.length ? g.list.map(s => { const p = F.parts.get(s.id); return `<div class="cu-row" style="padding:6px 0;border-bottom:1px solid var(--bd)"><input type="checkbox" data-sid="${E(s.id)}" ${p ? 'checked' : ''}><span class="cu-grow" style="font-size:12.5px;font-weight:700">${E(s.name)}${s.has_account ? '' : ' <span class="cu-mut">(بلا حساب دخول)</span>'}</span>
      ${F.settings.levels && p ? `<select class="cu-sel" style="width:96px;padding:5px 6px;font-size:11px" data-lv="${E(s.id)}">${LEVELS.map(l => `<option ${p.level === l ? 'selected' : ''}>${l}</option>`).join('')}</select>` : ''}</div>
      ${p ? `<input class="cu-in" style="margin:4px 0 2px;padding:6px 10px;font-size:11.5px" data-pn="${E(s.id)}" value="${E(p.note || '')}" maxlength="200" placeholder="هدفه الخاص (اختياري) مثل: ٥ أسطر يومياً — لمراعاة مستواه">` : ''}`; }).join('') : '<div class="cu-mut">لا يوجد طلاب في هذه الحلقة (تأكد من مزامنتها).</div>'}</div>`).join('')
    : '<div class="cu-mut">اختر حلقة أولاً.</div>';
  const pc = $('fPc'); if(pc) pc.textContent = '(' + AD(F.parts.size) + ')';
}
function fCats(){
  const box = $('fCats'); if(!box) return;
  const core = F.cats.filter(c => c.kind === 'core' && c.is_active).reduce((a, c) => a + Number(c.weekly_max_points || 0), 0);
  box.innerHTML = F.cats.map((c, i) => `<div class="cu-row" style="padding:6px 0;border-bottom:1px solid var(--bd);${c.is_active ? '' : 'opacity:.5'}">
      <input class="cu-in" style="flex:1;padding:8px" data-cn="${i}" value="${E(c.name)}" placeholder="اسم المجال" maxlength="60">
      <input class="cu-in" style="width:62px;padding:8px;text-align:center" type="number" min="0" step="0.5" data-cm="${i}" value="${c.weekly_max_points}" title="الحد الأسبوعي">
      <input class="cu-in" style="width:62px;padding:8px;text-align:center" type="number" min="0" step="0.5" data-cd="${i}" value="${c.daily_max_points == null ? '' : c.daily_max_points}" placeholder="${NF(Number(c.weekly_max_points || 0) / 5)}" title="الحد اليومي (فارغ = الأسبوعي ÷ ٥)">
      <div style="display:flex;flex-direction:column;gap:2px"><button class="cu-pill" style="padding:1px 7px" data-act="f_catup" data-i="${i}">▲</button><button class="cu-pill" style="padding:1px 7px" data-act="f_catdn" data-i="${i}">▼</button></div>
      <button class="cu-btn red sm" data-act="f_catdel" data-i="${i}">✕</button></div>${c.kind === 'bonus' ? '<div class="cu-mut" style="font-size:10px">⭐ مجال مكافآت (يُستخدم من لوحة النقاط)</div>' : ''}`).join('')
    + `<div class="cu-row wrap" style="margin-top:10px"><button class="cu-btn sec sm" data-act="f_catadd">＋ إضافة مجال</button><button class="cu-btn sec sm" data-act="f_catreset">↺ الافتراضي</button><span class="cu-mut">المجموع الأسبوعي: <b style="color:var(--ink)">${NF(core)}</b></span></div>`;
}
function fItems(){
  const box = $('fItems'); if(!box) return;
  box.innerHTML = F.settings.bonus_items.map((it, i) => `<div class="cu-row" style="margin-bottom:6px"><input class="cu-in" style="flex:1;padding:8px" data-in="${i}" value="${E(it.name)}" placeholder="مثال: صيام تطوع اختياري"><input class="cu-in" style="width:62px;padding:8px;text-align:center" type="number" min="0" step="0.5" data-ip="${i}" value="${it.points}"><button class="cu-btn red sm" data-act="f_itemdel" data-i="${i}">✕</button></div>`).join('')
    + `<button class="cu-btn sec sm" data-act="f_itemadd">＋ إضافة خيار</button><div class="cu-mut" style="margin-top:6px">⚠️ الصيام اختياري تماماً ويراعي العمر والصحة وموافقة ولي الأمر؛ يمكن استبداله بعمل خير مناسب.</div>`;
}
function fInput(e){
  const t = e.target; if(!F) return;
  if(t.dataset.f){ F[t.dataset.f] = t.value; if(t.dataset.f === 'start' || t.dataset.f === 'end') fDays(); }
  else if(t.dataset.s){ F.settings[t.dataset.s] = t.type === 'checkbox' ? t.checked : t.value; if(t.dataset.s === 'levels') fParts(); }
  else if(t.dataset.h){ t.checked ? F.halaqas.add(t.dataset.h) : F.halaqas.delete(t.dataset.h);
    (T.roster.students || []).forEach(s => { if(String(s.halaqa_id) === t.dataset.h){ if(t.checked){ if(!F.parts.has(s.id)) F.parts.set(s.id, {level: 'متوسط', note: ''}); } else F.parts.delete(s.id); } }); fParts(); }
  else if(t.dataset.sid){ t.checked ? F.parts.set(t.dataset.sid, F.parts.get(t.dataset.sid) || {level: 'متوسط', note: ''}) : F.parts.delete(t.dataset.sid); fParts(); }
  else if(t.dataset.lv){ const p = F.parts.get(t.dataset.lv); if(p) p.level = t.value; }
  else if(t.dataset.pn){ const p = F.parts.get(t.dataset.pn); if(p) p.note = t.value; }
  else if(t.dataset.cn != null){ F.cats[Number(t.dataset.cn)].name = t.value; }
  else if(t.dataset.cm != null){ F.cats[Number(t.dataset.cm)].weekly_max_points = t.value; if(e.type === 'change') fCats(); }
  else if(t.dataset.cd != null){ F.cats[Number(t.dataset.cd)].daily_max_points = t.value === '' ? null : t.value; }
  else if(t.dataset.in != null){ F.settings.bonus_items[Number(t.dataset.in)].name = t.value; }
  else if(t.dataset.ip != null){ F.settings.bonus_items[Number(t.dataset.ip)].points = t.value; }
}
function fPayload(){
  return {id: F.id || undefined, expected_updated_at: F.expected || undefined, name: F.name.trim(), description: F.desc.trim(), start_date: F.start, end_date: F.end, halaqa_ids: [...F.halaqas],
    settings: {show_ranking: !!F.settings.show_ranking, levels: !!F.settings.levels, bonus_weekly_cap: Number(F.settings.bonus_weekly_cap) || 0, bonus_items: F.settings.bonus_items.filter(x => String(x.name).trim()).map(x => ({name: String(x.name).trim(), points: Number(x.points) || 0}))},
    categories: F.cats.map(c => ({id: c.id, key: c.key, name: String(c.name).trim(), weekly_max_points: Number(c.weekly_max_points), daily_max_points: (c.daily_max_points === '' || c.daily_max_points == null) ? null : Number(c.daily_max_points), kind: c.kind, is_active: c.is_active})),
    participants: [...F.parts.entries()].map(([sid, p]) => ({student_id: sid, level: p.level, target_note: p.note}))};
}
function fCheck(){
  const p = fPayload();
  if(p.name.length < 2) return 'اكتب اسم المسابقة';
  if(!p.start_date || !p.end_date || p.end_date < p.start_date) return 'تحقق من تاريخ البداية والنهاية';
  if(!p.halaqa_ids.length) return 'اختر حلقة واحدة على الأقل';
  if(p.categories.some(c => !c.name || isNaN(c.weekly_max_points) || c.weekly_max_points < 0)) return 'أكمل أسماء المجالات ونقاطها';
  if(new Set(p.categories.map(c => c.name)).size !== p.categories.length) return 'يوجد مجالان بالاسم نفسه';
  if(p.categories.some(c => c.daily_max_points != null && (isNaN(c.daily_max_points) || c.daily_max_points < 0 || c.daily_max_points > c.weekly_max_points))) return 'الحد اليومي لا يجوز أن يتجاوز الحد الأسبوعي';
  if(!p.categories.some(c => c.kind === 'core')) return 'يلزم مجال تقييم واحد على الأقل';
  return '';
}
function fPreview(m){
  const e = fCheck(); const er = $('fErr');
  if(e){ er.textContent = e; er.style.display = 'block'; return; } er.style.display = 'none';
  const p = fPayload(); const core = p.categories.filter(c => c.kind === 'core' && c.is_active).reduce((a, c) => a + c.weekly_max_points, 0);
  const pm = modal(`<h3>👁 معاينة المسابقة</h3><div class="cu-hero"><h2>🏆 ${E(p.name)}</h2><div class="sub">${E(p.description || (AD(Math.round((new Date(p.end_date) - new Date(p.start_date)) / 864e5) + 1) + ' يوماً من القرآن والعبادة والأخلاق'))}</div>
    <div class="row"><span class="cu-chip">📅 ${fmtD(p.start_date)} ← ${fmtD(p.end_date)}</span><span class="cu-chip">👥 ${AD(p.participants.length)} مشارك</span><span class="cu-chip">📖 ${AD(p.halaqa_ids.length)} حلقة</span></div></div>
    <div class="cu-card"><div class="cu-h">مجالات التقييم</div>${p.categories.map(c => `<div class="cu-ent"><span>${c.kind === 'bonus' ? '⭐ ' : ''}${E(c.name)}</span><b>${NF(c.weekly_max_points)}</b></div>`).join('')}<div class="cu-ent"><b>المجموع الأسبوعي (دون المكافآت)</b><b>${NF(core)}</b></div></div>
    <div class="cu-mut">هكذا ستظهر للطلاب بعد النشر. الترتيب ${p.settings.show_ranking ? 'ظاهر' : 'مخفي'} أثناء المسابقة.</div><button class="cu-btn full" style="margin-top:10px" onclick="this.closest('.cu-modal').remove()">إغلاق المعاينة</button>`);
}
async function fSave(m, publish){
  const e = fCheck(); const er = $('fErr');
  if(e){ er.textContent = e; er.style.display = 'block'; return; } er.style.display = 'none';
  if(publish && !F.parts.size){ er.textContent = ERR.no_participants; er.style.display = 'block'; return; }
  m.querySelectorAll('[data-act="f_save"],[data-act="f_pub"]').forEach(b => b.disabled = true);
  try {
    const r = await api('comp_save', {p: fPayload()});
    if(publish){
      try { await api('comp_set_status', {p_id: r.id, p_status: 'active'}); toast2('🚀 تم حفظ المسابقة ونشرها'); }
      catch(e2){ toast2('✅ حُفظت كمسودة، لكن تعذّر النشر: ' + e2.message); }
    } else toast2('✅ تم حفظ المسابقة');
    T.cid = r.id; T.comp = null; m.remove(); await tLoadComps(); tGo('comps');
  } catch(err){
    m.querySelectorAll('[data-act="f_save"],[data-act="f_pub"]').forEach(b => b.disabled = false);
    let msg = err.message; if(err.r && err.r.error === 'student_not_found') msg += ' (' + (err.r.ids || []).join('، ') + ')';
    er.textContent = msg; er.style.display = 'block'; er.scrollIntoView({block: 'center'});
  }
}

/* ───── مدخلات اللوحة ───── */
function tInput(e){
  const t = e.target;
  if(t.dataset && t.dataset.g){ gInput(t); return; }
  if(t.id === 'pAmt'){ T.P.amt = t.value; pMark(); }
  else if(t.id === 'pReason') T.P.reason = t.value;
  else if(t.dataset && t.dataset.ps != null){ t.checked ? T.P.sids.add(t.dataset.ps) : T.P.sids.delete(t.dataset.ps); pSum(); pRecent(); }
  else if(t.id === 'pSearch'){ T.P.q = t.value; pStuList(); }
  else if(t.id === 'pDate') T.P.date = t.value;
  else if(t.id === 'gDate' && e.type === 'change'){ gDateChange(t.value); }
  else if(t.id === 'rSel' && e.type === 'change'){ T.repSid = t.value; tRepRender(); }
  else if(t.id === 'rWeek' && e.type === 'change'){ T.repWeek = Number(t.value); tRepRender(); }
}

/* ───── الترتيب ───── */
async function tBoard(){
  T.lb = await api('comp_leaderboard', {p_comp: T.cid});
  tBoardRender();
  T.timer = setInterval(async () => {
    if(T.tab !== 'board' || !online() || document.visibilityState !== 'visible') return;
    try { T.lb = await api('comp_leaderboard', {p_comp: T.cid}); tBoardRender(); } catch(e){}
  }, 30000);
}
function deltaHtml(d){ return d == null ? '<span class="cu-mut">—</span>' : d > 0 ? `<span class="cu-delta up">▲${AD(d)}</span>` : d < 0 ? `<span class="cu-delta dn">▼${AD(-d)}</span>` : '<span class="cu-delta eq">●</span>'; }
function tBoardRender(){
  const main = $('cuMain'); if(!T.lb || T.tab !== 'board' || !T.comp) return;
  const c = T.comp.competition, lb = T.lb, rows = lb.rows || [];
  const levels = [...new Set(rows.map(r => r.level).filter(Boolean))], hqs = [...new Set(rows.map(r => String(r.halaqa_id)))];
  let list = rows; if(T.bLvl) list = list.filter(r => r.level === T.bLvl); if(T.bHq) list = list.filter(r => String(r.halaqa_id) === T.bHq);
  const top = rows.slice(0, 3), order = [top[1], top[0], top[2]].filter(Boolean);
  let h = `<div class="cu-grid2" style="margin-bottom:12px"><div class="cu-stat"><b>${AD(lb.participants)}</b><span>المشاركون</span></div><div class="cu-stat"><b>${AD(lb.elapsed_weeks)}/${AD(lb.weeks_total)}</b><span>الأسبوع</span></div>
    <div class="cu-stat"><b>${c.state === 'running' ? AD(c.days_left) : '—'}</b><span>أيام متبقية</span></div><div class="cu-stat"><b style="font-size:15px">${rows[0] && rows[0].total > 0 ? E(rows[0].name) : '—'}</b><span>المتصدر</span></div></div>`;
  if(c.state === 'ended') h += `<div class="cu-warn" style="background:#ecfdf5;border-color:#6ee7b7;color:#065f46">🏁 انتهت المسابقة — هذه النتائج النهائية.</div>`;
  if(top.length && top[0].total > 0) h += `<div class="cu-card"><div class="cu-podium">${order.map(x => `<div class="cu-pod p${Math.min(3, x.rank)}"><div class="m">${x.rank === 1 ? '🥇' : x.rank === 2 ? '🥈' : '🥉'}</div><div class="n">${E(x.name)}</div><div class="p">${NF(x.total)}</div></div>`).join('')}</div></div>`;
  h += `<div class="cu-card"><div class="cu-h"><span class="dot"></span>الترتيب العام</div>`;
  if(levels.length > 1 || hqs.length > 1) h += `<div class="cu-chips" style="margin:0 0 8px">${levels.length > 1 ? `<button class="cu-pill ${T.bLvl ? '' : 'on'}" data-act="b_lvl" data-l="">كل المستويات</button>${LEVELS.filter(l => levels.includes(l)).map(l => `<button class="cu-pill ${T.bLvl === l ? 'on' : ''}" data-act="b_lvl" data-l="${l}">${l}</button>`).join('')}` : ''}
    ${hqs.length > 1 ? `<button class="cu-pill ${T.bHq ? '' : 'on'}" data-act="b_hq" data-h="">كل الحلقات</button>${hqs.map(x => `<button class="cu-pill ${T.bHq === x ? 'on' : ''}" data-act="b_hq" data-h="${E(x)}">${E(hqName(x))}</button>`).join('')}` : ''}</div>`;
  if(!list.length) h += emptyBox('👥', 'لا يوجد مشاركون', 'أضف طلاباً من «المسابقات ← تعديل».');
  else h += `<div class="cu-scroll"><table class="cu-tbl"><tr><th>#</th><th class="nm">الطالب</th><th>المجموع</th>${Array.from({length: lb.weeks_total}, (_, i) => `<th>أ${AD(i + 1)}</th>`).join('')}<th>التغير</th><th>آخر تحديث</th></tr>
    ${list.map(r => `<tr class="clk" data-act="detail" data-s="${E(r.student_id)}"><td>${AD(r.rank)}</td><td class="nm">${E(r.name)} ${c.settings && c.settings.levels !== false ? lvlChip(r.level) : ''}</td><td><b>${NF(r.total)}</b></td>
      ${Array.from({length: lb.weeks_total}, (_, i) => `<td>${r.weeks && r.weeks[i + 1] != null ? NF(r.weeks[i + 1]) : '·'}</td>`).join('')}<td>${deltaHtml(r.delta)}</td><td class="cu-mut" style="white-space:nowrap">${r.last_update ? fmtD(r.last_update) : '—'}</td></tr>`).join('')}</table></div>
    <div class="cu-mut" style="margin-top:8px">اضغط على أي طالب لعرض تفاصيل نقاطه وتصحيحها. يتحدث الترتيب تلقائياً بعد كل تعديل.</div>`;
  main.innerHTML = h + '</div>';
}

/* ───── تفاصيل طالب + تصحيح العمليات ───── */
function entRows(entries, canEdit, lim){
  const ar = (entries || []).slice(0, lim || 60);
  if(!ar.length) return '<div class="cu-mut">لا توجد عمليات.</div>';
  return ar.map(e => `<div class="cu-ent ${e.voided ? 'void' : ''}"><div style="min-width:0"><b>${E(e.category)}</b>${e.type !== 'eval' ? ' <span class="cu-st gray" style="font-size:9px">تعديل</span>' : ''}${e.post_close ? ' <span class="cu-st amber" style="font-size:9px">بعد الإغلاق</span>' : ''}
      <div class="cu-mut">${E(e.reason || '')}</div><div class="cu-mut">${fmtD(e.date)} · أ${AD(e.week)} · ${E(e.by || '')}${e.voided ? ' · 🚫 ملغاة: ' + E(e.void_reason || '') : ''}</div>
      ${canEdit ? `<div class="cu-row wrap" style="margin-top:4px">${e.voided ? `<button class="cu-btn sec sm" data-act="d_restore" data-id="${e.id}">↩ استرجاع</button>` : `<button class="cu-btn sec sm" data-act="d_edit" data-id="${e.id}" data-p="${e.points}" data-v="${e.ver}">✏️ تعديل</button><button class="cu-btn red sm" data-act="d_void" data-id="${e.id}">🗑 حذف</button>`}</div>` : ''}</div>
      <div class="pt ${e.points < 0 ? 'neg' : 'pos'}">${SG(e.points)}</div></div>`).join('');
}
const canEditNow = () => { const s = T.comp && T.comp.competition.state; return s === 'running' || (s === 'ended' && role() !== 'teacher'); };
async function tDetail(sid, reopen){
  T.detailSid = sid;
  let m = reopen && T.detailM && T.detailM.isConnected ? T.detailM : null;
  if(!m){ m = modal(`<div>${skel(3)}</div>`); bindClicks(m, TH); T.detailM = m; }
  let d; try { d = await api('comp_student_detail', {p_comp: T.cid, p_student: sid}); } catch(e){ m.remove(); toast2('❌ ' + e.message); return; }
  const ce = canEditNow();
  m.querySelector('.cu-sheet').innerHTML = `<div class="cu-row" style="justify-content:space-between"><h3 style="margin:0">${E(d.name || sid)}</h3><button class="cu-btn sec sm" onclick="this.closest('.cu-modal').remove()">✕</button></div>
    <div class="cu-grid2" style="margin:10px 0"><div class="cu-stat"><b>${NF(d.total)}</b><span>المجموع</span></div><div class="cu-stat"><b>${d.rank ? '#' + AD(d.rank) : '—'}</b><span>الترتيب من ${AD(d.participants)}</span></div></div>
    <div class="cu-mut">المستوى: ${lvlChip(d.level)} ${d.target_note ? '· الهدف: ' + E(d.target_note) : ''}</div>
    <div class="cu-card" style="margin-top:10px"><div class="cu-h">نقاط كل مجال</div>${(d.categories || []).map(g => `<div style="margin-bottom:8px"><div class="cu-row" style="justify-content:space-between;font-size:12px;font-weight:800"><span>${g.kind === 'bonus' ? '⭐ ' : ''}${E(g.name)}</span><span>${NF(g.total)} <span class="cu-mut">/ ${NF(g.possible)}</span></span></div>${bar(g.possible > 0 ? 100 * g.total / g.possible : 0)}</div>`).join('')}</div>
    <div class="cu-card"><div class="cu-h">سجل العمليات</div>${entRows(d.entries, ce)}</div>
    <div class="cu-grid2"><button class="cu-btn" data-act="d_pts" data-s="${E(sid)}">➕ إضافة/خصم نقاط</button><button class="cu-btn sec" data-act="d_print" data-s="${E(sid)}">🖨 تقرير الطالب</button></div>`;
}
async function entEdit(id, pts, ver){
  const v = await formModal('✏️ تعديل نقاط عملية', [{k: 'p', label: 'النقاط الجديدة', type: 'number', value: pts, step: '0.5', required: true}, {k: 'r', label: 'سبب التعديل (إلزامي)', type: 'textarea', required: true, ph: 'مثال: تصحيح خطأ في الإدخال'}], {ok: 'حفظ التعديل'});
  if(!v) return;
  await api('comp_score_update', {p_score: id, p_points: Number(v.p), p_reason: v.r, p_ver: Number(ver)});
  toast2('✅ تم تعديل النقاط وتسجيل العملية'); tAfterChange(); 
}
async function entVoid(id, restore){
  const v = await formModal(restore ? '↩ استرجاع عملية' : '🗑 حذف عملية خاطئة', [{k: 'r', label: 'السبب (إلزامي)', type: 'textarea', required: true, ph: restore ? 'سبب الاسترجاع' : 'سبب الحذف'}], {ok: restore ? 'استرجاع' : 'حذف العملية', danger: !restore,
    note: restore ? '' : 'لا تُحذف العملية نهائياً؛ تُلغى وتبقى في سجل التدقيق.'});
  if(!v) return;
  await api('comp_score_void', {p_score: id, p_reason: v.r, p_restore: !!restore});
  toast2(restore ? '✅ تم الاسترجاع' : '✅ تم الحذف وتسجيل السبب'); tAfterChange();
}
async function tAfterChange(){
  if(T.detailM && T.detailM.isConnected) await tDetail(T.detailSid, true);
  if(T.tab === 'board'){ try { T.lb = await api('comp_leaderboard', {p_comp: T.cid}); tBoardRender(); } catch(e){} }
  if(T.tab === 'pts') pRecent();
}

/* ───── الشبكة: التقييم اليومي لعدة طلاب دفعة واحدة (يعمل دون إنترنت) ───── */
const gk = (s, c) => s + '|' + c;
const DAYN = d => { try { return new Date(String(d).slice(0, 10) + 'T12:00:00').toLocaleDateString('ar', {weekday: 'long'}); } catch(e){ return ''; } };
/* جلب الشبكة: من السيرفر، أو من النسخة المحفوظة، أو بناؤها من بيانات المسابقة المحفوظة عند انقطاع الإنترنت */
async function gFetch(date){
  try { return await api('comp_grid', {p_comp: T.cid, p_date: date || null}); }
  catch(e){
    if(!e.net || !T.comp) throw e;
    const c = T.comp.competition, today = ymd(new Date()), st = String(c.start_date).slice(0, 10), en = String(c.end_date).slice(0, 10);
    const d = date || (today < st ? st : today > en ? en : today);
    const wk = Math.floor((new Date(d + 'T12:00:00') - new Date(st + 'T12:00:00')) / 864e5 / 7) + 1;
    const cats = (T.comp.categories || []).filter(x => x.is_active && x.kind === 'core').map(x => ({id: x.id, key: x.key, name: x.name, weekly_max: x.weekly_max_points, daily_max: x.daily_max != null ? x.daily_max : Math.round(x.weekly_max_points / 5 * 100) / 100}));
    const own = role() === 'teacher' ? String(_currentUser.halaqa_id) : null;
    const rows = (T.comp.participants || []).filter(p => p.status === 'active' && (!own || String(p.halaqa_id) === own)).map(p => ({student_id: p.student_id, name: p.name, halaqa_id: p.halaqa_id, level: p.level, cells: {}}));
    const state = c.status === 'active' ? (today < st ? 'upcoming' : today > en ? 'ended' : 'running') : (c.status === 'ended' ? 'ended' : c.state);
    return {ok: true, date: d, week: wk, today, state, status: c.status, start_date: st, end_date: en, categories: cats, rows, _offline: true};
  }
}
async function tGrid(){ T.G.edits = {}; T.G.state = {}; await gLoad(); }
async function gLoad(keep){
  const G = T.G;
  const r = await gFetch(G.date);
  G.date = String(r.date).slice(0, 10); G.data = r; G.orig = {}; G.off = !!(r._offline || r._cached);
  r.rows.forEach(row => r.categories.forEach(cat => { const cell = row.cells[cat.id] || {}; G.orig[gk(row.student_id, cat.id)] = {v: cell.points == null ? '' : String(Number(cell.points)), ver: cell.ver || null, used: Number(cell.used || 0), pts: Number(cell.points || 0)}; }));
  if(!keep){ G.edits = {}; G.state = {}; }
  /* ما لم يُزامَن بعد (من انقطاع سابق) يظهر بعلامة ⏳ */
  T.outbox.filter(x => x.uid === myId() && x.type === 'eval' && x.comp === T.cid && x.date === G.date).forEach(x => x.items.forEach(it => {
    const k = gk(it.student_id, it.category_id); if(G.orig[k]){ G.edits[k] = it.points == null ? '' : String(it.points); G.state[k] = 'pend'; } }));
  gRender();
}
function gEditable(){ const d = T.G.data; return d && d.state === 'running' && d.status === 'active' && T.G.date <= d.today; }
const dailyOf = cat => Number(cat.daily_max != null ? cat.daily_max : Math.round(cat.weekly_max / 5 * 100) / 100);
function gRem(k, cat){ const o = T.G.orig[k]; return Math.max(0, Number(cat.weekly_max) - (o.used - o.pts)); }
function gLim(k, cat){ return Math.min(dailyOf(cat), gRem(k, cat)); }
function gRender(){
  const main = $('cuMain'); const G = T.G; if(!main || T.tab !== 'grid' || !G.data) return;
  const d = G.data, ed = gEditable();
  let h = (G.off ? staleHtml() || '<div class="cu-warn">📴 تعمل دون اتصال: ما تحفظه يُخزَّن على جهازك بعلامة ⏳ ويُرفع تلقائياً عند عودة الإنترنت. الحد الأسبوعي يُتحقق منه نهائياً عند الرفع.</div>' : '')
    + `<div class="cu-card" style="padding:10px"><div class="cu-row"><button class="cu-btn sec sm" data-act="g_next">→</button><input class="cu-in" type="date" id="gDate" value="${G.date}" min="${String(d.start_date).slice(0, 10)}" max="${String(d.end_date).slice(0, 10) < d.today ? String(d.end_date).slice(0, 10) : d.today}" style="text-align:center;flex:1"><span class="cu-st green" style="font-size:12.5px;padding:8px 13px">${DAYN(G.date)}</span><button class="cu-btn sec sm" data-act="g_prev">←</button></div>
    <div class="cu-mut" style="text-align:center;margin-top:6px">الأسبوع ${AD(d.week)} · الرقم الباهت داخل الخانة = <b>الحد اليومي</b>، وتحتها مجموع الأسبوع من <b>الحد الأسبوعي</b>. يُحفظ ما تغيّر فقط.</div></div>`;
  if(!ed) h += `<div class="cu-warn">${d.state === 'ended' ? '🏁 المسابقة منتهية — لا يمكن تعديل التقييم اليومي (التصحيح من لوحة النقاط بسبب موثق للمشرف).' : d.status !== 'active' ? '⏸ المسابقة غير منشورة أو متوقفة — فعّلها من تبويب المسابقات للتقييم.' : d.state === 'upcoming' ? '🚀 المسابقة لم تبدأ بعد.' : 'لا يمكن التقييم في تاريخ مستقبلي.'}</div>`;
  if(!d.rows.length) { main.innerHTML = h + emptyBox('👥', 'لا يوجد طلاب في نطاق تقييمك', 'المشاركون في هذه المسابقة ليسوا من حلقتك.'); return; }
  h += `<div class="cu-card" style="padding:6px"><div class="cu-scroll"><table class="cu-g"><tr><th class="nm">الطالب</th>${d.categories.map(c => `<th>${E(c.name)}<br><span style="font-weight:600">يومي ${NF(dailyOf(c))} · أسبوعي ${NF(c.weekly_max)}</span>${ed ? `<br><a href="#" data-act="g_col" data-c="${c.id}" style="color:var(--g);font-size:10px">ملء الكل</a>` : ''}</th>`).join('')}</tr>
    ${d.rows.map(row => `<tr><td class="nm">${E(row.name)}</td>${d.categories.map(c => { const k = gk(row.student_id, c.id), o = G.orig[k], ev = G.edits[k], val = ev !== undefined ? ev : o.v;
      const cls = (ev !== undefined && ev !== o.v ? 'dirty ' : '') + (G.state[k] || '');
      return `<td><input data-g="${k}" inputmode="decimal" autocomplete="off" class="${cls}" value="${E(val)}" placeholder="${NF(dailyOf(c))}" ${ed ? '' : 'disabled'} title="المتاح اليوم: ${NF(gLim(k, c))}"><span class="rem">أسبوعي ${NF(o.used - o.pts + (val !== '' ? Number(val) || 0 : 0))}/${NF(c.weekly_max)}</span></td>`; }).join('')}</tr>`).join('')}</table></div></div>`;
  h += `<div class="cu-bar2"><div class="cu-qk">${['+1', '+2', '+5', '+10', 'max', 'clear'].map(q => `<button class="cu-pill" data-act="g_q" data-q="${q}">${q === 'max' ? 'الحد' : q === 'clear' ? 'مسح' : q}</button>`).join('')}</div>
    <button class="cu-btn full" data-act="g_save" id="gSaveBtn" ${ed ? '' : 'disabled'}>💾 حفظ التقييم</button></div>`;
  main.innerHTML = h; gCount();
}
function gDirtyKeys(){ const G = T.G; return Object.keys(G.edits).filter(k => G.orig[k] && G.edits[k] !== G.orig[k].v && G.state[k] !== 'pend'); }
function gCount(){ const b = $('gSaveBtn'); if(!b) return; const n = gDirtyKeys().length; b.textContent = n ? '💾 حفظ التقييم (' + AD(n) + ' تغيير)' : '💾 حفظ التقييم'; }
function gCat(cid){ return T.G.data.categories.find(c => c.id === cid); }
function gInput(t){
  const G = T.G, k = t.dataset.g; if(!G.orig[k]) return;
  const cat = gCat(k.split('|')[1]); const raw = t.value.replace(/[٠-٩]/g, x => '٠١٢٣٤٥٦٧٨٩'.indexOf(x)).replace('٫', '.').replace(/[^\d.]/g, '');
  if(raw !== t.value) t.value = raw;
  G.edits[k] = raw; delete G.state[k];
  const n = Number(raw), lim = gLim(k, cat), bad = raw !== '' && (isNaN(n) || n < 0 || n > lim + 1e-9);
  t.classList.toggle('bad', bad); t.classList.remove('ok', 'pend'); t.classList.toggle('dirty', raw !== G.orig[k].v && !bad);
  t.title = bad ? (n > dailyOf(cat) + 1e-9 ? 'أكبر من الحد اليومي (' + NF(dailyOf(cat)) + ')' : 'أكبر من المتبقي هذا الأسبوع (' + NF(gRem(k, cat)) + ')') : '';
  const sp = t.nextElementSibling; if(sp && sp.classList.contains('rem')) sp.textContent = 'أسبوعي ' + NF(G.orig[k].used - G.orig[k].pts + (isNaN(n) ? 0 : n)) + '/' + NF(cat.weekly_max);
  gCount();
}
function gQuick(q){
  const G = T.G; if(!G.focus){ toast2('اضغط على خانة أولاً ثم اختر القيمة'); return; }
  const k = G.focus, inp = T.el.querySelector('[data-g="' + k + '"]'); if(!inp || inp.disabled) return;
  const cat = gCat(k.split('|')[1]), lim = gLim(k, cat), cur = Number(G.edits[k] !== undefined ? G.edits[k] : G.orig[k].v) || 0;
  let v = q === 'max' ? lim : q === 'clear' ? '' : Math.min(lim, cur + Number(q.slice(1)));
  inp.value = v === '' ? '' : String(Math.round(v * 100) / 100); gInput(inp);
}
async function gColFill(cid){
  const cat = gCat(cid); const v = await formModal('ملء «' + cat.name + '» لكل الطلاب', [{k: 'v', label: 'القيمة (تُقصّ تلقائياً عند الحد اليومي/الأسبوعي لكل طالب)', type: 'number', step: '0.5', min: 0, required: true}]);
  if(!v) return; const n = Number(v.v); if(isNaN(n) || n < 0){ toast2('قيمة غير صالحة'); return; }
  T.G.data.rows.forEach(r => { const k = gk(r.student_id, cid); T.G.edits[k] = String(Math.min(n, gLim(k, cat))); delete T.G.state[k]; }); gRender();
}
function gDateChange(d){
  if(gDirtyKeys().length && !confirm('لديك تغييرات غير محفوظة. هل تريد تجاهلها؟')){ const i = $('gDate'); if(i) i.value = T.G.date; return; }
  T.G.date = d; T.G.edits = {}; T.G.state = {}; $('cuMain').innerHTML = skel(3); gLoad().catch(e => { $('cuMain').innerHTML = eb(e, 'reload'); });
}
function gShift(n){
  const d = T.G.data; const nd = addDays(T.G.date, n);
  if(nd < String(d.start_date).slice(0, 10) || nd > String(d.end_date).slice(0, 10) || nd > d.today){ toast2('لا يمكن الانتقال لتاريخ خارج فترة المسابقة'); return; }
  gDateChange(nd);
}
async function gSave(){
  const G = T.G, keys = gDirtyKeys();
  if(!keys.length){ toast2('لا توجد تغييرات للحفظ'); return; }
  const items = []; let badN = 0;
  keys.forEach(k => { const [sid, cid] = k.split('|'), raw = G.edits[k], cat = gCat(cid), n = Number(raw);
    if(raw !== '' && (isNaN(n) || n < 0 || n > gLim(k, cat) + 1e-9)){ G.state[k] = 'bad'; badN++; return; }
    const it = {student_id: sid, category_id: cid, points: raw === '' ? null : n}; if(G.orig[k].ver) it.ver = G.orig[k].ver; items.push(it); });
  if(badN){ toast2('⚠️ ' + AD(badN) + ' خانة تتجاوز الحد اليومي أو الأسبوعي — صحّحها أولاً'); gRender(); return; }
  const op = UID(), btn = $('gSaveBtn'); if(btn) btn.disabled = true;
  try {
    const r = await api('comp_eval_save', {p_comp: T.cid, p_date: G.date, p_items: items, p_op: op});
    const bad = (r.results || []).filter(x => !['saved', 'same', 'cleared', 'noop'].includes(x.status));
    keys.forEach(k => { delete G.edits[k]; delete G.state[k]; });
    bad.forEach(x => { const k = gk(x.student_id, x.category_id); const raw = items.find(i => i.student_id === x.student_id && i.category_id === x.category_id); G.edits[k] = raw && raw.points != null ? String(raw.points) : ''; G.state[k] = 'bad'; });
    const msgs = {cap: 'تجاوز الحد الأسبوعي', daily_cap: 'تجاوز الحد اليومي', conflict: 'عُدّل من جهاز آخر — حُدّثت القيمة', not_participant: 'ليس مشاركاً', forbidden: 'ليس من نطاق صلاحيتك', bad_points: 'قيمة غير صالحة', duplicate: 'تقييم مكرر', bad_category: 'مجال غير صالح'};
    toast2(bad.length ? '⚠️ حُفظ ' + AD(r.saved) + ' وتعذّر ' + AD(bad.length) + ': ' + (msgs[bad[0].status] || bad[0].status) : '✅ تم حفظ ' + AD(r.saved) + ' تقييماً');
    await gLoad(true); T.lb = null;
  } catch(e){
    if(e.net){ T.outbox.push({id: op, uid: myId(), type: 'eval', comp: T.cid, date: G.date, items, op, at: Date.now()}); obSave();
      keys.forEach(k => { G.state[k] = 'pend'; }); toast2('📴 لا يوجد اتصال — حُفظ التقييم على جهازك ⏳ وسيُرفع تلقائياً عند عودة الإنترنت'); gRender(); }
    else { toast2('❌ ' + e.message); if(btn) btn.disabled = false; }
  }
}

/* ───── طابور المزامنة (عند انقطاع الإنترنت) ───── */
async function flushOutbox(manual){
  if(T.flushing || !online()) { syncBadge(); return; }
  T.outbox = obLoad(); const mine = () => T.outbox.filter(x => x.uid === myId());
  if(!mine().length){ syncBadge(); return; }
  T.flushing = true; let ok = 0, dropped = [];
  try {
    for(const it of mine()){
      let r;
      try {
        if(it.type === 'eval') r = await _rpcT('comp_eval_save', {p_comp: it.comp, p_date: it.date, p_items: it.items, p_op: it.op}, true);
        else if(it.type === 'adjust') r = await _rpcT('comp_adjust', {p_comp: it.comp, p_student: it.student, p_category: it.category, p_points: it.points, p_reason: it.reason, p_date: it.date || null, p_op: it.op}, true);
        else if(it.type === 'adjust_many') r = await _rpcT('comp_adjust_many', {p_comp: it.comp, p_students: it.students, p_categories: it.categories, p_points: it.points, p_reason: it.reason, p_date: it.date || null, p_op: it.op}, true);
        else r = {ok: true};
      } catch(e){ break; }
      if(r && r.ok === false && r.error === 'auth') break;
      T.outbox = T.outbox.filter(x => x.id !== it.id); obSave();
      if(r && r.ok === false) dropped.push(errMsg(r));
      else { ok++; const badItems = (r && r.results || []).filter(x => !['saved', 'same', 'cleared', 'noop'].includes(x.status)); if(badItems.length) dropped.push(AD(badItems.length) + ' عنصر رُفض عند المزامنة (' + (ST_AR[badItems[0].status] || badItems[0].status) + ')'); }
    }
  } finally { T.flushing = false; syncBadge(); }
  if(ok) toast2('✅ تمت مزامنة ' + AD(ok) + ' عملية معلّقة');
  if(dropped.length) toast2('⚠️ رُفضت عملية معلّقة: ' + dropped[0]);
  if((ok || dropped.length) && T.el && (T.tab === 'grid')) { T.G.edits = {}; T.G.state = {}; gLoad().catch(() => {}); }
}
window.addEventListener('online', () => { syncBadge(); setTimeout(() => { if(typeof _currentUser !== 'undefined' && _currentUser && canComp()) flushOutbox(); }, 1200); });
window.addEventListener('offline', syncBadge);

/* ───── لوحة النقاط: إضافة/خصم لعدة طلاب ومجالات + سجل العمليات ───── */
const QUICK_REASONS = ['أداء متميز', 'التزام وانضباط', 'مخالفة سلوكية', 'تصحيح خطأ سابق', 'مبادرة طيبة'];
async function tPts(){
  const g = await gFetch(null);
  const cats = (T.comp.categories || []).filter(c => c.is_active);
  T.pts = {rows: g.rows, cats, state: g.state, status: g.status, today: g.today, start: String(g.start_date).slice(0, 10), end: String(g.end_date).slice(0, 10), off: !!(g._offline || g._cached)};
  const P = T.P;
  P.sids = new Set([...P.sids].filter(s => g.rows.some(r => r.student_id === s)));
  P.cats = new Set([...P.cats].filter(c => cats.some(x => x.id === c)));
  pRender(); pRecent();
}
function pStuList(){
  const box = $('pStuList'); if(!box) return; const q = (T.P.q || '').trim();
  const rows = T.pts.rows.filter(r => !q || r.name.includes(q));
  box.innerHTML = rows.map(r => `<label class="cu-row" style="padding:7px 4px;border-bottom:1px solid var(--bd);cursor:pointer"><input type="checkbox" data-ps="${E(r.student_id)}" ${T.P.sids.has(r.student_id) ? 'checked' : ''}><span style="font-size:13px;font-weight:700">${E(r.name)}</span></label>`).join('') || '<div class="cu-mut" style="padding:8px">لا نتائج.</div>';
}
function pSum(){
  const a = $('pSc'), b = $('pSummary'); const ns = T.P.sids.size, nc = T.P.cats.size;
  if(a) a.textContent = AD(ns);
  if(b) b.innerHTML = ns && nc ? `سيُطبَّق على <b>${AD(ns)}</b> طالب × <b>${AD(nc)}</b> مجال = <b>${AD(ns * nc)}</b> عملية، لكل عملية السبب نفسه.` : 'اختر طالباً واحداً أو أكثر ومجالاً واحداً أو أكثر.';
}
function pendHtml(){
  const list = T.outbox.filter(x => x.uid === myId() && x.comp === T.cid && x.type === 'adjust_many');
  if(!list.length) return '';
  return `<div class="cu-warn">⏳ ${AD(list.length)} عملية نقاط معلّقة لم تُزامن بعد — تُرفع تلقائياً عند عودة الإنترنت:<br>${list.map(x => '• ' + SG(x.points) + ' لـ ' + AD(x.students.length) + ' طالب × ' + AD(x.categories.length) + ' مجال — ' + E(x.reason)).join('<br>')}</div>`;
}
function pRender(){
  const main = $('cuMain'); const p = T.pts, P = T.P; if(!main || T.tab !== 'pts' || !p) return;
  if(!p.rows.length){ main.innerHTML = emptyBox('👥', 'لا يوجد طلاب في نطاق صلاحيتك', 'المشاركون في هذه المسابقة ليسوا من حلقتك.'); return; }
  const warn = p.state === 'ended' ? (role() === 'teacher' ? '🏁 المسابقة منتهية ومقفلة — التصحيح بعد الإغلاق للمشرف فقط.' : '🏁 المسابقة منتهية — أي تعديل يُسجَّل «بعد الإغلاق» وبسبب موثق.')
    : p.status !== 'active' ? '⏸ المسابقة غير منشورة أو متوقفة — لا يمكن تسجيل نقاط الآن.' : '';
  main.innerHTML = `${p.off ? (staleHtml() || '<div class="cu-warn">📴 دون اتصال — ما تضيفه يُحفظ على جهازك ويُرفع عند عودة الإنترنت.</div>') : ''}${warn ? `<div class="cu-warn">${warn}</div>` : ''}${pendHtml()}
    <div class="cu-card"><div class="cu-h"><span class="dot"></span>إضافة أو خصم نقاط</div>
    <label class="cu-lbl">الطلاب — <b id="pSc">${AD(P.sids.size)}</b> محدد</label>
    <div class="cu-row"><input class="cu-in" id="pSearch" placeholder="🔎 بحث عن طالب" value="${E(P.q || '')}"><button class="cu-btn sec sm" data-act="p_all">الكل</button><button class="cu-btn sec sm" data-act="p_none">مسح</button></div>
    <div id="pStuList" style="max-height:220px;overflow-y:auto;border:1px solid var(--bd);border-radius:12px;padding:2px 8px;margin-top:8px"></div>
    <label class="cu-lbl">مجالات التقييم — اختر واحداً أو أكثر</label>
    <div class="cu-chips" style="margin-top:0">${p.cats.map(c => `<button class="cu-pill ${P.cats.has(c.id) ? 'on' : ''}" data-act="p_cat" data-c="${c.id}">${c.kind === 'bonus' ? '⭐ ' : ''}${E(c.name)}</button>`).join('')}</div>
    <label class="cu-lbl">القيمة (لكل عملية)</label><div class="cu-chips" style="margin-top:0">${['1', '2', '5', '10'].map(a => `<button class="cu-pill" data-act="p_amt" data-a="${a}">+${AD(a)}</button>`).join('')}${['-1', '-2', '-5'].map(a => `<button class="cu-pill neg" data-act="p_amt" data-a="${a}">−${AD(a.slice(1))}</button>`).join('')}</div>
    <input class="cu-in" id="pAmt" type="text" inputmode="decimal" placeholder="أو أدخل قيمة مخصصة (سالبة للخصم)" value="${E(P.amt)}" style="margin-top:8px">
    <label class="cu-lbl">السبب (إلزامي)</label><textarea class="cu-ta" id="pReason" placeholder="اكتب سبب الإضافة أو الخصم">${E(P.reason)}</textarea><div class="cu-chips" id="pChips"></div>
    <label class="cu-lbl">التاريخ (اختياري — الافتراضي اليوم)</label><input class="cu-in" type="date" id="pDate" value="${E(P.date)}" min="${p.start}" max="${p.end}">
    <div class="cu-mut" id="pSummary" style="margin-top:10px"></div>
    <button class="cu-btn full" style="margin-top:10px" data-act="p_apply" id="pApplyBtn">تطبيق</button></div>
    <div class="cu-card"><div class="cu-row" style="justify-content:space-between"><div class="cu-h" style="margin:0"><span class="dot"></span>سجل الطالب</div><button class="cu-btn sec sm" data-act="p_audit">🧾 سجل التدقيق</button></div><div id="pRecent" style="margin-top:8px"></div></div>`;
  pStuList(); pChips(); pMark(); pSum();
}
function pMark(){ T.el.querySelectorAll('[data-act="p_amt"]').forEach(b => b.classList.toggle('on', b.dataset.a === String(T.P.amt))); }
function pChips(){
  const box = $('pChips'); if(!box) return; const set = (T.comp.competition.settings || {});
  const anyBonus = T.pts.cats.some(c => c.kind === 'bonus' && T.P.cats.has(c.id));
  box.innerHTML = (anyBonus && (set.bonus_items || []).length ? (set.bonus_items || []).map(i => `<button class="cu-pill" data-act="p_item" data-n="${E(i.name)}" data-a="${i.points}">⭐ ${E(i.name)} (+${NF(i.points)})</button>`).join('') : '')
    + QUICK_REASONS.map(r => `<button class="cu-pill" data-act="p_reason" data-n="${E(r)}">${E(r)}</button>`).join('');
}
async function pRecent(){
  const box = $('pRecent'); if(!box) return;
  if(T.P.sids.size !== 1){ box.innerHTML = '<div class="cu-mut">اختر طالباً واحداً لعرض سجله وتصحيح عملياته.</div>'; return; }
  const sid = [...T.P.sids][0];
  try { const d = await api('comp_student_detail', {p_comp: T.cid, p_student: sid}); if(!T.P.sids.has(sid) || T.P.sids.size !== 1) return;
    box.innerHTML = `<div class="cu-mut" style="margin-bottom:6px"><b style="color:var(--ink)">${E(d.name || '')}</b> · المجموع: <b style="color:var(--ink)">${NF(d.total)}</b> · الترتيب: ${d.rank ? '#' + AD(d.rank) : '—'}</div>` + entRows(d.entries, canEditNow(), 12); }
  catch(e){ box.innerHTML = eb(e); }
}
const ST_AR = {cap: 'تجاوز الحد الأسبوعي', below_zero: 'ينزل المجموع تحت الصفر', not_participant: 'غير مشارك', forbidden: 'خارج صلاحيتك', locked: 'مقفلة', bad_category: 'مجال غير صالح'};
async function pApply(){
  const P = T.P, p = T.pts; const amt = Number(String(P.amt).replace(/[٠-٩]/g, x => '٠١٢٣٤٥٦٧٨٩'.indexOf(x)).replace('−', '-'));
  const sids = [...P.sids], cids = [...P.cats];
  if(!sids.length || !cids.length){ toast2('اختر طالباً واحداً على الأقل ومجالاً واحداً على الأقل'); return; }
  if(!P.amt || isNaN(amt) || amt === 0){ toast2('أدخل قيمة النقاط (موجبة للإضافة وسالبة للخصم)'); return; }
  if((P.reason || '').trim().length < 2){ toast2('اكتب سبب العملية'); return; }
  const ops = sids.length * cids.length;
  if((amt < 0 || ops > 1) && !(await ask((amt < 0 ? 'خصم ' : 'إضافة ') + NF(Math.abs(amt)) + ' نقطة في كل عملية — ' + AD(sids.length) + ' طالب × ' + AD(cids.length) + ' مجال = ' + AD(ops) + ' عملية.\nالسبب: ' + P.reason, {danger: amt < 0, ok: amt < 0 ? 'تأكيد الخصم' : 'تأكيد'}))) return;
  const op = UID(), args = {p_comp: T.cid, p_students: sids, p_categories: cids, p_points: amt, p_reason: P.reason.trim(), p_date: P.date || null, p_op: op};
  const btn = $('pApplyBtn'); if(btn) btn.disabled = true;
  try {
    const r = await api('comp_adjust_many', args);
    const bad = (r.results || []).filter(x => x.status !== 'saved');
    toast2(bad.length ? '⚠️ نُفّذ ' + AD(r.saved) + ' وتعذّر ' + AD(bad.length) + ': ' + (ST_AR[bad[0].status] || bad[0].status) : (amt > 0 ? '✅ أُضيفت النقاط (' : '✅ خُصمت النقاط (') + AD(r.saved) + ' عملية)');
    P.amt = ''; P.reason = ''; T.lb = null; pRender(); pRecent();
  } catch(e){
    if(e.net){ T.outbox.push({id: op, uid: myId(), type: 'adjust_many', comp: T.cid, students: sids, categories: cids, points: amt, reason: args.p_reason, date: args.p_date, op, at: Date.now()}); obSave();
      toast2('📴 لا يوجد اتصال — حُفظت العملية على جهازك ⏳ وستُرفع تلقائياً عند عودة الإنترنت'); P.amt = ''; P.reason = ''; pRender(); }
    else { toast2('❌ ' + e.message); if(btn) btn.disabled = false; }
  }
}
const ACT_AR = {create: 'تقييم جديد', update: 'تعديل', void: 'حذف', restore: 'استرجاع', adjust: 'نقاط يدوية', adjust_after_close: 'تصحيح بعد الإغلاق', update_after_close: 'تعديل بعد الإغلاق', void_after_close: 'حذف بعد الإغلاق'};
async function auditView(more){
  let st = T.audit;
  if(!more || !st || !st.m.isConnected){ const m = modal('<div class="cu-row" style="justify-content:space-between"><h3 style="margin:0">🧾 سجل التدقيق</h3><button class="cu-btn sec sm" onclick="this.closest(\'.cu-modal\').remove()">✕</button></div><div id="audList" style="margin-top:10px"></div><div id="audMore"></div>');
    bindClicks(m, TH); st = T.audit = {m, before: null}; $('audList').innerHTML = skel(3); }
  try {
    const r = await api('comp_audit_list', {p_comp: T.cid, p_limit: 40, p_before: st.before});
    const l = $('audList'); if(!st.before) l.innerHTML = '';
    if(!r.rows.length && !st.before) l.innerHTML = emptyBox('🧾', 'لا توجد عمليات مسجلة');
    r.rows.forEach(a => { const d = document.createElement('div'); d.className = 'cu-ent';
      d.innerHTML = `<div style="min-width:0"><b>${E(a.student_name)}</b> — ${E(ACT_AR[a.action_type] || a.action_type)}<div class="cu-mut">${E(a.category_name || '')}${a.reason ? ' · ' + E(a.reason) : ''}</div><div class="cu-mut">${E(a.performed_by_name || '')} · ${fmtT(a.created_at)}</div></div>
        <div class="pt" style="font-size:11.5px">${a.old_points == null ? '' : NF(a.old_points) + ' ← '}${a.new_points == null ? 'حذف' : NF(a.new_points)}</div>`; l.appendChild(d); });
    if(r.rows.length) st.before = r.rows[r.rows.length - 1].id;
    $('audMore').innerHTML = r.rows.length >= 40 ? '<button class="cu-btn sec full" data-act="p_more" style="margin-top:8px">تحميل المزيد</button>' : '';
  } catch(e){ $('audList').innerHTML = errBox(e.message); }
}

/* ═════════ الواجبات (المعلم) ═════════ */
let A = null;
const A_ST = {draft: ['مسودة', 'gray'], published: ['منشور', 'green'], closed: ['مغلق', 'slate']};
async function tAsg(){
  const r = await api('asg_list'); const main = $('cuMain');
  let h = `<button class="cu-btn full" data-act="a_new" style="margin-bottom:12px">＋ واجب جديد</button>`;
  if(!r.rows.length) h += emptyBox('📋', 'لا توجد واجبات بعد', 'أنشئ واجباً بأسئلة اختيار من متعدد أو صح/خطأ أو مقالية، وانشره لطلاب حلقتك.');
  h += r.rows.map(a => { const s = A_ST[a.status] || ['', 'gray'];
    return `<div class="cu-card"><div class="cu-row" style="justify-content:space-between"><b style="font-size:14px">📝 ${E(a.title)}</b><span class="cu-st ${s[1]}">${s[0]}</span></div>
      <div class="cu-mut" style="margin-top:4px">📖 ${E(a.halaqa_name || hqName(a.halaqa_id))} · ${AD(a.questions)} أسئلة · ${NF(a.max_score)} درجة${a.due_at ? ' · آخر موعد ' + fmtT(a.due_at) : ''}</div>
      <div class="cu-grid2" style="margin-top:8px"><div class="cu-stat"><b>${AD(a.submitted)}/${AD(a.targets)}</b><span>سلّموا</span></div><div class="cu-stat"><b>${a.avg_pct == null ? '—' : AD(a.avg_pct) + '٪'}</b><span>المتوسط${a.pending ? ' · ' + AD(a.pending) + ' بانتظار التصحيح' : ''}</span></div></div>
      <div class="cu-row wrap" style="margin-top:10px"><button class="cu-btn sm" data-act="a_res" data-id="${a.id}">📊 النتائج</button><button class="cu-btn sec sm" data-act="a_edit" data-id="${a.id}">✏️ تعديل</button>
      ${a.status === 'draft' ? `<button class="cu-btn sm" data-act="a_stat" data-id="${a.id}" data-s="published">🚀 نشر</button>` : ''}${a.status === 'published' ? `<button class="cu-btn amb sm" data-act="a_stat" data-id="${a.id}" data-s="closed">🔒 إغلاق</button>` : ''}${a.status === 'closed' ? `<button class="cu-btn sec sm" data-act="a_stat" data-id="${a.id}" data-s="published">↩ إعادة نشر</button>` : ''}
      <button class="cu-btn red sm" data-act="a_del" data-id="${a.id}">🗑</button></div></div>`; }).join('');
  main.innerHTML = h;
}
async function aStatus(id, s){
  if(s === 'closed' && !(await ask('إغلاق الواجب؟ لن يستطيع الطلاب التسليم بعد ذلك.', {ok: 'إغلاق'}))) return;
  await api('asg_set_status', {p_id: id, p_status: s}); toast2('✅ تم تحديث حالة الواجب'); tGo('asg');
}
async function aDelete(id){
  if(!(await ask('حذف الواجب وجميع إجابات الطلاب نهائياً؟', {danger: true, ok: 'حذف نهائي'}))) return;
  await api('asg_delete', {p_id: id}); toast2('🗑 تم حذف الواجب'); tGo('asg');
}
const toLocalDT = ts => { if(!ts) return ''; const d = new Date(ts), p = n => String(n).padStart(2, '0'); return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes()); };
async function aForm(id){
  const m = modal(`<div>${skel(3)}</div>`, {sticky: true}); bindClicks(m, TH);
  try {
    await tRoster();
    const own = role() === 'teacher' ? String(_currentUser.halaqa_id) : '';
    A = {id: id || null, halaqa: own || (T.roster.halaqat[0] ? String(T.roster.halaqat[0].id) : ''), title: '', desc: '', due: '', mode: 'all', stu: new Set(), reveal: true, late: false, qs: [], hasSub: false, status: 'draft'};
    if(id){ const r = await api('asg_get', {p_id: id}), a = r.assignment;
      Object.assign(A, {halaqa: String(a.halaqa_id), title: a.title, desc: a.description, due: toLocalDT(a.due_at), mode: (a.student_ids || []).length ? 'sel' : 'all', stu: new Set(a.student_ids || []),
        reveal: !a.settings || a.settings.reveal_answers !== false, late: !!(a.settings && a.settings.allow_late), hasSub: r.has_submissions, status: a.status,
        qs: r.questions.map(q => ({qtype: q.qtype, prompt: q.prompt, options: q.qtype === 'mcq' ? q.options.slice() : [], correct: q.qtype === 'text' ? (q.correct || '') : q.correct, points: q.points}))}); }
    else A.qs = [{qtype: 'mcq', prompt: '', options: ['', ''], correct: 0, points: 1}];
  } catch(e){ m.remove(); toast2('❌ ' + e.message); return; }
  aRender(m);
}
function aRender(m){
  const isT = role() === 'teacher';
  m.querySelector('.cu-sheet').innerHTML = `<h3>${A.id ? '✏️ تعديل الواجب' : '📋 واجب جديد'}</h3>
    <div class="cu-card"><label class="cu-lbl">العنوان</label><input class="cu-in" data-a="title" value="${E(A.title)}" maxlength="120" placeholder="مثال: واجب سورة الملك">
      <label class="cu-lbl">تعليمات (اختياري)</label><textarea class="cu-ta" data-a="desc" maxlength="1000">${E(A.desc)}</textarea>
      <label class="cu-lbl">الحلقة</label><select class="cu-sel" data-a="halaqa" ${isT || A.id ? 'disabled' : ''}>${T.roster.halaqat.map(h => `<option value="${E(h.id)}" ${String(h.id) === A.halaqa ? 'selected' : ''}>${E(h.name)}</option>`).join('')}</select>
      <label class="cu-lbl">آخر موعد للتسليم (اختياري)</label><input class="cu-in" type="datetime-local" data-a="due" value="${A.due}">
      <label class="cu-lbl">الطلاب المستهدفون</label><div class="cu-row"><label class="cu-row"><input type="radio" name="aMode" value="all" data-act="a_stud" ${A.mode === 'all' ? 'checked' : ''}> كل طلاب الحلقة</label><label class="cu-row"><input type="radio" name="aMode" value="sel" data-act="a_stud" ${A.mode === 'sel' ? 'checked' : ''}> طلاب محددون</label></div>
      <div id="aStuBox" style="display:${A.mode === 'sel' ? 'block' : 'none'}"></div>
      <label class="cu-row" style="margin-top:10px"><input type="checkbox" data-a="reveal" ${A.reveal ? 'checked' : ''}> <span style="font-size:12.5px;font-weight:700">إظهار الإجابات الصحيحة للطالب بعد التسليم</span></label>
      <label class="cu-row" style="margin-top:6px"><input type="checkbox" data-a="late" ${A.late ? 'checked' : ''}> <span style="font-size:12.5px;font-weight:700">السماح بالتسليم بعد الموعد (يُعلَّم «متأخر»)</span></label></div>
    <div class="cu-card"><div class="cu-h">الأسئلة</div>${A.hasSub ? '<div class="cu-warn">وصلت إجابات لهذا الواجب — لا يمكن تغيير الأسئلة، ويمكنك تعديل العنوان والموعد والإعدادات فقط.</div>' : ''}<div id="aQs"></div>
      ${A.hasSub ? '' : `<div class="cu-row wrap" style="margin-top:8px"><button class="cu-btn sec sm" data-act="a_q" data-t="mcq">＋ اختيار من متعدد</button><button class="cu-btn sec sm" data-act="a_q" data-t="truefalse">＋ صح / خطأ</button><button class="cu-btn sec sm" data-act="a_q" data-t="text">＋ سؤال مقالي</button></div>`}</div>
    <div id="aErr" class="cu-err" style="display:none"></div>
    <div class="cu-grid2"><button class="cu-btn sec" onclick="this.closest('.cu-modal').remove()">إلغاء</button><button class="cu-btn" data-act="a_save">💾 حفظ</button></div>
    ${A.status !== 'published' ? '<button class="cu-btn full" data-act="a_pub" style="margin-top:8px;background:linear-gradient(135deg,#d97706,#ea580c)">🚀 حفظ ونشر للطلاب</button>' : ''}`;
  if(!m.dataset.ab){ m.dataset.ab = '1'; m.addEventListener('input', aInput); m.addEventListener('change', aInput); }
  aStu(); aQRender();
}
function aStu(){
  const box = $('aStuBox'); if(!box) return;
  const list = (T.roster.students || []).filter(s => String(s.halaqa_id) === A.halaqa);
  box.innerHTML = list.map(s => `<label class="cu-row" style="padding:5px 0"><input type="checkbox" data-as="${E(s.id)}" ${A.stu.has(s.id) ? 'checked' : ''}> <span style="font-size:12.5px;font-weight:700">${E(s.name)}</span></label>`).join('') || '<div class="cu-mut">لا يوجد طلاب.</div>';
}
function aQAdd(t){ A.qs.push(t === 'mcq' ? {qtype: 'mcq', prompt: '', options: ['', ''], correct: 0, points: 1} : t === 'truefalse' ? {qtype: 'truefalse', prompt: '', options: [], correct: true, points: 1} : {qtype: 'text', prompt: '', options: [], correct: '', points: 2}); aQRender(); }
function aQRender(){
  const box = $('aQs'); if(!box) return;
  const T3 = {mcq: 'اختيار من متعدد', truefalse: 'صح / خطأ', text: 'مقالي (يصحّحه المعلم)'};
  box.innerHTML = A.qs.map((q, i) => `<div class="cu-q"><div class="cu-row" style="justify-content:space-between"><b style="font-size:12px">${AD(i + 1)}. ${T3[q.qtype]}</b>${A.hasSub ? '' : `<div class="cu-row"><button class="cu-pill" data-act="a_qup" data-i="${i}">▲</button><button class="cu-pill" data-act="a_qdn" data-i="${i}">▼</button><button class="cu-btn red sm" data-act="a_qdel" data-i="${i}">✕</button></div>`}</div>
    <textarea class="cu-ta" style="min-height:54px" data-qp="${i}" placeholder="نص السؤال" ${A.hasSub ? 'disabled' : ''}>${E(q.prompt)}</textarea>
    ${q.qtype === 'mcq' ? q.options.map((o, k) => `<div class="cu-row" style="margin-top:6px"><input type="radio" name="qc${i}" data-qc="${i}" value="${k}" ${q.correct === k ? 'checked' : ''} ${A.hasSub ? 'disabled' : ''}><input class="cu-in" style="padding:8px" data-qo="${i}:${k}" value="${E(o)}" placeholder="الخيار ${AD(k + 1)}" ${A.hasSub ? 'disabled' : ''}>${q.options.length > 2 && !A.hasSub ? `<button class="cu-btn red sm" data-act="a_optdel" data-i="${i}" data-o="${k}">✕</button>` : ''}</div>`).join('') + (q.options.length < 6 && !A.hasSub ? `<button class="cu-btn sec sm" style="margin-top:6px" data-act="a_optadd" data-i="${i}">＋ خيار</button>` : '') + '<div class="cu-mut" style="margin-top:4px">حدّد الدائرة بجانب الإجابة الصحيحة.</div>' : ''}
    ${q.qtype === 'truefalse' ? `<label class="cu-lbl">الإجابة الصحيحة</label><select class="cu-sel" data-qtf="${i}" ${A.hasSub ? 'disabled' : ''}><option value="1" ${q.correct === true ? 'selected' : ''}>صح</option><option value="0" ${q.correct === false ? 'selected' : ''}>خطأ</option></select>` : ''}
    ${q.qtype === 'text' ? `<textarea class="cu-ta" style="min-height:44px;margin-top:6px" data-qm="${i}" placeholder="إجابة نموذجية للمعلم (اختياري، لا تظهر للطالب)" ${A.hasSub ? 'disabled' : ''}>${E(q.correct || '')}</textarea>` : ''}
    <label class="cu-lbl">الدرجة</label><input class="cu-in" style="width:90px;padding:8px" type="number" min="0" step="0.5" data-qpt="${i}" value="${q.points}" ${A.hasSub ? 'disabled' : ''}></div>`).join('') || '<div class="cu-mut">لا توجد أسئلة.</div>';
}
function aInput(e){
  const t = e.target; if(!A) return;
  if(t.dataset.a){ const k = t.dataset.a; A[k === 'desc' ? 'desc' : k] = t.type === 'checkbox' ? t.checked : t.value; if(k === 'halaqa'){ A.stu = new Set(); aStu(); } }
  else if(t.dataset.as){ t.checked ? A.stu.add(t.dataset.as) : A.stu.delete(t.dataset.as); }
  else if(t.name === 'aMode'){ A.mode = t.value; const b = $('aStuBox'); if(b) b.style.display = t.value === 'sel' ? 'block' : 'none'; }
  else if(t.dataset.qp != null) A.qs[Number(t.dataset.qp)].prompt = t.value;
  else if(t.dataset.qpt != null) A.qs[Number(t.dataset.qpt)].points = t.value;
  else if(t.dataset.qo){ const [i, k] = t.dataset.qo.split(':').map(Number); A.qs[i].options[k] = t.value; }
  else if(t.dataset.qc != null) A.qs[Number(t.dataset.qc)].correct = Number(t.value);
  else if(t.dataset.qtf != null) A.qs[Number(t.dataset.qtf)].correct = t.value === '1';
  else if(t.dataset.qm != null) A.qs[Number(t.dataset.qm)].correct = t.value;
}
async function aSave(m, publish){
  const er = $('aErr'), bad = msg => { er.textContent = msg; er.style.display = 'block'; er.scrollIntoView({block: 'center'}); };
  if((A.title || '').trim().length < 2) return bad('اكتب عنوان الواجب');
  if(!A.halaqa) return bad('اختر الحلقة');
  if(A.mode === 'sel' && !A.stu.size) return bad('حدّد طالباً واحداً على الأقل أو اختر «كل طلاب الحلقة»');
  const qs = [];
  if(!A.hasSub){
    if(!A.qs.length) return bad('أضف سؤالاً واحداً على الأقل');
    for(let i = 0; i < A.qs.length; i++){
      const q = A.qs[i]; if((q.prompt || '').trim().length < 2) return bad('اكتب نص السؤال ' + AD(i + 1));
      const pts = Number(q.points); if(isNaN(pts) || pts < 0) return bad('درجة السؤال ' + AD(i + 1) + ' غير صالحة');
      if(q.qtype === 'mcq'){ const opts = q.options.map((o, k) => ({o: String(o).trim(), k})).filter(x => x.o);
        if(opts.length < 2) return bad('السؤال ' + AD(i + 1) + ' يحتاج خيارين على الأقل');
        const ci = opts.findIndex(x => x.k === q.correct); if(ci < 0) return bad('حدّد الإجابة الصحيحة للسؤال ' + AD(i + 1));
        qs.push({qtype: 'mcq', prompt: q.prompt.trim(), options: opts.map(x => x.o), correct: ci, points: pts}); }
      else if(q.qtype === 'truefalse') qs.push({qtype: 'truefalse', prompt: q.prompt.trim(), correct: !!q.correct, points: pts});
      else qs.push({qtype: 'text', prompt: q.prompt.trim(), correct: (q.correct || '').trim(), points: pts});
    }
  }
  const payload = {id: A.id || undefined, halaqa_id: A.halaqa, title: A.title.trim(), description: (A.desc || '').trim(), due_at: A.due ? new Date(A.due).toISOString() : null,
    student_ids: A.mode === 'sel' ? [...A.stu] : [], settings: {reveal_answers: !!A.reveal, allow_late: !!A.late}};
  if(!A.hasSub) payload.questions = qs;
  m.querySelectorAll('[data-act="a_save"],[data-act="a_pub"]').forEach(b => b.disabled = true);
  try {
    const r = await api('asg_save', {p: payload});
    if(publish) await api('asg_set_status', {p_id: r.id, p_status: 'published'});
    toast2(publish ? '🚀 تم حفظ الواجب ونشره' : '✅ تم حفظ الواجب'); m.remove(); tGo('asg');
  } catch(e){ m.querySelectorAll('[data-act="a_save"],[data-act="a_pub"]').forEach(b => b.disabled = false); bad(e.message); }
}
async function aResults(id){
  const m = modal(`<div>${skel(3)}</div>`); bindClicks(m, TH);
  let r; try { r = await api('asg_results', {p_id: id}); } catch(e){ m.remove(); toast2('❌ ' + e.message); return; }
  const a = r.assignment, done = r.rows.filter(x => x.submitted), avg = done.length ? Math.round(done.reduce((s, x) => s + (x.pct || 0), 0) / done.length * 10) / 10 : null;
  m.querySelector('.cu-sheet').innerHTML = `<div class="cu-row" style="justify-content:space-between"><h3 style="margin:0">📊 ${E(a.title)}</h3><button class="cu-btn sec sm" onclick="this.closest('.cu-modal').remove()">✕</button></div>
    <div class="cu-grid2" style="margin:10px 0"><div class="cu-stat"><b>${AD(done.length)}/${AD(r.rows.length)}</b><span>سلّموا</span></div><div class="cu-stat"><b>${avg == null ? '—' : AD(avg) + '٪'}</b><span>متوسط الدرجات</span></div></div>
    <div class="cu-card"><div class="cu-scroll"><table class="cu-tbl"><tr><th class="nm">الطالب</th><th>الحالة</th><th>الدرجة</th></tr>${r.rows.map(x => `<tr class="${x.submitted ? 'clk' : ''}" ${x.submitted ? `data-act="a_sub" data-id="${id}" data-s="${E(x.student_id)}"` : ''}><td class="nm">${E(x.name)}</td>
      <td>${x.submitted ? (x.pending_manual ? '<span class="cu-st amber">بانتظار التصحيح</span>' : '<span class="cu-st green">مُصحَّح</span>') + (x.late ? ' <span class="cu-st gray">متأخر</span>' : '') : '<span class="cu-st slate">لم يسلّم</span>'}</td><td>${x.submitted ? NF(x.score) + ' / ' + NF(x.max) : '—'}</td></tr>`).join('')}</table></div><div class="cu-mut" style="margin-top:6px">اضغط على طالب لمراجعة إجاباته وتصحيح الأسئلة المقالية.</div></div>
    <div class="cu-card"><div class="cu-h">إحصاء الأسئلة</div>${r.questions.filter(q => q.qtype !== 'text').map(q => `<div class="cu-ent"><span>${AD(q.position)}. ${E(q.prompt)}</span><b>${AD(q.correct_count)}/${AD(q.answered)} صحيح</b></div>`).join('') || '<div class="cu-mut">لا أسئلة موضوعية.</div>'}</div>`;
}
async function aSubmission(id, sid){
  const m = modal(`<div>${skel(3)}</div>`, {sticky: true}); bindClicks(m, TH);
  let r; try { r = await api('asg_submission', {p_id: id, p_student: sid}); } catch(e){ m.remove(); toast2('❌ ' + e.message); return; }
  m.querySelector('.cu-sheet').innerHTML = `<div class="cu-row" style="justify-content:space-between"><h3 style="margin:0">${E(r.name || sid)}</h3><button class="cu-btn sec sm" onclick="this.closest('.cu-modal').remove()">✕</button></div>
    <div class="cu-mut" style="margin:6px 0 10px">${fmtT(r.submitted_at)} · الدرجة الحالية ${NF(r.score)} / ${NF(r.max)}${r.late ? ' · سُلّم متأخراً' : ''}</div>
    ${r.questions.map((q, i) => { const ans = q.answer;
      let body = q.qtype === 'mcq' ? `<div class="cu-opt ${ans === q.correct ? 'right' : 'wrong'}" style="cursor:default">${ans == null ? '— لم يُجب —' : E(q.options[ans])}</div>${ans !== q.correct ? `<div class="cu-mut">الصحيح: ${E(q.options[q.correct])}</div>` : ''}`
        : q.qtype === 'truefalse' ? `<div class="cu-opt ${ans === q.correct ? 'right' : 'wrong'}" style="cursor:default">${ans == null ? '— لم يُجب —' : ans ? 'صح' : 'خطأ'}</div>`
        : `<div class="cu-opt" style="cursor:default;white-space:pre-wrap">${E(ans || '— لم يُجب —')}</div>${q.correct ? `<div class="cu-mut">إجابة نموذجية: ${E(q.correct)}</div>` : ''}<label class="cu-lbl">الدرجة (من ${NF(q.points)})</label><input class="cu-in" style="width:100px" type="number" min="0" max="${q.points}" step="0.5" data-gr="${q.id}" value="${q.grade == null ? '' : q.grade}">`;
      return `<div class="cu-q"><div style="font-size:13px;font-weight:900">${AD(i + 1)}. ${E(q.prompt)} <span class="cu-mut">(${NF(q.points)})</span></div>${body}</div>`; }).join('')}
    <label class="cu-lbl">ملاحظة للطالب (اختياري)</label><textarea class="cu-ta" id="grFb" placeholder="أحسنت…">${E(r.feedback || '')}</textarea>
    <div id="grErr" class="cu-err" style="display:none;margin-top:8px"></div><button class="cu-btn full" style="margin-top:10px" data-act="a_grade" data-id="${id}" data-s="${E(sid)}">💾 حفظ التصحيح</button>`;
}
async function aGrade(id, sid){
  const m = document.querySelector('.cu-modal:last-of-type'); const grades = {};
  document.querySelectorAll('[data-gr]').forEach(i => { if(i.value !== '') grades[i.dataset.gr] = Number(i.value); });
  try { const r = await api('asg_grade', {p_id: id, p_student: sid, p_grades: grades, p_feedback: ($('grFb').value || '').trim() || null});
    toast2('✅ تم حفظ التصحيح — الدرجة ' + NF(r.score)); document.querySelectorAll('.cu-modal').forEach(x => x.remove()); aResults(id);
  } catch(e){ const er = $('grErr'); er.textContent = e.message; er.style.display = 'block'; }
}

/* ═════════ المحادثات v2: نصوص + صور + فيديو + صوت + ردود + تعديل/حذف + مجموعات + ترتيب + إشعارات ═════════ */
const CH = {hostId: 'cuMain', mode: 'staff', list: null, key: null, title: '', rows: [], canPost: true, kind: 's', staff: true, pend: [], reply: null, edit: null, order: false, rec: null, sig: ''};
const MEDIA = new Map();
const chHost = () => $(CH.hostId);
const isStaffUser = () => role() !== 'student';
const owner = () => CH.mode === 'student' ? S : T;
function chReset(){ CH.key = null; CH.reply = null; CH.edit = null; if(CH.rec) chRecStop(false); }
const kindPrev = (k, b) => k === 'image' ? '📷 صورة' : k === 'video' ? '🎬 فيديو' : k === 'audio' ? '🎤 رسالة صوتية' : (b || '');
async function sChat(){ return chList('cuBody', 'student'); }
async function tChatList(){ return chList('cuMain', 'staff'); }

async function chList(hostId, mode){
  CH.hostId = hostId; CH.mode = mode; CH.key = null;
  const host = chHost(); if(!host) return; host.innerHTML = skel(3);
  try { CH.list = await api('chat2_threads'); } catch(e){ host.innerHTML = eb(e, 'c_back'); return; }
  chListRender();
  const o = owner(); clearInterval(o.chatTimer);
  o.chatTimer = setInterval(async () => { if(CH.key || !online() || document.visibilityState !== 'visible') return; try { CH.list = await api('chat2_threads'); chListRender(); } catch(e){} }, 15000);
}
function chOrdered(rows, order){
  const idx = new Map((order || []).map((k, i) => [k, i]));
  const saved = rows.filter(r => idx.has(r.key)).sort((a, b) => idx.get(a.key) - idx.get(b.key));
  const fresh = rows.filter(r => !idx.has(r.key));
  const pinned = fresh.filter(r => r.pinned), rest = fresh.filter(r => !r.pinned).sort((a, b) => String(b.last_at || '').localeCompare(String(a.last_at || '')));
  return [...pinned, ...saved, ...rest];
}
function chListRender(){
  const host = chHost(); if(!host || CH.key) return; const r = CH.list, rows = chOrdered(r.rows, r.order), staff = isStaffUser();
  const canGroup = staff && (role() !== 'employee' || can('messages'));
  const notif = ('Notification' in window && Notification.permission === 'default') ? '<button class="cu-btn amb sm" data-act="c_notif">🔔 تفعيل الإشعارات</button>' : '';
  let h = `<div class="cu-row wrap" style="margin-bottom:10px">${staff ? '<button class="cu-btn sm" data-act="c_new">＋ محادثة مع طالب</button>' : ''}${canGroup ? '<button class="cu-btn sm" data-act="c_group">👥 مجموعة لجميع الطلاب</button>' : ''}<button class="cu-btn sec sm" data-act="c_order">${CH.order ? '✔ تم' : '⇅ ترتيب المحادثات'}</button>${notif}</div>`;
  if(!rows.length) h += emptyBox('💬', 'لا توجد محادثات بعد', staff ? 'ابدأ محادثة مع طالب أو أنشئ مجموعة لجميع الطلاب.' : 'ستظهر هنا محادثة معلمك ومجموعات حلقتك.');
  h += rows.map(t => `<div class="cu-card" style="padding:11px;margin-bottom:8px;cursor:pointer" data-act="c_open" data-k="${E(t.key)}" data-n="${E(t.title)}"><div class="cu-row"><span style="font-size:23px">${t.kind === 'g' ? '👥' : (staff ? '👤' : '🧑‍🏫')}</span>
    <div class="cu-grow" style="min-width:0"><div class="cu-row" style="justify-content:space-between"><b style="font-size:14px">${t.pinned ? '📌 ' : ''}${E(t.title)}</b><span class="cu-mut" style="white-space:nowrap">${t.last_at ? fmtT(t.last_at) : ''}</span></div>
    <div class="cu-mut" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${E(kindPrev(t.last_kind, t.last_body)) || '—'}</div></div>
    ${t.unread ? `<i class="cu-reddot" style="position:static">${AD(t.unread)}</i>` : ''}
    ${CH.order ? `<div style="display:flex;flex-direction:column;gap:2px"><button class="cu-pill" style="padding:1px 8px" data-act="c_up" data-k="${E(t.key)}">▲</button><button class="cu-pill" style="padding:1px 8px" data-act="c_dn" data-k="${E(t.key)}">▼</button></div>` : ''}</div></div>`).join('');
  host.innerHTML = h;
}
async function chMove(key, dir){
  const keys = chOrdered(CH.list.rows, CH.list.order).map(r => r.key), i = keys.indexOf(key), j = i + dir;
  if(i < 0 || j < 0 || j >= keys.length) return;
  [keys[i], keys[j]] = [keys[j], keys[i]]; CH.list.order = keys; chListRender();
  try { await api('chat2_prefs_set', {p_order: keys}); } catch(e){ toast2('❌ ' + e.message); }
}

async function chOpen(key, title){
  CH.key = key; CH.title = title; CH.rows = []; CH.pend = []; CH.reply = null; CH.edit = null; CH.sig = ''; CH.order = false;
  const host = chHost(); if(!host) return;
  host.innerHTML = `<div class="cu-row" style="margin-bottom:8px"><button class="cu-btn sec sm" data-act="c_back">→</button><b class="cu-grow" style="font-size:14px">${E(title)}</b><button class="cu-btn sec sm" data-act="c_menu">⋯</button></div>
    <div class="cu-card" style="padding:10px"><div class="cu-chat" id="cuChatList">${skel(2)}</div><div id="cuChatBar"></div>
    <div id="cuComposer" class="cu-send" style="align-items:flex-end"><button class="cu-pill" data-act="c_attach" title="إرفاق">📎</button><button class="cu-pill" data-act="c_rec" title="تسجيل صوتي">🎤</button>
      <textarea class="cu-in" id="cuChatIn" rows="1" maxlength="1500" placeholder="اكتب رسالتك…" style="resize:none;max-height:90px"></textarea><button class="cu-btn" data-act="c_send" id="cuSendBtn">إرسال</button></div>
    <div class="cu-mut" id="cuChatNote" style="margin-top:6px"></div></div>
    <input type="file" id="cuFImg" accept="image/*" hidden><input type="file" id="cuFVid" accept="video/*" hidden><input type="file" id="cuFAud" accept="audio/*" hidden>`;
  const ta = $('cuChatIn'); ta.addEventListener('keydown', e => { if(e.key === 'Enter' && !e.shiftKey){ e.preventDefault(); chSend(); } });
  [['cuFImg', 'image'], ['cuFVid', 'video'], ['cuFAud', 'audio']].forEach(([id, k]) => $(id).addEventListener('change', e => { const f = e.target.files && e.target.files[0]; e.target.value = ''; if(f) chFile(f, k); }));
  await chPoll(true);
  const o = owner(); clearInterval(o.chatTimer);
  o.chatTimer = setInterval(() => { if(CH.key === key && online() && document.visibilityState === 'visible') chPoll(false); }, 6000);
  notifyTick(true);
}
async function chPoll(first){
  if(!CH.key) return;
  try {
    const r = await api('chat2_get', {p_key: CH.key, p_limit: 150});
    CH.canPost = !!r.can_post; CH.kind = r.kind; CH.staff = !!r.staff;
    const sig = JSON.stringify(r.rows.map(m => [m.id, m.edited_at, m.deleted, (m.body || '').length])) + (r._cached || '');
    if(!first && sig === CH.sig) return; CH.sig = sig; CH.rows = r.rows;
    const comp = $('cuComposer'), note = $('cuChatNote');
    if(comp) comp.style.display = CH.canPost ? '' : 'none';
    if(note) note.textContent = CH.canPost ? 'الصور والفيديو والصوت متاحة من 📎 و 🎤 — حتى ٢٥ ميجابايت للفيديو.' : '🔒 الكتابة في هذه المجموعة مغلقة من المعلم (للقراءة فقط).';
    chRender(first);
  } catch(e){ if(first){ const l = $('cuChatList'); if(l) l.innerHTML = eb(e, 'c_back'); } }
}
function chBubble(m){
  let body = '';
  if(m.deleted) body = '<i style="opacity:.75">🚫 تم حذف هذه الرسالة</i>';
  else {
    if(m.reply) body += `<div class="cu-quote" data-act="c_goto" data-id="${m.reply.id}"><b>${E(m.reply.sender_name || '')}</b><br>${m.reply.deleted ? '🚫 رسالة محذوفة' : E(kindPrev(m.reply.kind, m.reply.body))}</div>`;
    if(m.media_id && m.kind === 'image') body += `<div class="cu-media" data-mid="${m.media_id}" data-kind="image"><span class="cu-mut">⏳ جارٍ تحميل الصورة…</span></div>`;
    else if(m.media_id) body += `<div class="cu-media" data-mid="${m.media_id}" data-kind="${m.kind}"><button class="cu-pill" data-act="c_play" data-mid="${m.media_id}" data-kind="${m.kind}">${m.kind === 'video' ? '🎬 تشغيل الفيديو' : '🎤 رسالة صوتية ▶'}${m.media && m.media.size ? ' (' + AD(Math.max(1, Math.round(m.media.size / 1024))) + ' ك.ب)' : ''}</button></div>`;
    else if(m.kind !== 'text') body += '<i style="opacity:.75">⌛ انتهت صلاحية المرفق</i>';
    if(m.body) body += `<div>${E(m.body).replace(/\n/g, '<br>')}</div>`;
  }
  return `<div class="cu-bub ${m.mine ? 'me' : 'th'}" id="msg${m.id}">${m.mine ? '' : `<b style="font-size:10.5px">${E(m.sender_name || '')}</b><br>`}${body}<small>${fmtT(m.created_at)}${m.edited_at ? ' · معدّلة' : ''}${m.deleted ? '' : ` <a href="#" data-act="c_msg" data-id="${m.id}" style="color:inherit;font-weight:900;text-decoration:none"> ⋯ </a>`}</small></div>`;
}
function chRender(scroll){
  const l = $('cuChatList'); if(!l) return;
  const atBottom = l.scrollHeight - l.scrollTop - l.clientHeight < 80;
  l.innerHTML = (CH.rows.map(chBubble).join('') + CH.pend.map(p => `<div class="cu-bub me pend">${E(p.body || p.label || '')}<small>${p.failed ? `⏳ لم تُرسل — <a href="#" data-act="c_retry" data-id="${p.id}" style="color:#fff;text-decoration:underline">إعادة الإرسال</a>` : (p.label ? E(p.label) : '⏳ جارٍ الإرسال…')}</small></div>`).join('')) || emptyBox('💬', 'ابدأ المحادثة');
  if(scroll || atBottom) l.scrollTop = l.scrollHeight;
  l.querySelectorAll('.cu-media[data-kind="image"]:not([data-done])').forEach(el => chShowMedia(el, false));
  chBarRender();
}
async function chMedia(id, el){
  if(MEDIA.has(id)) return MEDIA.get(id);
  const first = await api('chat2_media_get', {p_id: id, p_idx: 0}); const parts = [first.data];
  for(let i = 1; i < first.chunks; i++){ parts.push((await api('chat2_media_get', {p_id: id, p_idx: i})).data); if(el) el.dataset.p = Math.round(100 * (i + 1) / first.chunks); }
  const bytes = parts.map(b64 => { const bin = atob(b64), u = new Uint8Array(bin.length); for(let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; });
  const url = URL.createObjectURL(new Blob(bytes, {type: first.mime || 'application/octet-stream'})); MEDIA.set(id, url); return url;
}
async function chShowMedia(el, play){
  el.dataset.done = '1'; const id = el.dataset.mid, k = el.dataset.kind;
  try {
    const url = await chMedia(id, el);
    el.innerHTML = k === 'image' ? `<img src="${url}" data-act="c_zoom" data-src="${url}" style="max-width:220px;max-height:260px;border-radius:12px;cursor:zoom-in">`
      : k === 'video' ? `<video controls playsinline src="${url}" style="max-width:240px;border-radius:12px" ${play ? 'autoplay' : ''}></video>` : `<audio controls src="${url}" ${play ? 'autoplay' : ''}></audio>`;
  } catch(e){ delete el.dataset.done; el.innerHTML = `<span class="cu-mut">⚠️ ${E(e.message)} — <a href="#" data-act="c_play" data-mid="${id}" data-kind="${k}">إعادة</a></span>`; }
}
function chBarRender(){
  const bar = $('cuChatBar'); if(!bar) return;
  if(CH.rec){ bar.innerHTML = `<div class="cu-warn" style="background:#fef2f2;border-color:#fecaca;color:#991b1b;display:flex;align-items:center;gap:8px"><span>🔴 جارٍ التسجيل <b id="cuRecT">٠٠:٠٠</b></span><span class="cu-grow"></span><button class="cu-btn red sm" data-act="c_recx">إلغاء</button><button class="cu-btn sm" data-act="c_recs">إرسال ➤</button></div>`; return; }
  const q = CH.edit ? ['✏️ تعديل الرسالة', CH.edit.body] : CH.reply ? ['↩ رد على ' + (CH.reply.sender_name || ''), kindPrev(CH.reply.kind, CH.reply.body)] : null;
  bar.innerHTML = q ? `<div class="cu-quote" style="display:flex;align-items:center;gap:8px;margin-top:6px"><div class="cu-grow"><b>${E(q[0])}</b><br>${E(String(q[1]).slice(0, 80))}</div><button class="cu-pill" data-act="c_cancel">✕</button></div>` : '';
  const b = $('cuSendBtn'); if(b) b.textContent = CH.edit ? 'حفظ' : 'إرسال';
}
async function chSend(retryId){
  if(!CH.key) return; const inp = $('cuChatIn');
  if(CH.edit){
    const v = (inp.value || '').trim(); if(!v) return; const id = CH.edit.id;
    try { await api('chat2_edit', {p_id: id, p_body: v}); CH.edit = null; inp.value = ''; CH.sig = ''; await chPoll(true); } catch(e){ toast2('❌ ' + e.message); }
    return;
  }
  let item;
  if(retryId){ item = CH.pend.find(p => p.id === retryId); if(!item) return; item.failed = false; }
  else { const v = (inp.value || '').trim(); if(!v) return; item = {id: UID(), body: v, reply: CH.reply ? CH.reply.id : null, failed: false}; CH.pend.push(item); inp.value = ''; CH.reply = null; }
  chRender(true);
  try {
    await api('chat2_send', {p_key: CH.key, p_kind: 'text', p_body: item.body, p_media: null, p_reply: item.reply, p_op: item.id});
    CH.pend = CH.pend.filter(p => p.id !== item.id); CH.sig = ''; await chPoll(true);
  } catch(e){ item.failed = true; chRender(true); toast2('❌ لم تُرسل الرسالة: ' + e.message); }
}
/* ── المرفقات: صور (تُضغط) وفيديو وصوت، رفع مجزّأ ── */
const blobToB64 = b => new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => { const s = String(fr.result); res(s.slice(s.indexOf(',') + 1)); }; fr.onerror = rej; fr.readAsDataURL(b); });
async function chCompress(file){
  if(!/^image\//.test(file.type) || file.type === 'image/gif' || typeof createImageBitmap !== 'function') return file;
  try {
    const bmp = await createImageBitmap(file), sc = Math.min(1, 1280 / Math.max(bmp.width, bmp.height));
    const c = document.createElement('canvas'); c.width = Math.round(bmp.width * sc); c.height = Math.round(bmp.height * sc); c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
    const b = await new Promise(r => c.toBlob(r, 'image/jpeg', 0.72)); return (b && b.size < file.size) ? b : file;
  } catch(e){ return file; }
}
async function chUpload(blob, kind, name, onp){
  const CHUNK = 450000, n = Math.max(1, Math.ceil(blob.size / CHUNK));
  const st = await api('chat2_media_start', {p_key: CH.key, p_kind: kind, p_mime: blob.type || '', p_name: name || '', p_size: blob.size, p_chunks: n});
  for(let i = 0; i < n; i++){ await api('chat2_media_chunk', {p_id: st.id, p_idx: i, p_data: await blobToB64(blob.slice(i * CHUNK, (i + 1) * CHUNK))}); if(onp) onp(Math.round(100 * (i + 1) / n)); }
  await api('chat2_media_finish', {p_id: st.id}); return st.id;
}
async function chSendBlob(blob, kind, name){
  if(!CH.key) return;
  if(!online()){ toast2('📴 إرسال الوسائط يحتاج اتصالاً بالإنترنت'); return; }
  const lim = {image: 6291456, audio: 12582912, video: 26214400}[kind];
  if(kind === 'image') blob = await chCompress(blob);
  if(blob.size > lim){ toast2('⚠️ الملف كبير (الحد ' + AD(Math.round(lim / 1048576)) + ' ميجابايت) — اختر ملفاً أصغر'); return; }
  const item = {id: UID(), label: '⏳ جارٍ رفع ' + (kind === 'image' ? 'الصورة' : kind === 'video' ? 'الفيديو' : 'الصوت') + '… ٠٪', body: ''}; CH.pend.push(item); chRender(true);
  const reply = CH.reply ? CH.reply.id : null; CH.reply = null;
  try {
    const mid = await chUpload(blob, kind, name, p => { item.label = '⏳ جارٍ الرفع… ' + AD(p) + '٪'; const l = $('cuChatList'); if(l) chRender(true); });
    await api('chat2_send', {p_key: CH.key, p_kind: kind, p_body: '', p_media: mid, p_reply: reply, p_op: item.id});
    CH.pend = CH.pend.filter(p => p.id !== item.id); CH.sig = ''; await chPoll(true);
  } catch(e){ CH.pend = CH.pend.filter(p => p.id !== item.id); chRender(true); toast2('❌ تعذّر إرسال المرفق: ' + e.message); }
}
function chFile(f, kind){ chSendBlob(f, kind, f.name); }
async function chRecStart(){
  if(CH.rec) return;
  if(!navigator.mediaDevices || !window.MediaRecorder){ toast2('هذا المتصفح لا يدعم التسجيل الصوتي المباشر — استخدم 📎 لإرسال ملف صوتي'); return; }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({audio: true});
    const mime = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg'].find(m => MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(m)) || '';
    const rec = new MediaRecorder(stream, mime ? {mimeType: mime} : undefined), chunks = [];
    rec.ondataavailable = e => { if(e.data && e.data.size) chunks.push(e.data); };
    CH.rec = {rec, stream, chunks, t0: Date.now(), mime: rec.mimeType || mime || 'audio/webm', timer: setInterval(() => { const s = Math.floor((Date.now() - CH.rec.t0) / 1000), el = $('cuRecT'); if(el) el.textContent = AD(String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0')); if(s >= 300) chRecStop(true); }, 500)};
    rec.start(1000); chBarRender();
  } catch(e){ toast2('تعذّر الوصول إلى الميكروفون — اسمح بالإذن من إعدادات المتصفح'); }
}
function chRecStop(send){
  const R = CH.rec; if(!R) return; clearInterval(R.timer); CH.rec = null;
  R.rec.onstop = async () => {
    R.stream.getTracks().forEach(t => t.stop());
    if(!send) return;
    const blob = new Blob(R.chunks, {type: R.mime});
    if(blob.size < 800){ toast2('التسجيل قصير جداً'); return; }
    await chSendBlob(blob, 'audio', 'voice.' + (/mp4/.test(R.mime) ? 'm4a' : 'webm'));
  };
  try { R.rec.stop(); } catch(e){}
  chBarRender();
}
/* ── قوائم الإجراءات: رسالة / محادثة / مجموعة ── */
function chMsgMenu(id){
  const m = CH.rows.find(x => String(x.id) === String(id)); if(!m) return;
  const mod = m.mine || CH.staff;
  const md = modal(`<h3>الرسالة</h3><div class="cu-col" style="display:flex;flex-direction:column;gap:8px">
    ${CH.canPost ? '<button class="cu-btn sec" data-act="c_reply" data-id="' + id + '">↩ رد</button>' : ''}${m.body ? '<button class="cu-btn sec" data-act="c_copy" data-id="' + id + '">📋 نسخ النص</button>' : ''}
    ${m.mine && m.kind === 'text' ? '<button class="cu-btn sec" data-act="c_edit" data-id="' + id + '">✏️ تعديل</button>' : ''}${mod ? '<button class="cu-btn red" data-act="c_del" data-id="' + id + '">🗑 حذف الرسالة</button>' : ''}
    <button class="cu-btn sec" onclick="this.closest('.cu-modal').remove()">إغلاق</button></div>`);
  bindClicks(md, CHH);
}
function chThreadMenu(){
  const t = CH.list && CH.list.rows.find(r => r.key === CH.key), isG = CH.key.startsWith('g:');
  const md = modal(`<h3>${E(CH.title)}</h3><div style="display:flex;flex-direction:column;gap:8px">
    <button class="cu-btn sec" data-act="c_clr">🧹 مسح المحادثة من عندي فقط</button>
    ${CH.staff ? '<button class="cu-btn red" data-act="c_clrall">🗑 حذف المحادثة نهائياً للجميع</button>' : ''}
    ${isG && CH.staff ? '<button class="cu-btn sec" data-act="c_gedit">✏️ تعديل المجموعة (الاسم / إغلاق الكتابة)</button><button class="cu-btn red" data-act="c_gdel">🗑 حذف المجموعة بالكامل</button>' : ''}
    <button class="cu-btn sec" onclick="this.closest('.cu-modal').remove()">إغلاق</button></div>`);
  bindClicks(md, CHH);
}
async function chGroupForm(g){
  const ro = (isStaffUser() && !g && role() !== 'teacher') ? await tRoster().catch(() => null) : null;
  const fields = [{k: 'name', label: 'اسم المجموعة', value: g ? g.title : 'مجموعة الحلقة', required: true}];
  if(ro) fields.push({k: 'h', label: 'الحلقة', type: 'select', value: '', options: [['', 'كل طلاب المركز'], ...ro.halaqat.map(h => [h.id, h.name])]});
  fields.push({k: 'a', label: 'هل يستطيع الطلاب الكتابة؟', type: 'select', value: g && g.allow_students === false ? '0' : '1', options: [['1', 'نعم، يكتبون ويردّون'], ['0', 'لا — للمعلم فقط (إعلانات)']]});
  const v = await formModal(g ? '✏️ تعديل المجموعة' : '👥 مجموعة لجميع الطلاب', fields, {ok: g ? 'حفظ' : 'إنشاء المجموعة', note: g ? '' : 'تظهر مثبّتة في أول قائمة المحادثات عند الطلاب.'}); if(!v) return;
  await api('chat2_group_save', {p_id: g ? g.group_id : null, p_name: v.name, p_halaqa: v.h || null, p_allow: v.a !== '0'});
  toast2('✅ تم حفظ المجموعة'); CH.key = null; chList(CH.hostId, CH.mode);
}
async function tChatNew(){
  const ro = await tRoster(); const list = ro.students || [];
  if(!list.length){ toast2('لا يوجد طلاب'); return; }
  const v = await formModal('محادثة جديدة', [{k: 's', label: 'الطالب', type: 'select', value: list[0].id, options: list.map(s => [s.id, s.name + (ro.halaqat.length > 1 ? ' — ' + hqName(s.halaqa_id) : '')])}], {ok: 'فتح المحادثة'});
  if(!v) return; const s = list.find(x => String(x.id) === v.s); chOpen('s:' + v.s, s ? s.name : '');
}
const CHH = {
  c_open: t => chOpen(t.dataset.k, t.dataset.n),
  c_back: () => { if(CH.key){ CH.key = null; chList(CH.hostId, CH.mode); } else if(CH.mode === 'student') sChat(); else tGo('chat'); },
  c_new: () => tChatNew(), c_group: () => chGroupForm(null),
  c_order: () => { CH.order = !CH.order; chListRender(); }, c_up: t => chMove(t.dataset.k, -1), c_dn: t => chMove(t.dataset.k, 1),
  c_notif: async () => { try { const p = await Notification.requestPermission(); toast2(p === 'granted' ? '🔔 تم تفعيل الإشعارات' : 'لم يُمنح إذن الإشعارات'); } catch(e){} chListRender(); },
  c_send: () => chSend(), c_retry: t => chSend(t.dataset.id), c_cancel: () => { CH.reply = null; CH.edit = null; const i = $('cuChatIn'); if(i) i.value = ''; chBarRender(); },
  c_attach: () => { const md = modal(`<h3>إرفاق</h3><div style="display:flex;flex-direction:column;gap:8px"><button class="cu-btn sec" data-act="c_pick" data-k="cuFImg">📷 صورة</button><button class="cu-btn sec" data-act="c_pick" data-k="cuFVid">🎬 فيديو</button><button class="cu-btn sec" data-act="c_pick" data-k="cuFAud">🎵 ملف صوتي</button><button class="cu-btn sec" onclick="this.closest('.cu-modal').remove()">إلغاء</button></div>`); bindClicks(md, CHH); },
  c_pick: t => { t.closest('.cu-modal').remove(); const f = $(t.dataset.k); if(f) f.click(); },
  c_rec: () => chRecStart(), c_recx: () => chRecStop(false), c_recs: () => chRecStop(true),
  c_play: t => { const el = t.closest('.cu-media'); if(el) chShowMedia(el, t.dataset.kind !== 'image'); },
  c_zoom: t => { modal(`<div style="text-align:center"><img src="${t.dataset.src}" style="max-width:100%;max-height:78vh;border-radius:12px"></div><button class="cu-btn sec full" style="margin-top:10px" onclick="this.closest('.cu-modal').remove()">إغلاق</button>`); },
  c_goto: t => { const el = $('msg' + t.dataset.id); if(el){ el.scrollIntoView({block: 'center'}); el.style.outline = '2px solid var(--g2)'; setTimeout(() => el.style.outline = '', 1400); } },
  c_msg: t => chMsgMenu(t.dataset.id),
  c_reply: t => { const m = CH.rows.find(x => String(x.id) === t.dataset.id); t.closest('.cu-modal').remove(); if(m){ CH.reply = m; CH.edit = null; chBarRender(); const i = $('cuChatIn'); if(i) i.focus(); } },
  c_copy: t => { const m = CH.rows.find(x => String(x.id) === t.dataset.id); t.closest('.cu-modal').remove(); if(m && typeof clip === 'function') clip(m.body, '✅ تم النسخ'); },
  c_edit: t => { const m = CH.rows.find(x => String(x.id) === t.dataset.id); t.closest('.cu-modal').remove(); if(m){ CH.edit = m; CH.reply = null; const i = $('cuChatIn'); if(i){ i.value = m.body; i.focus(); } chBarRender(); } },
  c_del: async t => { const id = t.dataset.id; t.closest('.cu-modal').remove(); if(!(await ask('حذف هذه الرسالة للجميع؟', {danger: true, ok: 'حذف'}))) return; await api('chat2_delete', {p_id: Number(id)}); CH.sig = ''; await chPoll(true); },
  c_menu: () => chThreadMenu(),
  c_clr: async t => { t.closest('.cu-modal').remove(); if(!(await ask('مسح المحادثة من عندك فقط؟ ستبقى عند الطرف الآخر.', {ok: 'مسح'}))) return; await api('chat2_clear', {p_key: CH.key, p_everyone: false}); CH.sig = ''; await chPoll(true); },
  c_clrall: async t => { t.closest('.cu-modal').remove(); if(!(await ask('حذف المحادثة نهائياً للجميع (مع كل الوسائط)؟ لا يمكن التراجع.', {danger: true, ok: 'حذف نهائي'}))) return; await api('chat2_clear', {p_key: CH.key, p_everyone: true}); toast2('🗑 تم حذف المحادثة'); CH.key = null; chList(CH.hostId, CH.mode); },
  c_gedit: t => { t.closest('.cu-modal').remove(); const g = CH.list.rows.find(r => r.key === CH.key); chGroupForm(g || null); },
  c_gdel: async t => { t.closest('.cu-modal').remove(); if(!(await ask('حذف المجموعة بكل رسائلها ووسائطها؟', {danger: true, ok: 'حذف المجموعة'}))) return; await api('chat2_group_delete', {p_id: CH.key.slice(2)}); toast2('🗑 تم حذف المجموعة'); CH.key = null; chList(CH.hostId, CH.mode); }
};
Object.assign(SH, CHH); Object.assign(TH, CHH);

/* ── الإشعارات: نقطة حمراء + تنبيه داخل التطبيق + إشعار الجهاز + شارة أيقونة التطبيق ── */
const NT = {last: 0};
function setDot(el, n){
  if(!el) return; let d = [...el.children].find(c => c.classList && c.classList.contains('cu-reddot'));
  if(!n){ if(d) d.remove(); return; }
  if(!d){ if(getComputedStyle(el).position === 'static') el.style.position = 'relative'; d = document.createElement('i'); d.className = 'cu-reddot'; el.appendChild(d); }
  d.textContent = n > 99 ? '99+' : AD(n);
}
function applyDots(n){
  setDot($('nt-comp'), n); setDot($('hqCompBtn'), n); setDot(document.querySelector('.sp-tab[data-tab="badges"]'), n);
  if(T.el) setDot(T.el.querySelector('#cuTabs [data-t="chat"]'), n);
  const u = $('cuUnread'); if(u){ u.style.display = n && !(S.seg === 'chat' && CH.key) ? 'flex' : 'none'; u.textContent = AD(n); }
}
async function notifyTick(force){
  if(typeof _currentUser === 'undefined' || !_currentUser || !online() || !_authToken || (_currentUser.role === 'masool')) return;
  let r; try { r = await _rpcT('chat2_unread', {}, true); } catch(e){ return; }
  if(!r || r.ok === false) return;
  const n = r.unread || 0; applyDots(n);
  if(n > NT.last && !force){
    const who = (r.senders || []).slice(0, 2).join('، ');
    const viewing = CH.key && ((T.el && T.tab === 'chat') || (S.host && S.host.isConnected && S.seg === 'chat'));
    if(!viewing) toast2('💬 رسالة جديدة' + (who ? ' من ' + who : ''));
    if(document.hidden && 'Notification' in window && Notification.permission === 'granted'){
      try { const reg = navigator.serviceWorker && await navigator.serviceWorker.getRegistration(); const o = {body: 'لديك ' + AD(n) + ' رسالة غير مقروءة' + (who ? ' — ' + who : ''), tag: 'ridwan-chat', icon: './icon-192.png', vibrate: [120, 60, 120]};
        if(reg && reg.showNotification) reg.showNotification('نظام مركز الكتاب', o); else new Notification('نظام مركز الكتاب', o); } catch(e){}
    }
  }
  NT.last = n;
  try { if(navigator.setAppBadge){ if(n) navigator.setAppBadge(n); else navigator.clearAppBadge(); } } catch(e){}
}
CU.notify = notifyTick;
setInterval(() => { if(document.visibilityState === 'visible') notifyTick(); }, 60000);
document.addEventListener('visibilitychange', () => { if(document.visibilityState === 'visible') setTimeout(notifyTick, 800); });
window.addEventListener('online', () => setTimeout(notifyTick, 1500));
setTimeout(notifyTick, 5000);

/* ═════════ التقارير ═════════ */
const tblHtml = (head, rows) => `<div class="cu-scroll"><table class="cu-tbl"><tr>${head.map((h, i) => `<th${i === 1 ? ' class="nm"' : ''}>${E(h)}</th>`).join('')}</tr>${rows.map(r => `<tr>${r.map((c, i) => `<td${i === 1 ? ' class="nm"' : ''}>${E(c)}</td>`).join('')}</tr>`).join('')}</table></div>`;
async function tRep(){ T.rep = await api('comp_report', {p_comp: T.cid}); if(!T.repSid && T.rep.students[0]) T.repSid = T.rep.students[0].student_id; T.repStu = null; tRepRender(); }
function repData(mode){
  const r = T.rep, c = r.competition, wt = c.weeks_total, S0 = r.students;
  if(mode === 'all'){
    const head = ['#', 'الطالب', 'المستوى', 'المجموع', ...r.categories.map(x => x.name), ...Array.from({length: wt}, (_, i) => 'أ' + (i + 1))];
    return {title: 'تقرير جميع الطلاب', head, rows: S0.map(s => [s.rank, s.name, s.level || '', Number(s.total), ...r.categories.map(x => Number((s.by_category || {})[x.id] || 0)), ...Array.from({length: wt}, (_, i) => Number((s.by_week || {})[i + 1] || 0))])};
  }
  if(mode === 'week'){
    const w = T.repWeek || 1; const list = S0.map(s => ({n: s.name, l: s.level || '', p: Number((s.by_week || {})[w] || 0)})).sort((a, b) => b.p - a.p);
    return {title: 'نتائج الأسبوع ' + w, head: ['#', 'الطالب', 'المستوى', 'نقاط الأسبوع'], rows: list.map((x, i) => [i + 1, x.n, x.l, x.p])};
  }
  if(mode === 'top'){
    const rows = []; r.leaders.forEach(l => (l.top || []).forEach((t, i) => rows.push([l.category, i + 1, t.name, Number(t.points)])));
    return {title: 'المتميزون في كل مجال', head: ['المجال', 'المركز', 'الطالب', 'النقاط'], rows, improved: r.improved};
  }
  return null;
}
function repStudentHtml(d){
  return `<h2>${E(d.name || '')}</h2><div class="cu-mut">المجموع: ${NF(d.total)} · الترتيب: ${d.rank ? AD(d.rank) : '—'} من ${AD(d.participants)} · المستوى: ${E(d.level || '')}</div>
    <h3>نقاط المجالات</h3>${tblHtml(['المجال', 'المجموع', 'الممكن حتى الآن'], (d.categories || []).map(g => [g.name, NF(g.total), NF(g.possible)]))}
    <h3>الأسابيع</h3>${tblHtml(['الأسبوع', 'من', 'إلى', 'النقاط', 'الحد'], (d.weeks || []).map(w => [AD(w.week), fmtD(w.start), fmtD(w.end), NF(w.points), NF(w.max)]))}
    <h3>العمليات</h3>${tblHtml(['التاريخ', 'المجال', 'النقاط', 'السبب'], (d.entries || []).filter(e => !e.voided).map(e => [fmtD(e.date), e.category, SG(e.points), e.reason || '']))}`;
}
async function tRepRender(){
  const main = $('cuMain'); if(!main || T.tab !== 'rep' || !T.rep) return; const r = T.rep, c = r.competition, m = T.repMode;
  const modes = [['all', '👥 كل الطلاب'], ['student', '👤 طالب محدد'], ['week', '📅 أسبوع'], ['top', '🌟 المتميزون']];
  let h = `<div class="cu-chips" style="margin:0 0 10px">${modes.map(x => `<button class="cu-pill ${m === x[0] ? 'on' : ''}" data-act="r_mode" data-m="${x[0]}">${x[1]}</button>`).join('')}</div>`;
  if(!r.students.length){ main.innerHTML = h + emptyBox('📈', 'لا توجد بيانات للتقرير'); return; }
  if(m === 'student'){
    h += `<select class="cu-sel" id="rSel" style="margin-bottom:10px">${r.students.map(s => `<option value="${E(s.student_id)}" ${s.student_id === T.repSid ? 'selected' : ''}>${E(s.name)}</option>`).join('')}</select><div id="rBody">${skel(2)}</div>`;
    main.innerHTML = h;
    try { if(!T.repStu || T.repStu.student_id !== T.repSid) T.repStu = await api('comp_student_detail', {p_comp: T.cid, p_student: T.repSid});
      $('rBody').innerHTML = `<div class="cu-row wrap" style="margin-bottom:10px"><button class="cu-btn sm" data-act="r_print">🖨 طباعة / PDF</button><button class="cu-btn sec sm" data-act="r_csv">📤 تصدير Excel</button></div><div class="cu-card">${repStudentHtml(T.repStu)}</div>`;
    } catch(e){ $('rBody').innerHTML = errBox(e.message); }
    return;
  }
  const d = repData(m);
  if(m === 'week') h += `<select class="cu-sel" id="rWeek" style="margin-bottom:10px">${Array.from({length: c.weeks_total}, (_, i) => `<option value="${i + 1}" ${T.repWeek === i + 1 ? 'selected' : ''}>الأسبوع ${AD(i + 1)}</option>`).join('')}</select>`;
  h += `<div class="cu-row wrap" style="margin-bottom:10px"><button class="cu-btn sm" data-act="r_print">🖨 طباعة / PDF</button><button class="cu-btn sec sm" data-act="r_csv">📤 تصدير Excel</button></div><div class="cu-card"><div class="cu-h">${E(d.title)}</div>${tblHtml(d.head, d.rows.map(row => row.map(x => typeof x === 'number' ? NF(x) : x)))}</div>`;
  if(m === 'week'){ const w = (r.weeks || []).find(x => x.week === T.repWeek); h += `<div class="cu-mut">${w ? 'إجمالي نقاط الأسبوع: ' + NF(w.total) + ' · متوسط الطالب: ' + NF(w.average) : 'لا توجد نقاط في هذا الأسبوع.'}</div>`; }
  if(m === 'top'){
    h += `<div class="cu-card"><div class="cu-h">📈 الأكثر تطوراً (الأسبوع الأخير مقابل السابق)</div>${(d.improved || []).length ? d.improved.map((x, i) => `<div class="cu-ent"><span>${AD(i + 1)}. ${E(x.name)}</span><b class="cu-delta up">+${NF(x.improvement)}</b></div>`).join('') : '<div class="cu-mut">يظهر بعد اكتمال تقييم أسبوعين على الأقل.</div>'}</div>`;
  }
  main.innerHTML = h;
}
function repPrintHtml(){
  const c = T.rep.competition, head = `<h2>🏆 ${E(c.name)}</h2><div>${fmtD(c.start_date)} ← ${fmtD(c.end_date)} · طُبع ${fmtT(new Date())}</div>`;
  if(T.repMode === 'student') return head + (T.repStu ? repStudentHtml(T.repStu) : '');
  const d = repData(T.repMode); return head + `<h3>${E(d.title)}</h3>` + tblHtml(d.head, d.rows.map(row => row.map(x => typeof x === 'number' ? NF(x) : x)))
    + (T.repMode === 'top' && (d.improved || []).length ? '<h3>الأكثر تطوراً</h3>' + tblHtml(['الطالب', 'الأسبوع الأخير', 'السابق', 'التحسن'], d.improved.map(x => [x.name, NF(x.last_week), NF(x.prev_week), '+' + NF(x.improvement)])) : '');
}
function repPrint(){ printHtml(repPrintHtml()); }
async function repStudentPrint(sid){
  try { const d = await api('comp_student_detail', {p_comp: T.cid, p_student: sid}); const c = T.comp.competition;
    printHtml(`<h2>🏆 ${E(c.name)}</h2><div>${fmtD(c.start_date)} ← ${fmtD(c.end_date)} · طُبع ${fmtT(new Date())}</div>` + repStudentHtml(d)); }
  catch(e){ toast2('❌ ' + e.message); }
}
function repCsv(){
  const c = T.rep.competition, nm = 'فرسان-القرآن-' + c.name.replace(/[^\p{L}\p{N}]+/gu, '-');
  if(T.repMode === 'student'){ const d = T.repStu; if(!d) return;
    csvDownload(nm + '-' + (d.name || 'طالب') + '.csv', [['المجال', 'المجموع', 'الممكن'], ...(d.categories || []).map(g => [g.name, g.total, g.possible]), [], ['التاريخ', 'المجال', 'النقاط', 'السبب'], ...(d.entries || []).filter(e => !e.voided).map(e => [String(e.date).slice(0, 10), e.category, e.points, e.reason || ''])]); return; }
  const d = repData(T.repMode); csvDownload(nm + '-' + T.repMode + '.csv', [d.head, ...d.rows]);
}

})();
