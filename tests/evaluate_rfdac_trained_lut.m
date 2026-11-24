function report=evaluate_rfdac_trained_lut()
% Fixed-plant RF replay against the original result; preserve outputs/results.
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'outputs','validation','trained_lut_20261101');
if ~isfolder(folder), mkdir(folder); end
saved=load(fullfile(root,'outputs','results','single_results.mat'),'results');
original=saved.results; clear saved;
c=original.cfg;
c.TX_Nonlinearity_Beta=original.TX_Beta;
c.DPD_LUT_Size_Mode='training_order'; c.DPD_LUT_Training_Order=16384;
c.DPD_LUT_Training_Observed=[];
c.DPD_LUT_Fraction_Bits=0; c.DPD_LUT_Interpolation='nearest';
c.DPD_LUT_Value_Bits=c.DAC_Bits;
report.Source_MER_dB=original.metrics.Estimated_SNR_dB;
report.Engine='Independent numerical passband replay, using saved causal filters/timing';
report.Frozen_Beta=original.TX_Beta;
% Verify the replay engine on the actual saved DPD-off Simulink symbols.
off=c; off.DPD_Enable=false;
baseline=replay_rfdac_numeric(off,original);
report.Baseline_Max_Symbol_Difference= ...
    max(abs(baseline.Received_Symbols-original.DPD_Comparison.Before_Received_Symbols));
assert(report.Baseline_Max_Symbol_Difference<1e-7);
fprintf('Baseline matches actual saved SLX: maximum symbol difference %.9g\n', ...
    report.Baseline_Max_Symbol_Difference);
clear baseline;
main=replay_rfdac_numeric(c,original);
report.Full_Record_Metrics=main.metrics;
report.Full_Record_Config=c;
report.Full_Record_Received=main.Received_Symbols;
report.Full_Record_Reference=main.Reference_Symbols;
save(fullfile(folder,'trained_16384_numeric_results.mat'),'main','-v7');
clear main;
c.Num_Symbols=4096; c.Random_Seed=original.cfg.Random_Seed+1009;
names={'DPD off','Trained 4096QAM','Trained 16384QAM','Trained 65536QAM','Analytic reference'};
orders=[0 4096 16384 65536 0]; rows=cell(numel(names),1);
for k=1:numel(names)
    cc=c; cc.DPD_Enable=k>1; cc.DPD_IQ_Enable=true; cc.DPD_Nonlinearity_Enable=true;
    cc.DPD_Algorithm='lut';
    if k==5, cc.DPD_Algorithm='analytic';
    elseif k>1, cc.DPD_LUT_Training_Order=orders(k); end
    fprintf('\n%s, held-out seed %d\n',names{k},cc.Random_Seed);
    r=replay_rfdac_numeric(cc,original); m=r.metrics;
    rows{k}=table(string(names{k}),orders(k),m.EVM_Percent,m.Estimated_SNR_dB, ...
        m.Symbol_Errors,m.Symbol_Error_Rate,m.DPD_Untrained_Output_Samples, ...
        'VariableNames',{'Case','Training_Order','EVM_Percent','MER_dB', ...
        'Symbol_Errors','SER','Untrained_Output_Samples'});
    report.Cases=vertcat(rows{1:k});
    writetable(report.Cases,fullfile(folder,'training_order_comparison.csv'));
    save(fullfile(folder,'evaluation_report.mat'),'report');
    clear r;
end
report.Completed=true;
save(fullfile(folder,'evaluation_report.mat'),'report');
disp(report.Cases); disp(report.Full_Record_Metrics);
fprintf('TRAINED LUT RF REPLAY COMPLETE.\n');
end
