classdef TestSimulation < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addSourcePath(testCase)
            sourceDirectory = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceDirectory));
        end
    end

    methods (Test)
        function uniformFilmRemainsStationary(testCase)
            result = finish(struct('durationS', 0.25, 'thicknessUm', 1.4));
            testCase.verifyEqual(result.h, 1.4 * ones(16), 'AbsTol', 2e-13);
            testCase.verifyEqual(result.stats.volumeUm3, 1.4e4, 'AbsTol', 1e-8);
            testCase.verifyEqual(result.stats.cvPercent, 0, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.stats.massErrorPercent, 0, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.time, 0.25, 'AbsTol', 1e-14);
        end

        function flatFreeSurfaceIsAnEquilibrium(testCase)
            [x, y] = meshgrid(0:15);
            substrate = 0.12 * cos(2*pi*x/16) + 0.08 * sin(2*pi*y/16);
            height = 1 - substrate;
            result = finish(struct('pattern', 'custom', 'customHeightUm', height, ...
                'customSubstrateUm', substrate, 'durationS', 0.2));
            testCase.verifyEqual(result.h, height, 'AbsTol', 2e-12);
            testCase.verifyEqual(result.stats.massErrorPercent, 0, 'AbsTol', 1e-9);
        end

        function nonlinearLevelingConservesVolumeAndLowersEnergy(testCase)
            simulation = resist.Simulation(configuration(struct('pattern', 'gaussian', ...
                'amplitudeUm', 0.5, 'substratePattern', 'sine', ...
                'substrateUm', 0.08, 'durationS', 0.4)));
            initial = simulation.getSnapshot();
            initialEnergy = capillaryEnergy(initial);
            previousEnergy = initialEnergy;
            for target = 0.08:0.08:0.4
                while simulation.time < target
                    simulation.advance(target, 1000);
                end
                result = simulation.getSnapshot();
                currentEnergy = capillaryEnergy(result);
                testCase.verifyLessThanOrEqual(currentEnergy, previousEnergy*(1+1e-10));
                testCase.verifyEqual(result.stats.volumeUm3, initial.stats.volumeUm3, ...
                    'AbsTol', initial.stats.volumeUm3*1e-10);
                testCase.verifyTrue(all(isfinite(result.h(:)) & result.h(:) > 0));
                previousEnergy = currentEnergy;
            end
            testCase.verifyLessThan(previousEnergy, 0.95*initialEnergy);
        end

        function fourierModeMatchesDiscreteAnalyticalDecay(testCase)
            solution = fourierCase(16, 1);
            testCase.verifyEqual(solution.amplitude, solution.discrete, 'AbsTol', 2e-10);
        end

        function spatialRefinementApproachesContinuumSolution(testCase)
            coarse = fourierCase(16, 0.25);
            fine = fourierCase(32, 0.25);
            testCase.verifyLessThan(abs(fine.amplitude-fine.continuum), ...
                0.35*abs(coarse.amplitude-coarse.continuum));
        end

        function timeRefinementImprovesDiscreteSolution(testCase)
            coarse = fourierCase(16, 1);
            fine = fourierCase(16, 0.25);
            testCase.verifyLessThan(abs(fine.amplitude-fine.discrete), ...
                0.2*abs(coarse.amplitude-coarse.discrete));
        end

        function lateralAxesAreSymmetric(testCase)
            [x, y] = meshgrid(0:15);
            height = 1 + 0.12*cos(4*pi*x/16) + 0.07*sin(2*pi*y/16);
            first = finish(struct('pattern', 'custom', 'customHeightUm', height, 'durationS', 0.2));
            second = finish(struct('pattern', 'custom', 'customHeightUm', height.', 'durationS', 0.2));
            testCase.verifyEqual(first.h, second.h.', 'AbsTol', 2e-12);
        end

        function spinMatchesAnalyticalThinning(testCase)
            config = struct('mode', 'spin', 'thicknessUm', 10, 'viscosityPaS', 0.01, ...
                'rpm', 3000, 'densityKgM3', 1000, 'durationS', 10, 'solidsFraction', 0.2);
            initialHeight = config.thicknessUm*1e-6;
            omega = 2*pi*config.rpm/60;
            expected = initialHeight/sqrt(1+4*config.densityKgM3*omega^2* ...
                initialHeight^2*config.durationS/(3*config.viscosityPaS))/1e-6;
            result = finish(config);
            testCase.verifyEqual(result.stats.meanUm, expected, 'RelTol', 2e-6);
            testCase.verifyEqual(result.stats.solidsPercent, 20, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.stats.massErrorPercent, 0, 'AbsTol', 1e-8);
            testCase.verifyEqual(result.stats.soluteBalanceErrorPercent, 0, 'AbsTol', 1e-8);
            testCase.verifyGreaterThan(result.stats.drainedUm, 0);
        end

        function evaporationMatchesIntegratedLaw(testCase)
            result = finish(struct('mode', 'spin', 'thicknessUm', 2, 'rpm', 0, ...
                'evaporationNmS', 100, 'solidsFraction', 0.2, 'durationS', 10));
            initialHeight = 2e-6;
            height = result.stats.meanUm*1e-6;
            solute = initialHeight*0.2;
            integratedLoss = initialHeight-height + solute*log((initialHeight-solute)/(height-solute));
            testCase.verifyEqual(integratedLoss, 100e-9*10, 'AbsTol', 2e-12);
            testCase.verifyEqual(result.stats.meanUm*result.stats.solidsPercent/100, 0.4, 'AbsTol', 2e-12);
            testCase.verifyEqual(result.stats.drainedUm, 0, 'AbsTol', 1e-15);
        end

        function combinedSpinAndEvaporationPreserveBalances(testCase)
            result = finish(struct('mode', 'spin', 'thicknessUm', 5, 'viscosityPaS', 0.02, ...
                'rpm', 2000, 'evaporationNmS', 50, 'solidsFraction', 0.2, ...
                'concentrationFactor', 8, 'durationS', 20));
            testCase.verifyEqual(result.stats.massErrorPercent, 0, 'AbsTol', 1e-8);
            testCase.verifyEqual(result.stats.soluteBalanceErrorPercent, 0, 'AbsTol', 1e-8);
            testCase.verifyGreaterThan(result.stats.solidsPercent, 20);
            testCase.verifyLessThan(result.stats.solidsPercent, 99);
            testCase.verifyGreaterThan(result.stats.viscosityPaS, 0.02);
        end

        function uniformEvaporationRemovesExpectedVolume(testCase)
            result = finish(struct('evaporationNmS', 10, 'durationS', 2));
            testCase.verifyEqual(result.stats.meanUm, 0.98, 'AbsTol', 2e-12);
            testCase.verifyEqual(result.stats.evaporatedUm, 0.02, 'AbsTol', 2e-12);
            testCase.verifyEqual(result.stats.massErrorPercent, 0, 'AbsTol', 1e-9);
        end

        function wetLimitStopsAtPhysicalTime(testCase)
            simulation = resist.Simulation(configuration(struct('thicknessUm', 0.1, ...
                'evaporationNmS', 100, 'durationS', 5)));
            testCase.verifyError(@() simulation.advance(5, 1000000), 'resist:ModelLimit');
            result = simulation.getSnapshot();
            testCase.verifyEqual(result.time, 0.9, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.stats.minUm, 0.01, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.stats.massErrorPercent, 0, 'AbsTol', 1e-8);
            testCase.verifyTrue(result.done);
            testCase.verifyNotEmpty(result.terminationReason);
        end

        function spinLimitPreservesSoluteAtPhysicalTime(testCase)
            simulation = resist.Simulation(configuration(struct('mode', 'spin', ...
                'thicknessUm', 1, 'rpm', 0, 'evaporationNmS', 1000, ...
                'solidsFraction', 0.2, 'durationS', 5, 'accuracy', 0.25)));
            testCase.verifyError(@() simulation.advance(5, 1000000), 'resist:ModelLimit');
            result = simulation.getSnapshot();
            expectedHeight = 0.2/0.99;
            expectedTime = 1-expectedHeight+0.2*log(0.8/(expectedHeight-0.2));
            testCase.verifyEqual(result.stats.solidsPercent, 99, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.stats.meanUm, expectedHeight, 'AbsTol', 2e-12);
            testCase.verifyEqual(result.time, expectedTime, 'AbsTol', 2e-6);
            testCase.verifyEqual(result.stats.soluteBalanceErrorPercent, 0, 'AbsTol', 1e-8);
            testCase.verifyTrue(result.done);
        end

        function flowWithoutEvaporationAlsoStopsAtWetLimit(testCase)
            simulation = resist.Simulation(configuration(struct('n', 16, ...
                'lengthUm', 1, 'thicknessUm', 0.011, 'pattern', 'flat', ...
                'amplitudeUm', 0, 'substratePattern', 'sine', 'substrateUm', 0.005, ...
                'evaporationNmS', 0, 'durationS', 0.1)));
            testCase.verifyError(@() simulation.advance(0.1, 1000000), 'resist:ModelLimit');
            result = simulation.getSnapshot();
            testCase.verifyEqual(result.stats.minUm, 0.01, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.stats.massErrorPercent, 0, 'AbsTol', 1e-8);
            testCase.verifyEqual(result.stats.evaporatedUm, 0, 'AbsTol', 1e-15);
            testCase.verifyGreaterThan(result.time, 0);
            testCase.verifyLessThan(result.time, 0.1);
            testCase.verifyTrue(result.done);
        end

        function temperatureUsesReferenceViscosity(testCase)
            simulation = resist.Simulation(configuration(struct('viscosityPaS', 10, ...
                'temperatureC', 60, 'activationKJMol', 30)));
            result = simulation.getSnapshot();
            expected = 10*exp(30000/8.314462618*(1/333.15-1/298.15));
            testCase.verifyEqual(result.stats.viscosityPaS, expected, 'AbsTol', 1e-12);
        end

        function incrementalStepHonorsBudgetAndSnapshotsAreDetached(testCase)
            simulation = resist.Simulation(configuration(struct('durationS', 1, ...
                'pattern', 'sine', 'amplitudeUm', 0.1)));
            snapshot = simulation.getSnapshot();
            snapshot.h(1) = 1000;
            current = simulation.getSnapshot();
            testCase.verifyLessThan(current.h(1), 2);
            progress = simulation.advance(1, 1);
            testCase.verifyEqual(progress.steps, 1);
            testCase.verifyGreaterThan(progress.time, 0);
            testCase.verifyLessThan(progress.time, 1);
            testCase.verifyFalse(progress.done);
            testCase.verifyError(@() simulation.advance(-1), 'resist:InvalidConfig');
            testCase.verifyError(@() simulation.advance(1, 0), 'resist:InvalidConfig');
        end

        function malformedPhysicsAndFieldsAreRejected(testCase)
            invalid = {struct('viscosityPaS', 0), struct('viscosityPaS', NaN), ...
                struct('surfaceTensionMnM', -1), struct('densityKgM3', Inf), ...
                struct('durationS', 0), struct('n', 17), struct('rpm', -1), ...
                struct('solidsFraction', 1.1), struct('evaporationNmS', -10), ...
                struct('temperatureC', -273.15), struct('pattern', 'unknown'), ...
                struct('pattern', 'custom'), ...
                struct('pattern', 'custom', 'customHeightUm', [1 1]), ...
                struct('pattern', 'custom', 'customHeightUm', -ones(16)), ...
                struct('customSubstrateUm', Inf(16)), ...
                struct('pattern', 'sine', 'thicknessUm', 0.1, 'amplitudeUm', 1)};
            for index = 1:numel(invalid)
                config = configuration(invalid{index});
                testCase.verifyError(@() resist.validateConfig(config), 'resist:InvalidConfig');
            end
        end
    end
end

function config = configuration(overrides)
config = resist.defaultConfig();
base = struct('mode', 'leveling', 'n', 16, 'lengthUm', 100, 'thicknessUm', 1, ...
    'amplitudeUm', 0, 'pattern', 'flat', 'substrateUm', 0, 'substratePattern', 'flat', ...
    'viscosityPaS', 1, 'surfaceTensionMnM', 30, 'temperatureC', 25, ...
    'activationKJMol', 0, 'evaporationNmS', 0, 'concentrationFactor', 0, ...
    'durationS', 0.1, 'accuracy', 1);
for values = {base, overrides}
    names = fieldnames(values{1});
    for index = 1:numel(names)
        config.(names{index}) = values{1}.(names{index});
    end
end
end

function result = finish(overrides)
simulation = resist.Simulation(configuration(overrides));
batches = 0;
while ~simulation.done
    batches = batches+1;
    assert(batches <= 1000, 'resist:TestBudget', 'Simulation did not finish within test budget.');
    simulation.advance(simulation.config.durationS, 1000);
end
result = simulation.getSnapshot();
end

function energy = capillaryEnergy(snapshot)
surface = snapshot.h+snapshot.b;
eastDifference = circshift(surface, [0 -1])-surface;
northDifference = circshift(surface, [-1 0])-surface;
energy = sum(eastDifference(:).^2+northDifference(:).^2);
end

function solution = fourierCase(n, accuracy)
[x, y] = meshgrid((0:n-1)+0.5);
phase = 2*pi*(2*x+y)/n;
initialAmplitude = 1e-5;
height = 1+initialAmplitude*cos(phase);
lengthM = 100e-6;
diffusion = 30e-3*(1e-6)^3/3;
waveSquared = (2*pi/lengthM)^2*5;
duration = 0.4/(diffusion*waveSquared^2);
result = finish(struct('n', n, 'pattern', 'custom', 'customHeightUm', height, ...
    'durationS', duration, 'accuracy', accuracy));
projection = (result.h-1).*cos(phase);
dx = lengthM/n;
discreteWaveSquared = 4/dx^2*(sin(2*pi/n)^2+sin(pi/n)^2);
solution = struct('amplitude', 2*sum(projection(:))/n^2, ...
    'continuum', initialAmplitude*exp(-diffusion*waveSquared^2*duration), ...
    'discrete', initialAmplitude*exp(-diffusion*discreteWaveSquared^2*duration));
end
