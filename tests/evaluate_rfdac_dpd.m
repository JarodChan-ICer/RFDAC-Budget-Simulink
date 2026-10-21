function report=evaluate_rfdac_dpd(cfg)
% Compare digital IQ/AMAM calibration and random-jitter-limited performance.
if nargin<1, cfg=init_rfdac_model(); end
usercfg=cfg;
cfg.LO_Quadrature_Error_Deg=1; % dedicated example; do not edit user defaults
cfg.DPD_Quadrature_Estimate_Deg=[]; cfg.DPD_TX_Beta_Estimate=[];
cfg.DPD_Phase_Errors_Estimate_Deg=[];
cfg.Make_Plots=false; cfg.Save_Results=false; cfg.Figure_Visible='off';
paths=setup_rfdac_project(); cfg.Output_Directory=fullfile(paths.Validation,'dpd_evaluation');
if ~isfolder(cfg.Output_Directory), mkdir(cfg.Output_Directory); end
labels={'DPD off','IQ calibration','Nonlinear DPD','Joint DPD'};
flags=[0 0;1 0;0 1;1 1];
rows={}; symbols=cell(2,4); errors=symbols;
for clock=0:1
    for mode=1:4
        c=cfg; c.LO_Jitter_Enable=logical(clock); c.DPD_Enable=mode>1;
        c.DPD_IQ_Enable=logical(flags(mode,1)); c.DPD_Nonlinearity_Enable=logical(flags(mode,2));
        c.Run_Tag=sprintf('clock%d_mode%d',clock,mode);
        c.Save_Results=ismember(mode,[1 4]);
        r=run_rfdac_simulation(c);
        rows{end+1,1}=make_row(labels{mode},r); %#ok<AGROW>
        symbols{clock+1,mode}=r.Received_Symbols;
        errors{clock+1,mode}=r.Error_Vector;
        if clock==0 && mode==1, beta=r.TX_Beta; end
        assert(abs(r.TX_Beta-beta)<1e-12,'DPD toggling changed the physical TX model.');
        assert(r.metrics.DPD_Limited_Samples==0,'Nominal DPD hits its gain limit.');
        assert(r.metrics.DPD_DAC_I_Clipped_Full+r.metrics.DPD_DAC_Q_Clipped_Full==0,'Nominal DPD clips a DAC.');
        if mode==4
            joint{clock+1}=r; %#ok<AGROW>
        end
    end
end
report.Table=vertcat(rows{:});
assert(report.Table.EVM_Percent(4)<report.Table.EVM_Percent(1)/3,'Joint DPD did not suppress deterministic distortion.');
assert(report.Table.EVM_Percent(8)<report.Table.EVM_Percent(5),'DPD did not improve jitter-on performance.');
assert(report.Table.EVM_Percent(8)>report.Table.EVM_Percent(4),'Random jitter floor disappeared unexpectedly.');

% Ideal deterministic plant floor, and its random-jitter-limited counterpart.
for clock=0:1
    c=cfg; c.TX_Nonlinearity_Enable=false; c.LO_Quadrature_Error_Enable=false;
    c.DPD_Enable=false; c.LO_Jitter_Enable=logical(clock);
    r=run_rfdac_simulation(c);
    report.Linear_Reference{clock+1}=r.metrics;
end
report.Reference_Symbols=joint{1}.Reference_Symbols;
report.Reference_Constellation=joint{1}.Reference_Constellation;
report.Received_Symbols=symbols; report.Error_Vectors=errors;
report.Config=cfg; report.User_Config=usercfg; report.Frozen_TX_Beta=beta;

% Reuse the same physical plant on a different random record (no replay).
c=cfg; c.Num_Symbols=1024; c.Random_Seed=cfg.Random_Seed+101;
c.TX_Nonlinearity_Beta=beta; c.LO_Jitter_Enable=false; c.DPD_Enable=false;
a=run_rfdac_simulation(c); c.DPD_Enable=true; c.DPD_IQ_Enable=true; c.DPD_Nonlinearity_Enable=true;
b=run_rfdac_simulation(c);
assert(b.metrics.EVM_Percent<a.metrics.EVM_Percent/3,'Held-out-seed DPD improvement failed.');
report.Held_Out_Seed=[a.metrics.EVM_Percent b.metrics.EVM_Percent];

% Pure IQ test: zero-degree estimate leaves the 1-degree impairment intact.
c=cfg; c.Num_Symbols=512; c.TX_Nonlinearity_Enable=false;
c.DPD_Enable=true; c.DPD_IQ_Enable=true; c.DPD_Nonlinearity_Enable=false;
c.LO_Jitter_Enable=false; c.DPD_Quadrature_Estimate_Deg=0;
a=run_rfdac_simulation(c); c.DPD_Quadrature_Estimate_Deg=1;
b=run_rfdac_simulation(c);
assert(b.metrics.EVM_Percent<a.metrics.EVM_Percent/3,'Static 1-degree calibration failed.');
report.IQ_Estimate_Mismatch=[a.metrics.EVM_Percent b.metrics.EVM_Percent];

% Inverse saturation must stay finite and be reported under deliberate drive.
c=cfg; c.Num_Symbols=128; c.TX_Nonlinearity_Beta=beta; c.Input_Amplitude=3;
c.DPD_Enable=true; c.DPD_IQ_Enable=true; c.DPD_Nonlinearity_Enable=true;
c.DPD_TX_Beta_Estimate=3; % deliberate bad estimate exercises inverse gain bound
r=run_rfdac_simulation(c);
assert(r.metrics.DPD_Limited_Samples>0 && r.metrics.DPD_DAC_I_Clipped_Full>0);
assert(all(isfinite(r.waveforms.rf_output)),'Overdrive inverse was not bounded.');
report.Overdrive_Safeguard_Passed=true;

% Known model: validate RF fundamental inverse analytically and numerically.
A=linspace(.01,.9,31)'; k=sqrt(beta); angle=(0:4095)*2*pi/4096;
numeric=2*mean(atan(k*A.*cos(angle))/k.*cos(angle),2);
formula=2*A./(1+sqrt(1+beta*A.^2));
assert(max(abs(numeric-formula))<1e-10);
drive=A./(1-beta*A.^2/4);
assert(max(abs(2*drive./(1+sqrt(1+beta*drive.^2))-A))<1e-10);
report.Fundamental_Inverse_Passed=true;

% Historical 24 GHz example, with its original target and a shorter record.
c=cfg; c.LO_Frequency=24e9; c.RX_LO_Frequency=[]; c.QAM_Order=1024;
c.TX_Target_EVM_dB=-43; c.TX_Nonlinearity_Beta=[]; c.Num_Symbols=2048;
c.DPD_IQ_Enable=true; c.DPD_Nonlinearity_Enable=true;
refrows={};
for clock=0:1
    for enabled=0:1
        c.LO_Jitter_Enable=logical(clock); c.DPD_Enable=logical(enabled);
        r=run_rfdac_simulation(c);
        refrows{end+1,1}=make_row(sprintf('DPD %d',enabled),r); %#ok<AGROW>
    end
end
report.Reference_24GHz=vertcat(refrows{:});
assert(report.Reference_24GHz.EVM_Percent(2)<report.Reference_24GHz.EVM_Percent(1)/3);
assert(report.Reference_24GHz.EVM_Percent(4)<report.Reference_24GHz.EVM_Percent(3));

writetable(report.Table,fullfile(cfg.Output_Directory,'dpd_comparison.csv'));
writetable(report.Reference_24GHz,fullfile(cfg.Output_Directory,'dpd_24ghz_reference.csv'));
plot_rfdac_dpd_comparison(report);
% Detailed saved waveform plots for the jointly corrected operating point.
joint{2}.cfg.Make_Plots=true; joint{2}.cfg.Figure_Visible='off';
plot_rfdac_results(joint{2});
report.All_Passed=true;
save(fullfile(cfg.Output_Directory,'dpd_report.mat'),'report');
fid=fopen(fullfile(cfg.Output_Directory,'dpd_report.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'DPD BEFORE I/Q DACs: ALL VALIDATION CHECKS PASSED\n');
fprintf(fid,'Current plant %.3f GHz, %d-QAM, %d symbols, TX target %.2f dB; example IQ error 1 degree\n', ...
    cfg.LO_Frequency/1e9,cfg.QAM_Order,cfg.Num_Symbols,cfg.TX_Target_EVM_dB);
fprintf(fid,'Uncorrected / joint DPD, jitter OFF: %.8f / %.8f %% EVM\n',report.Table.EVM_Percent(1),report.Table.EVM_Percent(4));
fprintf(fid,'Uncorrected / joint DPD, jitter ON:  %.8f / %.8f %% EVM\n',report.Table.EVM_Percent(5),report.Table.EVM_Percent(8));
fprintf(fid,'Linear references, jitter OFF / ON: %.8f / %.8f %% EVM\n', ...
    report.Linear_Reference{1}.EVM_Percent,report.Linear_Reference{2}.EVM_Percent);
fprintf(fid,'Known-model inverse: optimistic calibration bound, not feedback-trained hardware DPD.\n');
fprintf(fid,'Nominal gain limit and full-record DAC clipping counts are zero.\n');
fprintf(fid,'Held-out seed, 1-degree estimate mismatch, bounded overdrive and RF inverse formula checks passed.\n');
disp(report.Table); disp(report.Reference_24GHz); disp('ALL DPD CHECKS PASSED.');
assignin('base','cfg',usercfg); assignin('base','results',joint{2}); close all;
if bdIsLoaded(usercfg.Model_Name), close_system(usercfg.Model_Name,0); end
end
function row=make_row(name,r)
m=r.metrics;
row=table(string(name),r.cfg.LO_Jitter_Enable,m.EVM_Percent,m.EVM_dB,m.Estimated_SNR_dB, ...
    m.Symbol_Error_Rate,m.DPD_Drive_Power_Expansion_dB,m.DPD_Limited_Samples, ...
    m.DPD_DAC_I_Clipped_Full+m.DPD_DAC_Q_Clipped_Full, ...
    'VariableNames',{'Mode','Jitter_On','EVM_Percent','EVM_dB','SNDR_dB','SER','Drive_Expansion_dB','Limited_Samples','DAC_Clipped_Samples'});
end
