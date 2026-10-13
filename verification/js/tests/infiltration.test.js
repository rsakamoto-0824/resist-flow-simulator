'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { DEFAULTS, validateConfig, createSimulation } = require('../../../macos/web/infiltration.js');

function close(actual, expected, tolerance = Math.max(1, Math.abs(expected)) * 1e-12) {
  assert.ok(Number.isFinite(actual), `non-finite result: ${actual}`);
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} versus ${expected}`);
}

function at(config, time) {
  const simulation = createSimulation(config);
  simulation.advance(time, 1);
  return simulation.getSnapshot();
}

test('slit filling starts empty and does not invent a finite onset velocity', () => {
  const simulation = createSimulation({});
  const snapshot = simulation.getSnapshot();
  assert.deepEqual(snapshot.h, [0]);
  assert.deepEqual(snapshot.b, [0]);
  assert.equal(snapshot.stats.fillPercent, 0);
  assert.ok(Number.isNaN(snapshot.stats.frontSpeedUmS));
  assert.equal(snapshot.filled, false);
  assert.equal(simulation.done, false);
  assert.ok(snapshot.warnings.some(warning => warning.includes('慣性')));
});

test('capillary infiltration matches the parallel-plate Washburn coefficient and units', () => {
  const result = at({ gapUm: 0.2, depthUm: 100, contactAngleDeg: 0 }, 1e-6);
  const expectedUm = Math.sqrt(4.8e6 * 1e-6);
  close(result.stats.capillaryPressurePa, 720000);
  close(result.h[0], expectedUm);
  close(result.stats.frontSpeedUmS, expectedUm / (2e-6));
  close(result.stats.volumeUm3, 0.2 * expectedUm);
  assert.equal(result.lengthUm, 0.2);
  assert.equal(result.stats.channelWidthUm, 1);
});

test('imposed pressure gives the parallel-slit factor six at exactly neutral wetting', () => {
  const result = at({ gapUm: 2, depthUm: 100, contactAngleDeg: 90,
    externalPressurePa: 1200, viscosityPaS: 0.01 }, 1e-4);
  assert.equal(result.stats.capillaryPressurePa, 0);
  close(result.h[0], Math.sqrt(8));
});

test('penetration scales with square roots of time, capillary gap, and inverse viscosity', () => {
  const base = { depthUm: 1000, durationS: 1 };
  const original = at(base, 1e-6).h[0];
  close(at(base, 4e-6).h[0], original * 2);
  close(at({ ...base, viscosityPaS: DEFAULTS.viscosityPaS * 4 }, 1e-6).h[0], original / 2);
  close(at({ ...base, gapUm: DEFAULTS.gapUm * 4 }, 1e-6).h[0], original * 2);
});

test('neutral and nonwetting empty slits remain blocked without a fill-time prediction', () => {
  for (const angle of [90, 120, 180]) {
    const result = at({ contactAngleDeg: angle }, DEFAULTS.durationS);
    assert.equal(result.h[0], 0);
    assert.equal(result.stats.frontSpeedUmS, 0);
    assert.ok(Number.isNaN(result.stats.fillTimeS));
    assert.equal(result.filled, false);
    assert.equal(result.done, true);
    assert.ok(result.warnings.some(warning => warning.includes('浸透しません')));
  }
});

test('external pressure overcomes nonwetting resistance only above its entry pressure', () => {
  const base = { contactAngleDeg: 120, depthUm: 100 };
  const result = at({ ...base, externalPressurePa: 400000 }, 1e-5);
  close(result.stats.capillaryPressurePa, -360000);
  close(result.stats.drivingPressurePa, 40000);
  assert.ok(result.h[0] > 0);
  assert.equal(at({ ...base, externalPressurePa: 350000 }, 1e-5).h[0], 0);
});

test('pressure cancellation suppresses roundoff leakage but preserves physical excess pressure', () => {
  const base = { contactAngleDeg: 60 };
  const pressure = at(base, 0).stats.capillaryPressurePa;
  const ulp = 2 ** (Math.floor(Math.log2(pressure)) - 52);
  for (const offset of [-16, 0, 16]) {
    const result = at({ ...base, externalPressurePa: -pressure + offset * ulp }, 1e-4);
    assert.equal(result.stats.drivingPressurePa, 0);
    assert.equal(result.h[0], 0);
  }
  assert.ok(at({ ...base, externalPressurePa: -pressure + 32 * ulp }, 1e-4).h[0] > 0);
});

test('filled slits hold their length and volume while simulation time continues', () => {
  const simulation = createSimulation({});
  const fillTime = simulation.getSnapshot().stats.fillTimeS;
  simulation.advance(fillTime / 2, 1);
  close(simulation.getSnapshot().h[0], DEFAULTS.depthUm / Math.sqrt(2));
  assert.equal(simulation.getSnapshot().filled, false);
  simulation.advance(fillTime, 1);
  const filled = simulation.getSnapshot();
  assert.equal(filled.filled, true);
  close(filled.h[0], DEFAULTS.depthUm);
  close(filled.stats.fillPercent, 100);
  assert.equal(filled.stats.frontSpeedUmS, 0);
  simulation.advance(fillTime * 2, 1);
  const later = simulation.getSnapshot();
  assert.equal(later.h[0], filled.h[0]);
  assert.equal(later.stats.volumeUm3, filled.stats.volumeUm3);
  assert.equal(simulation.done, false);
  const progress = simulation.advance(DEFAULTS.durationS * 2, 1);
  assert.deepEqual(progress, { reachedTarget: true, done: true, steps: 0, time: DEFAULTS.durationS });
});

test('temperature-dependent viscosity changes fill time by the same Arrhenius factor', () => {
  const base = { viscosityPaS: 0.1, activationKJMol: 30 };
  const cold = at(base, 0);
  const warm = at({ ...base, temperatureC: 60 }, 0);
  const ratio = Math.exp(30000 / 8.314462618 * (1 / 333.15 - 1 / 298.15));
  close(warm.stats.viscosityPaS, 0.1 * ratio);
  close(warm.stats.fillTimeS / cold.stats.fillTimeS, ratio);
});

test('validation normalizes decimal strings and preserves shared fields without modifying input', () => {
  const input = { gapUm: '0.5', depthUm: '8', durationS: '1e-5', rpm: 2000, customHeightUm: [1, 2] };
  const config = validateConfig(input);
  assert.equal(config.mode, 'infiltration');
  assert.equal(config.gapUm, 0.5);
  assert.equal(config.depthUm, 8);
  assert.equal(config.durationS, 1e-5);
  assert.equal(config.rpm, 2000);
  assert.deepEqual(config.customHeightUm, [1, 2]);
  assert.equal(input.gapUm, '0.5');
});

test('malformed and nonphysical scalar inputs are rejected', () => {
  for (const input of [null, undefined, [], 1, true, 'text', new Date(), new Float64Array(2)]) {
    assert.throws(() => validateConfig(input));
  }
  const invalid = {
    gapUm: [0, 101, [], [0.2], new Float64Array([0.2]), true, null, ' ', '0x1', 'bad'],
    depthUm: [-1, 100001], contactAngleDeg: [-1, 181, NaN], externalPressurePa: [Infinity, -1000001, 1000001],
    viscosityPaS: [0, true], surfaceTensionMnM: [-1], temperatureC: [-273.15, 251],
    activationKJMol: [-1, 151], durationS: [0, 1e-13, 36001]
  };
  for (const [key, values] of Object.entries(invalid)) {
    for (const value of values) assert.throws(() => validateConfig({ [key]: value }), `${key}: ${value}`);
  }
  assert.throws(() => validateConfig({ mode: 'spin' }));
  assert.throws(() => validateConfig({ mode: ['infiltration'] }));
});

test('advance rejects malformed time, backward travel, and invalid computation budgets', () => {
  const simulation = createSimulation({});
  for (const time of [-1, NaN, Infinity, [], [1], true, '0.1', null]) {
    assert.throws(() => simulation.advance(time, 1));
  }
  for (const budget of [0, -1, 1.5, 1000001, Infinity, NaN, [], true, '1', null]) {
    assert.throws(() => simulation.advance(1e-6, budget));
  }
  assert.equal(simulation.time, 0);
  simulation.advance(1e-6);
  assert.throws(() => simulation.advance(0));
  assert.equal(simulation.time, 1e-6);
});

test('snapshots do not alias previous results and include geometric model warnings', () => {
  const simulation = createSimulation({ gapUm: 0.005, depthUm: 0.02 });
  const initial = simulation.getSnapshot();
  initial.h[0] = 999;
  initial.warnings[0] = 'modified';
  const next = simulation.getSnapshot();
  assert.equal(next.h[0], 0);
  assert.ok(!next.warnings.includes('modified'));
  assert.ok(next.warnings.some(warning => warning.includes('10 nm')));
  assert.ok(next.warnings.some(warning => warning.includes('入口・出口')));
  assert.equal(next.stats.steps, 0);
  assert.equal(next.stats.massErrorPercent, 0);
  assert.ok(Number.isNaN(next.stats.solidsPercent));
});
