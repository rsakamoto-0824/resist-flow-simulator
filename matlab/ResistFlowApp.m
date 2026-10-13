function appFigure = ResistFlowApp()
%RESISTFLOWAPP Native desktop interface for three resist-flow models.
% Run this entry point in MATLAB or compile it on Windows with buildStandalone.

green = [0.08 0.40 0.32];
ink = [0.12 0.23 0.20];
muted = [0.39 0.48 0.43];
paper = [0.96 0.97 0.95];
frameCount = 60;
stepBudget = 100;
config = resist.defaultConfig();
runConfig = config;
simulation = [];
frames = {};
reference = [];
displayIndex = 1;
running = false;
dirty = false;
failed = false;
fields = struct();
screen = get(groot,'ScreenSize');
windowWidth = min(1400,max(640,screen(3) - 80));
windowHeight = min(900,max(500,screen(4) - 100));

appFigure = uifigure('Name','Resist Flow Lab | レジスト流体シミュレーター', ...
    'Position',[screen(1)+30 screen(2)+40 windowWidth windowHeight],'Color',paper, ...
    'CloseRequestFcn',@closeApp);
layout = uigridlayout(appFigure,[2 2], ...
    'RowHeight',{58,'1x'},'ColumnWidth',{330,'1x'}, ...
    'Padding',[18 14 18 14],'ColumnSpacing',18,'RowSpacing',14, ...
    'BackgroundColor',paper);
brand = uilabel(layout,'Text','RESIST FLOW LAB', ...
    'FontSize',23,'FontWeight','bold','FontColor',green);
brand.Layout.Row = 1;
brand.Layout.Column = 1;
heading = uilabel(layout,'Text','MATLAB  |  レジスト流体シミュレーター', ...
    'FontSize',17,'FontColor',ink);
heading.Layout.Row = 1;
heading.Layout.Column = 2;

left = uigridlayout(layout,[4 1],'RowHeight',{'1x',38,38,50}, ...
    'Padding',[0 0 0 0],'BackgroundColor',paper);
left.Layout.Row = 2;
left.Layout.Column = 1;
formPanel = uipanel(left,'Title','計算条件','BackgroundColor',[1 1 1]);
formGrid = uigridlayout(formPanel,[1 2],'ColumnWidth',{'1x',133}, ...
    'Scrollable','on','BackgroundColor',[1 1 1],'RowSpacing',9);
controls = uigridlayout(left,[1 2],'ColumnWidth',{'1x',76}, ...
    'Padding',[0 0 0 0],'BackgroundColor',paper);
runButton = uibutton(controls,'Text','実行','BackgroundColor',green, ...
    'FontColor',[1 1 1],'FontWeight','bold','ButtonPushedFcn',@runClicked);
resetButton = uibutton(controls,'Text','リセット','ButtonPushedFcn',@resetClicked);
files = uigridlayout(left,[1 2],'Padding',[0 0 0 0],'BackgroundColor',paper);
saveButton = uibutton(files,'Text','条件を保存 (JSON)','ButtonPushedFcn',@saveConfig);
loadButton = uibutton(files,'Text','条件を開く','ButtonPushedFcn',@loadConfig);
inputMessage = uilabel(left,'Text','材料値は例示です。実測値で校正してください。', ...
    'WordWrap','on','FontSize',11,'FontColor',muted);

right = uigridlayout(layout,[6 1], ...
    'RowHeight',{72,'1x',48,218,40,68}, ...
    'Padding',[0 0 0 0],'RowSpacing',10,'BackgroundColor',paper,'Scrollable','on');
right.Layout.Row = 2;
right.Layout.Column = 2;
metrics = uigridlayout(right,[1 4],'Padding',[0 0 0 0], ...
    'ColumnSpacing',10,'BackgroundColor',paper);
metricLabels = gobjects(1,4);
for k = 1:4
    panel = uipanel(metrics,'BackgroundColor',[1 1 1]);
    inner = uigridlayout(panel,[1 1],'Padding',[12 5 12 5],'BackgroundColor',[1 1 1]);
    metricLabels(k) = uilabel(inner,'Text','—','FontColor',ink, ...
        'FontSize',15,'WordWrap','on');
end
tabs = uitabgroup(right);
viewTab = uitab(tabs,'Title','形状・膜厚マップ');
viewGrid = uigridlayout(viewTab,[2 1],'RowHeight',{30,'1x'}, ...
    'BackgroundColor',[1 1 1]);
viewControls = uigridlayout(viewGrid,[1 2], ...
    'ColumnWidth',{135,'1x'},'Padding',[0 0 0 0],'BackgroundColor',[1 1 1]);
viewMenu = uidropdown(viewControls,'Items',{'立体表示','膜厚マップ'}, ...
    'ValueChangedFcn',@viewChanged);
geometryLabel = uilabel(viewControls,'Text','', ...
    'HorizontalAlignment','right','FontColor',muted,'FontSize',11);
surfaceAxes = uiaxes(viewGrid);
helpTab = uitab(tabs,'Title','モデルと使い方');
helpGrid = uigridlayout(helpTab,[1 1]);
uitextarea(helpGrid,'Value',helpText(),'Editable','off','FontSize',12);
compareTab = uitab(tabs,'Title','条件の比較');
compareGrid = uigridlayout(compareTab,[2 1],'RowHeight',{'1x',32});
comparisonTable = uitable(compareGrid,'ColumnName',{'項目','保持した結果','表示中の結果'}, ...
    'ColumnWidth',{'auto','auto','auto'},'RowName',{});
uibutton(compareGrid,'Text','比較を解除','ButtonPushedFcn',@clearComparison);

timeGrid = uigridlayout(right,[1 3],'ColumnWidth',{80,'1x',145}, ...
    'Padding',[0 0 0 0],'BackgroundColor',paper);
uilabel(timeGrid,'Text','表示時刻','FontColor',muted);
timeSlider = uislider(timeGrid,'Limits',[0 1],'Value',0, ...
    'MajorTicks',[],'MinorTicks',[],'ValueChangedFcn',@timeChanged, ...
    'ValueChangingFcn',@timeChanged);
timeLabel = uilabel(timeGrid,'Text','0 s','HorizontalAlignment','right');
plotGrid = uigridlayout(right,[1 2],'Padding',[0 0 0 0],'BackgroundColor',[1 1 1]);
sectionAxes = uiaxes(plotGrid);
historyAxes = uiaxes(plotGrid);
actionGrid = uigridlayout(right,[1 4],'Padding',[0 0 0 0],'BackgroundColor',paper);
uibutton(actionGrid,'Text','結果を比較用に保持','ButtonPushedFcn',@pinResult);
uibutton(actionGrid,'Text','時系列 CSV','ButtonPushedFcn',@exportHistory);
uibutton(actionGrid,'Text','膜厚 CSV','ButtonPushedFcn',@exportMap);
uibutton(actionGrid,'Text','図を PNG 保存','ButtonPushedFcn',@exportImage);
statusArea = uitextarea(right,'Editable','off','FontSize',11, ...
    'BackgroundColor',[0.91 0.95 0.90],'FontColor',muted);
drawForm();
prepare();
appFigure.SizeChangedFcn = @resizeApp;
resizeApp([],[]);
if isdeployed
    waitfor(appFigure);
end

    function drawForm()
        delete(formGrid.Children);
        fields = struct();
        row = 0;
        addChoice('mode','モデル',{'リフロー・段差平坦化','スピン塗布・蒸発','現像液の浸透'}, ...
            {'leveling','spin','infiltration'});
        fields.mode.ValueChangedFcn = @modelChanged;
        row = row + 1;
        label = uilabel(formGrid,'Text','サンプル条件');
        place(label,row,1);
        preset = uidropdown(formGrid,'Items',{'正弦波の平坦化','段差上の膜','局所的な盛り上がり','スピン塗布','溝への浸透'}, ...
            'ItemsData',{'leveling','topography','bump','spin','infiltration'}, ...
            'Value',presetName(),'ValueChangedFcn',@presetChanged);
        place(preset,row,2);
        if strcmp(config.mode,'infiltration')
            addNumber('gapUm','溝幅 (µm)');
            addNumber('depthUm','溝の深さ (µm)');
            addNumber('contactAngleDeg','接触角 (°)');
            addNumber('externalPressurePa','外部差圧 (Pa)');
        else
            addNumber('thicknessUm','初期平均膜厚 (µm)');
            addNumber('lengthUm','領域の一辺 (µm)');
        end
        if strcmp(config.mode,'leveling')
            addNumber('amplitudeUm','膜厚の振幅係数 (µm)');
            addChoice('n','各方向の格子数',{'16','32','64'},{16,32,64});
            addChoice('pattern','初期膜厚形状',{'正弦波 (x)','ガウス形状','ライン形状','均一','CSV'}, ...
                {'sine','gaussian','ridge','flat','custom'});
            addChoice('substratePattern','基板形状',{'平坦','正弦波','滑らかな周期段差'}, ...
                {'flat','sine','step'});
            addNumber('substrateUm','基板高さ係数 (µm)');
            fields.substratePattern.ValueChangedFcn = @clearCustomSubstrate;
            fields.substrateUm.ValueChangedFcn = @clearCustomSubstrate;
            if isfield(config,'customSubstrateUm') && ~isempty(config.customSubstrateUm)
                row = row + 1;
                label = uilabel(formGrid,'Text','基板 CSV を使用中（基板条件を変更すると解除）', ...
                    'FontColor',green,'WordWrap','on','FontSize',10);
                label.Layout.Row = row;
                label.Layout.Column = [1 2];
            end
            row = row + 1;
            button = uibutton(formGrid,'Text','初期膜厚 CSV を読み込む', ...
                'ButtonPushedFcn',@importMap);
            button.Layout.Row = row;
            button.Layout.Column = [1 2];
            row = row + 1;
            button = uibutton(formGrid,'Text','基板高さ CSV を読み込む', ...
                'ButtonPushedFcn',@importSubstrate);
            button.Layout.Row = row;
            button.Layout.Column = [1 2];
        end
        addNumber('viscosityPaS','基準粘度 25°C (Pa·s)');
        if ~strcmp(config.mode,'spin')
            addNumber('surfaceTensionMnM','表面張力 (mN/m)');
        end
        addNumber('temperatureC','一定温度 (°C)');
        addNumber('activationKJMol','粘度活性化エネルギー (kJ/mol)');
        if strcmp(config.mode,'spin')
            addNumber('densityKgM3','密度 (kg/m³)');
            addNumber('rpm','回転数 (rpm)');
            addNumber('solidsFraction','初期固形分の体積比');
            addNumber('concentrationFactor','濃縮粘度係数 β');
        end
        if ~strcmp(config.mode,'infiltration')
            addNumber('evaporationNmS','蒸発速度係数 (nm/s)');
        end
        addNumber('durationS','計算時間 (s)');
        if ~strcmp(config.mode,'infiltration')
            addChoice('accuracy','時間刻み係数',{'標準','1/2','1/4'},{1,0.5,0.25});
        end
        formGrid.RowHeight = repmat({32},1,row);

        function addNumber(key,labelText)
            row = row + 1;
            label = uilabel(formGrid,'Text',labelText,'FontSize',11,'WordWrap','on');
            place(label,row,1);
            control = uieditfield(formGrid,'numeric','Value',config.(key), ...
                'ValueDisplayFormat','%.6g','ValueChangedFcn',@markDirty);
            fields.(key) = control;
            place(control,row,2);
        end
        function addChoice(key,labelText,items,values)
            row = row + 1;
            label = uilabel(formGrid,'Text',labelText,'FontSize',11);
            place(label,row,1);
            control = uidropdown(formGrid,'Items',items,'ItemsData',values, ...
                'Value',config.(key),'ValueChangedFcn',@markDirty);
            fields.(key) = control;
            place(control,row,2);
        end
    end

    function name = presetName()
        name = config.mode;
        if strcmp(config.mode,'leveling') && strcmp(config.substratePattern,'step')
            name = 'topography';
        elseif strcmp(config.mode,'leveling') && strcmp(config.pattern,'gaussian')
            name = 'bump';
        end
    end

    function pending = readForm()
        pending = config;
        names = fieldnames(fields);
        for index = 1:numel(names)
            pending.(names{index}) = fields.(names{index}).Value;
        end
        pending = resist.validateConfig(pending);
    end

    function markDirty(~,~)
        dirty = true;
        runButton.Text = '変更した条件で実行';
        inputMessage.Text = '条件が変わっています。表示中の結果は前の条件です。';
    end

    function clearCustomSubstrate(source,event)
        config.customSubstrateUm = [];
        markDirty(source,event);
        inputMessage.Text = '基板 CSV を解除しました。変更した基板条件で再実行してください。';
    end

    function resizeApp(~,~)
        if appFigure.Position(4) < 790
            right.RowHeight = {72,270,48,218,40,68};
        else
            right.RowHeight = {72,'1x',48,218,40,68};
        end
        if appFigure.Position(3) < 1050
            right.ColumnWidth = {690};
        else
            right.ColumnWidth = {'1x'};
        end
    end

    function modelChanged(source,~)
        selectedMode = source.Value;
        % Switching models selects a usable example rather than retaining hidden inputs.
        applyPreset(selectedMode);
    end

    function presetChanged(source,~)
        applyPreset(source.Value);
    end

    function applyPreset(name)
        config = resist.defaultConfig();
        switch name
            case 'topography'
                config.pattern = 'flat';
                config.amplitudeUm = 0;
                config.substratePattern = 'step';
                config.substrateUm = 0.3;
            case 'bump'
                config.pattern = 'gaussian';
                config.thicknessUm = 0.8;
                config.amplitudeUm = 0.4;
            case 'spin'
                config.mode = 'spin';
                config.thicknessUm = 5;
                config.pattern = 'flat';
                config.amplitudeUm = 0;
                config.viscosityPaS = 0.02;
                config.rpm = 2000;
                config.concentrationFactor = 12;
                config.evaporationNmS = 100;
                config.durationS = 60;
            case 'infiltration'
                config.mode = 'infiltration';
                config.viscosityPaS = 0.001;
                config.surfaceTensionMnM = 72;
                config.durationS = 1e-5;
        end
        drawForm();
        safePrepare();
    end

    function safePrepare()
        try
            prepare();
        catch exception
            reportError(exception);
        end
    end

    function prepare()
        pending = readForm();
        nextSimulation = resist.Simulation(pending);
        config = pending;
        runConfig = pending;
        simulation = nextSimulation;
        frames = {simulation.getSnapshot()};
        displayIndex = 1;
        running = false;
        dirty = false;
        failed = false;
        timeSlider.Limits = [0 runConfig.durationS];
        timeSlider.Value = 0;
        runButton.Text = '実行';
        inputMessage.Text = '初期状態を表示しています。材料値は例示です。';
        render();
    end

    function resetClicked(~,~)
        safePrepare();
    end

    function runClicked(~,~)
        if running
            running = false;
            return
        end
        try
            if dirty || failed || isempty(simulation) || simulation.done
                prepare();
            end
            running = true;
            setRunningControls(true);
            inputMessage.Text = '計算中です。実行ボタンで一時停止できます。';
            while running && isvalid(appFigure) && ~simulation.done
                interval = runConfig.durationS / frameCount;
                target = min(runConfig.durationS, ...
                    (floor(frames{end}.time / interval + 1e-8) + 1) * interval);
                progress = simulation.advance(target,stepBudget);
                if progress.reachedTarget || simulation.done
                    recordFrame();
                    render();
                end
                timeLabel.Text = sprintf('計算 %.1f%%',100 * progress.time / runConfig.durationS);
                drawnow;
            end
            if ~isvalid(appFigure), return; end
            running = false;
            recordFrame();
            render();
            setRunningControls(false);
            if simulation.done
                runButton.Text = 'もう一度実行';
                inputMessage.Text = sprintf('計算完了: %d ステップ',frames{end}.stats.steps);
            else
                runButton.Text = '再開';
                inputMessage.Text = '一時停止中。結果の確認と保存ができます。';
            end
        catch exception
            running = false;
            failed = true;
            if ~isvalid(appFigure), return; end
            if ~isempty(simulation)
                recordFrame();
                render();
            end
            setRunningControls(false);
            runButton.Text = '初期状態から再実行';
            reportError(exception);
        end
    end

    function setRunningControls(value)
        if value, enabled = 'off'; else, enabled = 'on'; end
        handles = findall(formGrid,'-property','Enable');
        set(handles,'Enable',enabled);
        resetButton.Enable = enabled;
        saveButton.Enable = enabled;
        loadButton.Enable = enabled;
        timeSlider.Enable = enabled;
        if value, runButton.Text = '一時停止'; end
    end

    function recordFrame()
        current = simulation.getSnapshot();
        if ~isempty(frames) && current.time == frames{end}.time
            frames{end} = current;
        else
            frames{end+1} = current;
        end
        displayIndex = numel(frames);
        timeSlider.Value = current.time;
    end

    function timeChanged(~,event)
        if running || isempty(frames), return; end
        times = cellfun(@(snapshot) snapshot.time,frames);
        [~,displayIndex] = min(abs(times - event.Value));
        render();
    end

    function viewChanged(~,~)
        render();
    end

    function render()
        if isempty(frames) || ~isvalid(appFigure), return; end
        snapshot = frames{displayIndex};
        stats = snapshot.stats;
        if strcmp(runConfig.mode,'infiltration')
            metricLabels(1).Text = sprintf('浸透長\n%.4g µm',stats.penetrationUm);
            metricLabels(2).Text = sprintf('充填率\n%.2f %%',stats.fillPercent);
            metricLabels(3).Text = sprintf('毛管圧\n%.4g Pa',stats.capillaryPressurePa);
            metricLabels(4).Text = sprintf('総駆動圧\n%.4g Pa',stats.drivingPressurePa);
        else
            metricLabels(1).Text = sprintf('平均膜厚\n%.4g µm',stats.meanUm);
            metricLabels(2).Text = sprintf('膜厚 CV\n%.3f %%',stats.cvPercent);
            metricLabels(3).Text = sprintf('最小 / 最大 (µm)\n%.3g / %.3g',stats.minUm,stats.maxUm);
            if strcmp(runConfig.mode,'spin')
                metricLabels(4).Text = sprintf('固形分の体積比\n%.2f %%',stats.solidsPercent);
            else
                metricLabels(4).Text = sprintf('体積収支の残差\n%.2e %%',abs(stats.massErrorPercent));
            end
        end
        timeLabel.Text = sprintf('t = %.5g s',snapshot.time);
        drawSurface(snapshot);
        drawSection(snapshot);
        drawHistory();
        drawComparison(snapshot);
        notes = cellstr(string(snapshot.warnings(:)));
        if isempty(notes), notes = {'準備完了。入力は外部送信されません。'}; end
        statusArea.Value = notes;
    end

    function drawSurface(snapshot)
        cla(surfaceAxes);
        if strcmp(runConfig.mode,'infiltration')
            gap = runConfig.gapUm;
            depth = runConfig.depthUm;
            penetration = snapshot.stats.penetrationUm;
            rectangle(surfaceAxes,'Position',[0 0 gap depth], ...
                'FaceColor',[0.94 0.95 0.93],'EdgeColor',[0.5 0.6 0.53]);
            hold(surfaceAxes,'on');
            if penetration > 0
                rectangle(surfaceAxes,'Position',[0 0 gap penetration], ...
                    'FaceColor',[0.35 0.68 0.58],'EdgeColor','none');
            end
            plot(surfaceAxes,[0 gap],[penetration penetration],'-', ...
                'Color',green,'LineWidth',2);
            hold(surfaceAxes,'off');
            view(surfaceAxes,2);
            surfaceAxes.YDir = 'reverse';
            xlim(surfaceAxes,[-0.25 * gap 1.25 * gap]);
            ylim(surfaceAxes,[-0.05 * depth 1.05 * depth]);
            pbaspect(surfaceAxes,[1 1 1]);
            xlabel(surfaceAxes,'溝幅 (µm)');
            ylabel(surfaceAxes,'入口からの深さ (µm)');
            title(surfaceAxes,'通気された平行スリットへの浸透（模式図）');
            if isfinite(snapshot.stats.fillTimeS)
                geometryLabel.Text = sprintf('満充填の予測時間 %.4g s | 入口からの浸透のみ',snapshot.stats.fillTimeS);
            else
                geometryLabel.Text = '駆動圧が不足するため、入口から浸透しません';
            end
            colorbar(surfaceAxes,'off');
            return
        end
        surfaceAxes.YDir = 'normal';
        n = snapshot.n;
        if n == 1
            positions = [0 runConfig.lengthUm];
            thickness = repmat(snapshot.h,2,2);
            substrate = zeros(2,2);
        else
            positions = ((0:n-1) + 0.5) * runConfig.lengthUm / n;
            thickness = snapshot.h;
            substrate = snapshot.b;
        end
        if strcmp(viewMenu.Value,'膜厚マップ')
            imagesc(surfaceAxes,positions,positions,thickness);
            surfaceAxes.YDir = 'normal';
            axis(surfaceAxes,'image');
            title(surfaceAxes,'液体膜厚 (µm)');
        else
            [x,y] = meshgrid(positions,positions);
            surf(surfaceAxes,x,y,substrate + thickness,thickness, ...
                'EdgeColor',[0.38 0.61 0.49],'EdgeAlpha',0.2);
            view(surfaceAxes,40,28);
            axis(surfaceAxes,'tight');
            pbaspect(surfaceAxes,[1 1 0.36]);
            zlabel(surfaceAxes,'自由表面高さ (µm)');
            title(surfaceAxes,'自由表面（色: 液体膜厚 / 高さを拡大表示）');
        end
        xlabel(surfaceAxes,'x (µm)');
        ylabel(surfaceAxes,'y (µm)');
        palette = [linspace(0.81,0.12,128)',linspace(0.91,0.43,128)',linspace(0.84,0.34,128)'];
        colormap(surfaceAxes,palette);
        colorbar(surfaceAxes);
        colorLow = min([frames{1}.h(:);snapshot.h(:)]);
        colorHigh = max([frames{1}.h(:);snapshot.h(:)]);
        if colorHigh <= colorLow, colorHigh = colorLow + max(0.001,0.01 * colorLow); end
        clim(surfaceAxes,[colorLow colorHigh]);
        if strcmp(runConfig.mode,'spin')
            geometryLabel.Text = sprintf('均一膜モデル | %g rpm | 面内分布は計算しません',runConfig.rpm);
        else
            geometryLabel.Text = sprintf('周期境界 | %d × %d 格子 | %g × %g µm',n,n,runConfig.lengthUm,runConfig.lengthUm);
        end
    end

    function drawSection(snapshot)
        cla(sectionAxes);
        if strcmp(runConfig.mode,'infiltration')
            times = cellfun(@(frame) frame.time,frames);
            filled = cellfun(@(frame) frame.stats.fillPercent,frames);
            plot(sectionAxes,times,filled,'Color',green,'LineWidth',1.6);
            ylim(sectionAxes,[0 100]);
            xlabel(sectionAxes,'時間 (s)');
            ylabel(sectionAxes,'充填率 (%)');
            title(sectionAxes,'溝内の充填率');
        else
            initial = frames{1};
            if snapshot.n == 1
                x = [0 runConfig.lengthUm];
                current = [snapshot.h snapshot.h];
                original = [initial.h initial.h];
                base = [0 0];
            else
                x = ((0:snapshot.n-1) + 0.5) * runConfig.lengthUm / snapshot.n;
                row = floor(snapshot.n / 2) + 1;
                current = snapshot.h(row,:) + snapshot.b(row,:);
                original = initial.h(row,:) + initial.b(row,:);
                base = snapshot.b(row,:);
            end
            plot(sectionAxes,x,current,'Color',green,'LineWidth',1.6);
            hold(sectionAxes,'on');
            plot(sectionAxes,x,original,'--','Color',[0.6 0.67 0.61]);
            plot(sectionAxes,x,base,'Color',[0.6 0.48 0.34]);
            hold(sectionAxes,'off');
            xlabel(sectionAxes,'x (µm)');
            ylabel(sectionAxes,'高さ (µm)');
            title(sectionAxes,'中央断面');
            legend(sectionAxes,{'現在','初期','基板'},'Location','best','FontSize',9);
        end
        grid(sectionAxes,'on');
    end

    function drawHistory()
        cla(historyAxes);
        times = cellfun(@(frame) frame.time,frames);
        means = cellfun(@(frame) frame.stats.meanUm,frames);
        plot(historyAxes,times,means,'Color',green,'LineWidth',1.8);
        hold(historyAxes,'on');
        if strcmp(runConfig.mode,'leveling')
            minima = cellfun(@(frame) frame.stats.minUm,frames);
            maxima = cellfun(@(frame) frame.stats.maxUm,frames);
            plot(historyAxes,times,minima,':','Color',muted);
            plot(historyAxes,times,maxima,':','Color',muted);
        end
        if ~isempty(reference) && strcmp(reference.config.mode,runConfig.mode)
            referenceTimes = cellfun(@(frame) frame.time,reference.frames);
            referenceMean = cellfun(@(frame) frame.stats.meanUm,reference.frames);
            plot(historyAxes,referenceTimes,referenceMean,'--','Color',[0.71 0.47 0.25]);
        end
        plot(historyAxes,times(displayIndex),means(displayIndex),'o', ...
            'Color',green,'MarkerFaceColor',green);
        hold(historyAxes,'off');
        xlabel(historyAxes,'時間 (s)');
        if strcmp(runConfig.mode,'infiltration')
            title(historyAxes,'浸透長の時間変化');
            ylabel(historyAxes,'浸透長 (µm)');
        else
            title(historyAxes,'平均膜厚（点線: 最小・最大）');
            ylabel(historyAxes,'膜厚 (µm)');
        end
        grid(historyAxes,'on');
    end

    function drawComparison(snapshot)
        if isempty(reference)
            comparisonTable.Data = {'比較する結果を「保持」してください','',''};
            return
        end
        saved = reference.frames{end};
        comparisonTable.Data = { ...
            'モデル',reference.config.mode,runConfig.mode; ...
            '時刻 (s)',saved.time,snapshot.time; ...
            '基準粘度 (Pa·s)',reference.config.viscosityPaS,runConfig.viscosityPaS; ...
            '温度 (°C)',reference.config.temperatureC,runConfig.temperatureC; ...
            '平均膜厚 / 浸透長 (µm)',saved.stats.meanUm,snapshot.stats.meanUm; ...
            '膜厚 CV (%)',saved.stats.cvPercent,snapshot.stats.cvPercent};
    end

    function pinResult(~,~)
        reference = struct('config',runConfig,'frames',{frames(1:displayIndex)});
        render();
    end

    function clearComparison(~,~)
        reference = [];
        render();
    end

    function saveConfig(~,~)
        try
            pending = readForm();
            [name,folder] = uiputfile('*.json','計算条件の保存','resist-condition.json');
            if isequal(name,0), return; end
            record = struct('application','Resist Flow Lab','schemaVersion',1,'config',pending);
            text = jsonencode(record,'PrettyPrint',true);
            writeText(fullfile(folder,name),text);
            inputMessage.Text = '計算条件を保存しました。';
        catch exception
            reportError(exception);
        end
    end

    function loadConfig(~,~)
        [name,folder] = uigetfile('*.json','計算条件を開く');
        if isequal(name,0), return; end
        try
            path = fullfile(folder,name);
            information = dir(path);
            if information.bytes > 2000000
                error('Resist:FileSize','条件ファイルは 2 MB 以下にしてください。');
            end
            record = jsondecode(fileread(path));
            if ~isstruct(record) || ~isfield(record,'schemaVersion') || ...
                    ~isequal(record.schemaVersion,1) || ~isfield(record,'application') || ...
                    ~strcmp(record.application,'Resist Flow Lab') || ~isfield(record,'config')
                error('Resist:FileFormat','Resist Flow Lab の条件ファイルを選んでください。');
            end
            pending = resist.validateConfig(record.config);
            resist.Simulation(pending);
            config = pending;
            drawForm();
            prepare();
            inputMessage.Text = '保存した条件を読み込みました。';
        catch exception
            reportError(exception);
        end
    end

    function importMap(~,~)
        importField(false);
    end

    function importSubstrate(~,~)
        importField(true);
    end

    function importField(isSubstrate)
        [name,folder] = uigetfile('*.csv','高さ行列を読み込む（単位 µm / 見出しなし）');
        if isequal(name,0), return; end
        try
            path = fullfile(folder,name);
            information = dir(path);
            if information.bytes > 1000000
                error('Resist:FileSize','CSV は 1 MB 以下にしてください。');
            end
            values = readmatrix(path,'FileType','text','Delimiter',',','NumHeaderLines',0);
            [rows,columns] = size(values);
            if ~ismember(rows,[16 32 64]) || rows ~= columns || any(~isfinite(values(:)))
                error('Resist:CSV','16×16、32×32、64×64 の有限数の行列を指定してください。');
            end
            pending = readFormWithoutValidation();
            if pending.n ~= rows
                pending.customHeightUm = [];
                pending.customSubstrateUm = [];
                if strcmp(pending.pattern,'custom'), pending.pattern = 'flat'; end
            end
            pending.n = rows;
            if isSubstrate
                pending.customSubstrateUm = values;
            else
                pending.customHeightUm = values;
                pending.pattern = 'custom';
                pending.thicknessUm = mean(values(:));
            end
            pending = resist.validateConfig(pending);
            resist.Simulation(pending);
            config = pending;
            drawForm();
            prepare();
            inputMessage.Text = 'CSV を読み込みました。同じ格子数で膜厚と基板を指定できます。';
        catch exception
            reportError(exception);
        end
    end

    function pending = readFormWithoutValidation()
        pending = config;
        names = fieldnames(fields);
        for index = 1:numel(names)
            pending.(names{index}) = fields.(names{index}).Value;
        end
    end

    function exportHistory(~,~)
        [name,folder] = uiputfile('*.csv','時系列の保存','resist-history.csv');
        if isequal(name,0), return; end
        try
            time_s = cellfun(@(frame) frame.time,frames)';
            if strcmp(runConfig.mode,'infiltration')
                penetration_um = cellfun(@(frame) frame.stats.penetrationUm,frames)';
                fill_percent = cellfun(@(frame) frame.stats.fillPercent,frames)';
                capillary_pressure_Pa = cellfun(@(frame) frame.stats.capillaryPressurePa,frames)';
                driving_pressure_Pa = cellfun(@(frame) frame.stats.drivingPressurePa,frames)';
                fill_time_s = cellfun(@(frame) frame.stats.fillTimeS,frames)';
                front_speed_um_s = cellfun(@(frame) frame.stats.frontSpeedUmS,frames)';
                result = table(time_s,penetration_um,fill_percent,capillary_pressure_Pa, ...
                    driving_pressure_Pa,fill_time_s,front_speed_um_s);
            else
                mean_um = cellfun(@(frame) frame.stats.meanUm,frames)';
                min_um = cellfun(@(frame) frame.stats.minUm,frames)';
                max_um = cellfun(@(frame) frame.stats.maxUm,frames)';
                cv_percent = cellfun(@(frame) frame.stats.cvPercent,frames)';
                volume_um3 = cellfun(@(frame) frame.stats.volumeUm3,frames)';
                balance_error_percent = cellfun(@(frame) frame.stats.massErrorPercent,frames)';
                viscosity_Pa_s = cellfun(@(frame) frame.stats.viscosityPaS,frames)';
                result = table(time_s,mean_um,min_um,max_um,cv_percent,volume_um3,balance_error_percent,viscosity_Pa_s);
                if strcmp(runConfig.mode,'spin')
                    result.solids_percent = cellfun(@(frame) frame.stats.solidsPercent,frames)';
                end
            end
            writetable(result,fullfile(folder,name));
        catch exception
            reportError(exception);
        end
    end

    function exportMap(~,~)
        if strcmp(runConfig.mode,'infiltration')
            uialert(appFigure,'浸透モデルの結果は「時系列 CSV」で保存してください。','膜厚マップなし');
            return
        end
        [name,folder] = uiputfile('*.csv','表示時刻の膜厚 (µm)','resist-thickness-um.csv');
        if isequal(name,0), return; end
        try
            writematrix(frames{displayIndex}.h,fullfile(folder,name));
        catch exception
            reportError(exception);
        end
    end

    function exportImage(~,~)
        [name,folder] = uiputfile('*.png','表示図の保存','resist-surface.png');
        if isequal(name,0), return; end
        try
            exportgraphics(surfaceAxes,fullfile(folder,name),'Resolution',180);
        catch exception
            reportError(exception);
        end
    end

    function reportError(exception)
        inputMessage.Text = '処理を停止しました。条件と計算の前提を確認してください。';
        statusArea.Value = {exception.message};
        uialert(appFigure,exception.message,'入力または計算を確認');
    end

    function closeApp(~,~)
        running = false;
        delete(appFigure);
    end
end

function place(control,row,column)
control.Layout.Row = row;
control.Layout.Column = column;
end

function writeText(path,text)
[file,message] = fopen(path,'w','n','UTF-8');
if file < 0, error('Resist:Save','保存できません: %s',message); end
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
count = fprintf(file,'%s\n',text);
if count < 0, error('Resist:Save','ファイルへの書き込みに失敗しました。'); end
end

function text = helpText()
text = { ...
    '操作: サンプル条件 → 材料・形状・工程 → 実行。計算後は時刻スライダーで経過を確認します。'; ...
    '結果を保持して条件を変更すると、時間変化と数値を比較できます。条件は JSON、結果は CSV / PNG で保存できます。'; ...
    ''; ...
    'リフロー / 段差平坦化'; ...
    'h: 液体膜厚、b: 固定基板高さ。p = -γ∇²(h+b), q = -h³∇p/(3µ), ∂h/∂t = -∇·q - E。'; ...
    'ニュートン流体・小勾配・底面すべりなし・周期境界。蒸発は一様な膜厚減少です。濃縮と固化は解きません。'; ...
    '0.01 µm に達したらモデル下限として停止します。実材料の乾燥膜厚を意味しません。格子数と時間刻みを変えて収束を確認してください。'; ...
    'CSV は n×n の数値、単位 µm、見出しなし。列が x、行が y、先頭が小さい座標です。基板 CSV も同じ格子で指定できます。'; ...
    ''; ...
    'スピン塗布 / 蒸発'; ...
    'D = 2ρ ω²h³/(3µ), φ = s/h, dh/dt = -D-E(1-φ), ds/dt = -φD。s は非揮発成分の体積/面積です。'; ...
    'µ = µ25 exp[Ea/R(1/T-1/298.15)] exp[β(φ-φ0)]。温度は一定です。蒸発低減と濃縮粘度は簡易構成則です。'; ...
    '均一膜の平均値モデルです。ウェハ端、滴下、面内均一性は解きません。固形分99%で液体モデルを停止します。'; ...
    ''; ...
    '現像液のパターン間浸透'; ...
    '通気された平行スリットの Lucas-Washburn モデル。Δp = Δp外部 + 2γ cosθ / w。'; ...
    'ℓ² = w²Δp t/(6µ)。駆動圧が正の場合に進行し、ℓ は溝の深さで止まります。充填後の貫流は計算しません。'; ...
    '慣性を無視するため開始直後の速度は表現できません。接触角は一定で、空気閉じ込め・動的接触角・重力・溶解反応は対象外です。'; ...
    ''; ...
    '共通の注意'; ...
    '材料値は仮想値です。実測物性と実験による校正が必要です。数値収支の残差は物理モデルの予測精度ではありません。'; ...
    '3次元 CFD、露光化学、現像反応、非ニュートン流体、接触線、急峻な側壁、固化後の弾性は含みません。'; ...
    '計算と保存は端末内で行います。外部への送信機能はありません。'; ...
    ''; ...
    '式・出典・ビルド方法・未検証項目は配布フォルダの README.md と design.md を参照してください。'};
end
