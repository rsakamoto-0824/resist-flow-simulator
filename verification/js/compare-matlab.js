'use strict';

const fs = require('node:fs');
const path = require('node:path');
const solver = require('./solver.js');
const infiltration = require('../../macos/web/infiltration.js');

const DEFAULT_FIXTURE = path.resolve(__dirname, '../../output/mac-test/matlab-parity.json');
const HEIGHT_TOLERANCE_UM = 1e-6;
const MAX_BATCHES = 1000;
const STEP_BUDGET = 2000;
const STATS_TOLERANCES = {
  meanUm: [1e-6, 0], minUm: [1e-6, 0], maxUm: [1e-6, 0], cvPercent: [1e-6, 1e-6],
  solidsPercent: [1e-6, 1e-6], viscosityPaS: [1e-12, 1e-6], volumeUm3: [1e-8, 1e-6],
  massErrorPercent: [1e-8, 0], soluteBalanceErrorPercent: [1e-8, 0],
  evaporatedUm: [1e-6, 0], drainedUm: [1e-6, 0], penetrationUm: [1e-6, 0],
  fillPercent: [1e-6, 1e-6], capillaryPressurePa: [1e-6, 1e-6],
  drivingPressurePa: [1e-6, 1e-6], fillTimeS: [1e-12, 1e-6],
  frontSpeedUmS: [1e-6, 1e-6], channelWidthUm: [0, 0]
};

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function compareNumber(actual, expected, label, absoluteTolerance, relativeTolerance = 0) {
  if (expected === null) {
    assert(actual === null || Number.isNaN(actual), `${label}: expected an undefined model value, got ${actual}`);
    return;
  }
  assert(typeof actual === 'number' && Number.isFinite(actual), `${label}: invalid JavaScript value ${actual}`);
  assert(typeof expected === 'number' && Number.isFinite(expected), `${label}: invalid MATLAB fixture value ${expected}`);
  const tolerance = absoluteTolerance + relativeTolerance * Math.abs(expected);
  assert(Math.abs(actual - expected) <= tolerance,
    `${label}: JavaScript ${actual}, MATLAB ${expected}, tolerance ${tolerance}`);
}

function compareField(actual, expected, label) {
  assert(Array.isArray(actual) && Array.isArray(expected), `${label}: both fields must be row-major arrays`);
  assert(actual.length === expected.length, `${label}: mismatched field lengths`);
  let maximumError = 0;
  for (let index = 0; index < actual.length; index++) {
    compareNumber(actual[index], expected[index], `${label}[${index}]`, HEIGHT_TOLERANCE_UM);
    maximumError = Math.max(maximumError, Math.abs(actual[index] - expected[index]));
  }
  return maximumError;
}

function compareCase(record) {
  const api = record.config.mode === 'infiltration' ? infiltration : solver;
  const simulation = api.createSimulation(record.config);
  let batches = 0;
  while (simulation.time < record.targetTimeS && !simulation.done) {
    simulation.advance(record.targetTimeS, STEP_BUDGET);
    assert(++batches <= MAX_BATCHES, `${record.name}: exceeded the step budget`);
  }
  const actual = simulation.getSnapshot();
  const expected = record.expected;
  const label = record.name;
  for (const key of ['n', 'mode', 'done', 'hUnit', 'bUnit']) {
    assert(actual[key] === expected[key], `${label}.${key}: ${actual[key]} versus ${expected[key]}`);
  }
  if (Object.hasOwn(expected, 'filled')) {
    assert(actual.filled === expected.filled, `${label}.filled: inconsistent filling state`);
  }
  compareNumber(actual.time, record.targetTimeS, `${label}.targetTime`, 1e-12);
  compareNumber(actual.time, expected.time, `${label}.time`, 1e-12);
  compareNumber(actual.lengthUm, expected.lengthUm, `${label}.lengthUm`, 1e-12);
  assert(expected.flatH.length === actual.n * actual.n, `${label}: incorrect MATLAB grid size`);
  const maximumHeightError = compareField(actual.h, expected.flatH, `${label}.h`);
  const maximumSubstrateError = compareField(actual.b, expected.flatB, `${label}.b`);
  for (const [key, tolerance] of Object.entries(STATS_TOLERANCES)) {
    if (Object.hasOwn(expected.stats, key)) {
      compareNumber(actual.stats[key], expected.stats[key], `${label}.${key}`, ...tolerance);
    }
  }
  return { name: label, maximumHeightError, maximumSubstrateError };
}

function main() {
  const fixturePath = process.argv[2] ? path.resolve(process.argv[2]) : DEFAULT_FIXTURE;
  const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
  assert(fixture.schemaVersion === 1 && fixture.producer === 'MATLAB' && fixture.matrixOrder === 'row-major',
    'Unsupported fixture. Generate it with verification/exportParityFixtures.m.');
  assert(Array.isArray(fixture.cases) && fixture.cases.length > 0, 'MATLAB fixture contains no cases.');
  const modes = new Set(fixture.cases.map(record => record.config.mode));
  assert(['leveling', 'spin', 'infiltration'].every(mode => modes.has(mode)), 'MATLAB fixture must cover all three models.');
  let maximumError = 0;
  for (const record of fixture.cases) {
    const result = compareCase(record);
    maximumError = Math.max(maximumError, result.maximumHeightError);
    console.log(`PASS ${result.name}: maximum height error ${result.maximumHeightError.toExponential(3)} µm; substrate ${result.maximumSubstrateError.toExponential(3)} µm`);
  }
  console.log(`PASS ${fixture.cases.length} cases against MATLAB ${fixture.matlabRelease}; maximum height error ${maximumError.toExponential(3)} µm (limit ${HEIGHT_TOLERANCE_UM} µm).`);
}

try {
  main();
} catch (error) {
  console.error(`MATLAB parity check failed: ${error.message}`);
  process.exitCode = 1;
}
