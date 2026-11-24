function report=audit_rfdac_lut_assumptions(engine)
% Historical correction-LUT audit, frozen before the finite-training migration.
% Local legacy helpers preserve reproduction; production LUT uses trained words.
% Keep the physical beta fixed and use new data. Do not change user settings,
% the model, or outputs/results. All new artifacts go under outputs/validation.
if nargin<1, engine='offline'; end
assert(strcmp(engine,'offline'),'rfdac:HistoricalAudit', ...
    'This frozen correction-table audit supports offline replay only; use validate_rfdac_lut for the current SLX.');
engine=validatestring(engine,{'slx','offline'});
if strcmp(engine,'slx')
    paths=setup_rfdac_project();
else
    root=fileparts(fileparts(mfilename('fullpath')));
    paths.Validation=fullfile(root,'outputs','validation');
    paths.Results=fullfile(root,'outputs','results');
end
report.Engine=engine;
folder=fullfile(paths.Validation,'lut_assumptions_20261101');
if ~isfolder(folder), mkdir(folder); end
source=fullfile(paths.Results,'single_results.mat');
saved=load(source,'results'); original=saved.results; clear saved;
report.Source_Result=source;
report.Original_Config=original.cfg;
report.Original_Metrics=original.metrics;
report.Original_Before=original.DPD_Comparison.Before_Metrics;
report.Original_Calibration=original.TX_Calibration;

% Independently measure the logged, undecided received symbols.
r=original.Reference_Symbols(:); y=original.Received_Symbols_Raw(:);
g=(r'*y)/(r'*r);
report.Recomputed_EVM_Percent=100*norm(y/g-r)/norm(r);
assert(abs(report.Recomputed_EVM_Percent-original.metrics.EVM_Percent)<1e-10);
half=floor(numel(r)/2); training=1:half; test=half+1:numel(r);
gt=(r(training)'*y(training))/(r(training)'*r(training));
report.Second_Half_Training_Gain_EVM_Percent=100*norm(y(test)/gt-r(test))/norm(r(test));
gg=(r(test)'*y(test))/(r(test)'*r(test));
report.Second_Half_Refitted_Gain_EVM_Percent=100*norm(y(test)/gg-r(test))/norm(r(test));

% The LUT must be independent of both the QAM alphabet and runtime coefficients.
c=original.cfg; c.Make_Plots=false; c.Save_Results=false;
c.TX_Nonlinearity_Beta=original.TX_Beta;
d=original.DPD;
alternate=c; alternate.QAM_Order=1024;
other=legacy_rfdac_build_dpd_lut(alternate,d);
report.Table_Independent_Of_QAM_Order=isequal(other.Delta_I,d.LUT.Delta_I) && ...
    isequal(other.Delta_Q,d.LUT.Delta_Q);
assert(report.Table_Independent_Of_QAM_Order);
probe=complex((-500:7:500)',(500:-7:-500)')*d.LSB;
[v,~]=legacy_rfdac_dpd_apply(probe,d);
poison=d; poison.Beta=NaN; poison.Alpha=NaN; poison.Image=NaN;
[vp,~]=legacy_rfdac_dpd_apply(probe,poison);
report.Runtime_Reads_Stored_Table=isequal(v,vp);
zero=d; zero.LUT.Delta_I(:)=0; zero.LUT.Delta_Q(:)=0;
[vz,~]=legacy_rfdac_dpd_apply(probe,zero);
report.Zero_Correction_Retains_Input=isequal(vz,probe);
assert(report.Runtime_Reads_Stored_Table && report.Zero_Correction_Retains_Input);
report.Table_Generation=d.LUT.Generation;
report.Table_Grid_Code_Step=d.LUT.Code_Step;

% A separate symbol-domain noise demonstration. This is NOT an RF-chain run:
% add independent noise AFTER the recovered symbols, normalized to 30 dB
% at the final measurement plane. DPD has no access to this noise.
stream=RandStream('mt19937ar','Seed',20261101);
n=complex(randn(stream,size(r)),randn(stream,size(r)));
n=n/norm(n)*norm(r)*10^(-30/20);
withNoise=original.Received_Symbols(:)+n;
gn=(r'*withNoise)/(r'*r);
report.Symbol_Domain_30dB_Noise_Demo_MER_dB=-20*log10(norm(withNoise/gn-r)/norm(r));
report.Symbol_Domain_30dB_Noise_Demo_Note= ...
    'Independent noise added at final symbol plane; not an RF noise-injection simulation.';

fprintf('ORIGINAL saved before/after MER: %.6f / %.6f dB\n', ...
    report.Original_Before.Estimated_SNR_dB,report.Original_Metrics.Estimated_SNR_dB);
fprintf('Original EVM recomputed %.9f%%; split-half trained/refitted %.9f / %.9f%%\n', ...
    report.Recomputed_EVM_Percent,report.Second_Half_Training_Gain_EVM_Percent, ...
    report.Second_Half_Refitted_Gain_EVM_Percent);
fprintf('Independent final-symbol-plane 30-dB AWGN demo: MER %.6f dB\n', ...
    report.Symbol_Domain_30dB_Noise_Demo_MER_dB);
save(fullfile(folder,'audit_report.mat'),'report');

if strcmp(engine,'offline')
    % Verify the independent numerical RF replay against the saved actual SLX.
    replay=numeric_link(c,original);
    report.Original_Offline_Replay_EVM_Percent=replay.metrics.EVM_Percent;
    report.Original_Offline_Replay_Symbol_Max_Difference= ...
        max(abs(replay.Received_Symbols-original.Received_Symbols));
    fprintf('Numerical RF replay EVM %.9f%%; max symbol difference %.9g\n', ...
        report.Original_Offline_Replay_EVM_Percent,report.Original_Offline_Replay_Symbol_Max_Difference);
    assert(report.Original_Offline_Replay_Symbol_Max_Difference<1e-7, ...
        'Independent RF replay does not reproduce the actual saved SLX record.');
    clear replay;
end

% All comparisons share new data, fixed beta, and the same real SLX.
c.Num_Symbols=4096; c.Random_Seed=original.cfg.Random_Seed+1009;
c.Figure_Visible='off'; c.Plot_DPD_Comparison=false;
c.Output_Directory=folder;
labels={'DPD off','IQ only, LUT 16384','Nonlinearity only, LUT 16384', ...
    'Joint LUT 16384','Joint analytic','Joint LUT 4096','Joint LUT 65536', ...
    'Joint LUT 16384, IQ estimate 29 deg','Joint LUT 16384, bandlimited jitter'};
rows=cell(numel(labels),1);
for k=1:numel(labels)
    ck=c; ck.DPD_Enable=true; ck.DPD_IQ_Enable=true;
    ck.DPD_Nonlinearity_Enable=true; ck.DPD_Algorithm='lut';
    ck.DPD_LUT_Points=16384; ck.DPD_Quadrature_Estimate_Deg=[];
    switch k
        case 1, ck.DPD_Enable=false;
        case 2, ck.DPD_Nonlinearity_Enable=false;
        case 3, ck.DPD_IQ_Enable=false;
        case 5, ck.DPD_Algorithm='analytic';
        case 6, ck.DPD_LUT_Points=4096;
        case 7, ck.DPD_LUT_Points=65536;
        case 8, ck.DPD_Quadrature_Estimate_Deg=29;
        case 9, ck.Jitter_Mode='bandlimited';
    end
    fprintf('\nAUDIT CASE %d/%d: %s\n',k,numel(labels),labels{k});
    if strcmp(engine,'slx'), result=run_rfdac_simulation(ck);
    else, result=numeric_link(ck,original); end
    m=result.metrics;
    assert(abs(result.TX_Beta-original.TX_Beta)<1e-12);
    assert(m.Invalid_Output_Codeword_Pairs==0);
    rows{k}=table(string(labels{k}),m.EVM_Percent,m.Estimated_SNR_dB, ...
        m.Symbol_Error_Rate,m.Symbol_Errors,m.DPD_Drive_Power_Expansion_dB, ...
        m.DPD_DAC_I_Clipped_Full,m.DPD_DAC_Q_Clipped_Full, ...
        m.DPD_Limited_Samples,m.DPD_LUT_Value_Clipped_Nodes, ...
        'VariableNames',{'Case','EVM_Percent','MER_dB','SER','Symbol_Errors', ...
        'Drive_Expansion_dB','DAC_I_Clipped','DAC_Q_Clipped', ...
        'Gain_Limited','LUT_Clipped_Nodes'});
    if k==4
        report.Held_Out_Reference=result.Reference_Symbols;
        report.Held_Out_Joint_Received=result.Received_Symbols;
    end
    clear result;
    report.Cases=vertcat(rows{1:k});
    writetable(report.Cases,fullfile(folder,'cases.csv'));
    save(fullfile(folder,'audit_report.mat'),'report');
end
report.Held_Out_Num_Symbols=c.Num_Symbols;
report.Held_Out_Seed=c.Random_Seed;
report.Frozen_Beta=original.TX_Beta;
report.Completed=true;
save(fullfile(folder,'audit_report.mat'),'report');
disp(report.Cases);
fprintf('AUDIT COMPLETE: %s\n',folder);
if strcmp(engine,'slx') && bdIsLoaded(c.Model_Name), close_system(c.Model_Name,0); end
end

function result=numeric_link(c,original)
% Independent numerical passband replay; no Simulink runtime is loaded.
% Uses the exact saved causal filters/timing, new source symbols, and stored
% correction words (rebuilt only when a case changes the DPD configuration).
L=original.timing.DAC_Samples_Per_Symbol;
hold=round(c.Sample_Rate/c.DAC_Sample_Rate);
frames=c.Num_Symbols+original.timing.Decision_Frame_Delay+2;
stream=RandStream('mt19937ar','Seed',c.Random_Seed);
ids=randi(stream,c.QAM_Order,c.Num_Symbols,1)-1;
r=original.Reference_Constellation(ids+1);
d=original.DPD;
d.Enabled=logical(c.DPD_Enable);
d.IQ_Enable=d.Enabled && c.DPD_IQ_Enable;
d.Nonlinearity_Enable=d.Enabled && c.DPD_Nonlinearity_Enable;
d.Algorithm=c.DPD_Algorithm;
if ~isempty(c.DPD_Quadrature_Estimate_Deg)
    q=c.DPD_Quadrature_Estimate_Deg*pi/180;
    d.Alpha=(1+exp(1i*q))/2; d.Image=(1-exp(1i*q))/2;
    d.Determinant=abs(d.Alpha)^2-abs(d.Image)^2;
end
if strcmp(d.Algorithm,'lut'), d.LUT=legacy_rfdac_build_dpd_lut(c,d); end
jstream=RandStream('mt19937ar','Seed',c.Random_Seed+1);
a=exp(-2*pi*c.Jitter_Bandwidth/c.Sample_Rate);
jstate=a*randn(jstream);
phase=original.LO_Phase_Offsets_Deg*pi/180;
assert(strcmp(c.RX_LO_Mode,'ideal'),'Numeric audit currently supports the original ideal RX LO.');
index=original.timing.Total_Delay_DAC_Samples+1+(0:c.Num_Symbols-1)*L;
% Bounded-memory overlap-add convolution, also on the original full record.
blockFrames=64; maxRF=blockFrames*L*hold;
nfft=2^nextpow2(maxRF+max(numel(original.filters.TX_FIR),numel(original.filters.RX_FIR))-1);
txFFT=fft(original.filters.TX_FIR(:),nfft);
rxFFT=fft(original.filters.RX_FIR(:),nfft);
txTail=complex(zeros(numel(original.filters.TX_FIR)-1,1));
rxTail=complex(zeros(numel(original.filters.RX_FIR)-1,1));
rrcState=complex(zeros(numel(original.filters.RRC)-1,1));
matchState=rrcState;
fracState=complex(zeros(numel(original.filters.Fractional_FIR)-1,1));
y=complex(zeros(c.Num_Symbols,1)); stats=zeros(16,1);
for first=1:blockFrames:frames
    nf=min(blockFrames,frames-first+1);
    x=complex(zeros(nf*L,1));
    last=min(first+nf-1,c.Num_Symbols);
    if last>=first, x(1:L:(last-first+1)*L)=r(first:last)*sqrt(L)*c.Input_Amplitude; end
    [x,rrcState]=filter(original.filters.RRC,1,x,rrcState);
    [x,~,~,st]=legacy_rfdac_dpd_codewords(x,d);
    stats=stats+st;
    if first==1, maxima=st([4 8 16]); else, maxima=max(maxima,st([4 8 16])); end
    [x,txTail]=fft_block(repelem(x,hold),txFFT,txTail,nfft);
    N=numel(x); t=((first-1)*L*hold+(0:N-1)')/c.Sample_Rate;
    j=randn(jstream,N,1);
    if strcmp(c.Jitter_Mode,'bandlimited')
        [j,jstate]=filter(sqrt(1-a*a),[1 -a],j,jstate);
    end
    theta=2*pi*c.LO_Frequency*t+2*pi*c.LO_Frequency*c.LO_RMS_Jitter*c.LO_Jitter_Enable*j;
    loI=(cos(theta+phase(1))-cos(theta+phase(3)))/2;
    loQ=(cos(theta+phase(4))-cos(theta+phase(2)))/2;
    rf=real(x).*loI-imag(x).*loQ;
    if c.TX_Nonlinearity_Beta>0
        k=sqrt(c.TX_Nonlinearity_Beta); rf=atan(k*rf)/k;
    end
    down=2*rf.*exp(-1i*(2*pi*c.RX_LO_Frequency*t+c.RX_LO_Phase));
    [bb,rxTail]=fft_block(down,rxFFT,rxTail,nfft);
    bb=bb(1:hold:end);
    [bb,matchState]=filter(original.filters.RRC/sqrt(L),1,bb,matchState);
    [bb,fracState]=filter(original.filters.Fractional_FIR,1,bb,fracState);
    firstDAC=(first-1)*L+1;
    selected=find(index>=firstDAC & index<firstDAC+numel(bb));
    y(selected)=bb(index(selected)-firstDAC+1);
end
stats([4 8 16])=maxima;
g=(r'*y)/(r'*r); z=y/g;
evm=norm(z-r)/norm(r);
% Nearest square-QAM points, with independently computed decisions.
levels=unique(real(original.Reference_Constellation));
[~,ix]=min(abs(real(z)-levels.'),[],2);
[~,iy]=min(abs(imag(z)-levels.'),[],2);
decided=complex(levels(ix),levels(iy));
m.EVM_Percent=100*evm; m.Estimated_SNR_dB=-20*log10(evm);
m.Symbol_Errors=sum(abs(decided-r)>1e-10);
m.Symbol_Error_Rate=m.Symbol_Errors/c.Num_Symbols;
m.DPD_Drive_Power_Expansion_dB=10*log10(stats(2)/stats(1));
m.DPD_DAC_I_Clipped_Full=stats(6); m.DPD_DAC_Q_Clipped_Full=stats(7);
m.DPD_Limited_Samples=stats(5); m.Invalid_Output_Codeword_Pairs=stats(15);
m.DPD_LUT_Value_Clipped_Nodes=0;
if strcmp(d.Algorithm,'lut'), m.DPD_LUT_Value_Clipped_Nodes=d.LUT.Value_Clipped_Nodes; end
result.metrics=m; result.TX_Beta=c.TX_Nonlinearity_Beta;
result.Reference_Symbols=r; result.Received_Symbols=z;
fprintf('Numeric RF replay: EVM %.8f%% | MER %.6f dB | SER %.7g\n', ...
    m.EVM_Percent,m.Estimated_SNR_dB,m.Symbol_Error_Rate);
end

function [y,tail]=fft_block(x,B,tail,nfft)
n=numel(x); m=numel(tail);
full=ifft(fft(x,nfft).*B);
full(1:m)=full(1:m)+tail;
y=full(1:n); tail=full(n+1:n+m);
end


function lut=legacy_rfdac_build_dpd_lut(c,d)
% Uniform Cartesian bins. Each entry stores two finite-precision corrections.
mode=validatestring(c.DPD_LUT_Size_Mode,{'total_points','axis_bits','qam_multiple'});
if strcmp(mode,'axis_bits')
    bits=c.DPD_LUT_Address_Bits;
    validateattributes(bits,{'numeric'},{'vector','numel',2,'integer','>=',1,'<=',c.DAC_Bits});
    count=2.^reshape(bits,1,2);
else
    points=c.DPD_LUT_Points;
    if strcmp(mode,'qam_multiple')
        validateattributes(c.DPD_LUT_Points_Per_QAM_Symbol,{'numeric'},{'scalar','integer','positive'});
        points=c.QAM_Order*c.DPD_LUT_Points_Per_QAM_Symbol;
    end
    validateattributes(points,{'numeric'},{'scalar','integer','>=',4,'<=',2^20});
    axisBits=log2(points)/2;
    assert(abs(axisBits-round(axisBits))<1e-12 && axisBits<=c.DAC_Bits, ...
        'rfdac:LUTPointCount','Total LUT points must be a square power of two with <= DAC_Bits address bits per axis. Use axis_bits mode for rectangular grids.');
    count=[1 1]*2^round(axisBits);
end
assert(prod(count)<=2^20,'rfdac:LUTMemory','LUT is limited to 1048576 complex entries.');
validateattributes(c.DPD_LUT_Value_Bits,{'numeric'},{'scalar','integer','>=',2,'<=',24});
validateattributes(c.DPD_LUT_Fraction_Bits,{'numeric'}, ...
    {'scalar','integer','nonnegative','<=',c.DPD_LUT_Value_Bits-2});
lut.Interpolation=validatestring(c.DPD_LUT_Interpolation,{'nearest','linear'});
lut.Size_Mode=mode; lut.Size=count; lut.Points=prod(count); lut.Address_Bits=log2(count);
lut.Value_Bits=c.DPD_LUT_Value_Bits; lut.Fraction_Bits=c.DPD_LUT_Fraction_Bits;
lut.Code_Step=(d.Max_Code-d.Min_Code+1)./count;
lut.First_Code=d.Min_Code+(lut.Code_Step-1)/2;
lut.I_Breakpoints_Codes=lut.First_Code(1)+(0:count(1)-1)*lut.Code_Step(1);
lut.Q_Breakpoints_Codes=lut.First_Code(2)+(0:count(2)-1)*lut.Code_Step(2);
[ic,qc]=ndgrid(lut.I_Breakpoints_Codes,lut.Q_Breakpoints_Codes);
u=complex(ic,qc)*d.LSB;
[v,limited]=rfdac_dpd_analytic(u,d); % generation only, never the LUT runtime path
scale=2^lut.Fraction_Bits;
di=round((real(v)/d.LSB-ic)*scale); dq=round((imag(v)/d.LSB-qc)*scale);
lo=-2^(lut.Value_Bits-1); hi=2^(lut.Value_Bits-1)-1;
clipped=di<lo | di>hi | dq<lo | dq>hi;
lut.Delta_I=int32(min(max(di,lo),hi)); lut.Delta_Q=int32(min(max(dq,lo),hi));
errorI=double(lut.Delta_I)/scale-(real(v)/d.LSB-ic);
errorQ=double(lut.Delta_Q)/scale-(imag(v)/d.LSB-qc);
lut.Node_Quantization_Error_RMS_Code=sqrt(mean(errorI(:).^2+errorQ(:).^2));
lut.Gain_Limited=limited;
lut.Value_Clipped_Nodes=sum(clipped(:)); lut.Gain_Limited_Nodes=sum(limited(:));
lut.Packed_Payload_Bytes=ceil(lut.Points*2*lut.Value_Bits/8);
lut.Storage='Signed I/Q correction words; payload excludes addressing/metadata/interpolator';
lut.Generation='Known static model inverse, not feedback-trained';
end


function [v,limited]=legacy_rfdac_dpd_lut_lookup(u,d)
% Actual LUT runtime: index/interpolate stored words, add to original input.
lut=d.LUT;
x=(real(u)/d.LSB-lut.First_Code(1))/lut.Code_Step(1)+1;
y=(imag(u)/d.LSB-lut.First_Code(2))/lut.Code_Step(2)+1;
x=min(max(x,1),lut.Size(1)); y=min(max(y,1),lut.Size(2));
if strcmp(lut.Interpolation,'nearest')
    ix=round(x); iy=round(y); idx=ix+(iy-1)*lut.Size(1);
    di=double(lut.Delta_I(idx)); dq=double(lut.Delta_Q(idx));
    limited=lut.Gain_Limited(idx);
else
    ix=floor(x); iy=floor(y); fx=x-ix; fy=y-iy;
    jx=min(ix+1,lut.Size(1)); jy=min(iy+1,lut.Size(2));
    a=ix+(iy-1)*lut.Size(1); b=jx+(iy-1)*lut.Size(1);
    cc=ix+(jy-1)*lut.Size(1); e=jx+(jy-1)*lut.Size(1);
    wa=(1-fx).*(1-fy); wb=fx.*(1-fy); wc=(1-fx).*fy; we=fx.*fy;
    di=wa.*double(lut.Delta_I(a))+wb.*double(lut.Delta_I(b))+wc.*double(lut.Delta_I(cc))+we.*double(lut.Delta_I(e));
    dq=wa.*double(lut.Delta_Q(a))+wb.*double(lut.Delta_Q(b))+wc.*double(lut.Delta_Q(cc))+we.*double(lut.Delta_Q(e));
    limited=(wa.*lut.Gain_Limited(a)+wb.*lut.Gain_Limited(b)+wc.*lut.Gain_Limited(cc)+we.*lut.Gain_Limited(e))>0;
end
v=u+complex(di,dq)*(d.LSB/2^lut.Fraction_Bits);
end


function [v,stats]=legacy_rfdac_dpd_apply(u,d)
% Predistort desired complex envelope at the DAC sample rate.
% atan RF fundamental: F(A)=2*A/(1+sqrt(1+beta*A^2)).
% Its envelope inverse is A=R/(1-beta*R^2/4). Invert IQ AFTER this.
if isfield(d,'Algorithm') && strcmp(d.Algorithm,'lut') && (d.IQ_Enable || d.Nonlinearity_Enable)
    [v,limited]=legacy_rfdac_dpd_lut_lookup(u,d);
else
    [v,limited]=rfdac_dpd_analytic(u,d);
end
ratio=ones(size(u)); nz=abs(u)>eps;
ratio(nz)=abs(v(nz))./abs(u(nz));
ci=round(real(v)/d.LSB); cq=round(imag(v)/d.LSB);
stats=[sum(abs(u).^2);sum(abs(v).^2);numel(u);max(ratio);sum(limited); ...
    sum(ci<d.Min_Code | ci>d.Max_Code);sum(cq<d.Min_Code | cq>d.Max_Code);max(abs(v))];
end


function [v,ideal,inputCodes,stats]=legacy_rfdac_dpd_codewords(u,d)
% Only signed N-bit words cross the digital TX interface.
% Double stores the words exactly; it does not grant fractional code bits.
inputCodes=complex(clip(round(real(u)/d.LSB),d),clip(round(imag(u)/d.LSB),d));
formatted=inputCodes*d.LSB;
[ideal,base]=legacy_rfdac_dpd_apply(formatted,d);
outputCodes=complex(clip(round(real(ideal)/d.LSB),d),clip(round(imag(ideal)/d.LSB),d));
v=outputCodes*d.LSB;
stats=base;
stats(2)=sum(abs(v).^2); stats(8)=max(abs(v));
inputI=round(real(u)/d.LSB); inputQ=round(imag(u)/d.LSB);
invalid=real(outputCodes)~=round(real(outputCodes)) | imag(outputCodes)~=round(imag(outputCodes)) | ...
    real(outputCodes)<d.Min_Code | real(outputCodes)>d.Max_Code | ...
    imag(outputCodes)<d.Min_Code | imag(outputCodes)>d.Max_Code;
stats=[stats;sum(abs(ideal).^2);sum(abs(v-ideal).^2);sum(abs(formatted-u).^2); ...
    sum(outputCodes~=inputCodes);sum(inputI<d.Min_Code | inputI>d.Max_Code); ...
    sum(inputQ<d.Min_Code | inputQ>d.Max_Code);sum(invalid); ...
    max([abs(real(outputCodes));abs(imag(outputCodes))])];
end
function x=clip(x,d)
x=min(max(x,d.Min_Code),d.Max_Code);
end

