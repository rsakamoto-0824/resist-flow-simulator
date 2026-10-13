function config = validateConfig(input)
%VALIDATECONFIG Normalize a configuration without modifying the caller's data.
if nargin < 1
    input = struct();
end
if ~isstruct(input) || ~isscalar(input)
    error('resist:InvalidConfig', '計算条件は単一の構造体で指定してください。');
end
mode = 'leveling';
if isfield(input, 'mode')
    mode = exactChoice(input.mode, {'leveling', 'spin', 'infiltration'}, '計算モード');
end
config = resist.defaultConfig(mode);
names = fieldnames(input);
for index = 1:numel(names)
    config.(names{index}) = input.(names{index});
end
config.mode = mode;
if strcmp(mode, 'infiltration')
    % Inactive thin-film controls must not restrict the analytical slit mode.
    config = resist.validateInfiltration(config);
    return
end
config.pattern = exactChoice(config.pattern, ...
    {'sine', 'gaussian', 'ridge', 'flat', 'custom'}, '初期膜厚の形状');
config.substratePattern = exactChoice(config.substratePattern, ...
    {'flat', 'sine', 'step'}, '基板形状');
ranges = { ...
    'n', '分割数', 16, 64; ...
    'lengthUm', '領域サイズ（µm）', 1, 100000; ...
    'thicknessUm', '初期膜厚（µm）', 0.01, 1000; ...
    'amplitudeUm', '初期凹凸の振幅（µm）', 0, 1000; ...
    'substrateUm', '基板の高低差・振幅（µm）', 0, 1000; ...
    'viscosityPaS', '基準粘度（Pa·s）', 0.00001, 10000; ...
    'surfaceTensionMnM', '表面張力（mN/m）', 0.001, 1000; ...
    'densityKgM3', '密度（kg/m³）', 1, 30000; ...
    'rpm', '回転数（rpm）', 0, 100000; ...
    'evaporationNmS', '蒸発速度（nm/s）', 0, 1000000; ...
    'solidsFraction', '初期固形分率', 0.001, 0.99; ...
    'concentrationFactor', '濃度による粘度上昇係数', 0, 30; ...
    'temperatureC', '温度（°C）', -50, 250; ...
    'activationKJMol', '粘度の活性化エネルギー（kJ/mol）', 0, 150; ...
    'durationS', '計算時間（s）', 0.000001, 36000; ...
    'accuracy', '精度係数', 0.25, 1};
for index = 1:size(ranges, 1)
    key = ranges{index, 1};
    config.(key) = finiteScalar(config.(key), ranges{index, 2}, ...
        ranges{index, 3}, ranges{index, 4});
end
if ~ismember(config.n, [16, 32, 64])
    error('resist:InvalidConfig', '分割数は 16、32、64 から選択してください。');
end
if ~ismember(config.accuracy, [0.25, 0.5, 1])
    error('resist:InvalidConfig', '精度係数は 0.25、0.5、1 から選択してください。');
end
if strcmp(mode, 'spin') && config.solidsFraction >= 0.99
    error('resist:InvalidConfig', '初期固形分率は 0.99 未満にしてください。');
end
for name = {'customHeightUm', 'customSubstrateUm'}
    key = name{1};
    if ~isfield(config, key) || isempty(config.(key))
        continue
    end
    values = config.(key);
    validShape = isequal(size(values), [config.n, config.n]) || ...
        (isvector(values) && numel(values) == config.n^2);
    if ~isnumeric(values) || ~isreal(values) || ~validShape || ...
            any(~isfinite(values(:))) || any(abs(values(:)) > 100000)
        error('resist:InvalidConfig', ...
            '読み込み形状は分割数 × 分割数の有限な数値配列で指定してください（µm）。');
    end
    config.(key) = reshape(double(values), config.n, config.n);
    if strcmp(key, 'customHeightUm') && any(values(:) < 0.01)
        error('resist:InvalidConfig', '読み込み膜厚はすべて 0.01 µm 以上にしてください。');
    end
end
if strcmp(mode, 'leveling')
    if strcmp(config.pattern, 'custom') && ...
            (~isfield(config, 'customHeightUm') || isempty(config.customHeightUm))
        error('resist:InvalidConfig', '任意形状には膜厚の読み込みデータが必要です。');
    end
    resist.Simulation.initialFields(config);
end
end

function value = finiteScalar(input, label, minimum, maximum)
if ~(isnumeric(input) && isreal(input) && isscalar(input) && ...
        isfinite(input) && input >= minimum && input <= maximum)
    error('resist:InvalidConfig', '%s は %g ～ %g の数値で入力してください。', ...
        label, minimum, maximum);
end
value = double(input);
end

function value = exactChoice(input, choices, label)
if isstring(input) && isscalar(input) && ~ismissing(input)
    input = char(input);
end
if ~ischar(input) || ~isrow(input) || ~any(strcmp(input, choices))
    error('resist:InvalidConfig', '%sを正しく選択してください。', label);
end
value = input;
end
