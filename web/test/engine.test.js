// 문제 엔진 검사: node web/test/engine.test.js [확장모듈.js ...] [--only=t1,t2] [--n=20000]
// app.html 의 "==== ENGINE START/END ====" 구간을 잘라 실행하고, 모든 유형에 공통 규칙을 검사한다.
// 확장 모듈을 주면 /* @@EXTENSIONS@@ */ 자리에 끼워 넣어 함께 검사한다.
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = (k, d) => { const a = args.find(x => x.startsWith(`--${k}=`)); return a ? a.split('=')[1] : d; };
const modules = args.filter(a => !a.startsWith('--'));
const N = Number(opt('n', 20000));
const only = opt('only', '') ? opt('only', '').split(',') : null;

function loadEngine(extraFiles = []) {
  const html = fs.readFileSync(path.join(__dirname, '..', 'app.html'), 'utf8');
  const a = html.indexOf('// ==== ENGINE START ===='), b = html.indexOf('// ==== ENGINE END ====');
  if (a < 0 || b < 0) throw new Error('ENGINE 구간을 찾을 수 없음');
  let src = html.slice(a, b);
  const ext = extraFiles.map(f => fs.readFileSync(f, 'utf8')).join('\n');
  src = src.replace('/* @@EXTENSIONS@@ */', () => ext);
  const api = 'multSplitTips,chunkTerms,pctAB,pickA,delta,up,rnd,pick,coin,inR,gcd,fmt,sg,signed,tip,batchim,eun,ga,eul,wa,TYPES,typeList,pid,parse,knownId,answer,unit,answerText,prompt,label,hint,sectionOf,choices,accepts,calcTitle,finalToken,genType,genSection,multGrid,multTips,FRACTIONS,chunkLines,hintHTML';
  return new Function(`${src}\nreturn {${api}};`)();
}

function checkType(E, t, n) {
  const errors = [];
  const fail = (msg, p) => { if (errors.length < 8) errors.push(`${msg} :: ${p ? JSON.stringify(p) : ''}`); };
  const T = E.TYPES[t];
  for (const k of ['section', 'title', 'answer', 'prompt', 'label', 'hint']) if (!T[k]) fail(`TYPES.${t}.${k} 없음`);
  if (t !== 'm' && !T.ex) fail(`TYPES.${t}.ex 없음`);
  if (!['mult', 'div', 'pct'].includes(T.section)) fail(`잘못된 section ${T.section}`);
  const ids = new Set();
  let longest = '', longestSub = '';
  for (let i = 0; i < n; i++) {
    let p;
    try { p = t === 'm' ? { t: 'm', a: E.rnd(11, 999), b: E.rnd(2, 99) } : E.genType(t); } catch (e) { fail('gen 예외 ' + e.message); continue; }
    if (p.t !== t) { fail('p.t 불일치', p); continue; }
    const id = E.pid(p);
    ids.add(id);
    const back = E.parse(id);
    if (E.pid(back) !== id) fail('pid/parse 왕복 실패', p);
    for (const k of Object.keys(p)) if (typeof p[k] === 'number' && back[k] !== p[k]) fail(`parse 후 ${k} 달라짐`, p);
    for (const k of Object.keys(p)) if (k !== 't' && !Number.isInteger(p[k])) fail(`필드 ${k}가 정수가 아님`, p);
    if (id.includes('undefined') || id.includes('NaN')) fail('id에 undefined/NaN', p);
    let ans;
    try { ans = E.answer(p); } catch (e) { fail('answer 예외 ' + e.message, p); continue; }
    if (!Number.isInteger(ans) || ans < 1 || ans > 99999) fail(`정답이 1~99999 정수가 아님: ${ans}`, p);
    const ch = E.choices(p);
    if (ch && !(ans >= 1 && ans <= ch.length)) fail('고르기 문제 정답 번호가 범위 밖', p);
    if (!E.accepts(p, ans)) fail('정답을 정답으로 인정하지 않음', p);
    let texts;
    try {
      const pr = E.prompt(p);
      if (!pr.main) fail('prompt.main 비어 있음', p);
      if (pr.main.length > longest.length) longest = pr.main;
      if ((pr.sub || '').length > longestSub.length) longestSub = pr.sub;
      texts = [pr.main, pr.sub || '', E.label(p), E.answerText(p), E.calcTitle(p), E.hintHTML(p), ...(ch || [])];
    } catch (e) { fail('문구/풀이 예외 ' + e.message, p); continue; }
    for (const s of texts) if (/undefined|NaN|Infinity|\[object|null/.test(s)) { fail(`문구에 이상한 값: ${s.slice(0, 120)}`, p); break; }
    const h = E.hint(p);
    const token = E.finalToken(p);
    if (h.steps && h.steps.length) {
      const last = h.steps[h.steps.length - 1][1];
      if (!String(last).includes(token)) fail(`마지막 풀이 줄에 "${token}" 없음: ${last}`, p);
    } else if (h.grid) {
      const res = h.grid.rows.find(r => r.res);
      if (!res || Number(res.s) !== ans) fail('세로셈 결과 줄이 정답과 다름', p);
    } else fail('풀이(steps/grid) 없음', p);
    for (const tp of h.tips || []) if (!tp.title || !Array.isArray(tp.lines) || !tp.lines.length) fail('팁 형식 오류', p);
  }
  return { t, errors, distinct: ids.size, longest, longestSub };
}

function run() {
  const E = loadEngine(modules);
  const types = Object.keys(E.TYPES).filter(t => !only || only.includes(t));
  let bad = 0;
  for (const t of types) {
    const r = checkType(E, t, N);
    const ok = r.errors.length === 0;
    if (!ok) bad++;
    console.log(`${ok ? 'OK  ' : 'FAIL'} ${t.padEnd(8)} 서로 다른 문제 ${r.distinct}/${N}  가장 긴 문제 "${r.longest}" (${r.longest.length}자)  설명 "${r.longestSub}"`);
    for (const e of r.errors) console.log('     - ' + e);
  }
  for (const sec of ['mult', 'div', 'pct']) {
    const list = E.typeList(sec);
    if (list.length) for (let i = 0; i < 2000; i++) { const p = E.genSection(sec, 'mix'); if (E.sectionOf(p) !== sec) { console.log(`FAIL mix ${sec}: ${p.t}`); bad++; break; } }
  }
  console.log(bad ? `\n${bad}개 유형 실패` : `\n모든 유형 통과 (${types.length}개)`);
  process.exit(bad ? 1 : 0);
}

if (require.main === module) run();
module.exports = { loadEngine, checkType };
