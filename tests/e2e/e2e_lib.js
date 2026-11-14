const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { JSDOM, VirtualConsole } = require('jsdom');
const pool = new Pool({ host: '127.0.0.1', user: 'postgres', password: 'pw', database: process.env.E2E_DB || 't3', max: 5 });
const pgLog = [];
async function pgQuery(sql, params){
  const c = await pool.connect();
  try { await c.query('begin'); await c.query('set local role anon'); const r = await c.query(sql, params); await c.query('commit'); return r; }
  catch(e){ try{ await c.query('rollback'); }catch(_){} pgLog.push(e.message + '  <<' + sql.slice(0, 80) + '>>'); throw e; }
  finally { c.release(); }
}
async function admin(sql, params){ const c = await pool.connect(); try { return await c.query(sql, params); } finally { c.release(); } }
const sleep = ms => new Promise(r => setTimeout(r, ms));
const HTML = process.env.APP_HTML || path.join(__dirname, '..', '..', 'app', 'index.html');
const FAKE = fs.readFileSync(path.join(__dirname, 'fake_supabase.js'), 'utf8');
async function openApp(storage){
  let html = fs.readFileSync(HTML, 'utf8').replace(/<script src="https:\/\/[^"]+"><\/script>/g, '');
  html = html.replace('<head>', () => '<head><script>' + FAKE.replace(/<\/script>/g, '<\\/script>') + '</script>');
  const vc = new VirtualConsole(); const jerr = [];
  vc.on('jsdomError', e => { const m = String((e.detail && e.detail.message) || e.message); if(!/Not implemented|canvas/i.test(m)) jerr.push(m); });
  const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://ke3haker-eng.github.io/markaz-alkitab/app/', virtualConsole: vc,
    beforeParse(w){
      w.__pg = (sql, params) => pgQuery(sql, params).then(r => ({ rows: r.rows }), e => ({ error: { message: e.message, code: e.code } }));
      if(storage) Object.keys(storage).forEach(k => w.localStorage.setItem(k, storage[k]));
    } });
  await sleep(900);
  dom.jerr = jerr;
  return dom;
}
function dumpStorage(w){ const o = {}; for(let i = 0; i < w.localStorage.length; i++){ const k = w.localStorage.key(i); o[k] = w.localStorage.getItem(k); } return o; }
let pass = 0, fail = 0;
function ok(cond, msg){ if(cond){ pass++; console.log('  ✓', msg); } else { fail++; console.log('  ✗ FAIL:', msg); } }
function summary(){ console.log(`\n== ${pass} passed, ${fail} failed ==`); return fail; }
module.exports = { pool, pgLog, pgQuery, admin, sleep, openApp, dumpStorage, ok, summary };
