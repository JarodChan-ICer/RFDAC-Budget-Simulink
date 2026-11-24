function files=plot_rfdac_demodulated_qam(folder)
%PLOT_RFDAC_DEMODULATED_QAM Saved soft RX symbols, with full and corner views.
% Plot actual observations before hard decisions; no RF run or extra gain fit.
paths=setup_rfdac_project();
if nargin<1
    folder=fullfile(paths.Validation,'iq_mismatch_7GHz_42dB_16k_iq_only');
end
data=load(fullfile(folder,'iq_mismatch_report.mat'),'report'); report=data.report;
cases=cell(numel(report.Case_Files),1);
for k=1:numel(cases)
    saved=load(report.Case_Files{k},'caseData'); cases{k}=saved.caseData;
end
ideal=qammod((0:4095)',4096,'gray','UnitAveragePower',true);
levels=unique(real(ideal)); spacing=levels(2)-levels(1);
fullLimit=max(abs(levels))+1.3*spacing;
corner=[levels(end-4)-.6*spacing,levels(end)+.75*spacing];
mode='joint IQ / nonlinearity calibration';
if ~report.Configuration.DPD_Nonlinearity_Enable, mode='IQ-only calibration'; end
files=cell(2,1);
for source=1:2
    f=figure('Visible','off','Color','w','Renderer','painters', ...
        'Position',[40 40 1480 920]);
    layout=tiledlayout(f,2,numel(cases),'TileSpacing','compact','Padding','compact');
    for k=1:numel(cases)
        d=cases{k};
        if source==1
            received=d.Payload_Received(:); reference=d.Payload_Reference(:);
            m=d.Payload_Metrics; label='Payload';
        else
            received=d.Snake_Received_Normalized(:)/d.Configuration.Input_Amplitude;
            reference=d.Target4096(:)/d.Configuration.Input_Amplitude;
            m=d.Snake_Metrics; label='Serpentine';
        end
        wrong=qamdemod(received,4096,'gray','UnitAveragePower',true)~= ...
            qamdemod(reference,4096,'gray','UnitAveragePower',true);
        assert(sum(wrong)==m.Symbol_Errors,'Saved hard-decision errors disagree.');
        evm=20*log10(norm(received-reference)/norm(reference));
        assert(abs(evm-m.EVM_dB)<1e-9,'Saved EVM disagrees with plotted observations.');
        wrongPoints=received(wrong);
        if isempty(wrongPoints), wrongPoints=complex(NaN,NaN); end
        for zoom=0:1
            ax=nexttile(layout,k+zoom*numel(cases));
            hRef=plot(ax,real(ideal),imag(ideal),'+','Color',[.57 .59 .62], ...
                'MarkerSize',3+2*zoom,'LineWidth',.5); hold(ax,'on');
            hRx=plot(ax,real(received),imag(received),'.','Color',[.04 .36 .76], ...
                'MarkerSize',3+3*zoom);
            hErr=plot(ax,real(wrongPoints),imag(wrongPoints),'o', ...
                'Color',[.85 .12 .12],'MarkerSize',3+2*zoom,'LineWidth',.8);
            axis(ax,'equal'); grid(ax,'on'); box(ax,'on');
            ax.GridAlpha=.12; xlabel(ax,'Normalized I'); ylabel(ax,'Normalized Q');
            if zoom
                limits=corner;
                for j=numel(levels)-4:numel(levels)-1
                    xline(ax,(levels(j)+levels(j+1))/2,':','Color',[.82 .82 .82], ...
                        'HandleVisibility','off');
                    yline(ax,(levels(j)+levels(j+1))/2,':','Color',[.82 .82 .82], ...
                        'HandleVisibility','off');
                end
                title(ax,sprintf('%.0f deg: upper-right corner and decision boundaries',d.IQ_Mismatch_Deg));
            else
                limits=[-fullLimit fullLimit];
                title(ax,sprintf('IQ %.0f deg | EVM %.2f dB\n%d / %d symbol errors (%.3f%%)', ...
                    d.IQ_Mismatch_Deg,m.EVM_dB,sum(wrong),numel(received),100*mean(wrong)));
            end
            xlim(ax,limits); ylim(ax,limits);
            if k==1 && zoom==0
                leg=legend(ax,[hRef hRx hErr],{'Ideal 4096-QAM','Actual recovered observations', ...
                    'Observations decoded to the wrong symbol'},'Orientation','horizontal');
                leg.Layout.Tile='south';
            end
        end
    end
    c=report.Configuration;
    sgtitle(layout,sprintf('%s 4096-QAM | %s | TX %.0f dB | LO %.0f GHz | jitter %.0f fs', ...
        label,mode,-c.TX_Target_EVM_dB,c.LO_Frequency/1e9,c.LO_RMS_Jitter*1e15), ...
        'FontWeight','bold','FontSize',16);
    files{source}=fullfile(folder,sprintf('demodulated_%s_qam.png',lower(label)));
    rfdac_export_figure(f,files{source}); close(f);
end
end
