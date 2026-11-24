function report=rfdac_lut_select_precision(report)
% Recommend minimum payload among measured candidates meeting EVM penalty.
defaults=rfdac_default_config();
if ~isfield(report.Config,'DPD_LUT_Max_Penalty_dB')
    report.Config.DPD_LUT_Max_Penalty_dB=defaults.DPD_LUT_Max_Penalty_dB;
end
limit=report.Config.DPD_LUT_Max_Penalty_dB;
validateattributes(limit,{'numeric'},{'scalar','real','finite','nonnegative'});
t=report.Table; analytic=t.EVM_Percent(2);
t.EVM_Penalty_vs_Analytic_dB=20*log10(t.EVM_Percent/analytic);
t.Meets_Precision_Target=false(height(t),1);
t.Meets_Precision_Target(3:end)=t.EVM_Penalty_vs_Analytic_dB(3:end)<=limit;
eligible=find(t.Meets_Precision_Target);
report.Recommended_Points=[]; report.Recommended_Payload_KiB=[];
if ~isempty(eligible)
    [~,index]=min(t.Payload_KiB(eligible)); row=eligible(index);
    report.Recommended_Points=t.LUT_Points(row);
    report.Recommended_Payload_KiB=t.Payload_KiB(row);
end
report.Table=t;
report.Precision_Criterion='Minimum tested payload with 20*log10(EVM_LUT/EVM_analytic) <= configured penalty';
end
