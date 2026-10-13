'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { DEFAULTS, createSimulation, validateConfig } = require('../solver.js');

const MICROMETER = 1e-6;
const NANOMETER = 1e-9;
const BASE = {
  ...DEFAULTS, mode: 'leveling', n: 16, lengthUm: 100,
  thicknessUm: 1, amplitudeUm: 0, pattern: 'flat',
  substrateUm: 0, substratePattern: 'flat', viscosityPaS: 1,
  surfaceTensionMnM: 30, temperatureC: 25, activationKJMol: 0,
  evaporationNmS: 0, concentrationFactor: 0, durationS: 0.1, accuracy: 1
};

function close(actual, expected, tolerance, description) {
  assert.ok(Number.isFinite(actual), `${description}: non-finite value ${actual}`);
  assert.ok(Math.abs(actual - expected) <= tolerance,
    `${description}: ${actual} versus ${expected}, tolerance ${tolerance}`);
}

function finish(config) {
  const simulation = createSimulation({ ...BASE, ...config });
  for (let batch = 0; !simulation.done; batch++) {
    assert.ok(batch < 1000, 'simulation must finish within its documented step budget');
    simulation.advance(simulation.config.durationS, 1000);
  }
  return simulation.getSnapshot();
}

function periodicField(n, valueAt) {
  return Array.from({ length: n * n }, (_, index) =>
    valueAt(index % n, Math.floor(index / n)));
}

function surfaceEnergy(snapshot) {
  const { h, b, n } = snapshot;
  let energy = 0;
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const index = y * n + x;
      const east = y * n + (x + 1) % n;
      const north = ((y + 1) % n) * n + x;
      const surface = h[index] + b[index];
      energy += (h[east] + b[east] - surface) ** 2;
      energy += (h[north] + b[north] - surface) ** 2;
    }
  }
  // Constant positive factors cancel when comparing the same periodic grid.
  return energy;
}

function modeAmplitude(snapshot, waveX, waveY) {
  const { n, h } = snapshot;
  let projection = 0;
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const phase = 2 * Math.PI * (waveX * (x + 0.5) + waveY * (y + 0.5)) / n;
      projection += (h[y * n + x] - 1) * Math.cos(phase);
    }
  }
  return 2 * projection / (n * n);
}

function fourierCase(n, accuracy = 1) {
  const waveX = 2;
  const waveY = 1;
  const amplitudeUm = 0.00001;
  const length = BASE.lengthUm * MICROMETER;
  const diffusion = BASE.surfaceTensionMnM * 0.001 * MICROMETER ** 3 /
    (3 * BASE.viscosityPaS);
  const waveSquared = (2 * Math.PI / length) ** 2 * (waveX ** 2 + waveY ** 2);
  const durationS = 0.4 / (diffusion * waveSquared ** 2);
  const height = periodicField(n, (x, y) => 1 + amplitudeUm * Math.cos(
    2 * Math.PI * (waveX * (x + 0.5) + waveY * (y + 0.5)) / n));
  const result = finish({ n, pattern: 'custom', customHeightUm: height, durationS, accuracy });
  const dx = length / n;
  const discreteWaveSquared = 4 / dx ** 2 *
    (Math.sin(Math.PI * waveX / n) ** 2 + Math.sin(Math.PI * waveY / n) ** 2);
  return {
    result,
    amplitude: modeAmplitude(result, waveX, waveY),
    continuum: amplitudeUm * Math.exp(-diffusion * waveSquared ** 2 * durationS),
    discrete: amplitudeUm * Math.exp(-diffusion * discreteWaveSquared ** 2 * durationS),
    initialAmplitude: amplitudeUm
  };
}

test('a spatially uniform film remains stationary without forcing', () => {
  const snapshot = finish({ durationS: 0.25, thicknessUm: 1.4 });
  snapshot.h.forEach(value => close(value, 1.4, 2e-14, 'uniform thickness'));
  close(snapshot.stats.cvPercent, 0, 1e-10, 'uniformity');
  close(snapshot.stats.volumeUm3, 1.4 * BASE.lengthUm ** 2, 1e-8, 'volume and units');
  close(snapshot.stats.massErrorPercent, 0, 1e-10, 'volume balance');
  close(snapshot.time, 0.25, 1e-14, 'final physical time');
});

test('a flat free surface is an equilibrium over nonflat substrate', () => {
  const n = 16;
  const substrate = periodicField(n, (x, y) => 0.12 * Math.cos(2 * Math.PI * x / n) +
    0.08 * Math.sin(2 * Math.PI * y / n));
  const height = substrate.map(value => 1 - value);
  const snapshot = finish({ n, pattern: 'custom', customHeightUm: height,
    customSubstrateUm: substrate, durationS: 0.2 });
  snapshot.h.forEach((value, index) => close(value, height[index], 2e-13, 'equilibrium thickness'));
  close(snapshot.stats.massErrorPercent, 0, 1e-10, 'equilibrium volume');
});

test('2D nonlinear leveling conserves volume and dissipates capillary energy', () => {
  const simulation = createSimulation({ ...BASE, pattern: 'gaussian', amplitudeUm: 0.5,
    substratePattern: 'sine', substrateUm: 0.08, durationS: 0.4 });
  const initial = simulation.getSnapshot();
  let previousEnergy = surfaceEnergy(initial);
  for (const targetTime of [0.08, 0.16, 0.24, 0.32, 0.4]) {
    while (simulation.time < targetTime) simulation.advance(targetTime, 1000);
    const snapshot = simulation.getSnapshot();
    const energy = surfaceEnergy(snapshot);
    assert.ok(energy <= previousEnergy * (1 + 1e-10), 'capillary energy must not increase');
    close(snapshot.stats.volumeUm3, initial.stats.volumeUm3, initial.stats.volumeUm3 * 1e-11, 'conserved volume');
    close(snapshot.stats.massErrorPercent, 0, 1e-9, 'mass residual');
    assert.ok(snapshot.h.every(value => Number.isFinite(value) && value > 0), 'positive finite film');
    previousEnergy = energy;
  }
  assert.ok(previousEnergy < surfaceEnergy(initial) * 0.95, 'test must exercise actual flow');
});

test('2D Fourier mode follows the analytical small-amplitude decay of the discrete operator', () => {
  const solution = fourierCase(16);
  close(solution.amplitude, solution.discrete, solution.initialAmplitude * 0.00002, 'Fourier amplitude');
});

test('spatial refinement approaches the continuum Fourier solution', () => {
  const coarse = fourierCase(16, 0.25);
  const fine = fourierCase(32, 0.25);
  const coarseError = Math.abs(coarse.amplitude - coarse.continuum);
  const fineError = Math.abs(fine.amplitude - fine.continuum);
  assert.ok(fineError < coarseError * 0.35,
    `second-order spatial convergence: coarse ${coarseError}, fine ${fineError}`);
});

test('smaller time steps improve Fourier decay independently of spatial error', () => {
  const coarse = fourierCase(16, 1);
  const fine = fourierCase(16, 0.25);
  const coarseError = Math.abs(coarse.amplitude - coarse.discrete);
  const fineError = Math.abs(fine.amplitude - fine.discrete);
  assert.ok(fineError < coarseError * 0.2,
    `second-order time convergence: coarse ${coarseError}, fine ${fineError}`);
});

test('periodic flow treats both lateral axes symmetrically', () => {
  const n = 16;
  const original = periodicField(n, (x, y) => 1 + 0.12 * Math.cos(4 * Math.PI * x / n) +
    0.07 * Math.sin(2 * Math.PI * y / n));
  const transposed = periodicField(n, (x, y) => original[x * n + y]);
  const first = finish({ n, pattern: 'custom', customHeightUm: original, durationS: 0.2 });
  const second = finish({ n, pattern: 'custom', customHeightUm: transposed, durationS: 0.2 });
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      close(first.h[y * n + x], second.h[x * n + y], 2e-12, 'axis symmetry');
    }
  }
});

test('spin thinning without evaporation matches the Emslie analytical solution', () => {
  const config = { mode: 'spin', thicknessUm: 10, viscosityPaS: 0.01,
    rpm: 3000, densityKgM3: 1000, durationS: 10, solidsFraction: 0.2 };
  const initialHeight = config.thicknessUm * MICROMETER;
  const omega = 2 * Math.PI * config.rpm / 60;
  const expectedUm = initialHeight / Math.sqrt(1 + 4 * config.densityKgM3 * omega ** 2 *
    initialHeight ** 2 * config.durationS / (3 * config.viscosityPaS)) / MICROMETER;
  const snapshot = finish(config);
  close(snapshot.stats.meanUm, expectedUm, expectedUm * 2e-6, 'spin analytic thickness');
  close(snapshot.stats.solidsPercent, 20, 1e-10, 'non-evaporating concentration');
  close(snapshot.stats.massErrorPercent, 0, 1e-9, 'liquid balance including runoff');
  close(snapshot.stats.soluteBalanceErrorPercent, 0, 1e-9, 'polymer balance including runoff');
  assert.ok(snapshot.stats.drainedUm > 0, 'runoff must be recorded');
});

test('evaporation without rotation preserves polymer and matches its integrated analytical law', () => {
  const config = { mode: 'spin', thicknessUm: 2, rpm: 0, evaporationNmS: 100,
    solidsFraction: 0.2, durationS: 10 };
  const snapshot = finish(config);
  const h0 = config.thicknessUm * MICROMETER;
  const h = snapshot.stats.meanUm * MICROMETER;
  const solute = h0 * config.solidsFraction;
  // Integrating dh/dt = -E0(1 - a/h) for constant nonvolatile thickness a.
  const integratedLoss = h0 - h + solute * Math.log((h0 - solute) / (h - solute));
  close(integratedLoss, config.evaporationNmS * NANOMETER * config.durationS, 2e-12, 'integrated evaporation');
  close(snapshot.stats.meanUm * snapshot.stats.solidsPercent / 100,
    config.thicknessUm * config.solidsFraction, 2e-12, 'nonvolatile material');
  close(snapshot.stats.drainedUm, 0, 1e-15, 'zero runoff');
  close(snapshot.stats.massErrorPercent, 0, 1e-9, 'evaporation balance');
});

test('spin runoff and evaporation retain consistent liquid and polymer balances', () => {
  const snapshot = finish({ mode: 'spin', thicknessUm: 5, viscosityPaS: 0.02,
    rpm: 2000, evaporationNmS: 50, solidsFraction: 0.2,
    concentrationFactor: 8, durationS: 20 });
  close(snapshot.stats.massErrorPercent, 0, 1e-8, 'combined liquid balance');
  close(snapshot.stats.soluteBalanceErrorPercent, 0, 1e-8, 'combined polymer balance');
  assert.ok(snapshot.stats.solidsPercent > 20 && snapshot.stats.solidsPercent < 99, 'solvent loss enriches polymer');
  assert.ok(snapshot.stats.viscosityPaS > 0.02, 'concentration increases viscosity');
  assert.ok(snapshot.stats.meanUm * snapshot.stats.solidsPercent / 100 < 1, 'runoff carries polymer away');
});

test('uniform evaporation in leveling mode removes the prescribed volume', () => {
  const snapshot = finish({ thicknessUm: 1, evaporationNmS: 10, durationS: 2 });
  close(snapshot.stats.meanUm, 0.98, 2e-12, 'evaporated film');
  close(snapshot.stats.evaporatedUm, 0.02, 2e-12, 'recorded evaporation');
  close(snapshot.stats.massErrorPercent, 0, 1e-9, 'leveling evaporation balance');
});

test('the wet-thickness validity limit stops at its physical crossing time', () => {
  const simulation = createSimulation({ ...BASE, thicknessUm: 0.1,
    evaporationNmS: 100, durationS: 5 });
  assert.throws(() => simulation.advance(5, 1000000), /0\.01/);
  const snapshot = simulation.getSnapshot();
  close(snapshot.time, 0.9, 1e-10, 'wet-thickness crossing time');
  close(snapshot.stats.minUm, 0.01, 1e-12, 'wet-thickness crossing');
  close(snapshot.stats.massErrorPercent, 0, 1e-8, 'balance at early termination');
  assert.equal(snapshot.done, true);
  assert.match(snapshot.terminationReason, /0\.01/);
  assert.ok(snapshot.time < simulation.config.durationS, 'early termination is not presented as full duration');
});

test('the spin liquid-model limit stops at 99% solids and preserves polymer', () => {
  const simulation = createSimulation({ ...BASE, mode: 'spin', thicknessUm: 1,
    rpm: 0, evaporationNmS: 1000, solidsFraction: 0.2, durationS: 5, accuracy: 0.25 });
  assert.throws(() => simulation.advance(5, 1000000), /99%/);
  const snapshot = simulation.getSnapshot();
  const expectedHeightUm = 0.2 / 0.99;
  const expectedTime = 1 - expectedHeightUm + 0.2 * Math.log(0.8 / (expectedHeightUm - 0.2));
  close(snapshot.stats.solidsPercent, 99, 1e-9, 'liquid-model threshold');
  close(snapshot.stats.meanUm, expectedHeightUm, 2e-12, 'polymer conservation at threshold');
  close(snapshot.time, expectedTime, 2e-6, 'dry-limit crossing time');
  close(snapshot.stats.soluteBalanceErrorPercent, 0, 1e-8, 'polymer balance at threshold');
  assert.equal(snapshot.done, true);
  assert.match(snapshot.terminationReason, /99%/);
});

test('temperature response follows the specified reference-temperature viscosity law', () => {
  const temperatureC = 60;
  const activationKJMol = 30;
  const simulation = createSimulation({ ...BASE, viscosityPaS: 10, temperatureC, activationKJMol });
  const expected = 10 * Math.exp(activationKJMol * 1000 / 8.314462618 *
    (1 / (temperatureC + 273.15) - 1 / 298.15));
  close(simulation.getSnapshot().stats.viscosityPaS, expected, 1e-12, 'temperature-dependent viscosity');
});

test('incremental stepping honors its budget and returns detached snapshots', () => {
  const simulation = createSimulation({ ...BASE, durationS: 1, pattern: 'sine', amplitudeUm: 0.1 });
  const initial = simulation.getSnapshot();
  initial.h[0] = 1000;
  initial.b[0] = 1000;
  initial.warnings.push('external mutation');
  const unchanged = simulation.getSnapshot();
  assert.ok(unchanged.h[0] < 2 && unchanged.b[0] === 0, 'snapshot arrays must not alias the solver');
  assert.ok(!unchanged.warnings.includes('external mutation'), 'snapshot warnings must not alias the solver');
  const update = simulation.advance(1, 1);
  assert.equal(update.steps, 1);
  assert.ok(update.time > 0 && update.time < 1, 'single-step budget must yield control');
  assert.equal(update.done, false);
  assert.throws(() => simulation.advance(-1), /時刻/);
  assert.throws(() => simulation.advance(1, 0), /ステップ/);
});

test('invalid physics and malformed fields are rejected before simulation', () => {
  const invalidConfigs = [
    { viscosityPaS: 0 }, { viscosityPaS: NaN }, { surfaceTensionMnM: -1 },
    { densityKgM3: Infinity }, { durationS: 0 }, { n: 17 }, { rpm: -1 },
    { solidsFraction: 1.1 }, { evaporationNmS: -10 }, { temperatureC: -273.15 },
    { pattern: 'unknown' }, { pattern: 'custom' },
    { pattern: 'custom', customHeightUm: [1, 1] },
    { pattern: 'custom', customHeightUm: new Array(256).fill(-1) },
    { customSubstrateUm: new Array(256).fill(Infinity) },
    { pattern: 'sine', thicknessUm: 0.1, amplitudeUm: 1 }
  ];
  for (const invalid of invalidConfigs) {
    assert.throws(() => validateConfig({ ...BASE, ...invalid }), Error,
      `reject ${JSON.stringify(invalid)}`);
  }
  for (const invalid of [null, [], 'settings']) assert.throws(() => validateConfig(invalid), Error);
});
