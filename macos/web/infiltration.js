(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.ResistInfiltration = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const MICROMETER = 1e-6;
  const MILLINEWTON = 1e-3;
  const GAS_CONSTANT = 8.314462618;
  const REFERENCE_TEMPERATURE_K = 298.15;
  const CHANNEL_WIDTH_UM = 1;
  const MAX_STEP_BUDGET = 1000000;
  const PRESSURE_ROUNDOFF_ULPS = 16;
  const DEFAULTS = Object.freeze({
    mode: 'infiltration', gapUm: 0.2, depthUm: 5, contactAngleDeg: 45,
    externalPressurePa: 0, viscosityPaS: 0.001, surfaceTensionMnM: 72,
    temperatureC: 25, activationKJMol: 0, durationS: 0.001
  });
  const LIMITS = [
    ['gapUm', 'スリット間隔（µm）', 0.001, 100],
    ['depthUm', '浸透距離上限（µm）', 0.001, 100000],
    ['contactAngleDeg', '接触角（度）', 0, 180],
    ['externalPressurePa', '外部差圧（Pa）', -1000000, 1000000],
    ['viscosityPaS', '基準粘度（Pa·s）', 0.00001, 10000],
    ['surfaceTensionMnM', '表面張力（mN/m）', 0.001, 1000],
    ['temperatureC', '温度（°C）', -50, 250],
    ['activationKJMol', '粘度の活性化エネルギー（kJ/mol）', 0, 150],
    ['durationS', '計算時間（s）', 1e-12, 36000]
  ];

  function validateConfig(input) {
    if (!input || Object.prototype.toString.call(input) !== '[object Object]') {
      throw new Error('計算条件を単一のオブジェクトで指定してください。');
    }
    const config = Object.assign({}, DEFAULTS, input);
    if (config.mode !== 'infiltration') {
      throw new Error('浸透モードには mode = "infiltration" を指定してください。');
    }
    for (const [key, label, lower, upper] of LIMITS) {
      const raw = config[key];
      const numeric = typeof raw === 'number' ||
        (typeof raw === 'string' && /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(raw.trim()));
      const value = numeric ? Number(raw) : NaN;
      if (!Number.isFinite(value) || value < lower || value > upper) {
        throw new Error(label + 'は ' + lower + ' ～ ' + upper + ' の有限な数値で指定してください。');
      }
      config[key] = value;
    }
    return config;
  }

  function pressureSpacing(value) {
    // Read the binary exponent so cancellation uses MATLAB eps(value), including power-of-two boundaries.
    const binary = new DataView(new ArrayBuffer(8));
    binary.setFloat64(0, value);
    const exponent = ((binary.getUint32(0) >>> 20) & 0x7ff) - 1023;
    return 2 ** (exponent - 52);
  }

  function snapshotAt(config, time) {
    const gap = config.gapUm * MICROMETER;
    const depth = config.depthUm * MICROMETER;
    const gamma = config.surfaceTensionMnM * MILLINEWTON;
    const temperatureK = config.temperatureC + 273.15;
    const viscosity = config.viscosityPaS * Math.exp(config.activationKJMol * 1000 /
      GAS_CONSTANT * (1 / temperatureK - 1 / REFERENCE_TEMPERATURE_K));
    // Neutral wetting must be exactly zero, as in MATLAB cosd(90).
    const cosine = config.contactAngleDeg === 90 ? 0 : Math.cos(config.contactAngleDeg * Math.PI / 180);
    const capillaryPressure = 2 * gamma * cosine / gap;
    let drivingPressure = config.externalPressurePa + capillaryPressure;
    const pressureScale = Math.max(1, Math.abs(config.externalPressurePa), Math.abs(capillaryPressure));
    if (Math.abs(drivingPressure) <= PRESSURE_ROUNDOFF_ULPS * pressureSpacing(pressureScale)) {
      drivingPressure = 0;
    }

    const warnings = [
      '通気された平行平板スリットの解析モデルです。液体は入口の十分大きい供給源から流入します。',
      '慣性・入口損失・動的接触角・接触線の固着・壁面滑り・閉じ込め気体・重力・蒸発・硬化は計算しません。',
      '時刻 0 の前線速度はこの近似では定義できません。初期の慣性過程を表すモデルではありません。',
      '距離上限への到達後は浸透長を保持します。出口から流れ続ける流量は計算しません。'
    ];
    if (config.gapUm < 0.01) {
      warnings.push('間隔が 10 nm 未満です。連続体・一定接触角・滑りなし近似の妥当性を別途確認してください。');
    }
    if (config.depthUm < 10 * config.gapUm) {
      warnings.push('スリットが間隔に比べて短く、無視した入口・出口効果が結果に影響する可能性があります。');
    }

    let fillTime = NaN;
    let frontSpeed = 0;
    let penetration = 0;
    let filled = false;
    if (drivingPressure > 0) {
      // Parallel-plate pressure loss is 12*mu*l*dl/dt/gap^2, giving the factor six after integration.
      const squaredLengthRate = gap ** 2 * drivingPressure / (6 * viscosity);
      fillTime = depth ** 2 / squaredLengthRate;
      filled = time >= fillTime;
      if (filled) {
        penetration = depth;
      } else {
        penetration = Math.sqrt(squaredLengthRate * time);
        frontSpeed = time === 0 ? NaN : squaredLengthRate / (2 * penetration);
      }
    } else {
      warnings.push('合計駆動圧が 0 以下のため浸透しません。空のスリットからの後退・排液は計算しません。');
    }

    const penetrationUm = penetration / MICROMETER;
    return {
      time, n: 1, lengthUm: config.gapUm, h: [penetrationUm], b: [0],
      hUnit: 'um', bUnit: 'um', mode: 'infiltration', done: time >= config.durationS,
      filled, terminationReason: '', warnings,
      stats: {
        meanUm: penetrationUm, minUm: penetrationUm, maxUm: penetrationUm, cvPercent: 0,
        volumeUm3: config.gapUm * penetrationUm * CHANNEL_WIDTH_UM, massErrorPercent: 0,
        soluteBalanceErrorPercent: NaN, solidsPercent: NaN, viscosityPaS: viscosity,
        steps: 0, rejectedSteps: 0, lastStepS: 0, evaporatedUm: 0, drainedUm: 0,
        penetrationUm, fillPercent: 100 * penetration / depth,
        capillaryPressurePa: capillaryPressure, drivingPressurePa: drivingPressure,
        fillTimeS: fillTime, frontSpeedUmS: frontSpeed / MICROMETER, channelWidthUm: CHANNEL_WIDTH_UM
      }
    };
  }

  class Simulation {
    constructor(input) {
      this.config = validateConfig(input);
      this.time = 0;
      this.steps = 0;
      this.terminationReason = '';
    }

    get done() { return this.time >= this.config.durationS; }

    advance(targetTime, maxSteps = 2000) {
      if (typeof targetTime !== 'number' || !Number.isFinite(targetTime) || targetTime < this.time) {
        throw new Error('到達時刻は現在時刻以降の数値で指定してください。');
      }
      if (typeof maxSteps !== 'number' || !Number.isInteger(maxSteps) || maxSteps < 1 || maxSteps > MAX_STEP_BUDGET) {
        throw new Error('1 回の計算ステップ数は 1 ～ 1000000 の整数で指定してください。');
      }
      this.time = Math.min(targetTime, this.config.durationS);
      return { reachedTarget: true, done: this.done, steps: 0, time: this.time };
    }

    getSnapshot() { return snapshotAt(this.config, this.time); }
  }

  return Object.freeze({ DEFAULTS, validateConfig, createSimulation: config => new Simulation(config) });
});
