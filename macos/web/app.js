(() => {
  'use strict';
  const FRAME_INTERVALS = 60;
  const STEP_BUDGET = 100;
  const MAX_IMPORT_BYTES = 1024 * 1024;
  const COLORS = { ink: '#355847', muted: '#92a188', line: '#e7ecdf', green: '#2b7959', mint: '#bad9b3', gray: '#aebba4', substrate: '#e7e7d8' };
  const $ = id => document.getElementById(id);
  const MODES = {
    leveling: { eyebrow: 'THIN FILM / CAPILLARY FLOW', title: '表面張力による、膜の平坦化。', description: '膜厚分布と時間変化を観察して、材料・形状の影響を比較します。', label: '2D リフロー' },
    spin: { eyebrow: 'SPIN COATING / SOLVENT EVAPORATION', title: '回転と蒸発で変わる、レジスト膜。', description: '平均膜厚、固形分、粘度の変化を調べます。面内分布は計算しません。', label: 'スピン塗布' },
    infiltration: { eyebrow: 'CAPILLARY FILLING / OPEN SLIT', title: '濡れが進める、細隙への充填。', description: '開放されたスリットへの液体の進入を、毛管圧力と外部圧力から求めます。', label: '細隙充填' }
  };
  const PRESETS = {
    leveling: { mode: 'leveling', n: 16, lengthUm: 80, thicknessUm: 1, amplitudeUm: 0.2, viscosityPaS: 0.1, surfaceTensionMnM: 30, durationS: 1, evaporationNmS: 0, pattern: 'sine', substratePattern: 'flat', substrateUm: 0 },
    step: { mode: 'leveling', n: 16, lengthUm: 80, thicknessUm: 1, amplitudeUm: 0, viscosityPaS: 0.1, surfaceTensionMnM: 30, durationS: 1, evaporationNmS: 0, pattern: 'flat', substratePattern: 'step', substrateUm: 0.25 },
    spin: { mode: 'spin', thicknessUm: 5, viscosityPaS: 0.02, rpm: 2000, evaporationNmS: 100, solidsFraction: 0.2, concentrationFactor: 12, durationS: 60 },
    infiltration: { mode: 'infiltration', gapUm: 0.2, depthUm: 5, viscosityPaS: 0.001, surfaceTensionMnM: 72, contactAngleDeg: 45, externalPressurePa: 0, durationS: 0.00001 }
  };
  const FIELD = {
    n: ['分割数', '各方向のセル数', [[16, '16 × 16'], [32, '32 × 32'], [64, '64 × 64']]],
    lengthUm: ['計算領域の一辺', 'µm', 1, 100000], thicknessUm: ['初期平均膜厚', 'µm', 0.01, 1000],
    amplitudeUm: ['膜厚の凹凸振幅', 'µm', 0, 1000], pattern: ['膜厚の形状', '', [['sine', '正弦波'], ['gaussian', 'ガウス山'], ['ridge', 'リッジ'], ['flat', '平坦'], ['custom', 'CSV から']]],
    substratePattern: ['基板形状', '', [['flat', '平坦'], ['sine', '正弦波'], ['step', '滑らかな段差']]], substrateUm: ['基板の高低差・振幅', 'µm', 0, 1000],
    viscosityPaS: ['基準粘度', 'Pa·s / 25°C・初期濃度', 0.00001, 10000], surfaceTensionMnM: ['表面張力', 'mN/m', 0.001, 1000], densityKgM3: ['密度', 'kg/m³', 1, 30000],
    temperatureC: ['温度', '°C', -50, 250], activationKJMol: ['粘度の活性化エネルギー', 'kJ/mol / 0 で温度依存なし', 0, 150],
    rpm: ['回転数', 'rpm', 0, 100000], evaporationNmS: ['蒸発速度係数', 'nm/s', 0, 1000000], solidsFraction: ['初期固形分率', '体積比 / 0～1', 0.001, 0.99], concentrationFactor: ['濃縮粘度係数', '無次元', 0, 30],
    durationS: ['計算する時間', 's', 0.000001, 36000], accuracy: ['時間刻み・精度', '', [[1, '標準'], [0.5, '標準の 1/2'], [0.25, '標準の 1/4']]],
    gapUm: ['スリット間隔', 'µm', 0.001, 100], depthUm: ['スリット深さ', 'µm', 0.001, 100000], contactAngleDeg: ['接触角', '°', 0, 180], externalPressurePa: ['外部からの加圧', 'Pa', -1000000, 1000000]
  };
  const GROUPS = {
    leveling: [['形状と格子', '01', ['n', 'lengthUm', 'thicknessUm', 'pattern', 'amplitudeUm', 'substratePattern', 'substrateUm']], ['材料', '02', ['viscosityPaS', 'surfaceTensionMnM', 'temperatureC', 'activationKJMol']], ['工程と計算', '03', ['evaporationNmS', 'durationS', 'accuracy']]],
    spin: [['初期膜', '01', ['thicknessUm', 'solidsFraction']], ['材料', '02', ['viscosityPaS', 'densityKgM3', 'concentrationFactor', 'temperatureC', 'activationKJMol']], ['工程と計算', '03', ['rpm', 'evaporationNmS', 'durationS', 'accuracy']]],
    infiltration: [['スリット形状', '01', ['gapUm', 'depthUm']], ['材料と濡れ', '02', ['viscosityPaS', 'surfaceTensionMnM', 'contactAngleDeg', 'temperatureC', 'activationKJMol']], ['工程と計算', '03', ['externalPressurePa', 'durationS']]]
  };
  let config = {}, simulation = null, frames = [], selectedFrame = 0, running = false, dirty = false, failed = false;
  let generation = 0, nextFrame = 1, currentView = 'map', pinned = null, importKind = 'height';
  let colorBounds = [0, 1];
  const clone = value => JSON.parse(JSON.stringify(value));
  const api = mode => mode === 'infiltration' ? window.ResistInfiltration : window.ResistSolver;
  const finite = value => typeof value === 'number' && Number.isFinite(value);
  function format(value, digits = 3) {
    if (!finite(value)) return '—';
    if (value !== 0 && (Math.abs(value) < 0.001 || Math.abs(value) >= 100000)) return value.toExponential(2);
    return value.toLocaleString('en-US', { maximumFractionDigits: digits, minimumFractionDigits: 0 });
  }
  const timeLabel = value => format(value, 6);
  const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  function notify(message, isError = false) {
    $('alert').hidden = !message;
    $('alert').textContent = message || '';
    if (isError) setStatus('入力・計算を確認', 'error');
  }
  function setStatus(text, kind = '') {
    $('statusTag').className = 'status-tag ' + kind;
    $('statusTag').querySelector('span').textContent = text;
  }
  function renderFields() {
    const root = $('parameterGroups');
    root.replaceChildren();
    for (const [title, index, keys] of GROUPS[config.mode]) {
      const section = document.createElement('section');
      section.className = 'input-section';
      section.innerHTML = `<div class="section-heading"><span>${title}</span><span class="section-number">${index}</span></div>`;
      for (const key of keys) {
        const [label, unit, range, max] = FIELD[key];
        const row = document.createElement('div');
        row.className = 'parameter';
        const text = document.createElement('label');
        text.htmlFor = key;
        text.className = 'wide-label';
        text.append(document.createTextNode(label));
        if (unit) { const span = document.createElement('span'); span.textContent = unit; text.append(span); }
        const input = document.createElement(Array.isArray(range) ? 'select' : 'input');
        input.id = key; input.name = key;
        if (Array.isArray(range)) {
          for (const [value, caption] of range) { const option = document.createElement('option'); option.value = value; option.textContent = caption; input.append(option); }
        } else { input.type = 'number'; input.step = 'any'; input.min = key === 'durationS' && config.mode === 'infiltration' ? 1e-12 : range; input.max = max; input.required = true; }
        input.value = config[key];
        input.addEventListener('input', markDirty);
        input.addEventListener('change', markDirty);
        row.append(text, input); section.append(row);
      }
      root.append(section);
    }
    $('customImport').hidden = config.mode !== 'leveling';
    updateCustomDataNote();
  }
  function updateCustomDataNote(message = '') {
    const loaded = [config.customHeightUm ? '膜厚' : '', config.customSubstrateUm ? '基板' : ''].filter(Boolean);
    const status = loaded.length ? `読み込み済み: ${loaded.join('・')}（${config.n} × ${config.n}）` : '16 / 32 / 64 の正方行列、単位 µm。各 1 MB 以下。';
    $('customDataNote').textContent = message ? `${message} ${status}` : status;
  }
  function readFields() {
    const candidate = { ...config, mode: $('mode').value };
    for (const [, , keys] of GROUPS[candidate.mode]) {
      for (const key of keys) {
        const input = $(key);
        input.removeAttribute('aria-invalid');
        candidate[key] = ['pattern', 'substratePattern'].includes(key) ? input.value : input.value.trim() === '' ? '' : Number(input.value);
      }
    }
    return api(candidate.mode).validateConfig(candidate);
  }
  function markDirty(event) {
    pause(); dirty = true;
    if (event.target.id === 'n' && Number(event.target.value) !== config.n) {
      delete config.customHeightUm; delete config.customSubstrateUm;
      if ($('pattern')?.value === 'custom') $('pattern').value = 'sine';
      updateCustomDataNote('分割数を変更したため、CSV の形状データを解除しました。');
    }
    if (['substratePattern', 'substrateUm'].includes(event.target.id) && config.customSubstrateUm) {
      delete config.customSubstrateUm;
      updateCustomDataNote('基板条件を変更したため、基板 CSV を解除しました。');
    }
    setStatus('条件を変更'); $('runInfo').textContent = '表示中の結果は変更前の条件です。実行すると更新されます。';
    $('runButton').innerHTML = '<span>▶</span> 新しい条件で実行';
  }
  function selectPreset(name) {
    if (!PRESETS[name]) throw new Error('未対応のサンプル条件です。');
    const preset = PRESETS[name];
    config = { ...api(preset.mode).DEFAULTS, ...preset };
    $('mode').value = config.mode; $('preset').value = name;
    renderFields(); reset();
  }
  function setConfig(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('計算条件は単一の JSON オブジェクトで指定してください。');
    const mode = input.mode || config.mode;
    if (!Object.hasOwn(MODES, mode)) throw new Error('計算モデルは leveling、spin、infiltration から指定してください。');
    const validated = api(mode).validateConfig({ ...api(mode).DEFAULTS, ...input, mode });
    config = validated; $('mode').value = mode; $('preset').value = '';
    renderFields(); reset();
  }
  function pause() {
    if (!running) return;
    running = false; generation++;
    $('pauseButton').disabled = true; $('runButton').disabled = false;
    $('runButton').innerHTML = '<span>▶</span> 計算を再開'; setStatus('一時停止');
  }
  function reset() {
    pause(); generation++;
    try {
      const validated = readFields();
      const created = api(validated.mode).createSimulation(validated);
      config = validated; simulation = created; frames = [simulation.getSnapshot()]; selectedFrame = 0;
      nextFrame = 1; dirty = false; failed = false; notify('');
      colorBounds = [frames[0].stats.minUm, frames[0].stats.maxUm];
      if (colorBounds[1] - colorBounds[0] < 1e-12) colorBounds = [0, Math.max(config.thicknessUm || config.depthUm, 0.01)];
      $('runButton').disabled = false; $('runButton').innerHTML = '<span>▶</span> 計算を実行'; $('pauseButton').disabled = true;
      $('runInfo').textContent = '条件を確認して計算を実行してください'; setStatus('準備完了');
      updateModelText(); render();
      return true;
    } catch (error) { failed = true; notify(error.message, true); return false; }
  }
  function run() {
    if (running) return;
    if (dirty || !simulation || simulation.done || failed) { if (!reset()) return; }
    running = true; failed = false; notify('');
    $('runButton').disabled = true; $('pauseButton').disabled = false; setStatus('計算中', 'running');
    const token = ++generation;
    const tick = () => {
      if (!running || token !== generation) return;
      try {
        const target = config.durationS * Math.min(nextFrame, FRAME_INTERVALS) / FRAME_INTERVALS;
        const result = simulation.advance(target, STEP_BUDGET);
        if (result.reachedTarget || simulation.done) {
          frames.push(simulation.getSnapshot()); selectedFrame = frames.length - 1; nextFrame++;
          render();
        }
        $('runInfo').textContent = `${format(simulation.time / config.durationS * 100, 1)}% · ${timeLabel(simulation.time)} / ${timeLabel(config.durationS)} s · ${format(simulation.getSnapshot().stats.steps, 0)} steps`;
        if (simulation.done || nextFrame > FRAME_INTERVALS) { finish(); return; }
        requestAnimationFrame(tick);
      } catch (error) {
        const snapshot = simulation.getSnapshot();
        if (frames.at(-1).time !== snapshot.time) frames.push(snapshot);
        selectedFrame = frames.length - 1;
        failed = !snapshot.terminationReason; finish(Boolean(snapshot.terminationReason));
        notify(error.message, !snapshot.terminationReason); render();
      }
    };
    requestAnimationFrame(tick);
  }
  function finish(stopped = false) {
    running = false; $('pauseButton').disabled = true; $('runButton').disabled = false;
    $('runButton').innerHTML = '<span>▶</span> もう一度実行';
    setStatus(failed ? '計算エラー' : stopped ? 'モデルの限界で停止' : '計算完了', failed ? 'error' : '');
  }
  function updateModelText() {
    const model = MODES[config.mode], infiltrating = config.mode === 'infiltration', spin = config.mode === 'spin';
    $('modelEyebrow').textContent = model.eyebrow; $('modelTitle').textContent = model.title; $('modelDescription').textContent = model.description;
    $('mapTitle').textContent = infiltrating ? 'スリットへの充填状態' : spin ? '均一膜の模式図' : currentView === 'surface' ? '自由表面の立体表示' : '液体膜厚マップ';
    $('sectionTitle').textContent = infiltrating ? 'スリット深さと充填先端' : '中央断面';
    $('historyTitle').textContent = infiltrating ? '充填長の時間変化' : '膜厚の時間変化';
    $('sectionNote').textContent = infiltrating ? '入口からの距離 / 横方向の幅は模式表示' : spin ? '面内で一様な膜を仮定した断面' : '基板高さ + 膜厚（自由表面） / y = L/2';
    $('historyNote').textContent = infiltrating ? '緑の線：充填先端位置 / 点線：保持した同一モデルの結果' : '緑の線：平均膜厚 / 塗り：最小～最大';
    $('figureNote').textContent = infiltrating ? '幅と深さは別々の縮尺です。空気が出口へ逃げる開放スリットを仮定します。' : spin ? '色と高さは一様な平均膜厚です。面内分布やウェハ端部は計算しません。' : currentView === 'surface' ? '高さは基板 + 液体膜厚、色は液体膜厚。高さ方向は強調表示です。' : '色は液体膜厚を表します。左右・上下は周期境界です。';
    $('surfaceView').disabled = infiltrating; $('mapView').disabled = infiltrating;
    $('exportMatrix').disabled = infiltrating;
    $('legendLabel').textContent = infiltrating ? '充填率 [%]' : '液体膜厚 [µm]';
    $('colorMin').textContent = infiltrating ? '0' : format(colorBounds[0]); $('colorMax').textContent = infiltrating ? '100' : format(colorBounds[1]);
  }
  function render() {
    if (!frames.length) return;
    const snapshot = frames[selectedFrame], s = snapshot.stats, infiltration = config.mode === 'infiltration';
    const stats = infiltration ? [
      ['充填先端', s.penetrationUm, 'µm', `対象深さ ${format(config.depthUm)} µm`], ['充填率', s.fillPercent, '%', '入口から先端までの長さの割合'],
      ['駆動圧力', s.drivingPressurePa, 'Pa', '毛管圧力 + 外部圧力'], ['予測充填時間', s.fillTimeS, 's', finite(s.fillTimeS) ? '一定条件の解析近似' : '駆動圧力がないため充填しません']
    ] : [
      ['平均膜厚', s.meanUm, 'µm', `初期 ${format(frames[0].stats.meanUm)} µm`], ['最小 / 最大膜厚', `${format(s.minUm)} / ${format(s.maxUm)}`, 'µm', '表示中の時刻の分布'],
      [config.mode === 'spin' ? '固形分率' : '膜厚のばらつき CV', config.mode === 'spin' ? s.solidsPercent : s.cvPercent, '%', config.mode === 'spin' ? '非揮発成分の体積比' : '標準偏差 / 平均 × 100'],
      ['体積収支の残差', s.massErrorPercent, '%', '流出・蒸発を含む数値的な収支']
    ];
    $('statistics').innerHTML = stats.map(([label, value, unit, note]) => `<div class="stat"><div class="stat-label">${label}</div><div class="stat-value"${typeof value === 'string' ? ' style="font-size:22px"' : ''}>${typeof value === 'string' ? value : format(value)}<small>${unit}</small></div><div class="stat-caption">${note}</div></div>`).join('');
    $('timeDisplay').innerHTML = `${timeLabel(snapshot.time)}<span>s</span>`;
    const details = infiltration ? [['スリット間隔', `${format(config.gapUm)} µm`], ['接触角', `${format(config.contactAngleDeg)}°`], ['毛管圧力', `${format(s.capillaryPressurePa)} Pa`]] : [['計算格子', config.mode === 'spin' ? '均一膜' : `${snapshot.n} × ${snapshot.n}`], ['粘度', `${format(s.viscosityPaS)} Pa·s`], ['累積蒸発厚', `${format(s.evaporatedUm)} µm`]];
    $('mapDetails').innerHTML = details.map(([key, value]) => `<div><span>${key}</span><strong>${value}</strong></div>`).join('');
    $('timeline').max = frames.length - 1; $('timeline').value = selectedFrame; $('timeline').disabled = frames.length < 2;
    $('timelineValue').textContent = `${timeLabel(snapshot.time)} / ${timeLabel(frames.at(-1).time)} s`; $('frameCount').textContent = `${frames.length} frames`;
    const warnings = snapshot.warnings || [];
    $('warningList').replaceChildren(...warnings.map(message => { const li = document.createElement('li'); li.textContent = message; return li; }));
    $('warningCount').textContent = `${warnings.length} 件`;
    updateModelText(); drawMap(snapshot); drawSection(snapshot); drawHistory(snapshot); renderComparison(snapshot);
  }
  function canvasContext(id) {
    const canvas = $(id), rect = canvas.getBoundingClientRect(), scale = Math.min(window.devicePixelRatio || 1, 2);
    const width = Math.max(rect.width, 100), height = Math.max(rect.height, 100);
    canvas.width = Math.round(width * scale); canvas.height = Math.round(height * scale);
    const ctx = canvas.getContext('2d'); ctx.scale(scale, scale); ctx.clearRect(0, 0, width, height);
    ctx.font = '10px -apple-system, sans-serif'; ctx.fillStyle = COLORS.muted;
    return { canvas, ctx, width, height };
  }
  function color(value) {
    const stops = [[232, 239, 186], [176, 206, 139], [110, 174, 127], [51, 126, 110], [22, 79, 80]];
    const ratio = Math.max(0, Math.min(1, (value - colorBounds[0]) / Math.max(colorBounds[1] - colorBounds[0], 1e-12))) * (stops.length - 1);
    const lower = Math.min(Math.floor(ratio), stops.length - 2), fraction = ratio - lower;
    return `rgb(${stops[lower].map((c, i) => Math.round(c + (stops[lower + 1][i] - c) * fraction)).join(',')})`;
  }
  function drawMap(snapshot) {
    const { ctx, width, height } = canvasContext('mapCanvas');
    if (config.mode === 'infiltration') { drawSlit(ctx, width, height, snapshot, false); return; }
    if (currentView === 'surface') { drawSurface(ctx, width, height, snapshot); return; }
    const size = Math.min(height - 55, width - 95), x0 = (width - size) / 2 + 10, y0 = 14, n = snapshot.n, cell = size / n;
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) { ctx.fillStyle = color(snapshot.h[y * n + x]); ctx.fillRect(x0 + x * cell, y0 + y * cell, cell + 0.4, cell + 0.4); }
    ctx.strokeStyle = '#becbb1'; ctx.lineWidth = 1; ctx.strokeRect(x0, y0, size, size);
    ctx.strokeStyle = '#ffffff90'; ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.moveTo(x0, y0 + size / 2); ctx.lineTo(x0 + size, y0 + size / 2); ctx.stroke(); ctx.setLineDash([]);
    ctx.fillStyle = COLORS.muted; ctx.textAlign = 'center';
    for (let i = 0; i <= 4; i++) { const label = format(snapshot.lengthUm * i / 4, 1); ctx.fillText(label, x0 + size * i / 4, y0 + size + 18); ctx.textAlign = 'right'; ctx.fillText(label, x0 - 9, y0 + size * i / 4 + 3); ctx.textAlign = 'center'; }
    ctx.fillText('x [µm]', x0 + size / 2, y0 + size + 36);
    ctx.save(); ctx.translate(x0 - 39, y0 + size / 2); ctx.rotate(-Math.PI / 2); ctx.fillText('y [µm]', 0, 0); ctx.restore();
  }
  function drawSurface(ctx, width, height, snapshot) {
    const n = snapshot.n === 1 ? 16 : snapshot.n;
    const values = snapshot.h, base = snapshot.b;
    const initial = frames[0];
    const maxSurface = Math.max(...initial.h.map((v, i) => v + initial.b[i]), ...values.map((v, i) => v + base[i]), 0.01);
    const span = Math.min(width * 0.42, height * 0.83), depth = span * 0.42, zScale = Math.min(height * 0.27, 84) / maxSurface;
    const originX = width / 2, originY = height * 0.61;
    const project = (x, y, z) => [originX + (x - y) * span, originY + (x + y - 1) * depth - z * zScale];
    const polygon = points => { ctx.beginPath(); points.forEach((p, i) => i ? ctx.lineTo(...p) : ctx.moveTo(...p)); ctx.closePath(); };
    polygon([project(0, 0, 0), project(1, 0, 0), project(1, 1, 0), project(0, 1, 0)]); ctx.fillStyle = '#e7eadb'; ctx.fill(); ctx.strokeStyle = '#ced8bf'; ctx.stroke();
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      const i = snapshot.n === 1 ? 0 : y * n + x, z = values[i] + base[i];
      polygon([project(x / n, y / n, z), project((x + 1) / n, y / n, z), project((x + 1) / n, (y + 1) / n, z), project(x / n, (y + 1) / n, z)]);
      ctx.fillStyle = color(values[i]); ctx.fill(); ctx.strokeStyle = '#ffffff35'; ctx.lineWidth = 0.5; ctx.stroke();
    }
    ctx.fillStyle = COLORS.muted; ctx.textAlign = 'center'; ctx.fillText(`x: 0–${format(snapshot.lengthUm)} µm`, originX + span * 0.63, originY + depth * 0.74 + 17); ctx.fillText(`y: 0–${format(snapshot.lengthUm)} µm`, originX - span * 0.64, originY + depth * 0.74 + 17);
    ctx.fillText('高さ方向を強調した自由表面の表示', originX, height - 12);
  }
  function drawSlit(ctx, width, height, snapshot, compact) {
    const fill = Math.min(1, snapshot.stats.fillPercent / 100), top = compact ? 20 : 23, bottom = height - (compact ? 29 : 39), channelHeight = bottom - top;
    const channelWidth = compact ? 54 : 95, left = width * 0.46 - channelWidth / 2, right = left + channelWidth, wall = compact ? 24 : 45;
    ctx.fillStyle = '#eeeee2'; ctx.fillRect(left - wall, top, wall, channelHeight); ctx.fillRect(right, top, wall, channelHeight);
    ctx.fillStyle = '#f6f9f2'; ctx.fillRect(left, top, channelWidth, channelHeight);
    if (fill > 0) { const gradient = ctx.createLinearGradient(left, top, right, bottom); gradient.addColorStop(0, '#8cbd8c'); gradient.addColorStop(1, '#377e69'); ctx.fillStyle = gradient; ctx.fillRect(left, top, channelWidth, channelHeight * fill); }
    ctx.strokeStyle = '#a8b99f'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(left, top); ctx.lineTo(left, bottom); ctx.moveTo(right, top); ctx.lineTo(right, bottom); ctx.stroke();
    const front = top + channelHeight * fill; ctx.strokeStyle = '#1d6850'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(left, front); ctx.lineTo(right, front); ctx.stroke();
    ctx.fillStyle = COLORS.muted; ctx.textAlign = 'left'; ctx.fillText('入口 0', right + wall + 13, top + 4); ctx.fillText(`${format(config.depthUm)} µm`, right + wall + 13, bottom + 4);
    ctx.fillStyle = COLORS.green; ctx.fillText(`${format(snapshot.stats.penetrationUm)} µm`, right + wall + 13, Math.min(bottom - 16, Math.max(top + 23, front + 4)));
    ctx.textAlign = 'center'; ctx.fillStyle = COLORS.muted; ctx.fillText(`間隔 ${format(config.gapUm)} µm`, left + channelWidth / 2, bottom + 23);
    if (!compact) { ctx.fillText('液体供給', left + channelWidth / 2, top - 9); ctx.save(); ctx.translate(left - wall - 17, (top + bottom) / 2); ctx.rotate(-Math.PI / 2); ctx.fillText('深さ方向', 0, 0); ctx.restore(); }
  }
  function chartAxes(ctx, width, height, xMax, yMin, yMax, xUnit, yUnit) {
    const plot = { left: 60, top: 24, right: width - 22, bottom: height - 32 };
    if (yMax - yMin < 1e-12) { yMin -= 0.1; yMax += 0.1; }
    const yPadding = (yMax - yMin) * 0.08; yMin -= yPadding; yMax += yPadding;
    const x = v => plot.left + v / Math.max(xMax, 1e-15) * (plot.right - plot.left);
    const y = v => plot.bottom - (v - yMin) / (yMax - yMin) * (plot.bottom - plot.top);
    ctx.lineWidth = 1; ctx.strokeStyle = COLORS.line; ctx.fillStyle = COLORS.muted; ctx.font = '9px -apple-system, sans-serif';
    for (let i = 0; i <= 3; i++) { const value = yMin + (yMax - yMin) * i / 3, yy = y(value); ctx.beginPath(); ctx.moveTo(plot.left, yy); ctx.lineTo(plot.right, yy); ctx.stroke(); ctx.textAlign = 'right'; ctx.fillText(format(value, 2), plot.left - 9, yy + 3); }
    for (let i = 0; i <= 4; i++) { ctx.textAlign = 'center'; ctx.fillText(timeLabel(xMax * i / 4), x(xMax * i / 4), plot.bottom + 17); }
    ctx.textAlign = 'left'; ctx.fillText(yUnit, plot.left, 12); ctx.textAlign = 'right'; ctx.fillText(xUnit, plot.right, height - 4);
    return { ...plot, x, y };
  }
  function line(ctx, values, getX, getY, colorValue, dashed = false, width = 2) {
    if (!values.length) return;
    ctx.strokeStyle = colorValue; ctx.lineWidth = width; ctx.setLineDash(dashed ? [5, 4] : []); ctx.beginPath();
    values.forEach((value, i) => { const x = getX(value, i), y = getY(value, i); if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y); }); ctx.stroke(); ctx.setLineDash([]);
  }
  function drawSection(snapshot) {
    const { ctx, width, height } = canvasContext('sectionCanvas');
    if (config.mode === 'infiltration') { drawSlit(ctx, width, height, snapshot, true); return; }
    const first = frames[0], n = snapshot.n;
    const getSlice = frame => { if (n === 1) return [frame.h[0] + frame.b[0], frame.h[0] + frame.b[0]]; const row = Math.floor(n / 2); return Array.from({ length: n }, (_, i) => frame.h[row * n + i] + frame.b[row * n + i]); };
    const initial = getSlice(first), current = getSlice(snapshot), substrate = n === 1 ? [0, 0] : Array.from({ length: n }, (_, i) => snapshot.b[Math.floor(n / 2) * n + i]);
    const min = Math.min(0, ...substrate, ...current), max = Math.max(...initial, ...current);
    const axis = chartAxes(ctx, width, height, snapshot.lengthUm, min, max, 'x [µm]', '高さ [µm]');
    const px = (_, i) => axis.x(i / (current.length - 1) * snapshot.lengthUm);
    ctx.fillStyle = COLORS.substrate; ctx.beginPath(); ctx.moveTo(axis.left, axis.y(min)); substrate.forEach((v, i) => ctx.lineTo(px(v, i), axis.y(v))); ctx.lineTo(axis.right, axis.y(min)); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#b5d6b340'; ctx.beginPath(); current.forEach((v, i) => i ? ctx.lineTo(px(v, i), axis.y(v)) : ctx.moveTo(px(v, i), axis.y(v))); substrate.slice().reverse().forEach((v, i) => ctx.lineTo(px(v, substrate.length - i - 1), axis.y(v))); ctx.closePath(); ctx.fill();
    line(ctx, initial, px, v => axis.y(v), COLORS.gray, true, 1.5); line(ctx, current, px, v => axis.y(v), COLORS.green);
  }
  function drawHistory(snapshot) {
    const { ctx, width, height } = canvasContext('historyCanvas');
    const matching = pinned?.config.mode === config.mode ? pinned.frames : [];
    const xMax = Math.max(config.durationS, matching.at(-1)?.time || 0);
    const all = frames.concat(matching), min = Math.min(...all.map(f => f.stats.minUm)), max = Math.max(...all.map(f => f.stats.maxUm));
    const axis = chartAxes(ctx, width, height, xMax, config.mode === 'infiltration' ? 0 : Math.min(min, max * 0.9), Math.max(max, config.mode === 'infiltration' ? config.depthUm : 0.01), 't [s]', config.mode === 'infiltration' ? '充填長 [µm]' : '膜厚 [µm]');
    ctx.fillStyle = '#b5d6b355'; ctx.beginPath(); frames.forEach((f, i) => i ? ctx.lineTo(axis.x(f.time), axis.y(f.stats.maxUm)) : ctx.moveTo(axis.x(f.time), axis.y(f.stats.maxUm))); frames.slice().reverse().forEach(f => ctx.lineTo(axis.x(f.time), axis.y(f.stats.minUm))); ctx.closePath(); ctx.fill();
    line(ctx, matching, f => axis.x(f.time), f => axis.y(f.stats.meanUm), COLORS.gray, true, 1.5);
    line(ctx, frames, f => axis.x(f.time), f => axis.y(f.stats.meanUm), COLORS.green);
    ctx.fillStyle = COLORS.green; ctx.beginPath(); ctx.arc(axis.x(snapshot.time), axis.y(snapshot.stats.meanUm), 3.5, 0, 2 * Math.PI); ctx.fill();
  }
  function renderComparison(snapshot) {
    if (!pinned) return;
    const base = pinned.snapshot, compatible = base.mode === snapshot.mode;
    const metric = config.mode === 'infiltration' ? '充填長 [µm]' : '平均膜厚 [µm]';
    $('comparison').className = 'comparison-table';
    $('comparison').innerHTML = `<button id="clearPin" title="保持した比較結果を解除">保持を解除 ×</button><table><thead><tr><th>結果</th><th>モデル</th><th>時刻 [s]</th><th>${metric}</th></tr></thead><tbody><tr><td>保持した基準</td><td>${MODES[pinned.config.mode].label}</td><td>${timeLabel(base.time)}</td><td>${compatible ? format(base.stats.meanUm) : '別モデル'}</td></tr><tr><td>現在の表示</td><td>${MODES[config.mode].label}</td><td>${timeLabel(snapshot.time)}</td><td>${format(snapshot.stats.meanUm)}</td></tr></tbody></table><p class="compare-note">${compatible ? `現在 − 基準: ${format(snapshot.stats.meanUm - base.stats.meanUm)} µm。時刻と条件の違いを確認して比較してください。` : '異なるモデルの数値は直接比較しません。'} 保持結果はアプリ終了時に消去されます。</p>`;
    $('clearPin').onclick = () => { pinned = null; $('comparison').className = 'comparison-empty'; $('comparison').textContent = '基準結果を保持してから条件を変えると、結果を並べて比較できます。'; render(); };
  }
  function saveFile(name, content, encoding = 'utf8') {
    const native = window.webkit?.messageHandlers?.saveFile;
    if (native) { native.postMessage({ name, content, encoding }); return; }
    const blob = encoding === 'base64' ? new Blob([Uint8Array.from(atob(content), c => c.charCodeAt(0))], { type: 'image/png' }) : new Blob([content], { type: name.endsWith('.json') ? 'application/json;charset=utf-8' : 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob), link = document.createElement('a'); link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify('保存用ファイルを作成しました。');
  }
  function exportHistory() {
    const keys = ['meanUm', 'minUm', 'maxUm', 'cvPercent', 'massErrorPercent', 'solidsPercent', 'viscosityPaS', 'evaporatedUm', 'drainedUm', 'soluteBalanceErrorPercent', 'steps'];
    if (config.mode === 'infiltration') keys.splice(0, keys.length, 'penetrationUm', 'fillPercent', 'capillaryPressurePa', 'drivingPressurePa', 'fillTimeS', 'frontSpeedUmS', 'volumeUm3');
    const rows = ['timeS,' + keys.join(','), ...frames.map(f => [f.time, ...keys.map(key => f.stats[key])].map(value => finite(value) ? String(value) : 'NaN').join(','))];
    saveFile(`ResistFlow-${config.mode}-history.csv`, rows.join('\r\n'));
  }
  function exportMatrix() {
    const snapshot = frames[selectedFrame], rows = [];
    for (let y = 0; y < snapshot.n; y++) rows.push(snapshot.h.slice(y * snapshot.n, (y + 1) * snapshot.n).join(','));
    saveFile(`ResistFlow-${config.mode}-thickness-um.csv`, rows.join('\r\n'));
  }
  function exportImage() {
    const output = document.createElement('canvas'); output.width = 1600; output.height = 1110;
    const ctx = output.getContext('2d'); ctx.fillStyle = '#f5f5ee'; ctx.fillRect(0, 0, output.width, output.height);
    ctx.fillStyle = COLORS.ink; ctx.font = '600 35px -apple-system, sans-serif'; ctx.fillText('Resist Flow Lab', 55, 65);
    ctx.font = '21px -apple-system, sans-serif'; ctx.fillText(`${MODES[config.mode].label} / t = ${timeLabel(frames[selectedFrame].time)} s`, 55, 104);
    ctx.font = '16px -apple-system, sans-serif'; ctx.fillStyle = COLORS.muted; ctx.fillText('Mac テスト版 · 近似モデル / 立体図の高さ・充填図の幅と深さは強調表示', 55, 138);
    ctx.fillStyle = '#fff'; ctx.fillRect(40, 160, 1520, 530); ctx.fillRect(40, 715, 745, 290); ctx.fillRect(805, 715, 755, 290);
    const map = $('mapCanvas'), section = $('sectionCanvas'), history = $('historyCanvas');
    const mapWidth = Math.min(1150, 470 * map.width / map.height); ctx.drawImage(map, 55, 190, mapWidth, 470);
    ctx.fillStyle = COLORS.ink; ctx.font = '19px -apple-system, sans-serif'; ctx.fillText($('mapTitle').textContent, 70, 190);
    const statX = Math.max(mapWidth + 95, 1080); let statY = 240;
    for (const card of $('statistics').children) { ctx.fillStyle = COLORS.muted; ctx.font = '15px -apple-system, sans-serif'; ctx.fillText(card.querySelector('.stat-label').textContent, statX, statY); ctx.fillStyle = COLORS.ink; ctx.font = '23px -apple-system, sans-serif'; ctx.fillText(card.querySelector('.stat-value').textContent, statX, statY + 30); statY += 98; }
    ctx.font = '18px -apple-system, sans-serif'; ctx.fillText($('sectionTitle').textContent, 65, 750); ctx.fillText($('historyTitle').textContent, 830, 750);
    ctx.drawImage(section, 55, 763, 715, 222); ctx.drawImage(history, 820, 763, 725, 222);
    ctx.fillStyle = COLORS.muted; ctx.font = '15px -apple-system, sans-serif'; ctx.fillText('サンプルは仮想材料。実材料には物性校正と実測検証が必要です。', 55, 1040);
    ctx.fillText(`計算条件: ${config.mode} / μ25 = ${config.viscosityPaS} Pa·s / T = ${config.temperatureC} °C / duration = ${config.durationS} s`, 55, 1070);
    saveFile(`ResistFlow-${config.mode}-result.png`, output.toDataURL('image/png').split(',')[1], 'base64');
  }
  async function loadConfigFile(file) {
    if (!file) return;
    if (file.size > MAX_IMPORT_BYTES) throw new Error('条件ファイルは 1 MB 以下にしてください。');
    const loaded = JSON.parse(await file.text());
    if (!loaded || typeof loaded !== 'object' || Array.isArray(loaded)) throw new Error('条件 JSON の形式を確認してください。');
    setConfig(Object.hasOwn(loaded, 'config') ? loaded.config : loaded); notify('条件ファイルを読み込みました。計算を実行してください。');
  }
  async function loadMatrixFile(file) {
    if (!file) return;
    if (file.size > MAX_IMPORT_BYTES) throw new Error('CSV は 1 MB 以下にしてください。');
    const text = (await file.text()).replace(/^\uFEFF/, '').trim();
    const rows = text.split(/\r?\n/).map(row => row.split(',').map(value => value.trim() === '' ? NaN : Number(value)));
    const n = rows.length;
    if (![16, 32, 64].includes(n) || rows.some(row => row.length !== n || row.some(value => !Number.isFinite(value)))) throw new Error('CSV は 16 × 16、32 × 32、64 × 64 の数値行列にしてください。単位は µm です。');
    let updated = readFields();
    if (n !== updated.n) { delete updated.customHeightUm; delete updated.customSubstrateUm; if (updated.pattern === 'custom') updated.pattern = 'sine'; }
    updated = { ...updated, n };
    if (importKind === 'height') { updated.customHeightUm = rows.flat(); updated.pattern = 'custom'; }
    else updated.customSubstrateUm = rows.flat();
    setConfig(updated); notify(`${importKind === 'height' ? '初期膜厚' : '基板高さ'}を読み込みました（${n} × ${n}、単位 µm）。`);
  }
  $('configForm').addEventListener('submit', event => event.preventDefault());
  $('mode').addEventListener('change', event => selectPreset(event.target.value));
  $('preset').addEventListener('change', event => selectPreset(event.target.value));
  $('runButton').addEventListener('click', run); $('pauseButton').addEventListener('click', pause); $('resetButton').addEventListener('click', reset);
  $('timeline').addEventListener('input', event => { selectedFrame = Number(event.target.value); render(); });
  for (const [id, view] of [['mapView', 'map'], ['surfaceView', 'surface']]) $(id).addEventListener('click', () => { currentView = view; for (const [button, selected] of [['mapView', view === 'map'], ['surfaceView', view === 'surface']]) { $(button).classList.toggle('active', selected); $(button).setAttribute('aria-pressed', selected); } render(); });
  $('pinResult').addEventListener('click', () => { pinned = { config: clone(config), snapshot: clone(frames[selectedFrame]), frames: clone(frames) }; render(); notify('表示中の結果と計算済みの時系列を比較用に保持しました。'); });
  $('saveConfig').addEventListener('click', () => { try { const candidate = readFields(); saveFile('ResistFlow-conditions.json', JSON.stringify({ app: 'Resist Flow Lab', formatVersion: 1, config: candidate }, null, 2)); } catch (error) { notify(error.message, true); } });
  $('loadConfig').addEventListener('click', () => $('configFile').click());
  $('configFile').addEventListener('change', async event => { try { await loadConfigFile(event.target.files[0]); } catch (error) { notify('読み込めませんでした: ' + error.message, true); } finally { event.target.value = ''; } });
  for (const [button, kind] of [['loadMatrix', 'height'], ['loadSubstrate', 'substrate']]) $(button).addEventListener('click', () => { importKind = kind; $('matrixFile').click(); });
  $('matrixFile').addEventListener('change', async event => { try { await loadMatrixFile(event.target.files[0]); } catch (error) { notify('読み込めませんでした: ' + error.message, true); } finally { event.target.value = ''; } });
  $('exportHistory').addEventListener('click', exportHistory); $('exportMatrix').addEventListener('click', exportMatrix); $('exportImage').addEventListener('click', exportImage);
  window.addEventListener('native-save-result', event => { const result = event.detail; if (result?.ok) notify(`${result.name || 'ファイル'} を保存しました。`); else if (!result?.cancelled) notify('保存できませんでした。保存先とアクセス権を確認してください。', true); });
  let resizeFrame = 0; window.addEventListener('resize', () => { cancelAnimationFrame(resizeFrame); resizeFrame = requestAnimationFrame(render); });
  window.ResistPreviewTest = Object.freeze({ selectPreset, setConfig, run, pause, reset, getState: () => ({ running, failed, dirty, mode: config.mode, frameCount: frames.length, time: simulation?.time || 0, duration: config.durationS, snapshot: simulation?.getSnapshot(), config: clone(config), displayedFrame: selectedFrame }), exportHistory, exportMatrix, exportImage });
  try { selectPreset('leveling'); } catch (error) { failed = true; notify('計算エンジンを読み込めませんでした: ' + error.message, true); }
})();
