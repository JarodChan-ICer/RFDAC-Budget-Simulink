function figs=plot_rfdac_identification(report)
%PLOT_RFDAC_IDENTIFICATION RX identification estimates and four DPD modes.
% Cases are ordered: TX only, IQ only, both, none. Each case contains final
% recovered symbols, ideal reference constellation, and measured EVM/MER.
% Truth is used only to label the diagnostic plots, never for estimation.
folder=report.Output_Directory;
if ~isfolder(folder), mkdir(folder); end
visible='off';
if isfield(report,'Figure_Visible'), visible=report.Figure_Visible; end
cases=report.Cases;
if isstruct(cases), cases=num2cell(cases); end
assert(iscell(cases) && numel(cases)==4,'Expected four calibration cases.');
names={'TX nonlinearity only','Static IQ only','TX + static IQ','No calibration'};
extent=0;
for k=1:4
    z=cases{k}.Received_Symbols(:); reference=cases{k}.Reference_Constellation(:);
    assert(~isempty(z) && all(isfinite(z)) && all(isfinite(reference)), ...
        'Constellation data must be finite and nonempty.');
    extent=max(extent,max(abs([real(z);imag(z);real(reference);imag(reference)])));
end
extent=max(extent,eps)*1.10;
figs=gobjects(2,1);
figs(1)=figure('Name','RX validation: four calibration modes','Color','w', ...
    'Position',[40 40 1450 1050],'Visible',visible,'Renderer','painters');
layout=tiledlayout(figs(1),2,2,'TileSpacing','compact','Padding','compact');
mainAxes=gobjects(4,1);
for k=1:4
    c=cases{k}; ax=nexttile(layout,k); mainAxes(k)=ax;
    reference=c.Reference_Constellation(:); z=c.Received_Symbols(:);
    constellation(ax,reference,z,false);
    xlim(ax,[-extent extent]); ylim(ax,[-extent extent]);
    label=names{k};
    if isfield(c,'Label') && ~isempty(c.Label), label=char(c.Label); end
    title(ax,sprintf('%s\nEVM %.4f%% (%+.2f dB) | RX MER %.2f dB', ...
        label,c.EVM_Percent,c.EVM_dB,c.MER_dB),'Interpreter','none');
    legend(ax,'Ideal reference','Recovered symbols','Location','southoutside');
end
mode='unspecified';
if isfield(report,'Config') && isfield(report.Config,'Jitter_Mode'), mode=report.Config.Jitter_Mode; end
sgtitle(layout,sprintf(['Held-out RX constellation comparison | LO %.2f GHz | jitter %.0f fs RMS (%s)\n' ...
    'DPD uses RX-estimated parameters only | 10-bit input/output words'], ...
    report.Truth.LO_Frequency/1e9,report.Truth.Jitter_RMS_s*1e15,mode));

% An identical corner inset makes high-order QAM residuals visible while
% retaining the full four-quadrant constellation as the primary figure.
showInset=numel(cases{1}.Reference_Constellation)>=256;
if isfield(report,'Show_Corner_Inset'), showInset=logical(report.Show_Corner_Inset); end
if showInset
    drawnow;
    reference=cases{1}.Reference_Constellation(:);
    levels=unique(real(reference));
    if numel(levels)>1
        spacing=median(diff(levels));
        limits=[levels(max(1,end-3))-.7*spacing levels(end)+.7*spacing];
        for k=1:4
            position=getpixelposition(mainAxes(k),true);
            insetPosition=[position(1)+.57*position(3),position(2)+.045*position(4), ...
                .39*position(3),.39*position(4)];
            ax=axes('Parent',figs(1),'Units','pixels','Position',insetPosition, ...
                'Color','w','FontSize',7,'Box','on');
            set(ax,'Units','normalized');
            c=cases{k};
            constellation(ax,c.Reference_Constellation(:),c.Received_Symbols(:),true);
            xlim(ax,limits); ylim(ax,limits);
            xlabel(ax,''); ylabel(ax,''); title(ax,''); xticks(ax,[]); yticks(ax,[]);
            text(ax,.03,.97,'Same corner zoom','Units','normalized', ...
                'VerticalAlignment','top','FontSize',7,'BackgroundColor','w','Margin',1);
            rectangle(mainAxes(k),'Position',[limits(1) limits(1) diff(limits) diff(limits)], ...
                'EdgeColor',[.1 .1 .1],'LineStyle','--','LineWidth',.8);
        end
    end
end
rfdac_export_figure(figs(1),fullfile(folder,'identification_four_cases.png'));

figs(2)=figure('Name','RX identification: truth and uncertainty','Color','w', ...
    'Position',[80 80 1200 560],'Visible',visible,'Renderer','painters');
layout=tiledlayout(figs(2),1,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(layout);
interval=[];
if isfield(report.Estimate,'TX_SNR_CI95_dB'), interval=report.Estimate.TX_SNR_CI95_dB; end
estimate_panel(ax,report.Truth.TX_SNR_dB,report.Estimate.TX_SNR_dB,interval, ...
    'TX EVM-equivalent SNDR (dB)','TX performance');
ax=nexttile(layout);
interval=[];
if isfield(report.Estimate,'IQ_CI95_Deg'), interval=report.Estimate.IQ_CI95_Deg; end
estimate_panel(ax,report.Truth.IQ_Error_Deg,report.Estimate.IQ_Error_Deg,interval, ...
    'Effective static IQ phase error (deg)','Static IQ mismatch');
sgtitle(layout,'Configured truth vs RX-only estimates | 95% confidence intervals when available');
rfdac_export_figure(figs(2),fullfile(folder,'identification_estimates.png'));
if nargout==0 && strcmpi(visible,'off'), close(figs); end
end

function constellation(ax,reference,z,inset)
if inset, refSize=5; rxSize=5; else, refSize=3; rxSize=3; end
plot(ax,real(reference),imag(reference),'k+','MarkerSize',refSize); hold(ax,'on');
plot(ax,real(z),imag(z),'.','Color',[.05 .4 .85],'MarkerSize',rxSize);
axis(ax,'equal'); grid(ax,'on'); xlabel(ax,'Recovered I'); ylabel(ax,'Recovered Q');
end

function estimate_panel(ax,truth,estimate,interval,label,name)
validateattributes(truth,{'numeric'},{'scalar','real','finite'});
validateattributes(estimate,{'numeric'},{'scalar','real','finite'});
plot(ax,1,truth,'kd','MarkerFaceColor','k','MarkerSize',8); hold(ax,'on');
plot(ax,2,estimate,'o','Color',[.05 .4 .85],'MarkerFaceColor',[.05 .4 .85],'MarkerSize',8);
hasInterval=numel(interval)==2 && all(isfinite(interval));
if hasInterval
    interval=sort(interval(:));
    assert(interval(1)<=estimate && estimate<=interval(2),'CI must contain its estimate.');
    errorbar(ax,2,estimate,estimate-interval(1),interval(2)-estimate, ...
        'Color',[.05 .4 .85],'LineWidth',1.5,'CapSize',14,'LineStyle','none');
    values=[truth;estimate;interval];
    caption=sprintf('RX estimate %.5g | 95%% CI [%.5g, %.5g]',estimate,interval(1),interval(2));
else
    values=[truth;estimate]; caption=sprintf('RX estimate %.5g | CI unavailable',estimate);
end
span=max(values)-min(values); padding=max(.3*span,1e-4);
xlim(ax,[.5 2.5]); ylim(ax,[min(values)-padding max(values)+padding]);
xticks(ax,[1 2]); xticklabels(ax,{'Configured truth','RX estimate'});
ylabel(ax,label); grid(ax,'on');
title(ax,sprintf('%s\nTruth %.5g | signed error %+.5g',name,truth,estimate-truth));
xlabel(ax,caption,'FontSize',10);
end
