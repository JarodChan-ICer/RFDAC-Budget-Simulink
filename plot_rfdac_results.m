function figs=plot_rfdac_results(results)
% Final receiver constellation first; every auxiliary figure has an init flag.
setup_rfdac_project();
if nargin<1, results=evalin('base','results'); end
c=results.cfg; defaults=rfdac_default_config();
c.Output_Directory=rfdac_output_directory(c.Output_Directory);
names={'Plot_Constellation','Plot_DPD_Comparison','Plot_DPD_LUT_Selection', ...
    'Plot_LPF_Response','Plot_Waveforms','Plot_Spectra','Plot_Diagnostics'};
for k=1:numel(names)
    if ~isfield(c,names{k}), c.(names{k})=defaults.(names{k}); end
end
figs=gobjects(0,1);
if ~c.Make_Plots, return; end
if ~isfolder(c.Output_Directory), mkdir(c.Output_Directory); end
results.cfg=c; w=results.waveforms; m=results.metrics;
if c.Plot_Constellation
    if c.Plot_DPD_Comparison && isfield(results,'DPD_Comparison')
        figs(end+1,1)=plot_rfdac_dpd_pair(results);
    else
        f=newfigure(c,'Final demodulated constellation',[60 60 1100 510]);
        tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
        nexttile; constellation(results.Received_Symbols,results.Reference_Constellation,false);
        title(sprintf('Final RX: EVM %.4f%% (%+.2f dB)',m.EVM_Percent,m.EVM_dB));
        nexttile; constellation(results.Received_Symbols,results.Reference_Constellation,true); title('Same recovered symbols: corner zoom');
        sgtitle(sprintf('%d-QAM | LO %.2f GHz | %d-bit codewords | DPD %d', ...
            c.QAM_Order,c.LO_Frequency/1e9,c.DAC_Bits,m.DPD_Enabled));
        export(f,c,'constellation'); figs(end+1,1)=f;
    end
end
if c.Plot_LPF_Response
    f=newfigure(c,'LPF response and RX in-band compensation',[80 80 1000 750]);
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact'); nexttile;
    frequency=results.filters.Frequency;
    rx=freqz(results.filters.RX_FIR,1,frequency,c.Sample_Rate);
    plot(frequency/1e9,20*log10(max(abs(results.filters.Response),1e-8)), ...
        frequency/1e9,20*log10(max(abs(rx),1e-8)),'--');
    grid on; ylim([-140 5]); xlim([0 min(c.DAC_Sample_Rate,c.Sample_Rate/2)/1e9]);
    xlabel('Frequency (GHz)'); ylabel('Magnitude (dB)'); legend('TX LPF','RX LPF');
    title(sprintf('FIR response: TX order %d / RX order %d',c.LPF_Order,c.RX_LPF_Order));
    nexttile;
    if isfield(results,'RX_Equalizer')
        eq=results.RX_Equalizer; inband=eq.Frequency_Hz<=eq.Bandwidth_Hz;
        plot(eq.Frequency_Hz(inband)/1e6,20*log10(max(abs(eq.Path_Response(inband)),eps)), ...
            eq.Frequency_Hz(inband)/1e6,20*log10(max(abs(eq.Response(inband)),eps)),'--', ...
            eq.Frequency_Hz(inband)/1e6,20*log10(max(abs(eq.Combined_Response(inband)),eps)),'LineWidth',1.3);
        grid on; xlabel('Baseband frequency (MHz)'); ylabel('Magnitude (dB)');
        legend('TX/RX LPFs + DAC hold','RX equalizer','Compensated path','Location','best');
        title(sprintf('RX equalizer %d: in-band ripple %.4f -> %.4f dB; peak gain %.2f dB', ...
            eq.Enabled,eq.Ripple_Before_dB,eq.Ripple_After_dB,eq.Peak_Gain_dB));
    else
        axis off; text(0,.5,'This saved result predates the RX equalizer.');
    end
    export(f,c,'lpf_response'); figs(end+1,1)=f;
end
if c.Plot_Waveforms
    f=newfigure(c,'RF DAC time-domain waveforms',[100 80 1250 950]);
    tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
    td=(0:numel(w.input_i)-1)'/c.DAC_Sample_Rate; tr=(0:numel(w.dac_i)-1)'/c.Sample_Rate;
    window=[2 10]/c.Symbol_Rate; di=find(td>=window(1)&td<=window(2)); ri=find(tr>=window(1)&tr<=window(2));
    nexttile;
    if isfield(w,'input_codes_i'), stairs(td(di)*1e9,w.input_codes_i(di),'--'); hold on; end
    stairs(td(di)*1e9,w.codes_i(di)); hold on; stairs(td(di)*1e9,w.codes_q(di)); grid on;
    if isfield(w,'input_codes_i'), legend('I input code','I output code','Q output code');
    else, legend('I DAC code','Q DAC code'); end
    xlabel('Time (ns)'); ylabel('Signed integer code'); title(sprintf('Actual %d-bit words at DAC input',c.DAC_Bits));
    nexttile; plot(tr(ri)*1e9,w.dac_i(ri),tr(ri)*1e9,w.filtered_i(ri),tr(ri)*1e9,w.filtered_q(ri)); grid on;
    legend('I DAC ZOH','I reconstruction LPF','Q reconstruction LPF'); xlabel('Time (ns)'); ylabel('V');
    nexttile; rfid=find(tr>=4/c.Symbol_Rate & tr<=4/c.Symbol_Rate+1e-9);
    plot(tr(rfid)*1e9,w.rf_before_gm(rfid),'--',tr(rfid)*1e9,w.rf_output(rfid)); grid on;
    legend('RF before unchanged TX nonlinearity','RF output'); xlabel('Time (ns)'); ylabel('V');
    nexttile; plot(tr(ri)*1e9,real(w.rx_baseband(ri)),tr(ri)*1e9,imag(w.rx_baseband(ri))); grid on;
    legend('Recovered I','Recovered Q'); xlabel('Time (ns)'); ylabel('V');
    sgtitle(sprintf('Continuous waveform preview, origin %.6f us',results.waveform_start_time.dac_i*1e6));
    export(f,c,'waveforms'); figs(end+1,1)=f;
end
if c.Plot_Spectra
    f=newfigure(c,'RF DAC spectra',[120 90 1200 750]);
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
    nexttile; spectrum(w.dac_i+1i*w.dac_q,c.Sample_Rate); hold on;
    spectrum(w.filtered_i+1i*w.filtered_q,c.Sample_Rate); grid on;
    xlim([-c.DAC_Sample_Rate c.DAC_Sample_Rate]/1e9); legend('DAC ZOH','Reconstruction LPF'); title('Complex baseband PSD');
    nexttile; spectrum(w.rf_before_gm,c.Sample_Rate); hold on; spectrum(w.rf_output,c.Sample_Rate); grid on;
    xlim([0 c.Sample_Rate/2]/1e9); legend('Real RF before nonlinearity','Real RF output'); title('Real RF PSD');
    export(f,c,'spectra'); figs(end+1,1)=f;
end
if c.Plot_Diagnostics
    f=newfigure(c,'Error vectors, timing jitter and unchanged analog TX',[100 70 1100 760]);
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    nexttile; er=results.Error_Vector.*exp(-1i*angle(results.Reference_Symbols));
    plot(real(er),imag(er),'.'); axis equal; grid on; xlabel('Radial error'); ylabel('Tangential error'); title('Final receiver error vectors');
    nexttile; t=results.waveform_start_time.lo_phase_error+(0:numel(results.TX_Jitter)-1)'/c.Sample_Rate;
    id=1:max(1,floor(numel(t)/10000)):numel(t);
    plot(t(id)*1e6,results.TX_Jitter(id)*1e15,t(id)*1e6,results.RX_Jitter(id)*1e15); grid on;
    xlabel('Time (us)'); ylabel('Timing error (fs)'); legend('TX','RX'); title('Jitter remains active');
    nexttile; x=linspace(-1.2*c.DAC_Full_Scale,1.2*c.DAC_Full_Scale,1000); k=max(sqrt(results.TX_Beta),eps);
    plot(x,x,'--',x,atan(k*x)/k,'LineWidth',1.3); grid on; xlabel('RF input (V)'); ylabel('RF output (V)');
    title(sprintf('Original analog TX: beta %.5g',results.TX_Beta)); legend('Linear','Actual TX');
    nexttile; axis off;
    text(0,1,sprintf('EVM %.5f %% / %.3f dB\nSNDR %.3f dB\nSER %.5g\nDPD %d, %d-bit words\nDAC quantization SQNR %.2f dB', ...
        m.EVM_Percent,m.EVM_dB,m.Estimated_SNR_dB,m.Symbol_Error_Rate,m.DPD_Enabled,c.DAC_Bits,m.DAC_SQNR_dB), ...
        'VerticalAlignment','top','FontSize',12);
    export(f,c,'diagnostics'); figs(end+1,1)=f;
end
if nargout==0 && strcmp(c.Figure_Visible,'off'), close(figs); end
end
function f=newfigure(c,name,position)
f=figure('Name',name,'Color','w','Position',position,'Visible',c.Figure_Visible,'Renderer','painters');
end
function export(f,c,suffix)
rfdac_export_figure(f,fullfile(c.Output_Directory,[c.Run_Tag '_' suffix '.png']));
end
function constellation(z,reference,zoom)
plot(real(reference),imag(reference),'k+','MarkerSize',6); hold on;
plot(real(z),imag(z),'.','Color',[.05 .4 .85],'MarkerSize',5);
axis equal; grid on; xlabel('I'); ylabel('Q');
if zoom
    levels=unique(real(reference)); spacing=levels(2)-levels(1);
    limits=[levels(max(1,end-3))-.7*spacing levels(end)+.7*spacing]; xlim(limits); ylim(limits);
end
legend('Ideal reference','Final recovered symbols','Location','southoutside');
end
function spectrum(x,fs)
n=min(32768,2^floor(log2(numel(x)/4)));
[power,f]=pwelch(x,hann(n,'periodic'),floor(n/2),n,fs,'centered');
plot(f/1e9,10*log10(max(power,realmin)),'LineWidth',1);
xlabel('Frequency (GHz)'); ylabel('PSD (dBV^2/Hz)');
end
