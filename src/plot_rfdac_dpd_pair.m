function f=plot_rfdac_dpd_pair(r)
% Compare actual final recovered symbols, with identical plant/data/jitter.
c=r.cfg; b=r.DPD_Comparison; ref=r.Reference_Constellation;
description='analytic';
if isfield(r.DPD,'Algorithm'), description=r.DPD.Algorithm; end
if strcmp(description,'lut')
    l=r.DPD.LUT;
    description=sprintf('LUT %dx%d / %s / %d-bit correction, F=%d',l.Size,l.Interpolation,l.Value_Bits,l.Fraction_Bits);
end
f=figure('Name','Final RX constellation: DPD before and after','Color','w', ...
    'Position',[60 40 1200 900],'Visible',c.Figure_Visible,'Renderer','painters');
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
symbols={b.Before_Received_Symbols,r.Received_Symbols}; metrics={b.Before_Metrics,r.metrics};
names={'DPD OFF','DPD ON'}; levels=unique(real(ref)); spacing=levels(2)-levels(1);
zoom=[levels(max(1,end-3))-.7*spacing levels(end)+.7*spacing];
full=1.12*max(abs([real(ref);imag(ref);real(symbols{1});imag(symbols{1});real(symbols{2});imag(symbols{2})]));
for k=1:2
    for row=1:2
        nexttile((row-1)*2+k);
        plot(real(ref),imag(ref),'k+','MarkerSize',5); hold on;
        z=symbols{k}; plot(real(z),imag(z),'.','Color',[.05 .4 .85],'MarkerSize',5);
        axis equal; grid on; xlabel('Recovered I'); ylabel('Recovered Q');
        if row==1
            xlim([-full full]); ylim([-full full]);
            title(sprintf('%s: EVM %.4f%% (%+.2f dB), SNDR %.2f dB', ...
                names{k},metrics{k}.EVM_Percent,metrics{k}.EVM_dB,metrics{k}.Estimated_SNR_dB));
        else
            xlim(zoom); ylim(zoom); title([names{k} ': identical corner zoom']);
        end
        legend('Ideal reference','Final recovered symbols','Location','southoutside');
    end
end
sgtitle(sprintf(['Final receiver constellation | %.2f GHz / %d-QAM / %d-bit input and output words\n' ...
    'Same analog TX beta %.5g | quadrature %.2f deg | jitter %.0f fs | seed %d | DPD IQ %d / NL %d\n%s'], ...
    c.LO_Frequency/1e9,c.QAM_Order,c.DAC_Bits,r.TX_Beta, ...
    c.LO_Quadrature_Error_Deg*c.LO_Quadrature_Error_Enable, ...
    c.LO_RMS_Jitter*1e15*c.LO_Jitter_Enable,c.Random_Seed,r.metrics.DPD_IQ_Enabled,r.metrics.DPD_Nonlinearity_Enabled,description));
rfdac_export_figure(f,fullfile(c.Output_Directory,[c.Run_Tag '_dpd_before_after_constellation.png']));
end
