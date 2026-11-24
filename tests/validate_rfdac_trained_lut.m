function report=validate_rfdac_trained_lut()
% Core contract checks without Simulink: outputs belong to training alphabet,
% selection minimizes observed output error, and no analytic runtime leaks in.
c=rfdac_default_config(); c.DPD_Nonlinearity_Enable=true;
c.DPD_LUT_Training_Mode='static'; c.DPD_LUT_Drive_Range=1; % explicit legacy reference
c.DPD_LUT_Interpolation='nearest';
d=struct('Enabled',true,'IQ_Enable',true,'Nonlinearity_Enable',true, ...
    'Beta',2.42146663163114,'Max_Gain',2,'LSB',2/1024,'Min_Code',-512, ...
    'Max_Code',511,'Code_Bits',10,'Algorithm','lut');
q=pi/6; d.Alpha=(1+exp(1i*q))/2; d.Image=(1-exp(1i*q))/2;
d.Determinant=abs(d.Alpha)^2-abs(d.Image)^2;
d.LUT=rfdac_build_dpd_lut(c,d); lut=d.LUT;
assert(lut.Points==16384 && isequal(lut.Size,[128 128]));
assert(~isfield(lut,'Delta_I') && ~isfield(lut,'Delta_Q'));
alphabet=complex(double(lut.Output_I(:)),double(lut.Output_Q(:)));
assert(numel(unique(alphabet))==lut.Points && lut.Packed_Payload_Bytes==40960);
assert(numel(unique(real(alphabet)))==128 && numel(unique(imag(alphabet)))==128);

% Check RF training against an independently derived forward fundamental.
drive=alphabet*d.LSB; z=d.Alpha*drive+d.Image*conj(drive);
forward=2*z./(1+sqrt(1+d.Beta*abs(z).^2));
report.Training_Fundamental_Max_Error=max(abs(forward-lut.Training_Output(:)));
assert(report.Training_Fundamental_Max_Error<1e-11);

stream=RandStream('mt19937ar','Seed',20261102);
u=complex(randi(stream,1401,65536,1)-701,randi(stream,1401,65536,1)-701)*d.LSB;
[v,~,~,stats]=rfdac_dpd_codewords(u,d);
assert(all(ismember(v/d.LSB,alphabet)) && stats(15)==0);
assert(numel(unique(v))<=lut.Points);
probe=u(1:128); [actual,~,index]=rfdac_dpd_lut_lookup(probe,d);
for k=1:numel(probe)
    best=min(abs(lut.Training_Output(:)-probe(k)).^2);
    chosen=abs(lut.Training_Output(index(k))-probe(k))^2;
    assert(abs(chosen-best)<1e-12,'Selected word is not the nearest observed response.');
end
poison=d; poison.Beta=NaN; poison.Alpha=NaN; poison.Image=NaN;
assert(isequal(actual,rfdac_dpd_lut_lookup(probe,poison)));
zero=d; zero.LUT.Output_I(:)=0; zero.LUT.Output_Q(:)=0;
assert(all(rfdac_dpd_lut_lookup(probe,zero)==0),'Input addition remains in LUT runtime.');
center=lut.Training_Output(5000);
assert(isequal(rfdac_dpd_lut_lookup(center,d), ...
    rfdac_dpd_lut_lookup(center+d.LSB/1000,d)),'Input low bits leaked through.');

% Supplied observations must determine selection, without reading model beta.
observed=c; observed.DPD_LUT_Training_Observed=1i*drive;
external=poison; external.LUT=rfdac_build_dpd_lut(observed,poison);
target=observed.DPD_LUT_Training_Observed(5000);
assert(rfdac_dpd_lut_lookup(target,external)==drive(5000));
partial=poison; partial.IQ_Enable=false;
must_fail(@()rfdac_build_dpd_lut(observed,partial),'rfdac:LUTObservedCalibration');
inactive=poison; inactive.IQ_Enable=false; inactive.Nonlinearity_Enable=false;
inactive.LUT=rfdac_build_dpd_lut(observed,inactive);
assert(all(isfinite(inactive.LUT.Training_Output(:))));

for mode={'total_points','axis_bits','qam_multiple'}
    cc=c; cc.DPD_LUT_Size_Mode=mode{1};
    if strcmp(mode{1},'axis_bits'), cc.DPD_LUT_Address_Bits=[6 8]; end
    alternate=rfdac_build_dpd_lut(cc,d);
    assert(alternate.Points==16384 && numel(unique(complex( ...
        double(alternate.Output_I(:)),double(alternate.Output_Q(:)))))==16384);
end
bad=c; bad.DPD_LUT_Interpolation='linear';
must_fail(@()rfdac_build_dpd_lut(bad,d),'rfdac:LUTDiscreteSelection');
bad=c; bad.DPD_LUT_Fraction_Bits=1;
must_fail(@()rfdac_build_dpd_lut(bad,d),'rfdac:LUTDiscreteWords');
bad=c; bad.DPD_LUT_Training_Order=10000;
must_fail(@()rfdac_build_dpd_lut(bad,d),'rfdac:LUTPointCount');

off=d; off.Enabled=false; off.IQ_Enable=false; off.Nonlinearity_Enable=false;
[v,~,input]=rfdac_dpd_codewords(u,off);
assert(isequal(v,input*d.LSB),'DPD bypass altered the original N-bit interface.');
report.All_Passed=true; report.Random_Inputs_Tested=numel(u);
report.Training_Order=lut.Training_Order; report.Output_Alphabet_Count=numel(unique(alphabet));
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'outputs','validation','trained_lut_20261101');
if ~isfolder(folder), mkdir(folder); end
save(fullfile(folder,'core_validation.mat'),'report');
disp(report); fprintf('FINITE TRAINING LUT CORE CHECKS PASSED.\n');
end

function must_fail(action,id)
try
    action();
catch err
    assert(strcmp(err.identifier,id),'Unexpected validation failure: %s',err.message); return;
end
error('rfdac:MissingGuard','Expected guard %s did not fire.',id);
end
