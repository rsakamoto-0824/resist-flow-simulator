function config = validateInfiltration(input)
%VALIDATEINFILTRATION Validate a vented parallel-slit filling configuration.
%   Unknown fields are retained so this validator can share the app config.

if ~isstruct(input) || ~isscalar(input)
    error('resist:InvalidConfig', '計算条件を単一の構造体で指定してください。');
end

defaults = struct('mode', 'infiltration', 'gapUm', 0.2, 'depthUm', 5, ...
    'contactAngleDeg', 45, 'externalPressurePa', 0, ...
    'viscosityPaS', 0.001, 'surfaceTensionMnM', 72, ...
    'temperatureC', 25, 'activationKJMol', 0, 'durationS', 0.001);
config = input;
names = fieldnames(defaults);
for index = 1:numel(names)
    name = names{index};
    if ~isfield(config, name)
        config.(name) = defaults.(name);
    end
end

mode = config.mode;
if isstring(mode) && isscalar(mode)
    mode = char(mode);
end
if ~ischar(mode) || ~isrow(mode) || ~strcmp(mode, 'infiltration')
    error('resist:InvalidMode', '浸透モードには mode = ''infiltration'' を指定してください。');
end
config.mode = mode;

limits = {
    'gapUm',              'スリット間隔（µm）',          0.001,    100;
    'depthUm',            '浸透距離上限（µm）',          0.001,    100000;
    'contactAngleDeg',    '接触角（度）',                0,        180;
    'externalPressurePa','外部差圧（Pa）',              -1000000, 1000000;
    'viscosityPaS',       '基準粘度（Pa·s）',            0.00001,  10000;
    'surfaceTensionMnM',  '表面張力（mN/m）',            0.001,    1000;
    'temperatureC',       '温度（°C）',                  -50,      250;
    'activationKJMol',    '粘度の活性化エネルギー（kJ/mol）', 0,    150;
    'durationS',          '計算時間（s）',               1e-12,    36000
    };

for index = 1:size(limits, 1)
    name = limits{index, 1};
    value = config.(name);
    if isstring(value) && isscalar(value)
        value = char(value);
    end
    if ischar(value) && isrow(value) && ~isempty(strtrim(value))
        value = str2double(value);
    end
    lower = limits{index, 3};
    upper = limits{index, 4};
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value < lower || value > upper
        error('resist:InvalidParameter', '%sは %g ～ %g の有限な数値で指定してください。', ...
            limits{index, 2}, lower, upper);
    end
    config.(name) = double(value);
end
end
