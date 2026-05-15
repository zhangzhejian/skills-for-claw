#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: qipan.sh --year Y --month M --day D --hour H --gender male|female [options]

Options:
  --repo PATH        ziwei-doushu repo path. Defaults to cwd or /Users/zhejianzhang/PrivateProject/ziwei-doushu
  --out DIR          output directory. Defaults to ./ziwei-chart-output
  --name NAME        optional name
  --city CITY        optional city
  --longitude NUM    optional longitude

Outputs:
  chart.json
  chart.html
EOF
}

REPO=""
OUT=""
NAME=""
YEAR=""
MONTH=""
DAY=""
HOUR=""
GENDER=""
CITY=""
LONGITUDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --year) YEAR="$2"; shift 2 ;;
    --month) MONTH="$2"; shift 2 ;;
    --day) DAY="$2"; shift 2 ;;
    --hour) HOUR="$2"; shift 2 ;;
    --gender) GENDER="$2"; shift 2 ;;
    --city) CITY="$2"; shift 2 ;;
    --longitude) LONGITUDE="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$REPO" ]; then
  if [ -f "$PWD/lib/ziwei/algorithm.ts" ]; then
    REPO="$PWD"
  else
    REPO="/Users/zhejianzhang/PrivateProject/ziwei-doushu"
  fi
fi
if [ -z "$OUT" ]; then OUT="$PWD/ziwei-chart-output"; fi

for v in YEAR MONTH DAY HOUR GENDER; do
  if [ -z "${!v}" ]; then echo "Missing required --${v,,}" >&2; usage; exit 2; fi
done
if [ "$GENDER" != "male" ] && [ "$GENDER" != "female" ]; then
  echo "--gender must be male or female" >&2
  exit 2
fi
if [ ! -f "$REPO/lib/ziwei/algorithm.ts" ]; then
  echo "Cannot find ziwei-doushu repo at $REPO" >&2
  exit 1
fi

mkdir -p "$OUT"
RUNNER="$(mktemp -t ziwei-qipan-runner.XXXXXX.ts)"
trap 'rm -f "$RUNNER"' EXIT

cat > "$RUNNER" <<'TS'
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const env = process.env;
const repo = env.REPO!;
const out = env.OUT!;

const branches = ['子','丑','寅','卯','辰','巳','午','未','申','酉','戌','亥'];
const stems = ['甲','乙','丙','丁','戊','己','庚','辛','壬','癸'];
const order = [5,6,7,8,4,null,null,9,3,null,null,10,2,1,0,11];
function esc(s: any) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
}
function palaceCell(branch: number | null, chart: any, palaceByBranch: Record<string, any>) {
  if (branch === null) return `<section class="center" data-center="1">
    <div class="seal">紫微斗数</div>
    <div>命宫 ${branches[chart.mingGongBranch]}</div>
    <div>身宫 ${branches[chart.shenGongBranch]}</div>
    <div>${esc(chart.wuxingJuName)}</div>
  </section>`;
  const p = palaceByBranch[branch];
  const major = p.stars.filter((s: any) => s.type === 'major');
  const others = p.stars.filter((s: any) => s.type !== 'major').slice(0, 8);
  return `<button class="palace ${p.isMingGong ? 'ming' : ''} ${p.isShenGong ? 'shen' : ''}" data-branch="${p.branch}">
    <span class="meta">${stems[p.stem]}${branches[p.branch]} ${p.daXianAge ? `${p.daXianAge[0]}-${p.daXianAge[1]}` : ''}</span>
    <strong>${esc(p.name)}${p.isMingGong ? ' · 命' : ''}${p.isShenGong ? ' · 身' : ''}</strong>
    <span class="majors">${major.length ? major.map((s: any) => `${esc(s.name)}${s.siHua ? '化' + esc(s.siHua) : ''}`).join(' / ') : '空宫'}</span>
    <span class="others">${others.map((s: any) => esc(s.name)).join(' ')}</span>
  </button>`;
}

async function main() {
  const birthInfo: any = {
    year: Number(env.YEAR),
    month: Number(env.MONTH),
    day: Number(env.DAY),
    hour: Number(env.HOUR),
    gender: env.GENDER,
  };
  if (env.NAME) birthInfo.name = env.NAME;
  if (env.CITY) birthInfo.city = env.CITY;
  if (env.LONGITUDE) birthInfo.longitude = Number(env.LONGITUDE);

  const algorithm = await import(pathToFileURL(path.join(repo, 'lib/ziwei/algorithm.ts')).href);
  let patternsMod: any = null;
  try {
    patternsMod = await import(pathToFileURL(path.join(repo, 'lib/ziwei/patterns.ts')).href);
  } catch {}

  const chart = algorithm.generateChart(birthInfo);
  const patterns = patternsMod?.detectPatterns ? patternsMod.detectPatterns(chart) : [];
  const payload = { chart, patterns };
  fs.writeFileSync(path.join(out, 'chart.json'), JSON.stringify(payload, null, 2), 'utf8');

  const palaceByBranch = Object.fromEntries(chart.palaces.map((p: any) => [p.branch, p]));
  const html = `<!doctype html><meta charset="utf-8">
<title>${esc(birthInfo.name || '')} 紫微斗数命盘</title>
<style>
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;background:#f8f3e6;color:#241b10}
.wrap{max-width:1180px;margin:0 auto;padding:24px}
h1{font-size:22px;letter-spacing:.15em}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:1px;background:#c8a14a;border:1px solid #c8a14a}
.palace,.center{min-height:118px;border:0;background:#fffaf0;padding:10px;text-align:left;display:flex;flex-direction:column;gap:5px}
.palace{cursor:pointer}.palace:hover,.palace.active{background:#fff0bd}.ming{box-shadow:inset 4px 0 #b88719}.shen{box-shadow:inset 0 -4px #2f80aa}
.meta{font-size:11px;color:#8d7445}.majors{font-size:18px;font-weight:700;color:#8a5b00}.others{font-size:12px;color:#5b6470}
.center{grid-column:2 / span 2;grid-row:2 / span 2;align-items:center;justify-content:center;text-align:center}
.seal{font-size:26px;font-weight:700;color:#9d741d}.detail{margin-top:18px;padding:16px;background:#fff;border:1px solid #d8bd72;white-space:pre-wrap}
.patterns{margin-top:18px;display:grid;gap:8px}.pattern{background:#fff;border:1px solid #e3cf95;padding:10px}
</style>
<div class="wrap">
<h1>${esc(birthInfo.name || '命主')} · 紫微斗数命盘</h1>
<p>${birthInfo.year}-${birthInfo.month}-${birthInfo.day} · ${birthInfo.gender === 'male' ? '男' : '女'} · ${branches[birthInfo.hour]}时</p>
<main class="grid">${order.map(branch => palaceCell(branch, chart, palaceByBranch)).join('')}</main>
<section id="detail" class="detail">点击任意宫位查看详情。</section>
<section class="patterns">${patterns.map((p: any) => `<div class="pattern"><b>${esc(p.name)}</b> · ${esc(p.level)}<br>${esc(p.description)}</div>`).join('')}</section>
</div>
<script>
const chart=${JSON.stringify(chart)};
const branches=${JSON.stringify(branches)};
const detail=document.getElementById('detail');
document.querySelectorAll('.palace').forEach(btn=>btn.addEventListener('click',()=>{
  document.querySelectorAll('.palace').forEach(x=>x.classList.remove('active'));
  btn.classList.add('active');
  const p=chart.palaces.find(x=>x.branch===Number(btn.dataset.branch));
  detail.textContent = p.name + '（' + branches[p.branch] + '）\\n' +
    '主星：' + (p.stars.filter(s=>s.type==='major').map(s=>s.name+(s.siHua?'化'+s.siHua:'')).join('、') || '空宫') + '\\n' +
    '其他：' + p.stars.filter(s=>s.type!=='major').map(s=>s.name).join('、') + '\\n' +
    (p.isEmpty ? ('空宫借对宫：' + (p.borrowedFromName || '') + ' ' + (p.borrowedStars || []).join('、')) : '');
}));
</script>`;
  fs.writeFileSync(path.join(out, 'chart.html'), html, 'utf8');
  console.log(JSON.stringify({ json: path.join(out, 'chart.json'), html: path.join(out, 'chart.html') }, null, 2));
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
TS

if [ ! -d "$REPO/node_modules" ]; then
  (cd "$REPO" && npm install)
fi

REPO="$REPO" OUT="$OUT" NAME="$NAME" YEAR="$YEAR" MONTH="$MONTH" DAY="$DAY" HOUR="$HOUR" GENDER="$GENDER" CITY="$CITY" LONGITUDE="$LONGITUDE" \
  npx -y tsx "$RUNNER"
