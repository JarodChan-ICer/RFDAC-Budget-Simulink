function f=plot_rfdac_identification_reliability(report)
%PLOT_RFDAC_IDENTIFICATION_RELIABILITY Conditional repeated-training evidence.
% Truth is used only to score estimates. Coverage is empirical over the
% supplied trials and is not a guarantee of confidence-interval calibration.
folder=report.Output_Directory;
if ~isfolder(folder), mkdir(folder); end
visible='off';
if isfield(report,'Figure_Visible'), visible=report.Figure_Visible; end
e=report.Estimate; truth=report.Truth; trials=report.Identification_Trials;
assert(istable(trials) && height(trials)>0,'Identification_Trials must be a nonempty table.');
repeated=height(trials)>1;
f=figure('Name','RX identification reliability','Color','w','Renderer','painters', ...
    'Visible',visible,'Position',[60 40 1450 1000]);
layout=tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');

ax=nexttile(layout,1);
power=e.Low_Amplitude_Power(:); iq=e.Low_Amplitude_IQ_Deg(:);
se=e.Low_Amplitude_IQ_SE_Deg(:);
assert(numel(power)==numel(iq) && numel(se)==numel(iq),'Low-drive arrays must have equal lengths.');
assert(all(isfinite(power)) && all(power>=0) && all(isfinite(iq)));
[power,order]=sort(power); iq=iq(order); se=se(order);
assert(all(isfinite(se)) && all(se>=0),'Low-drive standard errors must be finite and nonnegative.');
h1=errorbar(ax,power,iq,1.96*se,'o','Color',[.05 .4 .85], ...
    'MarkerFaceColor',[.05 .4 .85],'LineStyle','none','LineWidth',1.1,'CapSize',8);
hold(ax,'on');
h2=plot(ax,0,e.IQ_Error_Deg,'s','Color',[.8 .25 .1],'MarkerFaceColor',[.8 .25 .1],'MarkerSize',8);
if isfield(e,'IQ_CI95_Deg') && numel(e.IQ_CI95_Deg)==2 && all(isfinite(e.IQ_CI95_Deg))
    limits=sort(e.IQ_CI95_Deg(:));
    plot(ax,[0 0],limits,'Color',[.8 .25 .1],'LineWidth',1.4);
end
h3=yline(ax,truth.IQ_Error_Deg,'k--','LineWidth',1.1);
grid(ax,'on'); xlabel(ax,'Known training drive power'); ylabel(ax,'Effective IQ phase error (deg)');
title(ax,'Low-drive measurements and zero-power extrapolation');
legend(ax,[h1 h2 h3],{'Capture fit +/- 1.96 SE','Zero-power estimate','Configured truth'}, ...
    'Location','best');
width=max(max(power),eps); xlim(ax,[-.06*width 1.08*width]);

ax=nexttile(layout,2);
interval_series(ax,trials.Trial,trials.IQ_Error_Deg,trials.IQ_CI_Low,trials.IQ_CI_High,truth.IQ_Error_Deg);
ylabel(ax,'Effective IQ phase error (deg)');
if repeated, title(ax,'Independent training trials: IQ estimate and 95% CI');
else, title(ax,'Primary identification: IQ estimate and conditional 95% CI'); end

ax=nexttile(layout,3);
interval_series(ax,trials.Trial,trials.TX_SNR_dB,trials.SNR_CI_Low,trials.SNR_CI_High,truth.TX_SNR_dB);
ylabel(ax,'TX EVM-equivalent SNDR (dB)');
if repeated, title(ax,'Independent training trials: TX estimate and 95% CI');
else, title(ax,'Primary identification: TX estimate and conditional 95% CI'); end

% Recompute descriptive scores from the plotted trials to avoid assumptions
% about optional names in report.Reliability or inconsistent cached scores.
iqError=trials.IQ_Error_Deg-truth.IQ_Error_Deg;
snrError=trials.TX_SNR_dB-truth.TX_SNR_dB;
iqCoverage=mean(trials.IQ_CI_Low<=truth.IQ_Error_Deg & truth.IQ_Error_Deg<=trials.IQ_CI_High);
snrCoverage=mean(trials.SNR_CI_Low<=truth.TX_SNR_dB & truth.TX_SNR_dB<=trials.SNR_CI_High);
ax=nexttile(layout,4); axis(ax,'off');
assumptions=sprintf(['CONDITIONAL IDENTIFICATION CHECK\n\n' ...
    'Assumed atan AM/AM family; nominal calibrated filters.\n' ...
    'Coherent calibrated RX; known pilots and jitter statistics.\n' ...
    'No true TX beta, IQ offset or jitter trace given to estimator.\n\n']);
if repeated
    scores=sprintf([ ...
    'Independent training trials: %d\n' ...
    'IQ bias / RMSE: %+.5g / %.5g deg\n' ...
    'TX bias / RMSE: %+.5g / %.5g dB\n' ...
    'Observed 95%% CI coverage: IQ %.1f%%; TX %.1f%%\n\n' ...
    'Small trial count: coverage is descriptive, not a guarantee.\n'], ...
    height(trials),mean(iqError),sqrt(mean(iqError.^2)),mean(snrError),sqrt(mean(snrError.^2)), ...
    100*iqCoverage,100*snrCoverage);
else
    scores=sprintf(['Primary identification only; extra repeats disabled.\n' ...
        'Primary signed errors: IQ %+.5g deg; TX %+.5g dB\n' ...
        'Repeatability / repeated-trial RMSE / coverage: not evaluated.\n' ...
        'Set opt.Monte_Carlo_Repeats = 5 for six total fits.\n' ...
        'Shown CIs are conditional single-fit intervals.\n'],iqError,snrError);
end
summary=[assumptions scores sprintf(['\n' ...
    'The primary estimate alone controls all four DPD cases.\n' ...
    'Unmodeled RX errors, drift and model mismatch are outside CI.\n' ...
    'TX value describes deterministic EVM-equivalent SNDR.'])];
text(ax,0,1,summary,'VerticalAlignment','top','FontName','Consolas','FontSize',11,'Interpreter','none');
sgtitle(layout,'Receiver-only identification: amplitude consistency and conditional uncertainty');
rfdac_export_figure(f,fullfile(folder,'identification_reliability.png'));
if nargout==0 && strcmpi(visible,'off'), close(f); end
end

function interval_series(ax,index,value,lo,hi,truth)
index=double(index(:)); value=value(:); lo=lo(:); hi=hi(:);
assert(all(isfinite([index;value;lo;hi])) && all(lo<=hi),'Trial estimates and intervals must be finite and ordered.');
hold(ax,'on');
for k=1:numel(index)
    plot(ax,[index(k) index(k)],[lo(k) hi(k)],'-','Color',[.05 .4 .85],'LineWidth',1.2);
    plot(ax,index(k)+[-.10 .10],[lo(k) lo(k)],'-','Color',[.05 .4 .85]);
    plot(ax,index(k)+[-.10 .10],[hi(k) hi(k)],'-','Color',[.05 .4 .85]);
end
plot(ax,index,value,'o','Color',[.05 .4 .85],'MarkerFaceColor',[.05 .4 .85],'MarkerSize',5);
yline(ax,truth,'k--','Configured truth','LineWidth',1.1);
grid(ax,'on'); xlabel(ax,'Independent training trial');
xlim(ax,[min(index)-.5 max(index)+.5]);
if numel(index)<=20, xticks(ax,index); end
end
