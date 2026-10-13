classdef Simulation < handle
    %SIMULATION Toolbox-free thin-film flow, spin coating, and infiltration.
    % Internal lengths use SI meters. Snapshot h/b use micrometer matrices:
    % rows are y, columns are x, and opposite edges are periodic.
    properties (SetAccess = private)
        config
        time = 0
        steps = 0
        terminationReason = ''
    end
    properties (Dependent)
        done
    end
    properties (Access = private)
        h
        b
        n
        dx
        initialMean
        initialSolute
        soluteThickness
        evaporatedThickness = 0
        drainedThickness = 0
        soluteOutflow = 0
        rejectedSteps = 0
        lastStepS = 0
        spinNextStep
        fixedViscosity
        warnings = {}
    end
    properties (Constant, Access = private)
        Micrometer = 1e-6
        Nanometer = 1e-9
        MinimumWetThickness = 1e-8
        MaximumSolidsFraction = 0.99
        MaximumSteps = 1000000
        StabilityFactor = 0.55
        GasConstant = 8.314462618
        ReferenceTemperatureK = 298.15
        WetLimitMessage = '最小膜厚が 0.01 µm に達したため計算を停止しました。乾燥に近い膜はこの液体モデルの対象外です。'
    end

    methods
        function obj = Simulation(input)
            if nargin < 1
                input = struct();
            end
            obj.config = resist.validateConfig(input);
            if strcmp(obj.config.mode, 'infiltration')
                return
            end
            fields = resist.Simulation.initialFields(obj.config);
            obj.h = fields.h;
            obj.b = fields.b;
            obj.n = fields.n;
            obj.dx = obj.config.lengthUm * obj.Micrometer / obj.n;
            obj.initialMean = mean(obj.h(:));
            obj.initialSolute = obj.initialMean * obj.config.solidsFraction;
            obj.soluteThickness = obj.initialSolute;
            obj.spinNextStep = min(obj.config.durationS / 100, 0.1);
            if strcmp(obj.config.mode, 'leveling')
                obj.prepareLeveling();
            else
                obj.warnings{end + 1} = ...
                    '回転塗布は面内で一様な膜の平均値モデルです。ウェハ端部・液滴の広がり・面内分布は計算しません。';
            end
        end

        function value = get.done(obj)
            value = obj.time >= obj.config.durationS || ~isempty(obj.terminationReason);
        end

        function result = advance(obj, targetTime, maxSteps)
            if nargin < 3
                maxSteps = 2000;
            end
            if ~(isnumeric(targetTime) && isreal(targetTime) && isscalar(targetTime) && ...
                    isfinite(targetTime) && targetTime >= obj.time)
                error('resist:InvalidConfig', '到達時刻は現在時刻以降の数値で指定してください。');
            end
            if ~(isnumeric(maxSteps) && isreal(maxSteps) && isscalar(maxSteps) && ...
                    isfinite(maxSteps) && maxSteps == fix(maxSteps) && ...
                    maxSteps >= 1 && maxSteps <= obj.MaximumSteps)
                error('resist:InvalidConfig', '1 回の計算ステップ数は 1 ～ 1000000 の整数で指定してください。');
            end
            target = min(double(targetTime), obj.config.durationS);
            accepted = 0;
            if strcmp(obj.config.mode, 'infiltration')
                obj.time = target;
                result = struct('reachedTarget', true, 'done', obj.done, ...
                    'steps', 0, 'time', obj.time);
                return
            end
            if obj.time < target && ~obj.done && min(obj.h(:)) <= obj.MinimumWetThickness
                obj.setWetLimit();
                error('resist:ModelLimit', '%s', obj.terminationReason);
            end
            while obj.time < target && accepted < maxSteps && ~obj.done
                if obj.steps >= obj.MaximumSteps
                    error('resist:StepLimit', ...
                        '計算が100万ステップに達しました。分割数・計算時間・膜厚を小さくして再実行してください。');
                end
                remaining = target - obj.time;
                if strcmp(obj.config.mode, 'spin')
                    dt = obj.spinStep(remaining);
                else
                    dt = obj.levelingStep(remaining);
                end
                if (~isfinite(dt) || dt <= 0 || obj.time + dt == obj.time) && isempty(obj.terminationReason)
                    error('resist:NumericalFailure', ...
                        '時間刻みが小さすぎるため計算を停止しました。計算条件を見直してください。');
                end
                if dt == remaining
                    obj.time = target;
                else
                    obj.time = obj.time + dt;
                end
                obj.lastStepS = dt;
                obj.steps = obj.steps + 1;
                accepted = accepted + 1;
                % Save the event state and time before the UI receives the error.
                if ~isempty(obj.terminationReason)
                    error('resist:ModelLimit', '%s', obj.terminationReason);
                end
            end
            result = struct('reachedTarget', obj.time >= target, 'done', obj.done, ...
                'steps', accepted, 'time', obj.time);
        end

        function snapshot = getSnapshot(obj)
            if strcmp(obj.config.mode, 'infiltration')
                snapshot = resist.infiltrationSnapshot(obj.config, obj.time);
                snapshot.done = obj.done;
                snapshot.terminationReason = obj.terminationReason;
                return
            end
            meanThickness = mean(obj.h(:));
            expectedMean = obj.initialMean - obj.evaporatedThickness - obj.drainedThickness;
            phi = NaN;
            soluteError = NaN;
            if strcmp(obj.config.mode, 'spin')
                phi = obj.soluteThickness / obj.h;
                soluteError = 100 * (obj.soluteThickness + obj.soluteOutflow - obj.initialSolute) / obj.initialSolute;
            end
            snapshot = struct();
            snapshot.time = obj.time;
            snapshot.n = obj.n;
            snapshot.lengthUm = obj.config.lengthUm;
            snapshot.h = obj.h / obj.Micrometer;
            snapshot.b = obj.b / obj.Micrometer;
            snapshot.hUnit = 'um';
            snapshot.bUnit = 'um';
            snapshot.mode = obj.config.mode;
            snapshot.done = obj.done;
            snapshot.terminationReason = obj.terminationReason;
            snapshot.stats = struct( ...
                'meanUm', meanThickness / obj.Micrometer, ...
                'minUm', min(obj.h(:)) / obj.Micrometer, ...
                'maxUm', max(obj.h(:)) / obj.Micrometer, ...
                'cvPercent', sqrt(mean((obj.h(:) - meanThickness).^2)) / meanThickness * 100, ...
                'volumeUm3', meanThickness / obj.Micrometer * obj.config.lengthUm^2, ...
                'massErrorPercent', 100 * (meanThickness - expectedMean) / obj.initialMean, ...
                'soluteBalanceErrorPercent', soluteError, 'solidsPercent', phi * 100, ...
                'viscosityPaS', obj.viscosity(phi), 'steps', obj.steps, ...
                'rejectedSteps', obj.rejectedSteps, 'lastStepS', obj.lastStepS, ...
                'evaporatedUm', obj.evaporatedThickness / obj.Micrometer, ...
                'drainedUm', obj.drainedThickness / obj.Micrometer);
            snapshot.warnings = obj.warnings;
        end

        function value = snapshot(obj)
            % Alias for consumers that prefer sim.snapshot().
            value = obj.getSnapshot();
        end
    end

    methods (Static)
        function fields = initialFields(config)
            % Public for input validation; h and b here use SI meters.
            if strcmp(config.mode, 'spin')
                fields = struct('h', config.thicknessUm * 1e-6, 'b', 0, 'n', 1);
                return
            end
            n = config.n;
            coordinate = ((0:n-1) + 0.5) / n - 0.5;
            [ux, uy] = meshgrid(coordinate, coordinate);
            shape = zeros(n);
            switch config.pattern
                case 'sine'
                    shape = cos(2 * pi * ux);
                case 'gaussian'
                    shape = exp(-(ux.^2 + uy.^2) / (2 * 0.12^2));
                case 'ridge'
                    shape = exp(-ux.^2 / (2 * 0.1^2));
            end
            h = (config.thicknessUm + config.amplitudeUm * (shape - mean(shape(:)))) * 1e-6;
            b = zeros(n);
            switch config.substratePattern
                case 'sine'
                    b = config.substrateUm * cos(2 * pi * ux) * 1e-6;
                case 'step'
                    b = config.substrateUm * 0.5 * (1 + tanh(sin(2 * pi * ux) / 0.25)) * 1e-6;
            end
            if strcmp(config.pattern, 'custom')
                h = config.customHeightUm * 1e-6;
            end
            if isfield(config, 'customSubstrateUm') && ~isempty(config.customSubstrateUm)
                b = config.customSubstrateUm * 1e-6;
            end
            if any(~isfinite(h(:))) || any(h(:) < 1e-8 * (1 - 1e-12))
                error('resist:InvalidConfig', ...
                    '初期膜厚が 0.01 µm 未満になります。平均膜厚を増やすか、凹凸の振幅を小さくしてください。');
            end
            fields = struct('h', h, 'b', b, 'n', n);
        end
    end

    methods (Access = private)
        function value = viscosity(obj, phi)
            temperatureK = obj.config.temperatureC + 273.15;
            exponent = obj.config.activationKJMol * 1000 / obj.GasConstant * ...
                (1 / temperatureK - 1 / obj.ReferenceTemperatureK);
            if strcmp(obj.config.mode, 'spin')
                exponent = exponent + obj.config.concentrationFactor * (phi - obj.config.solidsFraction);
            end
            value = obj.config.viscosityPaS * exp(exponent);
        end

        function prepareLeveling(obj)
            obj.fixedViscosity = obj.viscosity(obj.config.solidsFraction);
            obj.warnings{end + 1} = ...
                '面内流動は周期境界・ニュートン流体・小勾配の薄膜近似です。露光反応、現像、接触線、乾燥後の固体力学は含みません。';
            if obj.config.evaporationNmS > 0
                obj.warnings{end + 1} = ...
                    '面内モードの蒸発は一様な膜厚減少のみです。濃度・粘度の変化は連成せず、最小膜厚 0.01 µm で計算を停止します。';
            end
            totalHeight = obj.h + obj.b;
            slope = [ ...
                abs(circshift(totalHeight, [0, -1]) - totalHeight); ...
                abs(circshift(totalHeight, [-1, 0]) - totalHeight); ...
                abs(circshift(obj.b, [0, -1]) - obj.b); ...
                abs(circshift(obj.b, [-1, 0]) - obj.b)] / obj.dx;
            if max(slope(:)) > 0.2 || max(obj.h(:)) / (obj.config.lengthUm * obj.Micrometer) > 0.05
                obj.warnings{end + 1} = ...
                    '膜の厚さまたは表面・基板の勾配が大きいため、薄膜近似の精度が低下する可能性があります。';
            end
            if strcmp(obj.config.substratePattern, 'step') && obj.config.substrateUm > 0
                obj.warnings{end + 1} = ...
                    '基板段差は傾斜を滑らかにした周期形状です。垂直な側壁や孤立した段差を直接表すものではありません。';
            end
            if obj.config.durationS / obj.stableStep(max(obj.h(:))) > obj.MaximumSteps
                obj.warnings{end + 1} = ...
                    '100万ステップの上限に達する可能性があります。分割数、計算時間、膜厚を小さくすると計算量を減らせます。';
            end
        end

        function dt = stableStep(obj, maximumThickness)
            mobility = maximumThickness^3 / (3 * obj.fixedViscosity);
            gamma = obj.config.surfaceTensionMnM * 0.001;
            % The periodic two-dimensional biharmonic radius is 64 / dx^4.
            dt = obj.StabilityFactor * obj.dx^4 * obj.config.accuracy / (32 * gamma * mobility);
        end

        function rate = flowRates(obj, h)
            totalHeight = h + obj.b;
            gamma = obj.config.surfaceTensionMnM * 0.001;
            pressure = -gamma / obj.dx^2 * ( ...
                circshift(totalHeight, [0, -1]) + circshift(totalHeight, [0, 1]) + ...
                circshift(totalHeight, [-1, 0]) + circshift(totalHeight, [1, 0]) - 4 * totalHeight);
            faceX = (h + circshift(h, [0, -1])) / 2;
            faceY = (h + circshift(h, [-1, 0])) / 2;
            exchangeX = faceX.^3 / (3 * obj.fixedViscosity) .* ...
                (circshift(pressure, [0, -1]) - pressure) / obj.dx^2;
            exchangeY = faceY.^3 / (3 * obj.fixedViscosity) .* ...
                (circshift(pressure, [-1, 0]) - pressure) / obj.dx^2;
            % Opposite contributions use the identical shared-face exchange.
            rate = exchangeX - circshift(exchangeX, [0, 1]) + ...
                exchangeY - circshift(exchangeY, [1, 0]);
        end

        function [candidate, valid] = levelingCandidate(obj, dt, firstRate)
            intermediate = obj.h + dt * firstRate;
            valid = all(isfinite(intermediate(:))) && all(intermediate(:) > 0);
            candidate = [];
            if ~valid
                return
            end
            secondRate = obj.flowRates(intermediate);
            candidate = obj.h + 0.5 * dt * (firstRate + secondRate);
            valid = all(isfinite(candidate(:))) && all(candidate(:) > 0);
        end

        function dt = levelingStep(obj, remainingTime)
            dt = min(remainingTime, obj.stableStep(max(obj.h(:))));
            firstRate = obj.flowRates(obj.h);
            for attempt = 1:40
                [candidate, valid] = obj.levelingCandidate(dt, firstRate);
                if valid
                    evaporationRate = obj.config.evaporationNmS * obj.Nanometer;
                    if min(candidate(:)) - evaporationRate * dt <= obj.MinimumWetThickness
                        lower = 0;
                        upper = dt;
                        for iteration = 1:45
                            middle = (lower + upper) / 2;
                            [trial, trialValid] = obj.levelingCandidate(middle, firstRate);
                            if trialValid && min(trial(:)) - evaporationRate * middle > obj.MinimumWetThickness
                                lower = middle;
                            else
                                upper = middle;
                            end
                        end
                        dt = upper;
                        [candidate, valid] = obj.levelingCandidate(dt, firstRate);
                        if ~valid
                            error('resist:NumericalFailure', '膜厚下限の停止時刻を確定できませんでした。');
                        end
                        obj.setWetLimit();
                    end
                    evaporationLoss = evaporationRate * dt;
                    obj.h = candidate - evaporationLoss;
                    obj.evaporatedThickness = obj.evaporatedThickness + evaporationLoss;
                    return
                end
                obj.rejectedSteps = obj.rejectedSteps + 1;
                dt = dt / 2;
                if obj.time + dt == obj.time
                    break
                end
            end
            error('resist:NumericalFailure', ...
                '正の膜厚を維持できず計算を停止しました。膜厚・基板段差・初期凹凸・分割数を見直してください。');
        end

        function derivative = spinDerivative(obj, state)
            h = state(1);
            solute = state(2);
            derivative = [];
            if ~isfinite(h + solute) || h <= 0 || solute < 0 || solute > h
                return
            end
            phi = solute / h;
            angularVelocity = obj.config.rpm * 2 * pi / 60;
            drain = 2 * obj.config.densityKgM3 * angularVelocity^2 * h^3 / ...
                (3 * obj.viscosity(phi));
            evaporation = obj.config.evaporationNmS * obj.Nanometer * (1 - phi);
            derivative = [-drain - evaporation; -phi * drain; evaporation; drain; phi * drain];
        end

        function candidate = rk4(obj, state, dt)
            candidate = [];
            k1 = obj.spinDerivative(state);
            if isempty(k1), return; end
            k2 = obj.spinDerivative(state + k1 * dt / 2);
            if isempty(k2), return; end
            k3 = obj.spinDerivative(state + k2 * dt / 2);
            if isempty(k3), return; end
            k4 = obj.spinDerivative(state + k3 * dt);
            if isempty(k4), return; end
            value = state + dt * (k1 + 2 * k2 + 2 * k3 + k4) / 6;
            if ~isempty(obj.spinDerivative(value)) && all(isfinite(value))
                candidate = value;
            end
        end

        function value = twoHalfSteps(obj, state, dt)
            firstHalf = obj.rk4(state, dt / 2);
            value = [];
            if ~isempty(firstHalf)
                value = obj.rk4(firstHalf, dt / 2);
            end
        end

        function dt = spinStep(obj, remainingTime)
            state = [obj.h; obj.soluteThickness; obj.evaporatedThickness; ...
                obj.drainedThickness; obj.soluteOutflow];
            dt = min(remainingTime, obj.spinNextStep);
            relativeTolerance = 1e-7 * obj.config.accuracy;
            absoluteTolerance = max(obj.initialMean * 1e-12, 1e-18);
            for attempt = 1:60
                full = obj.rk4(state, dt);
                twoHalves = obj.twoHalfSteps(state, dt);
                localError = Inf;
                if ~isempty(full) && ~isempty(twoHalves)
                    tolerance = absoluteTolerance + relativeTolerance * max(abs(state(1:2)), abs(twoHalves(1:2)));
                    localError = max(abs(twoHalves(1:2) - full(1:2)) ./ (15 * tolerance));
                end
                if localError <= 1
                    acceptedState = twoHalves;
                    if twoHalves(2) / twoHalves(1) >= obj.MaximumSolidsFraction || ...
                            twoHalves(1) <= obj.MinimumWetThickness
                        lower = 0;
                        upper = dt;
                        for iteration = 1:45
                            middle = (lower + upper) / 2;
                            trial = obj.twoHalfSteps(state, middle);
                            if ~isempty(trial) && trial(2) / trial(1) < obj.MaximumSolidsFraction && ...
                                    trial(1) > obj.MinimumWetThickness
                                lower = middle;
                            else
                                upper = middle;
                            end
                        end
                        dt = upper;
                        acceptedState = obj.twoHalfSteps(state, dt);
                        if isempty(acceptedState)
                            error('resist:NumericalFailure', '液体モデルの停止時刻を確定できませんでした。');
                        end
                        if acceptedState(1) <= obj.MinimumWetThickness * (1 + 1e-10)
                            obj.setWetLimit();
                        else
                            obj.terminationReason = ...
                                '固形分率が 99% に達したため計算を停止しました。ゲル化・乾燥後の固体はこの液体モデルの対象外です。';
                            obj.warnings{end + 1} = obj.terminationReason;
                        end
                    end
                    obj.h = acceptedState(1);
                    obj.soluteThickness = acceptedState(2);
                    obj.evaporatedThickness = acceptedState(3);
                    obj.drainedThickness = acceptedState(4);
                    obj.soluteOutflow = acceptedState(5);
                    if localError == 0
                        growth = 2;
                    else
                        growth = min(2, max(0.2, 0.9 * localError^(-0.2)));
                    end
                    obj.spinNextStep = dt * growth;
                    return
                end
                obj.rejectedSteps = obj.rejectedSteps + 1;
                if isfinite(localError)
                    dt = dt * max(0.1, min(0.5, 0.9 * localError^(-0.2)));
                else
                    dt = dt / 2;
                end
                if obj.time + dt == obj.time
                    break
                end
            end
            error('resist:NumericalFailure', ...
                '回転塗布の時間刻みを確保できず計算を停止しました。回転数・蒸発速度・初期膜厚を見直してください。');
        end

        function setWetLimit(obj)
            obj.terminationReason = obj.WetLimitMessage;
            obj.warnings{end + 1} = obj.terminationReason;
        end
    end
end
