classdef TestInfiltration < matlab.unittest.TestCase
    % Analytical and boundary-condition checks for parallel-slit filling.

    methods (TestClassSetup)
        function addSourcePath(testCase)
            sourceDirectory = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceDirectory));
        end
    end

    methods (Test)
        function sharedSimulationDispatchesToTheAnalyticalModel(testCase)
            config = resist.defaultConfig('infiltration');
            config.durationS = 1e-7;
            simulation = resist.Simulation(config);
            initial = simulation.getSnapshot();
            testCase.verifyEqual(initial.h,0);
            progress = simulation.advance(config.durationS,1);
            result = simulation.getSnapshot();
            expected = resist.infiltrationSnapshot(config,config.durationS);
            testCase.verifyEqual(result.h,expected.h,'RelTol',1e-13);
            testCase.verifyEqual(result.stats.fillPercent,expected.stats.fillPercent,'RelTol',1e-13);
            testCase.verifyTrue(progress.reachedTarget);
            testCase.verifyTrue(simulation.done);
        end

        function startsEmptyWithoutArtificialInitialLength(testCase)
            config = resist.validateInfiltration(struct());
            snapshot = resist.infiltrationSnapshot(config, 0);
            testCase.verifyEqual(snapshot.h, 0);
            testCase.verifyEqual(snapshot.b, 0);
            testCase.verifyEqual(snapshot.n, 1);
            testCase.verifyEqual(snapshot.stats.fillPercent, 0);
            testCase.verifyTrue(isnan(snapshot.stats.frontSpeedUmS));
            testCase.verifyFalse(snapshot.done);
            testCase.verifyFalse(snapshot.filled);
            testCase.verifyTrue(any(contains(snapshot.warnings, '慣性')));
        end

        function capillaryOnlyMatchesParallelPlateWashburnLaw(testCase)
            config = struct('gapUm', 0.2, 'depthUm', 100, ...
                'contactAngleDeg', 0, 'surfaceTensionMnM', 72, ...
                'viscosityPaS', 0.001, 'durationS', 0.1);
            time = 1e-6;
            snapshot = resist.infiltrationSnapshot(config, time);
            % l^2/t = gamma*gap*cos(theta)/(3*mu), converted to um^2/s.
            expectedUm = sqrt(4.8e6 * time);
            testCase.verifyEqual(snapshot.stats.penetrationUm, expectedUm, 'RelTol', 1e-13);
            testCase.verifyEqual(snapshot.stats.capillaryPressurePa, 720000, 'RelTol', 1e-13);
            testCase.verifyEqual(snapshot.stats.frontSpeedUmS, expectedUm / (2 * time), 'RelTol', 1e-13);
        end

        function imposedPressureUsesTheParallelSlitFactorSix(testCase)
            config = struct('gapUm', 2, 'depthUm', 100, ...
                'contactAngleDeg', 90, 'externalPressurePa', 1200, ...
                'viscosityPaS', 0.01, 'durationS', 1);
            time = 1e-4;
            snapshot = resist.infiltrationSnapshot(config, time);
            expectedUm = sqrt((2e-6)^2 * 1200 * time / (6 * 0.01)) / 1e-6;
            testCase.verifyEqual(snapshot.stats.capillaryPressurePa, 0);
            testCase.verifyEqual(snapshot.stats.penetrationUm, expectedUm, 'RelTol', 1e-13);
        end

        function followsTimeGapAndViscosityScaling(testCase)
            config = resist.validateInfiltration(struct('depthUm', 1000, 'durationS', 1));
            initial = resist.infiltrationSnapshot(config, 1e-6);
            later = resist.infiltrationSnapshot(config, 4e-6);
            testCase.verifyEqual(later.h, 2 * initial.h, 'RelTol', 1e-13);
            config.viscosityPaS = 4 * config.viscosityPaS;
            viscous = resist.infiltrationSnapshot(config, 1e-6);
            testCase.verifyEqual(viscous.h, initial.h / 2, 'RelTol', 1e-13);
            config.viscosityPaS = config.viscosityPaS / 4;
            config.gapUm = config.gapUm * 4;
            wider = resist.infiltrationSnapshot(config, 1e-6);
            testCase.verifyEqual(wider.h, initial.h * 2, 'RelTol', 1e-13);
        end

        function neutralAndNonwettingEmptySlitsRemainEmpty(testCase)
            for angle = [90, 120, 180]
                snapshot = resist.infiltrationSnapshot(struct('contactAngleDeg', angle), 0.001);
                testCase.verifyEqual(snapshot.h, 0);
                testCase.verifyEqual(snapshot.stats.frontSpeedUmS, 0);
                testCase.verifyTrue(isnan(snapshot.stats.fillTimeS));
                testCase.verifyFalse(snapshot.filled);
                testCase.verifyTrue(snapshot.done);
                testCase.verifyTrue(any(contains(snapshot.warnings, '浸透しません')));
            end
        end

        function imposedPressureCanOvercomeNonwettingResistance(testCase)
            config = struct('contactAngleDeg', 120, 'externalPressurePa', 400000, ...
                'depthUm', 100, 'durationS', 1);
            snapshot = resist.infiltrationSnapshot(config, 1e-5);
            testCase.verifyEqual(snapshot.stats.capillaryPressurePa, -360000, 'AbsTol', 1e-8);
            testCase.verifyEqual(snapshot.stats.drivingPressurePa, 40000, 'AbsTol', 1e-8);
            testCase.verifyGreaterThan(snapshot.h, 0);
            config.externalPressurePa = 350000;
            blocked = resist.infiltrationSnapshot(config, 1e-5);
            testCase.verifyEqual(blocked.h, 0);
        end

        function pressureCancellationDoesNotCauseNumericalLeakage(testCase)
            config = resist.validateInfiltration(struct('contactAngleDeg', 60));
            config.externalPressurePa = -2 * config.surfaceTensionMnM * 1e-3 * ...
                cosd(config.contactAngleDeg) / (config.gapUm * 1e-6);
            snapshot = resist.infiltrationSnapshot(config, config.durationS);
            testCase.verifyEqual(snapshot.stats.drivingPressurePa, 0);
            testCase.verifyEqual(snapshot.h, 0);
        end

        function distanceCapDoesNotPretendToComputeOutletFlow(testCase)
            config = resist.validateInfiltration(struct());
            initial = resist.infiltrationSnapshot(config, 0);
            fillTime = initial.stats.fillTimeS;
            before = resist.infiltrationSnapshot(config, fillTime / 2);
            atFill = resist.infiltrationSnapshot(config, fillTime);
            after = resist.infiltrationSnapshot(config, fillTime * 2);
            testCase.verifyEqual(before.h, config.depthUm / sqrt(2), 'RelTol', 1e-13);
            testCase.verifyFalse(before.filled);
            testCase.verifyTrue(atFill.filled);
            testCase.verifyEqual(atFill.h, config.depthUm, 'RelTol', 1e-13);
            testCase.verifyEqual(atFill.stats.fillPercent, 100, 'AbsTol', 1e-12);
            testCase.verifyEqual(after.h, atFill.h);
            testCase.verifyEqual(after.stats.volumeUm3, atFill.stats.volumeUm3);
            testCase.verifyEqual(after.stats.frontSpeedUmS, 0);
            testCase.verifyFalse(after.done);
            final = resist.infiltrationSnapshot(config, config.durationS * 2);
            testCase.verifyEqual(final.time, config.durationS);
            testCase.verifyTrue(final.done);
        end

        function volumeIsPerOneMicrometerOfChannelWidth(testCase)
            config = struct('gapUm', 0.5, 'depthUm', 100);
            snapshot = resist.infiltrationSnapshot(config, 1e-6);
            testCase.verifyEqual(snapshot.lengthUm, 0.5);
            testCase.verifyEqual(snapshot.stats.channelWidthUm, 1);
            testCase.verifyEqual(snapshot.stats.volumeUm3, 0.5 * snapshot.h, 'RelTol', 1e-13);
            testCase.verifyEqual(snapshot.stats.massErrorPercent, 0);
            testCase.verifyEqual(snapshot.stats.steps, 0);
        end

        function temperatureViscosityChangesTheFillingTime(testCase)
            config = struct('viscosityPaS', 0.1, 'activationKJMol', 30, 'temperatureC', 25);
            reference = resist.infiltrationSnapshot(config, 0);
            config.temperatureC = 60;
            warm = resist.infiltrationSnapshot(config, 0);
            expectedRatio = exp(30000 / 8.314462618 * (1 / 333.15 - 1 / 298.15));
            testCase.verifyEqual(warm.stats.viscosityPaS, 0.1 * expectedRatio, 'RelTol', 1e-13);
            testCase.verifyEqual(warm.stats.fillTimeS / reference.stats.fillTimeS, expectedRatio, 'RelTol', 1e-13);
        end

        function normalizesNumbersAndRetainsSharedConfiguration(testCase)
            input = struct('mode', "infiltration", 'gapUm', '0.5', 'depthUm', "8", ...
                'rpm', 2000, 'customHeightUm', [1, 2, 3]);
            config = resist.validateInfiltration(input);
            testCase.verifyEqual(config.mode, 'infiltration');
            testCase.verifyEqual(config.gapUm, 0.5);
            testCase.verifyEqual(config.depthUm, 8);
            testCase.verifyEqual(config.rpm, 2000);
            testCase.verifyEqual(config.customHeightUm, [1, 2, 3]);
            testCase.verifyEqual(input.gapUm, '0.5');
        end

        function snapshotsAreIndependentValues(testCase)
            config = resist.validateInfiltration(struct());
            first = resist.infiltrationSnapshot(config, 1e-6);
            first.h = 999;
            first.warnings{1} = 'modified';
            second = resist.infiltrationSnapshot(config, 1e-6);
            testCase.verifyNotEqual(second.h, 999);
            testCase.verifyFalse(any(strcmp(second.warnings, 'modified')));
            testCase.verifyEqual(config.gapUm, 0.2);
        end

        function rejectsNonphysicalOrMalformedInputs(testCase)
            cases = {
                'gapUm', 0; 'gapUm', 101; 'depthUm', -1;
                'contactAngleDeg', 181; 'contactAngleDeg', NaN;
                'externalPressurePa', Inf; 'externalPressurePa', 1000001;
                'viscosityPaS', 0; 'viscosityPaS', true;
                'surfaceTensionMnM', -1; 'temperatureC', -273.15;
                'activationKJMol', -1; 'durationS', 0;
                'gapUm', []; 'gapUm', [1, 2]; 'gapUm', 1i;
                'gapUm', ' '; 'gapUm', 'not a number'
                };
            for index = 1:size(cases, 1)
                config = struct();
                config.(cases{index, 1}) = cases{index, 2};
                testCase.verifyError(@() resist.validateInfiltration(config), 'resist:InvalidParameter');
            end
            testCase.verifyError(@() resist.validateInfiltration([]), 'resist:InvalidConfig');
            testCase.verifyError(@() resist.validateInfiltration(struct('mode', 'spin')), 'resist:InvalidMode');
            for invalidTime = {-1, NaN, Inf, [], [1, 2], true, 1i, '0.1'}
                testCase.verifyError(@() resist.infiltrationSnapshot(struct(), invalidTime{1}), 'resist:InvalidTime');
            end
        end
    end
end
