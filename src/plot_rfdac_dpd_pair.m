function f=plot_rfdac_dpd_pair(r)
% Two recovered constellations above one centered training RF-output panel.
c=r.cfg; b=r.DPD_Comparison; ref=r.Reference_Constellation;
description='analytic';
if isfield(r.DPD,'Algorithm'), description=r.DPD.Algorithm; end
hasTraining=strcmp(description,'lut') && isfield(r.DPD,'LUT') && ...
    isfield(r.DPD.LUT,'Output_I');
if strcmp(description,'lut')
    l=r.DPD.LUT;
    if isfield(l,'Training_Order')
        description=sprintf('Trained %d-QAM alphabet / %s / %d-bit training inputs', ...
            l.Training_Order,l.Interpolation,l.Value_Bits);
        if strcmp(l.Format,'ppt_measured_2d_lut_v1')
            description=sprintf('PPT 2D LUT: %d measured -> %d interpolated DAC inputs / %d-bit', ...
                l.Training_Order,l.Points,l.Value_Bits);
        end
    else
        description=sprintf('Historical correction LUT %dx%d / %s / %d-bit, F=%d', ...
            l.Size,l.Interpolation,l.Value_Bits,l.Fraction_Bits);
    end
end
showSelection=~isfield(c,'Plot_DPD_LUT_Selection') || c.Plot_DPD_LUT_Selection;
showTraining=showSelection && hasTraining && r.DPD.Enabled && ...
    (r.DPD.IQ_Enable || r.DPD.Nonlinearity_Enable);
if showTraining, height=1060; else, height=560; end
f=figure('Name','DPD before/after and training RF constellation','Color','w', ...
    'Position',[60 30 1250 height],'Visible',c.Figure_Visible,'Renderer','painters');
if showTraining
    layout=tiledlayout(f,2,4,'TileSpacing','compact','Padding','compact');
else
    layout=tiledlayout(f,1,4,'TileSpacing','compact','Padding','compact');
end
symbols={b.Before_Received_Symbols,r.Received_Symbols};
metrics={b.Before_Metrics,r.metrics}; names={'DPD OFF','DPD ON'};
full=1.12*max(abs([real(ref);imag(ref);real(symbols{1});imag(symbols{1}); ...
    real(symbols{2});imag(symbols{2})]));
for k=1:2
    ax=nexttile(layout,1+2*(k-1),[1 2]);
    set(ax,'Tag',sprintf('rfdac_rx_constellation_axes_%d',k));
    hRef=plot(ax,real(ref),imag(ref),'k+','MarkerSize',5); hold(ax,'on');
    z=symbols{k};
    hRX=plot(ax,real(z),imag(z),'.','Color',[.05 .4 .85],'MarkerSize',5, ...
        'Tag',sprintf('rfdac_rx_symbols_%d',k));
    axis(ax,'equal'); grid(ax,'on'); box(ax,'on');
    xlabel(ax,'Recovered I'); ylabel(ax,'Recovered Q');
    xlim(ax,[-full full]); ylim(ax,[-full full]);
    title(ax,sprintf('%s: EVM %.4f%% (%+.2f dB), SNDR %.2f dB', ...
        names{k},metrics{k}.EVM_Percent,metrics{k}.EVM_dB,metrics{k}.Estimated_SNR_dB));
    legend(ax,[hRef hRX],{'Ideal reference','Final recovered symbols'}, ...
        'Location','southoutside');
end
if showTraining
    usage=rfdac_lut_usage(r);
    trainingOutput=r.DPD.LUT.Training_Output(:);
    pptMode=strcmp(r.DPD.LUT.Format,'ppt_measured_2d_lut_v1');
    if pptMode, trainingOutput=r.DPD.LUT.Dense_Output(:); end
    selected=trainingOutput(usage.Mapped);
    % Tiles 6--7 center a panel of the same width below the two top panels.
    ax=nexttile(layout,6,[1 2]); set(ax,'Tag','rfdac_lut_training_axes');
    shown=1:numel(trainingOutput);
    if pptMode, shown=unique(round(linspace(1,numel(trainingOutput),min(60000,numel(trainingOutput))))); end
    hAll=plot(ax,real(trainingOutput(shown)),imag(trainingOutput(shown)),'.', ...
        'Color',[.40 .57 .73],'MarkerSize',4,'Tag','rfdac_lut_training_outputs');
    hold(ax,'on');
    hSelected=plot(ax,real(selected),imag(selected),'.','Color',[.88 .08 .12], ...
        'MarkerSize',5,'Tag','rfdac_selected_lut_overlay');
    axis(ax,'equal'); grid(ax,'on'); box(ax,'on');
    extent=1.08*max(abs([real(trainingOutput);imag(trainingOutput)]));
    xlim(ax,[-extent extent]); ylim(ax,[-extent extent]);
    if pptMode
        xlabel(ax,'Phase-aligned RX envelope I (V)'); ylabel(ax,'Phase-aligned RX envelope Q (V)');
        title(ax,sprintf('Measured %d-point snake -> interpolated 2D LUT; red: actual DAC selections',r.DPD.LUT.Training_Order));
        if isfield(r.DPD.LUT,'Calibration_Mode') && strcmp(r.DPD.LUT.Calibration_Mode,'iq_only')
            xlabel(ax,'Fitted linear IQ output I (V)'); ylabel(ax,'Fitted linear IQ output Q (V)');
            title(ax,'IQ-only fitted mapping responses; TX radial compression is uncompensated');
        end
    elseif isfield(r.DPD,'Placement') && strcmp(r.DPD.Placement,'symbol_before_rrc')
        xlabel(ax,'Demodulated training I (V)'); ylabel(ax,'Demodulated training Q (V)');
        title(ax,sprintf('%d-QAM through actual RFDAC + RX: measured centroids',r.DPD.LUT.Training_Order));
    else
        xlabel(ax,'RF output fundamental I (V)'); ylabel(ax,'RF output fundamental Q (V)');
        title(ax,sprintf('%d-QAM static-model reference (not a link capture)',r.DPD.LUT.Training_Order));
    end
    background=sprintf('All %d training outputs',usage.Total_Points);
    if pptMode, background=sprintf('%d interpolated outputs (%d shown)',usage.Total_Points,numel(shown)); end
    legend(ax,[hAll hSelected],{background, ...
        sprintf('Selected %d points (%.1f%%)',usage.Used_Points, ...
        100*usage.Used_Points/usage.Total_Points)},'Location','southoutside');
end
sgtitle(layout,sprintf(['Final receiver constellation | %.2f GHz / %d-QAM / %d-bit DAC\n' ...
    'TX target %.2f dB | IQ %.2f deg | jitter %.0f fs\n' ...
    '%s | beta %.5g | seed %d | DPD IQ %d / NL %d'], ...
    c.LO_Frequency/1e9,c.QAM_Order,c.DAC_Bits,-c.TX_Target_EVM_dB, ...
    c.LO_Quadrature_Error_Deg*c.LO_Quadrature_Error_Enable, ...
    c.LO_RMS_Jitter*1e15*c.LO_Jitter_Enable,description,r.TX_Beta,c.Random_Seed, ...
    r.metrics.DPD_IQ_Enabled,r.metrics.DPD_Nonlinearity_Enabled));
rfdac_export_figure(f,fullfile(c.Output_Directory,[c.Run_Tag '_dpd_before_after_constellation.png']));
if showTraining
    save(fullfile(c.Output_Directory,[c.Run_Tag '_dpd_lut_training_selection.mat']), ...
        'usage','trainingOutput','selected');
end
end
