(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.ResistSolver = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const MICROMETER = 1e-6;
  const NANOMETER = 1e-9;
  const MIN_WET_THICKNESS = 0.01 * MICROMETER;
  const MAX_LIQUID_SOLIDS_FRACTION = 0.99;
  const GAS_CONSTANT = 8.314462618;
  const REFERENCE_TEMPERATURE_K = 298.15;
  const MAX_TOTAL_STEPS = 1000000;
  const STABILITY_FACTOR = 0.55;
  const STEP_SMOOTHNESS = 0.25;
  const WET_LIMIT_MESSAGE = '最小膜厚が 0.01 µm に達したため計算を停止しました。乾燥に近い膜はこの液体モデルの対象外です。';
  const DEFAULTS = Object.freeze({
    mode: 'leveling', n: 16, lengthUm: 80, thicknessUm: 1,
    amplitudeUm: 0.2, pattern: 'sine', substrateUm: 0,
    substratePattern: 'flat', viscosityPaS: 0.1, surfaceTensionMnM: 30,
    densityKgM3: 1000, rpm: 3000, evaporationNmS: 0,
    solidsFraction: 0.2, concentrationFactor: 8, temperatureC: 25,
    activationKJMol: 0, durationS: 1, accuracy: 1
  });

  function numberInRange(config, key, label, minimum, maximum) {
    const numericInput = typeof config[key] === 'number' ||
      (typeof config[key] === 'string' && config[key].trim() !== '');
    const value = Number(config[key]);
    if (!numericInput || !Number.isFinite(value) || value < minimum || value > maximum) {
      throw new Error(label + 'は ' + minimum + ' ～ ' + maximum + ' の数値で入力してください。');
    }
    config[key] = value;
  }

  function validateConfig(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) {
      throw new Error('計算条件をオブジェクトで指定してください。');
    }
    const config = Object.assign({}, DEFAULTS, input);
    if (!['leveling', 'spin'].includes(config.mode)) throw new Error('計算モードを選択してください。');
    numberInRange(config, 'n', '分割数', 16, 64);
    if (![16, 32, 64].includes(config.n)) throw new Error('分割数は 16、32、64 から選択してください。');
    numberInRange(config, 'lengthUm', '領域サイズ（µm）', 1, 100000);
    numberInRange(config, 'thicknessUm', '初期膜厚（µm）', 0.01, 1000);
    numberInRange(config, 'amplitudeUm', '初期凹凸の振幅（µm）', 0, 1000);
    numberInRange(config, 'substrateUm', '基板の高低差・振幅（µm）', 0, 1000);
    numberInRange(config, 'viscosityPaS', '基準粘度（Pa·s）', 0.00001, 10000);
    numberInRange(config, 'surfaceTensionMnM', '表面張力（mN/m）', 0.001, 1000);
    numberInRange(config, 'densityKgM3', '密度（kg/m³）', 1, 30000);
    numberInRange(config, 'rpm', '回転数（rpm）', 0, 100000);
    numberInRange(config, 'evaporationNmS', '蒸発速度（nm/s）', 0, 1000000);
    numberInRange(config, 'solidsFraction', '初期固形分率', 0.001, 0.99);
    numberInRange(config, 'concentrationFactor', '濃度による粘度上昇係数', 0, 30);
    numberInRange(config, 'temperatureC', '温度（°C）', -50, 250);
    numberInRange(config, 'activationKJMol', '粘度の活性化エネルギー（kJ/mol）', 0, 150);
    numberInRange(config, 'durationS', '計算時間（s）', 0.000001, 36000);
    numberInRange(config, 'accuracy', '精度係数', 0.25, 1);
    if (![0.25, 0.5, 1].includes(config.accuracy)) throw new Error('精度係数は 0.25、0.5、1 から選択してください。');
    if (config.mode === 'spin' && config.solidsFraction >= MAX_LIQUID_SOLIDS_FRACTION) {
      throw new Error('初期固形分率は 0.99 未満にしてください。乾燥に近い膜は液体モデルの対象外です。');
    }
    if (!['sine', 'gaussian', 'ridge', 'flat', 'custom'].includes(config.pattern)) {
      throw new Error('初期膜厚の形状を選択してください。');
    }
    if (!['flat', 'sine', 'step'].includes(config.substratePattern)) {
      throw new Error('基板形状を選択してください。');
    }
    for (const key of ['customHeightUm', 'customSubstrateUm']) {
      if (config[key] === undefined || config[key] === null) continue;
      if ((!Array.isArray(config[key]) && !ArrayBuffer.isView(config[key])) || config[key].length !== config.n * config.n) {
        throw new Error((key === 'customHeightUm' ? '膜厚' : '基板') + 'の読み込みデータは分割数 × 分割数の配列にしてください。');
      }
      config[key] = Array.from(config[key], value => {
        if (typeof value !== 'number' && !(typeof value === 'string' && value.trim() !== '')) return NaN;
        return Number(value);
      });
      if (config[key].some(value => !Number.isFinite(value) || Math.abs(value) > 100000)) {
        throw new Error('読み込みデータに範囲外または数値でない値があります（単位: µm）。');
      }
      if (key === 'customHeightUm' && config[key].some(value => value < MIN_WET_THICKNESS / MICROMETER)) {
        throw new Error('読み込み膜厚はすべて 0.01 µm 以上にしてください。');
      }
    }
    if (config.mode === 'leveling' && config.pattern === 'custom' && !config.customHeightUm) {
      throw new Error('任意形状には膜厚の読み込みデータが必要です。');
    }
    // Validate the actual generated field, including combinations of baseline and amplitude.
    if (config.mode === 'leveling') initialFields(config);
    return config;
  }

  function viscosity(config, solidsFraction) {
    const temperatureK = config.temperatureC + 273.15;
    const temperatureExponent = config.activationKJMol * 1000 / GAS_CONSTANT *
      (1 / temperatureK - 1 / REFERENCE_TEMPERATURE_K);
    const concentrationExponent = config.mode === 'spin' ?
      config.concentrationFactor * (solidsFraction - config.solidsFraction) : 0;
    return config.viscosityPaS * Math.exp(temperatureExponent + concentrationExponent);
  }

  function initialFields(config) {
    const n = config.mode === 'spin' ? 1 : config.n;
    const count = n * n;
    const h = new Float64Array(count);
    const b = new Float64Array(count);
    const shape = new Float64Array(count);
    let shapeMean = 0;
    for (let y = 0; y < n; y++) {
      for (let x = 0; x < n; x++) {
        const i = y * n + x;
        const ux = (x + 0.5) / n - 0.5;
        const uy = (y + 0.5) / n - 0.5;
        if (config.pattern === 'sine') shape[i] = Math.cos(2 * Math.PI * ux);
        if (config.pattern === 'gaussian') shape[i] = Math.exp(-(ux * ux + uy * uy) / (2 * 0.12 * 0.12));
        if (config.pattern === 'ridge') shape[i] = Math.exp(-ux * ux / (2 * 0.1 * 0.1));
        shapeMean += shape[i] / count;
        if (config.mode !== 'spin' && config.substratePattern === 'sine') {
          b[i] = config.substrateUm * Math.cos(2 * Math.PI * ux) * MICROMETER;
        }
        if (config.mode !== 'spin' && config.substratePattern === 'step') {
          b[i] = config.substrateUm * 0.5 *
            (1 + Math.tanh(Math.sin(2 * Math.PI * ux) / STEP_SMOOTHNESS)) * MICROMETER;
        }
      }
    }
    for (let i = 0; i < count; i++) {
      h[i] = (config.thicknessUm + (config.mode === 'spin' ? 0 : config.amplitudeUm * (shape[i] - shapeMean))) * MICROMETER;
      if (config.mode === 'leveling' && config.pattern === 'custom') h[i] = config.customHeightUm[i] * MICROMETER;
      if (config.mode === 'leveling' && config.customSubstrateUm) b[i] = config.customSubstrateUm[i] * MICROMETER;
      if (!Number.isFinite(h[i]) || h[i] < MIN_WET_THICKNESS * (1 - 1e-12)) {
        throw new Error('初期膜厚が 0.01 µm 未満になります。平均膜厚を増やすか、凹凸の振幅を小さくしてください。');
      }
    }
    return { h, b, n };
  }

  function fieldStats(h) {
    let sum = 0;
    let minimum = Infinity;
    let maximum = -Infinity;
    for (const value of h) {
      sum += value;
      if (value < minimum) minimum = value;
      if (value > maximum) maximum = value;
    }
    const mean = sum / h.length;
    let squaredDeviation = 0;
    for (const value of h) squaredDeviation += (value - mean) ** 2;
    return { mean, minimum, maximum, cv: Math.sqrt(squaredDeviation / h.length) / mean };
  }

  class Simulation {
    constructor(input) {
      this.config = validateConfig(input);
      const fields = initialFields(this.config);
      this.h = fields.h;
      this.b = fields.b;
      this.n = fields.n;
      this.time = 0;
      this.steps = 0;
      this.rejectedSteps = 0;
      this.evaporatedThickness = 0;
      this.drainedThickness = 0;
      this.soluteOutflow = 0;
      this.initialMean = fieldStats(this.h).mean;
      this.initialSolute = this.initialMean * this.config.solidsFraction;
      this.soluteThickness = this.initialSolute;
      this.terminationReason = null;
      this.warnings = [];
      this.lastStepS = 0;
      this.spinNextStep = Math.min(this.config.durationS / 100, 0.1);
      this.dx = this.config.lengthUm * MICROMETER / this.n;
      if (this.config.mode === 'leveling') this.prepareLeveling();
      else this.warnings.push('回転塗布は面内で一様な膜の平均値モデルです。ウェハ端部・液滴の広がり・面内分布は計算しません。');
    }

    get done() { return this.time >= this.config.durationS || this.terminationReason !== null; }

    prepareLeveling() {
      const count = this.n * this.n;
      this.east = new Int32Array(count);
      this.north = new Int32Array(count);
      this.pressure = new Float64Array(count);
      this.ratesFirst = new Float64Array(count);
      this.ratesSecond = new Float64Array(count);
      this.intermediate = new Float64Array(count);
      this.candidate = new Float64Array(count);
      this.fixedViscosity = viscosity(this.config, this.config.solidsFraction);
      for (let y = 0; y < this.n; y++) {
        for (let x = 0; x < this.n; x++) {
          const i = y * this.n + x;
          this.east[i] = y * this.n + (x + 1) % this.n;
          this.north[i] = ((y + 1) % this.n) * this.n + x;
        }
      }
      this.warnings.push('面内流動は周期境界・ニュートン流体・小勾配の薄膜近似です。露光反応、現像、接触線、乾燥後の固体力学は含みません。');
      if (this.config.evaporationNmS > 0) {
        this.warnings.push('面内モードの蒸発は一様な膜厚減少のみです。濃度・粘度の変化は連成せず、最小膜厚 0.01 µm で計算を停止します。');
      }
      const stats = fieldStats(this.h);
      let maximumSlope = 0;
      for (let i = 0; i < count; i++) {
        const totalHeight = this.h[i] + this.b[i];
        maximumSlope = Math.max(maximumSlope,
          Math.abs(this.h[this.east[i]] + this.b[this.east[i]] - totalHeight) / this.dx,
          Math.abs(this.h[this.north[i]] + this.b[this.north[i]] - totalHeight) / this.dx,
          Math.abs(this.b[this.east[i]] - this.b[i]) / this.dx,
          Math.abs(this.b[this.north[i]] - this.b[i]) / this.dx);
      }
      if (maximumSlope > 0.2 || stats.maximum / (this.config.lengthUm * MICROMETER) > 0.05) {
        this.warnings.push('膜の厚さまたは表面・基板の勾配が大きいため、薄膜近似の精度が低下する可能性があります。');
      }
      if (this.config.substratePattern === 'step' && this.config.substrateUm > 0) {
        this.warnings.push('基板段差は傾斜を滑らかにした周期形状です。垂直な側壁や孤立した段差を直接表すものではありません。');
      }
      const estimatedSteps = this.config.durationS / this.stableStep(stats.maximum);
      if (estimatedSteps > MAX_TOTAL_STEPS) {
        this.warnings.push('この条件は計算量が大きく、100万ステップの上限に達する可能性があります。分割数、計算時間、膜厚を小さくすると計算量を減らせます。');
      }
    }

    stableStep(maximumThickness) {
      const mobility = maximumThickness ** 3 / (3 * this.fixedViscosity);
      const gamma = this.config.surfaceTensionMnM * 0.001;
      // The periodic 2D biharmonic operator has spectral radius 64/dx^4.
      return STABILITY_FACTOR * this.dx ** 4 * this.config.accuracy / (32 * gamma * mobility);
    }

    flowRates(h, rates) {
      const gamma = this.config.surfaceTensionMnM * 0.001;
      const invDxSquared = 1 / (this.dx * this.dx);
      const pressure = this.pressure;
      pressure.fill(0);
      rates.fill(0);
      // Each shared face is visited once, so paired updates conserve total volume.
      for (let i = 0; i < h.length; i++) {
        for (let axis = 0; axis < 2; axis++) {
          const j = axis === 0 ? this.east[i] : this.north[i];
          const curvatureContribution = ((h[j] + this.b[j]) - (h[i] + this.b[i])) * invDxSquared;
          pressure[i] -= gamma * curvatureContribution;
          pressure[j] += gamma * curvatureContribution;
        }
      }
      for (let i = 0; i < h.length; i++) {
        for (let axis = 0; axis < 2; axis++) {
          const j = axis === 0 ? this.east[i] : this.north[i];
          const faceThickness = 0.5 * (h[i] + h[j]);
          const exchange = faceThickness ** 3 / (3 * this.fixedViscosity) * (pressure[j] - pressure[i]) * invDxSquared;
          rates[i] += exchange;
          rates[j] -= exchange;
        }
      }
    }

    levelingStep(remainingTime) {
      let maximum = 0;
      for (const value of this.h) maximum = Math.max(maximum, value);
      let dt = Math.min(remainingTime, this.stableStep(maximum));
      this.flowRates(this.h, this.ratesFirst);
      for (let attempt = 0; attempt < 40; attempt++) {
        const valid = this.computeLevelingCandidate(dt);
        if (valid) {
          let minimum = Infinity;
          for (const value of this.candidate) minimum = Math.min(minimum, value);
          const evaporationRate = this.config.evaporationNmS * NANOMETER;
          if (minimum - evaporationRate * dt <= MIN_WET_THICKNESS) {
            let lower = 0;
            let upper = dt;
            for (let iteration = 0; iteration < 45; iteration++) {
              const middle = (lower + upper) / 2;
              const validTrial = this.computeLevelingCandidate(middle);
              let trialMinimum = Infinity;
              for (const value of this.candidate) trialMinimum = Math.min(trialMinimum, value);
              if (validTrial && trialMinimum - evaporationRate * middle > MIN_WET_THICKNESS) lower = middle;
              else upper = middle;
            }
            dt = upper;
            this.computeLevelingCandidate(dt);
            this.terminationReason = WET_LIMIT_MESSAGE;
            this.warnings.push(this.terminationReason);
          }
          const evaporationLoss = evaporationRate * dt;
          for (let i = 0; i < this.h.length; i++) this.candidate[i] -= evaporationLoss;
          this.evaporatedThickness += evaporationLoss;
          this.h.set(this.candidate);
          return dt;
        }
        this.rejectedSteps++;
        dt *= 0.5;
        if (this.time + dt === this.time) break;
      }
      throw new Error('正の膜厚を維持できず計算を停止しました。膜厚・基板段差・初期凹凸・分割数を見直してください。');
    }

    computeLevelingCandidate(dt) {
      for (let i = 0; i < this.h.length; i++) {
        this.intermediate[i] = this.h[i] + dt * this.ratesFirst[i];
        if (!(this.intermediate[i] > 0) || !Number.isFinite(this.intermediate[i])) return false;
      }
      this.flowRates(this.intermediate, this.ratesSecond);
      for (let i = 0; i < this.h.length; i++) {
        this.candidate[i] = this.h[i] + 0.5 * dt * (this.ratesFirst[i] + this.ratesSecond[i]);
        if (!(this.candidate[i] > 0) || !Number.isFinite(this.candidate[i])) return false;
      }
      return true;
    }

    spinDerivative(state) {
      const h = state[0];
      const solute = state[1];
      if (!(h > 0) || solute < 0 || solute > h || !Number.isFinite(h + solute)) return null;
      const phi = solute / h;
      const angularVelocity = this.config.rpm * 2 * Math.PI / 60;
      const drain = 2 * this.config.densityKgM3 * angularVelocity ** 2 * h ** 3 /
        (3 * viscosity(this.config, phi));
      const evaporation = this.config.evaporationNmS * NANOMETER * (1 - phi);
      return [-drain - evaporation, -phi * drain, evaporation, drain, phi * drain];
    }

    rk4(state, dt) {
      const k1 = this.spinDerivative(state);
      if (!k1) return null;
      const stage = (base, derivative, factor) => base.map((value, i) => value + derivative[i] * factor);
      const k2 = this.spinDerivative(stage(state, k1, dt / 2));
      if (!k2) return null;
      const k3 = this.spinDerivative(stage(state, k2, dt / 2));
      if (!k3) return null;
      const k4 = this.spinDerivative(stage(state, k3, dt));
      if (!k4) return null;
      const candidate = state.map((value, i) => value + dt * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i]) / 6);
      return this.spinDerivative(candidate) ? candidate : null;
    }

    spinStep(remainingTime) {
      const state = [this.h[0], this.soluteThickness, this.evaporatedThickness, this.drainedThickness, this.soluteOutflow];
      let dt = Math.min(remainingTime, this.spinNextStep);
      const relativeTolerance = 1e-7 * this.config.accuracy;
      const absoluteTolerance = Math.max(this.initialMean * 1e-12, 1e-18);
      for (let attempt = 0; attempt < 60; attempt++) {
        const full = this.rk4(state, dt);
        const firstHalf = this.rk4(state, dt / 2);
        const twoHalves = firstHalf ? this.rk4(firstHalf, dt / 2) : null;
        let error = Infinity;
        if (full && twoHalves) {
          error = 0;
          for (let i = 0; i < 2; i++) {
            const tolerance = absoluteTolerance + relativeTolerance * Math.max(Math.abs(state[i]), Math.abs(twoHalves[i]));
            error = Math.max(error, Math.abs(twoHalves[i] - full[i]) / (15 * tolerance));
          }
        }
        if (error <= 1) {
          let acceptedState = twoHalves;
          if (twoHalves[1] / twoHalves[0] >= MAX_LIQUID_SOLIDS_FRACTION || twoHalves[0] <= MIN_WET_THICKNESS) {
            // Resolve the dry-limit crossing in time before accepting the final state.
            let lower = 0;
            let upper = dt;
            for (let iteration = 0; iteration < 45; iteration++) {
              const middle = (lower + upper) / 2;
              const middleHalf = this.rk4(state, middle / 2);
              const middleState = middleHalf ? this.rk4(middleHalf, middle / 2) : null;
              if (middleState && middleState[1] / middleState[0] < MAX_LIQUID_SOLIDS_FRACTION && middleState[0] > MIN_WET_THICKNESS) lower = middle;
              else upper = middle;
            }
            dt = upper;
            const eventHalf = this.rk4(state, dt / 2);
            acceptedState = this.rk4(eventHalf, dt / 2);
            this.terminationReason = acceptedState[0] <= MIN_WET_THICKNESS * (1 + 1e-10) ? WET_LIMIT_MESSAGE :
              '固形分率が 99% に達したため計算を停止しました。ゲル化・乾燥後の固体はこの液体モデルの対象外です。';
            this.warnings.push(this.terminationReason);
          }
          this.h[0] = acceptedState[0];
          this.soluteThickness = acceptedState[1];
          this.evaporatedThickness = acceptedState[2];
          this.drainedThickness = acceptedState[3];
          this.soluteOutflow = acceptedState[4];
          const growth = error === 0 ? 2 : Math.min(2, Math.max(0.2, 0.9 * error ** -0.2));
          this.spinNextStep = dt * growth;
          return dt;
        }
        this.rejectedSteps++;
        dt *= Number.isFinite(error) ? Math.max(0.1, Math.min(0.5, 0.9 * error ** -0.2)) : 0.5;
        if (this.time + dt === this.time) break;
      }
      throw new Error('回転塗布の時間刻みを確保できず計算を停止しました。回転数・蒸発速度・初期膜厚を見直してください。');
    }

    advance(targetTime, maxSteps) {
      const requestedTime = Number(targetTime);
      const stepBudget = maxSteps === undefined ? 2000 : Number(maxSteps);
      if (!Number.isFinite(requestedTime) || requestedTime < this.time) throw new Error('到達時刻は現在時刻以降の数値で指定してください。');
      if (!Number.isInteger(stepBudget) || stepBudget < 1 || stepBudget > MAX_TOTAL_STEPS) throw new Error('1 回の計算ステップ数は 1 ～ 1000000 の整数で指定してください。');
      const target = Math.min(requestedTime, this.config.durationS);
      if (this.time < target && !this.done) {
        let minimum = Infinity;
        for (const value of this.h) minimum = Math.min(minimum, value);
        if (minimum <= MIN_WET_THICKNESS) {
          this.terminationReason = WET_LIMIT_MESSAGE;
          this.warnings.push(this.terminationReason);
          throw new Error(this.terminationReason);
        }
      }
      let accepted = 0;
      while (this.time < target && accepted < stepBudget && !this.done) {
        if (this.steps >= MAX_TOTAL_STEPS) throw new Error('計算が100万ステップに達しました。分割数・計算時間・膜厚を小さくして再実行してください。');
        const remaining = target - this.time;
        const dt = this.config.mode === 'spin' ? this.spinStep(remaining) : this.levelingStep(remaining);
        if ((!(dt > 0) || this.time + dt === this.time) && !this.terminationReason) {
          throw new Error('時間刻みが小さすぎるため計算を停止しました。計算条件を見直してください。');
        }
        this.time = dt === remaining ? target : this.time + dt;
        this.lastStepS = dt;
        this.steps++;
        accepted++;
        if (this.terminationReason) throw new Error(this.terminationReason);
      }
      return { reachedTarget: this.time >= target, done: this.done, steps: accepted, time: this.time };
    }

    getSnapshot() {
      const stats = fieldStats(this.h);
      const expectedMean = this.initialMean - this.evaporatedThickness - this.drainedThickness;
      const phi = this.config.mode === 'spin' ? this.soluteThickness / this.h[0] : null;
      return {
        time: this.time, n: this.n, lengthUm: this.config.lengthUm,
        h: Array.from(this.h, value => value / MICROMETER),
        b: Array.from(this.b, value => value / MICROMETER),
        hUnit: 'um', bUnit: 'um', mode: this.config.mode, done: this.done,
        terminationReason: this.terminationReason,
        stats: {
          meanUm: stats.mean / MICROMETER, minUm: stats.minimum / MICROMETER,
          maxUm: stats.maximum / MICROMETER, cvPercent: stats.cv * 100,
          volumeUm3: stats.mean / MICROMETER * this.config.lengthUm ** 2,
          massErrorPercent: 100 * (stats.mean - expectedMean) / this.initialMean,
          soluteBalanceErrorPercent: phi === null ? null :
            100 * (this.soluteThickness + this.soluteOutflow - this.initialSolute) / this.initialSolute,
          solidsPercent: phi === null ? null : phi * 100,
          viscosityPaS: viscosity(this.config, phi), steps: this.steps,
          rejectedSteps: this.rejectedSteps, lastStepS: this.lastStepS,
          evaporatedUm: this.evaporatedThickness / MICROMETER,
          drainedUm: this.drainedThickness / MICROMETER
        },
        warnings: this.warnings.slice()
      };
    }
  }

  return Object.freeze({
    DEFAULTS, validateConfig,
    createSimulation: config => new Simulation(config),
    constants: Object.freeze({ MIN_WET_THICKNESS_UM: MIN_WET_THICKNESS / MICROMETER, MAX_LIQUID_SOLIDS_FRACTION, MAX_TOTAL_STEPS })
  });
});
