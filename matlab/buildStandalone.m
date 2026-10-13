function outputDirectory = buildStandalone(runtimeDelivery)
%BUILDSTANDALONE Test and package the Windows application.
%   buildStandalone() bundles MATLAB Runtime for offline installation.
%   buildStandalone('web') downloads Runtime during installation instead.

if nargin == 0
    runtimeDelivery = 'installer';
end
runtimeDelivery = validatestring(runtimeDelivery, {'installer', 'web'});
if ~ispc
    error('resist:WindowsBuildRequired', ...
        'Windows 用 EXE は Windows 上の MATLAB で作成してください。');
end
if verLessThan('matlab', '23.2')
    error('resist:UnsupportedMATLAB', 'MATLAB R2023b 以降が必要です。');
end
if isempty(which('compiler.build.standaloneApplication')) || ...
        ~license('test', 'Compiler')
    error('resist:CompilerRequired', ...
        'ビルドには MATLAB Compiler のインストールとライセンスが必要です。');
end

sourceDirectory = fileparts(mfilename('fullpath'));
projectDirectory = fileparts(sourceDirectory);
originalPath = path;
restorePath = onCleanup(@() path(originalPath)); %#ok<NASGU>
addpath(sourceDirectory);

testResults = runtests(fullfile(sourceDirectory, 'tests'));
if isempty(testResults) || ~all([testResults.Passed])
    error('resist:TestsNotPassed', ...
        'すべての MATLAB テストが成功するまで配布物を作成できません。');
end

% Each build keeps its own output so a previous package is not overwritten.
buildStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outputDirectory = fullfile(projectDirectory, 'dist', 'windows', buildStamp);
if isfolder(outputDirectory)
    error('resist:BuildDirectoryExists', ...
        '出力先が既に存在します。少し待ってから再実行してください。');
end
mkdir(outputDirectory);
executableDirectory = fullfile(outputDirectory, 'application');
installerDirectory = fullfile(outputDirectory, 'installer');
mainFile = fullfile(sourceDirectory, 'ResistFlowApp.m');

buildResults = compiler.build.standaloneApplication(mainFile, ...
    'ExecutableName', 'ResistFlowLab', ...
    'OutputDir', executableDirectory, ...
    'AutoDetectDataFiles', 'off', ...
    'AdditionalFiles', {fullfile(sourceDirectory, '+resist')}, ...
    'Verbose', 'on');

compiler.package.installer(buildResults, ...
    'ApplicationName', 'Resist Flow Lab', ...
    'InstallerName', 'ResistFlowLabInstaller', ...
    'Version', '1.0', ...
    'RuntimeDelivery', runtimeDelivery, ...
    'OutputDir', installerDirectory, ...
    'AdditionalFiles', {fullfile(projectDirectory, 'README.md'), ...
        fullfile(projectDirectory, 'design.md')}, ...
    'Summary', 'Resist thin-film flow and slit-filling simulator', ...
    'Verbose', 'on');

infoFile = fullfile(outputDirectory, 'build-info.txt');
fileId = fopen(infoFile, 'w', 'n', 'UTF-8');
if fileId < 0
    error('resist:BuildInfoWriteFailed', ...
        '配布物は作成しましたが、ビルド情報を保存できません: %s', infoFile);
end
closeInfo = onCleanup(@() fclose(fileId)); %#ok<NASGU>
fprintf(fileId, 'Application: Resist Flow Lab\n');
fprintf(fileId, 'MATLAB: %s (%s)\n', version, version('-release'));
fprintf(fileId, 'Platform: %s\n', computer);
fprintf(fileId, 'Runtime delivery: %s\n', runtimeDelivery);
fprintf(fileId, 'MATLAB tests passed: %d\n', numel(testResults));
fprintf(fileId, 'Windows installer smoke test: NOT YET RUN\n');
fprintf('配布物の保存先: %s\n', outputDirectory);
fprintf('対象 Windows でインストール・起動・3 モードの実行を確認してください。\n');
end
