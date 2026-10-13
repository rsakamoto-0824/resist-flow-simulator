function outputPath = exportParityFixtures()
%EXPORTPARITYFIXTURES Export native MATLAB results for the macOS JavaScript port.
%   Run from MATLAB with addpath('verification'); exportParityFixtures();
%   Compare with node verification/js/compare-matlab.js from the project root.

verificationDirectory = fileparts(mfilename('fullpath'));
projectDirectory = fileparts(verificationDirectory);
originalPath = path;
restorePath = onCleanup(@() path(originalPath)); %#ok<NASGU>
addpath(fullfile(projectDirectory, 'matlab'));

leveling = resist.defaultConfig('leveling');
leveling.n = 16;
leveling.lengthUm = 80;
leveling.amplitudeUm = 0.2;
leveling.durationS = 0.15;

step = leveling;
step.pattern = 'flat';
step.amplitudeUm = 0;
step.substratePattern = 'step';
step.substrateUm = 0.3;
step.durationS = 0.1;

custom = leveling;
custom.pattern = 'custom';
custom.durationS = 0.08;
coordinate = ((0:custom.n-1) + 0.5) / custom.n;
[x, y] = meshgrid(coordinate, coordinate);
custom.customHeightUm = 1 + 0.08 * cos(2 * pi * x) + 0.04 * sin(4 * pi * y);
custom.customSubstrateUm = 0.03 * sin(2 * pi * x + 4 * pi * y);

spin = resist.defaultConfig('spin');
spin.thicknessUm = 5;
spin.pattern = 'flat';
spin.amplitudeUm = 0;
spin.viscosityPaS = 0.02;
spin.rpm = 2000;
spin.evaporationNmS = 100;
spin.solidsFraction = 0.2;
spin.concentrationFactor = 12;
spin.durationS = 10;

infiltration = resist.defaultConfig('infiltration');
infiltration.gapUm = 0.2;
infiltration.depthUm = 5;
infiltration.contactAngleDeg = 45;
infiltration.durationS = 1e-5;

cases = { ...
    'leveling-sine', leveling, leveling.durationS; ...
    'leveling-step', step, step.durationS; ...
    'leveling-custom-maps', custom, custom.durationS; ...
    'spin-evaporation', spin, spin.durationS; ...
    'infiltration-partial', infiltration, 1e-6; ...
    'infiltration-filled', infiltration, 1e-5};
records = cell(1, size(cases, 1));
maximumBatches = 1000;
stepBudget = 2000;
for index = 1:size(cases, 1)
    simulation = resist.Simulation(cases{index, 2});
    target = cases{index, 3};
    batches = 0;
    while simulation.time < target && ~simulation.done
        simulation.advance(target, stepBudget);
        batches = batches + 1;
        if batches > maximumBatches
            error('resist:ParityStepLimit', 'Parity case exceeded the step budget: %s', cases{index, 1});
        end
    end
    if simulation.time ~= target
        error('resist:ParityIncomplete', 'Parity case did not reach its target time: %s', cases{index, 1});
    end
    result = simulation.getSnapshot();
    exportedConfig = simulation.config;
    for name = {'customHeightUm', 'customSubstrateUm'}
        key = name{1};
        if isfield(exportedConfig, key) && ~isempty(exportedConfig.(key))
            exportedConfig.(key) = rowMajorArray(exportedConfig.(key));
        end
    end
    expected = struct('time', result.time, 'n', result.n, 'lengthUm', result.lengthUm, ...
        'mode', result.mode, 'done', result.done, 'hUnit', result.hUnit, 'bUnit', result.bUnit, ...
        'flatH', {rowMajorArray(result.h)}, 'flatB', {rowMajorArray(result.b)}, 'stats', result.stats);
    if isfield(result, 'filled')
        expected.filled = result.filled;
    end
    records{index} = struct('name', cases{index, 1}, 'config', exportedConfig, ...
        'targetTimeS', target, 'expected', expected);
end

fixture = struct('schemaVersion', 1, 'producer', 'MATLAB', ...
    'matlabRelease', version('-release'), 'matlabVersion', version, ...
    'matrixOrder', 'row-major', 'cases', {records});
outputDirectory = fullfile(projectDirectory, 'output', 'mac-test');
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
outputPath = fullfile(outputDirectory, 'matlab-parity.json');
fileId = fopen(outputPath, 'w', 'n', 'UTF-8');
if fileId < 0
    error('resist:ParityWriteFailed', 'Could not write MATLAB parity fixture: %s', outputPath);
end
closeFile = onCleanup(@() fclose(fileId)); %#ok<NASGU>
written = fprintf(fileId, '%s\n', jsonencode(fixture, 'PrettyPrint', true));
if written < 0
    error('resist:ParityWriteFailed', 'Could not write MATLAB parity fixture: %s', outputPath);
end
fprintf('Exported %d MATLAB parity cases: %s\n', numel(records), outputPath);
end

function values = rowMajorArray(matrix)
% A cell vector keeps even a one-element matrix as a JSON array.
values = num2cell(reshape(matrix.', 1, []));
end
