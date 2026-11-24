function validation=validate_rfdac_iq_only_lut()
% Regression of measured-map mode switching, preserving raw observations.
paths=setup_rfdac_project();
data=load(fullfile(paths.Validation,'iq_mismatch_7GHz_42dB_16k','iq_01p00.mat'),'caseData');
c=data.caseData.Configuration; c.DPD_Nonlinearity_Enable=true;
[joint,~]=rfdac_prepare(c);
c.DPD_Nonlinearity_Enable=false; [iq,~]=rfdac_prepare(c);
assert(isequal(joint.DPD.LUT.Training_Output,iq.DPD.LUT.Training_Output));
assert(strcmp(iq.DPD.LUT.Calibration_Mode,'iq_only') && ~iq.DPD.Nonlinearity_Enable);
assert(norm(iq.DPD.LUT.Mapping_Training_Output(:)-iq.DPD.LUT.Training_Output(:))>1);
assert(isequal(joint.DPD.LUT.Mapping_Training_Output,joint.DPD.LUT.Training_Output));
assert(~isequal(joint.DPD.LUT.Inverse_Index,iq.DPD.LUT.Inverse_Index));
c.DPD_Nonlinearity_Enable=true; [again,~]=rfdac_prepare(c);
assert(isequal(joint.DPD.LUT.Inverse_Index,again.DPD.LUT.Inverse_Index));
saved=load(fullfile(paths.Validation,'iq_mismatch_7GHz_42dB_16k_iq_only', ...
    'iq_mismatch_report.mat'),'report');
baseline=load(fullfile(saved.report.Output_Directory,'uncorrected_tx_ideal_iq_baseline.mat'));
floorDifference=max(abs(saved.report.Table.Payload_EVM_dB-baseline.baselineMetrics.EVM_dB));
assert(floorDifference<.5,'IQ-only result moved away from the unchanged TX distortion floor.');
validation=struct('All_Passed',true,'Mode_Cache_Separated',true, ...
    'Raw_Measured_Response_Preserved',true, ...
    'Maximum_Distance_From_Uncorrected_TX_Floor_dB',floorDifference);
disp(validation);
end
