function figs=plot_rfdac_iq_mismatch_sweep(report)
%PLOT_RFDAC_IQ_MISMATCH_SWEEP Plot measured EVM and the saved serpentine flow.
% Snake EVM uses point-averaged raw captures. Payload EVM uses the ordinary
% pulse-shaped receiver. Keep the two measurements separate in every figure.
t=report.Table;
assert(istable(t) && height(t)>0,'A nonempty sweep table is required.');
required={'IQ_Mismatch_Deg','Snake_EVM_dB','Snake_SER'};
assert(all(ismember(required,t.Properties.VariableNames)),'Sweep table is missing required measurements.');
folder=report.Output_Directory;
if ~isfolder(folder), mkdir(folder); end
visible='off';
if isfield(report,'Figure_Visible'), visible=report.Figure_Visible;
elseif isfield(report,'Configuration') && isfield(report.Configuration,'Figure_Visible')
    visible=report.Configuration.Figure_Visible;
end
target=-40;
if isfield(report,'Target_EVM_dB'), target=report.Target_EVM_dB; end
[angles,order]=sort(t.IQ_Mismatch_Deg);
figs=gobjects(0,1);
f=figure('Name','16384-point LUT: static IQ mismatch sweep','Color','w', ...
    'Visible',visible,'Renderer','painters','Position',[60 60 1120 810]);
figs(end+1,1)=f;
layout=tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
ax=nexttile(layout);
h=gobjects(0,1);
h(end+1,1)=plot(ax,angles,t.Snake_EVM_dB(order),'-o','Color',[.05 .4 .85], ...
    'LineWidth',1.5,'MarkerFaceColor',[.05 .4 .85]);
labels={'4096-point snake: point-averaged capture'};
hold(ax,'on');
if ismember('Payload_EVM_dB',t.Properties.VariableNames) && any(isfinite(t.Payload_EVM_dB))
    h(end+1,1)=plot(ax,angles,t.Payload_EVM_dB(order),'-s', ...
        'Color',[.82 .25 .1],'LineWidth',1.5,'MarkerFaceColor',[.82 .25 .1]);
    labels{end+1}='Random 4096-QAM: RRC payload';
end
h(end+1,1)=yline(ax,target,'k--','LineWidth',1.2);
labels{end+1}=sprintf('EVM target: %g dB',target);
grid(ax,'on'); box(ax,'on'); ylabel(ax,'EVM (dB)');
xlabel(ax,'Static IQ phase mismatch (deg)');
title(ax,'Actual RF captures after mapping from 16,384 measured training responses');
legend(ax,h,labels,'Location','best'); anglelimits(ax,angles);

ax=nexttile(layout);
h=gobjects(0,1);
h(end+1,1)=plot(ax,angles,100*t.Snake_SER(order),'-o','Color',[.05 .4 .85], ...
    'LineWidth',1.5,'MarkerFaceColor',[.05 .4 .85]);
labels={'4096-point snake: point-averaged capture'};
hold(ax,'on');
if ismember('Payload_SER',t.Properties.VariableNames) && any(isfinite(t.Payload_SER))
    h(end+1,1)=plot(ax,angles,100*t.Payload_SER(order),'-s', ...
        'Color',[.82 .25 .1],'LineWidth',1.5,'MarkerFaceColor',[.82 .25 .1]);
    labels{end+1}='Random 4096-QAM: RRC payload';
end
grid(ax,'on'); box(ax,'on'); ylabel(ax,'Measured symbol error rate (%)');
xlabel(ax,'Static IQ phase mismatch (deg)'); anglelimits(ax,angles);
legend(ax,h,labels,'Location','best');
title(ax,'Symbol error rate over the measured record');
sgtitle(layout,headline(report),'FontSize',15,'FontWeight','bold');
rfdac_export_figure(f,fullfile(folder,'iq_mismatch_evm.png'));

% Show only actual measured training nodes, rather than plotting a dense
% interpolation grid as though it were additional measured LUT capacity.
[caseData,index]=worstcase(report,t);
if ~isempty(caseData)
    f=figure('Name','16384 training responses to 4096-point output snake', ...
        'Color','w','Visible',visible,'Renderer','painters','Position',[40 70 1480 560]);
    figs(end+1,1)=f;
    layout=tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');
    ax=nexttile(layout);
    scatterpoints(ax,caseData.Training_Output,[.15 .4 .65]);
    title(ax,sprintf('1. Measured RF responses: %d points',numel(caseData.Training_Output)));
    ax=nexttile(layout);
    scatterpoints(ax,caseData.Mapped4096,[.8 .25 .1]);
    title(ax,sprintf('2. Mapped DAC inputs: %d targets',numel(caseData.Mapped4096)));
    ax=nexttile(layout);
    desired=caseData.Target4096(:);
    if isfield(caseData,'Snake_Received_Normalized')
        received=caseData.Snake_Received_Normalized(:);
    else
        received=caseData.Capture.Output(:);
        assert(numel(received)==numel(desired),'Capture and desired constellation have unequal lengths.');
        gain=(desired'*received)/(desired'*desired);
        assert(abs(gain)>eps,'Received serpentine signal has zero gain.');
        received=received/gain;
    end
    plot(ax,real(desired),imag(desired),'k+','MarkerSize',4); hold(ax,'on');
    plot(ax,real(received),imag(received),'.','Color',[.05 .4 .85],'MarkerSize',5);
    axesstyle(ax);
    title(ax,sprintf('3. Actual RF output: EVM %.2f dB',t.Snake_EVM_dB(index)));
    legend(ax,{'Desired 4096-QAM','Recovered; one scalar gain removed'},'Location','southoutside');
    sgtitle(layout,sprintf('Measured training -> mapped inputs -> actual output | IQ mismatch %.3g deg', ...
        t.IQ_Mismatch_Deg(index)),'FontSize',15,'FontWeight','bold');
    rfdac_export_figure(f,fullfile(folder,'iq_mismatch_serpentine.png'));
end
if nargout==0 && strcmpi(visible,'off'), close(figs); end
end

function [data,index]=worstcase(report,t)
data=[]; index=[];
if ~isfield(report,'Case_Files') || isempty(report.Case_Files), return; end
files=cellstr(string(report.Case_Files));
[~,rank]=sort(t.Snake_EVM_dB,'descend');
for k=1:numel(rank)
    row=rank(k);
    if row>numel(files) || isempty(files{row}) || ~isfinite(t.Snake_EVM_dB(row)), continue; end
    file=files{row};
    if ~isfile(file), file=fullfile(report.Output_Directory,file); end
    if ~isfile(file), continue; end
    saved=load(file,'caseData');
    if ~isfield(saved,'caseData'), continue; end
    value=saved.caseData;
    needed={'Training_Output','Mapped4096','Target4096'};
    if ~all(isfield(value,needed)), continue; end
    if ~isfield(value,'Snake_Received_Normalized') && ...
            (~isfield(value,'Capture') || ~isfield(value.Capture,'Output')), continue; end
    data=value; index=row; return;
end
end

function scatterpoints(ax,z,color)
z=z(:);
plot(ax,real(z),imag(z),'.','Color',color,'MarkerSize',4);
axesstyle(ax);
end

function axesstyle(ax)
axis(ax,'equal'); grid(ax,'on'); box(ax,'on');
xlabel(ax,'I (V)'); ylabel(ax,'Q (V)');
end

function anglelimits(ax,x)
width=max(max(x)-min(x),.25);
xlim(ax,[min(x)-.04*width max(x)+.04*width]);
if numel(x)<=21, xticks(ax,x); end
end

function value=headline(report)
value='16,384 measured LUT points | 4,096-QAM | interpolation from measured responses';
if ~isfield(report,'Configuration'), return; end
c=report.Configuration;
if all(isfield(c,{'LO_Frequency','LO_RMS_Jitter','TX_Target_EVM_dB'}))
    value=sprintf('16,384 measured points | LO %.3g GHz | jitter %.3g fs | clean TX EVM %.3g dB', ...
        c.LO_Frequency/1e9,c.LO_RMS_Jitter*1e15,c.TX_Target_EVM_dB);
    if isfield(report,'Calibration_Mode') && strcmp(report.Calibration_Mode,'iq_only')
        value=[value ' | IQ only'];
    end
end
end
