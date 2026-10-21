function d=rfdac_prepare_dpd(c,p)
% Model-informed static inverse; no access to instantaneous timing jitter.
flags={'DPD_Enable','DPD_IQ_Enable','DPD_Nonlinearity_Enable'};
for k=1:numel(flags), validateattributes(c.(flags{k}),{'logical','numeric'},{'scalar','binary'}); end
validateattributes(c.DPD_Max_Gain,{'numeric'},{'scalar','real','finite','>=',1});
d.Enabled=logical(c.DPD_Enable);
d.IQ_Enable=d.Enabled && logical(c.DPD_IQ_Enable);
d.Nonlinearity_Enable=d.Enabled && logical(c.DPD_Nonlinearity_Enable);
d.Max_Gain=c.DPD_Max_Gain;
if isempty(c.DPD_TX_Beta_Estimate), d.Beta=p.TX_Beta;
else
    validateattributes(c.DPD_TX_Beta_Estimate,{'numeric'},{'scalar','real','finite','nonnegative'});
    d.Beta=c.DPD_TX_Beta_Estimate;
end
q=double(c.LO_Quadrature_Error_Enable)*c.LO_Quadrature_Error_Deg;
if ~isempty(c.DPD_Quadrature_Estimate_Deg)
    validateattributes(c.DPD_Quadrature_Estimate_Deg,{'numeric'},{'scalar','real','finite'});
    q=c.DPD_Quadrature_Estimate_Deg;
end
extra=double(c.LO_Quadrature_Error_Enable)*c.LO_Phase_Errors_Deg;
if ~isempty(c.DPD_Phase_Errors_Estimate_Deg)
    validateattributes(c.DPD_Phase_Errors_Estimate_Deg,{'numeric'},{'vector','numel',4,'real','finite'});
    extra=reshape(c.DPD_Phase_Errors_Estimate_Deg,1,4);
end
phase=pi/180*([0 90 180 270]+[0 q 0 q]+reshape(extra,1,4));
ip=(exp(1i*phase(1))-exp(1i*phase(3)))/2;
qp=(exp(1i*phase(4))-exp(1i*phase(2)))/2;
d.Alpha=(ip+1i*qp)/2; d.Image=(ip-1i*qp)/2;
d.Determinant=abs(d.Alpha)^2-abs(d.Image)^2;
if d.IQ_Enable
    assert(abs(d.Determinant)>1e-3,'rfdac:DPDSingularIQ', ...
        'Estimated IQ mapping is nearly singular; static inversion is unsafe.');
end
d.Estimated_Phases_Deg=phase*180/pi;
d.LSB=p.LSB; d.Min_Code=p.Min_Code; d.Max_Code=p.Max_Code;
d.Code_Bits=c.DAC_Bits;
d.Method='N-bit words -> known-model fundamental/IQ inverse -> N-bit round/saturate';
d.Algorithm=validatestring(c.DPD_Algorithm,{'analytic','lut'});
if strcmp(d.Algorithm,'lut')
    d.LUT=rfdac_build_dpd_lut(c,d);
    d.Method='N-bit words -> 2-D I/Q correction LUT -> N-bit round/saturate';
end
end
