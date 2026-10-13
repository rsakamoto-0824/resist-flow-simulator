function snapshot = infiltrationSnapshot(input, requestedTime)
%INFILTRATIONSNAPSHOT Analytical filling of a vented parallel-plate slit.
%   Positive externalPressurePa pushes liquid into an initially empty slit.
%   Fluid volume is reported per 1 micrometer of out-of-plane channel width.
%   The front is held at depthUm after filling; outlet flow is not modeled.
%
%   Parallel-plate viscous pressure drop is 12*mu*l*(dl/dt)/gap^2.
%   Reference: Diotallevi et al., arXiv:0801.4223, equations (1) and (2).
%   https://arxiv.org/html/0801.4223

config = resist.validateInfiltration(input);
if ~isnumeric(requestedTime) || ~isreal(requestedTime) || ...
        ~isscalar(requestedTime) || ~isfinite(requestedTime) || requestedTime < 0
    error('resist:InvalidTime', '時刻は 0 以上の有限な数値で指定してください。');
end
time = min(double(requestedTime), config.durationS);
micrometer = 1e-6;
millinewton = 1e-3;
gasConstant = 8.314462618;
referenceTemperatureK = 298.15;
channelWidthUm = 1;

gap = config.gapUm * micrometer;
depth = config.depthUm * micrometer;
gamma = config.surfaceTensionMnM * millinewton;
temperatureK = config.temperatureC + 273.15;
viscosity = config.viscosityPaS * exp(config.activationKJMol * 1000 / ...
    gasConstant * (1 / temperatureK - 1 / referenceTemperatureK));

% cosd(90) is exactly zero, avoiding artificial filling at neutral wetting.
capillaryPressure = 2 * gamma * cosd(config.contactAngleDeg) / gap;
drivingPressure = config.externalPressurePa + capillaryPressure;
pressureScale = max([1, abs(config.externalPressurePa), abs(capillaryPressure)]);
if abs(drivingPressure) <= 16 * eps(pressureScale)
    drivingPressure = 0;
end

warnings = {
    '通気された平行平板スリットの解析モデルです。液体は入口の十分大きい供給源から流入します。';
    '慣性・入口損失・動的接触角・接触線の固着・壁面滑り・閉じ込め気体・重力・蒸発・硬化は計算しません。';
    '時刻 0 の前線速度はこの近似では定義できません。初期の慣性過程を表すモデルではありません。';
    '距離上限への到達後は浸透長を保持します。出口から流れ続ける流量は計算しません。'
    };
if config.gapUm < 0.01
    warnings{end + 1, 1} = '間隔が 10 nm 未満です。連続体・一定接触角・滑りなし近似の妥当性を別途確認してください。';
end
if config.depthUm < 10 * config.gapUm
    warnings{end + 1, 1} = 'スリットが間隔に比べて短く、無視した入口・出口効果が結果に影響する可能性があります。';
end

fillTime = NaN;
frontSpeed = 0;
penetration = 0;
filled = false;
if drivingPressure > 0
    squaredLengthRate = gap ^ 2 * drivingPressure / (6 * viscosity);
    fillTime = depth ^ 2 / squaredLengthRate;
    filled = time >= fillTime;
    if filled
        penetration = depth;
    else
        penetration = sqrt(squaredLengthRate * time);
        if time == 0
            frontSpeed = NaN;
        else
            frontSpeed = squaredLengthRate / (2 * penetration);
        end
    end
else
    warnings{end + 1, 1} = '合計駆動圧が 0 以下のため浸透しません。空のスリットからの後退・排液は計算しません。';
end

penetrationUm = penetration / micrometer;
stats = struct( ...
    'meanUm', penetrationUm, 'minUm', penetrationUm, 'maxUm', penetrationUm, ...
    'cvPercent', 0, 'volumeUm3', config.gapUm * penetrationUm * channelWidthUm, ...
    'massErrorPercent', 0, 'soluteBalanceErrorPercent', NaN, 'solidsPercent', NaN, ...
    'viscosityPaS', viscosity, 'steps', 0, 'rejectedSteps', 0, 'lastStepS', 0, ...
    'evaporatedUm', 0, 'drainedUm', 0, 'penetrationUm', penetrationUm, ...
    'fillPercent', 100 * penetration / depth, ...
    'capillaryPressurePa', capillaryPressure, 'drivingPressurePa', drivingPressure, ...
    'fillTimeS', fillTime, 'frontSpeedUmS', frontSpeed / micrometer, ...
    'channelWidthUm', channelWidthUm);
snapshot = struct('time', time, 'n', 1, 'lengthUm', config.gapUm, ...
    'h', penetrationUm, 'b', 0, 'hUnit', 'um', 'bUnit', 'um', ...
    'mode', 'infiltration', 'done', time >= config.durationS, ...
    'filled', filled, 'terminationReason', '', 'stats', stats, 'warnings', {warnings});
end
