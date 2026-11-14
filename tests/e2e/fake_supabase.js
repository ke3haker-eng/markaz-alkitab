(function(){
  const q = id => '"' + String(id).replace(/"/g, '""') + '"';
  function val(v, params){ 
    if(v !== null && typeof v === 'object'){ params.push(JSON.stringify(v)); return '$' + params.length + '::jsonb'; }
    params.push(v); return '$' + params.length;
  }
  function Q(table){
    const st = {op:'select', cols:'*', f:[], order:null, lim:null, payload:null, conflict:'id', ret:false, single:false, maybe:false};
    const self = {
      select(cols){ if(st.op === 'select'){ st.cols = cols || '*'; } else { st.ret = true; } return self; },
      insert(p){ st.op = 'insert'; st.payload = p; return self; },
      upsert(p, o){ st.op = 'upsert'; st.payload = p; st.conflict = (o && o.onConflict) || 'id'; return self; },
      update(p){ st.op = 'update'; st.payload = p; return self; },
      delete(){ st.op = 'delete'; return self; },
      eq(c, v){ st.f.push([c, '=', v]); return self; },
      neq(c, v){ st.f.push([c, '<>', v]); return self; },
      in(c, a){ st.f.push([c, 'in', a]); return self; },
      is(c, v){ st.f.push([c, 'is', v]); return self; },
      ilike(c, v){ st.f.push([c, 'ilike', v]); return self; },
      order(c, o){ st.order = [c, (o && o.ascending === false) ? 'desc' : 'asc']; return self; },
      limit(n){ st.lim = n; return self; },
      range(){ return self; },
      single(){ st.single = true; return self; },
      maybeSingle(){ st.maybe = true; return self; },
      then(res, rej){ return run().then(res, rej); }
    };
    async function run(){
      const params = []; let sql;
      const where = () => st.f.length ? ' where ' + st.f.map(([c, o, v]) => {
        if(o === 'in'){ if(!v.length) return 'false'; return q(c) + '::text = any($' + (params.push(v.map(String))) + '::text[])'; }
        if(o === 'is'){ return q(c) + ' is ' + (v === null ? 'null' : v); }
        params.push(v); return q(c) + ' ' + o + ' $' + params.length;
      }).join(' and ') : '';
      try {
        if(st.op === 'select'){
          const cols = st.cols === '*' ? '*' : st.cols.split(',').map(s => q(s.trim())).join(',');
          sql = 'select ' + cols + ' from public.' + q(table) + where() + (st.order ? ' order by ' + q(st.order[0]) + ' ' + st.order[1] : '') + (st.lim ? ' limit ' + st.lim : '');
        } else if(st.op === 'insert' || st.op === 'upsert'){
          const rows = Array.isArray(st.payload) ? st.payload : [st.payload];
          if(!rows.length) return {data: [], error: null};
          const keys = [...new Set(rows.flatMap(r => Object.keys(r)))];
          const vals = rows.map(r => '(' + keys.map(k => r[k] === undefined ? 'default' : val(r[k], params)).join(',') + ')').join(',');
          sql = 'insert into public.' + q(table) + ' (' + keys.map(q).join(',') + ') values ' + vals;
          if(st.op === 'upsert') sql += ' on conflict (' + st.conflict.split(',').map(q).join(',') + ') do update set ' + keys.filter(k => !st.conflict.split(',').includes(k)).map(k => q(k) + '=excluded.' + q(k)).join(',');
          sql += ' returning *';
        } else if(st.op === 'update'){
          const keys = Object.keys(st.payload);
          sql = 'update public.' + q(table) + ' set ' + keys.map(k => q(k) + '=' + val(st.payload[k], params)).join(',') + where() + ' returning *';
        } else if(st.op === 'delete'){
          sql = 'delete from public.' + q(table) + where() + ' returning *';
        }
        const r = await window.__pg(sql, params);
        if(r.error) return {data: null, error: r.error};
        let data = r.rows;
        if(st.single){ if(data.length !== 1) return {data: null, error: {message: 'JSON object requested, multiple (or no) rows returned', code: 'PGRST116'}}; data = data[0]; }
        else if(st.maybe){ data = data[0] || null; }
        else if((st.op !== 'select') && !st.ret) data = null;
        return {data, error: null};
      } catch(e){ return {data: null, error: {message: String(e.message || e)}}; }
    }
    return self;
  }
  window.supabase = { createClient(){
    return {
      from: Q,
      async rpc(name, args){
        const keys = Object.keys(args || {});
        const params = keys.map(k => { const v = args[k]; return (v !== null && typeof v === 'object' && !Array.isArray(v)) ? JSON.stringify(v) : v; });
        const sql = 'select public.' + name + '(' + keys.map((k, i) => k + ' => $' + (i + 1)).join(',') + ') as r';
        const r = await window.__pg(sql, params);
        if(r.error) return {data: null, error: r.error};
        return {data: r.rows[0].r, error: null};
      },
      channel(){ const c = {on(){ return c; }, subscribe(){ return c; }}; return c; },
      removeChannel(){},
      auth: {}
    };
  }};
  window.JSZip = function(){}; window.Chart = function(){ return {destroy(){}, update(){}}; };
  window.alert = () => {}; window.confirm = () => true; window.prompt = () => '';
  window.matchMedia = window.matchMedia || (() => ({matches: false, addListener(){}, removeListener(){}, addEventListener(){}, removeEventListener(){}}));
  window.scrollTo = () => {}; Element.prototype.scrollIntoView = function(){};
  window.__errors = [];
  window.addEventListener('error', e => window.__errors.push('ERR: ' + e.message));
  window.addEventListener('unhandledrejection', e => window.__errors.push('REJ: ' + ((e.reason && e.reason.message) || e.reason)));
})();
