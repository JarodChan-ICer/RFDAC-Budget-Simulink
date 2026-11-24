function est=rfdac_identify_tx(captures,meta,options)
% Identify unknown TX parameters from known codes and an RF observation only.
% Public assumptions: nominal linear reconstruction is known; the static TX
% belongs to the atan family. No true impairment, phase trace or TX SNR enters.
if nargin<3, options=struct(); end
if ~iscell(captures), captures=num2cell(captures); end
assert(numel(captures)>=3,'Use at least two small-swing captures and one working-swing capture.');
clusterSymbols=getoption(options,'Cluster_Symbols',32);
maxSamples=getoption(options,'Max_Fit_Samples',180000);
validateattributes(clusterSymbols,{'numeric'},{'scalar','integer','positive'});
validateattributes(maxSamples,{'numeric'},{'scalar','integer','>=',1000});
blockLength=max(16,round(clusterSymbols*meta.DAC_Hold*meta.DAC_Samples_Per_Symbol));
sigma=2*pi*meta.LO_Frequency*meta.Known_Jitter_RMS_s;
lowCount=numel(captures)-1;
power=zeros(lowCount,1); iq=zeros(lowCount,1); iqVar=iq; phase=iq; ratios=iq;
groupCount=iq; condition=iq; fitNMSE=iq; coefficients=zeros(lowCount,5);
for k=1:lowCount
    [z,t,y]=preparecapture(captures{k},meta,maxSamples);
    carrier=2*pi*meta.LO_Frequency*t;
    cs=cos(carrier); sn=sin(carrier);
    X=[real(z).*cs,real(z).*sn,imag(z).*cs,imag(z).*sn,ones(size(z))];
    coef=X\y; residual=y-X*coef;
    [covariance,groups]=clustercovariance(X,residual,blockLength);
    iv=complex(coef(1),-coef(2)); qv=complex(coef(3),-coef(4));
    assert(abs(iv)>eps && abs(qv)>eps,'Calibration signal is too weak.');
    iq(k)=angle(exp(1i*(angle(qv/iv)-pi/2)));
    gi=max(coef(1)^2+coef(2)^2,realmin); gq=max(coef(3)^2+coef(4)^2,realmin);
    gradient=[-coef(2)/gi;coef(1)/gi;coef(4)/gq;-coef(3)/gq;0];
    iqVar(k)=max(real(gradient'*covariance*gradient),1e-16);
    phase(k)=angle(iv); ratios(k)=abs(qv/iv);
    power(k)=mean(abs(z).^2); groupCount(k)=groups;
    condition(k)=cond(X'*X);
    fitNMSE(k)=mean(residual.^2)/max(mean((y-mean(y)).^2),realmin);
    coefficients(k,:)=coef.';
end

% Small but nonzero compression can bias an individual low-power estimate.
% Extrapolate the independently fitted IQ angle linearly to zero input power.
design=[ones(lowCount,1),power]; weights=1./iqVar;
normal=design'*(weights.*design); covExtrap=pinv(normal);
extrap=covExtrap*(design'*(weights.*iq));
extrapResidual=iq-design*extrap;
inflation=max(1,sum(weights.*extrapResidual.^2)/max(lowCount-2,1));
iqVariance=max(covExtrap(1,1)*inflation,realmin);
epsilon=extrap(1);
phaseExtrap=design\unwrap(phase); initialPhase=phaseExtrap(1);
critical=critical95(max(2,min(groupCount)-1));

[z,t,y]=preparecapture(captures{end},meta,maxSamples);
baseCarrier=exp(1i*(2*pi*meta.LO_Frequency*t));
weightsGH=[2/3 1/6 1/6]; anglesGH=[0 sqrt(3)*sigma -sqrt(3)*sigma];
yCentered=y-mean(y); yPower=max(mean(yCentered.^2),realmin);
grid=[.003 .01 .03 .1 .3 1 3 10 30]; cost=zeros(size(grid));
for k=1:numel(grid), cost(k)=objective([log(grid(k));0]); end
[~,best]=min(cost);
searchOptions=optimset('Display','off','MaxIter',150,'MaxFunEvals',300,'TolX',1e-8,'TolFun',1e-12);
[parameters,finalCost,exitFlag,optimizer]=fminsearch(@objective,[log(grid(best));0],searchOptions);
beta=exp(parameters(1)); commonPhase=initialPhase+.01*parameters(2);
[model,db,dphase,depsilon]=meanresponse(beta,commonPhase);
[gain,dc,residual]=profile(model);
J=[gain*db,gain*dphase,model,ones(size(model))];
[covariance,groups]=clustercovariance(J,residual,blockLength);
% Propagate the independent small-swing IQ estimate into the TX-strength CI.
sensitivity=pinv(J'*J)*(J'*(gain*depsilon));
covariance=covariance+(sensitivity*sensitivity')*iqVariance;
betaSE=sqrt(max(real(covariance(1,1)),0));
criticalBeta=critical95(max(2,groups-1));

est.IQ_Error_Deg=epsilon*180/pi;
est.IQ_CI95_Deg=(epsilon+[-1 1]*critical*sqrt(iqVariance))*180/pi;
est.Beta=beta;
est.Beta_CI95=[max(0,beta-criticalBeta*betaSE),beta+criticalBeta*betaSE];
est.IQ_Standard_Error_Deg=sqrt(iqVariance)*180/pi;
est.Beta_Standard_Error=betaSE;
est.Observer_Gain_Estimate=gain; est.Observer_DC_Estimate=dc;
est.Common_Phase_Estimate_rad=commonPhase;
est.Training_RF_NMSE_dB=10*log10(max(finalCost,realmin));
est.Low_Amplitude_IQ_Deg=iq*180/pi;
est.Low_Amplitude_IQ_SE_Deg=sqrt(iqVar)*180/pi;
est.Low_Amplitude_Power=power;
est.Low_Amplitude_Gain_Ratios=ratios;
est.Low_Amplitude_Linear_Coefficients=coefficients;
est.Low_Amplitude_NMSE_dB=10*log10(max(fitNMSE,realmin));
est.Diagnostics=struct('Optimizer_Exit_Flag',exitFlag,'Optimizer',optimizer, ...
    'Low_Cluster_Counts',groupCount,'High_Cluster_Count',groups, ...
    'Cluster_Symbols',clusterSymbols,'Max_RF_Fit_Samples',maxSamples, ...
    'Low_Design_Condition',condition,'High_Design_Condition',cond(J'*J), ...
    'IQ_Extrapolation_LackOfFit_Inflation',inflation, ...
    'Jitter_Phase_RMS_rad',sigma,'GH_Order',3, ...
    'Pure_White_Noise_SNR_Identifiable',false);
est.Method='Known-structure unknown-parameter RF fit; low-power IQ extrapolation, high-power atan fit';
est.CI_Description=['Approximate 95% model-conditional cluster-sandwich intervals, including IQ-to-beta propagation. ' ...
    'They exclude unknown reconstruction errors, RX imbalance and wrong model family; validate empirical coverage separately.'];
est.Assumptions=['Known nominal TX/RX linear chain and coherent timing; known stationary Gaussian timing-jitter RMS; ' ...
    'calibrated RX except fitted scalar gain/phase/DC; static equal-gain IQ geometry and atan RF family.'];

    function value=objective(theta)
        if any(~isfinite(theta)) || theta(1)<log(1e-9) || theta(1)>log(1e5) || abs(theta(2))>100
            value=1e5; return;
        end
        m=meanresponse(exp(theta(1)),initialPhase+.01*theta(2));
        [~,~,e]=profile(m);
        value=mean(e.^2)/yPower;
    end
    function [g,b,e]=profile(m)
        centered=m-mean(m);
        g=(centered'*yCentered)/max(centered'*centered,realmin);
        b=mean(y)-g*mean(m); e=y-g*m-b;
    end
    function [m,db,dpsi,deps]=meanresponse(b,psi)
        envelope=real(z)+1i*imag(z)*exp(1i*epsilon);
        derivativeEnvelope=-imag(z)*exp(1i*epsilon);
        m=zeros(size(z));
        if nargout>1, db=m; dpsi=m; deps=m; end
        rootb=sqrt(b);
        for q=1:3
            carrier=baseCarrier*exp(1i*(psi+anglesGH(q)));
            voltage=envelope.*carrier; r=real(voltage); kr=rootb*r;
            m=m+weightsGH(q)*atan(kr)/rootb;
            if nargout>1
                denominator=1+kr.^2;
                db=db+weightsGH(q)*(kr./denominator-atan(kr))/(2*rootb^3);
                dpsi=dpsi-weightsGH(q)*imag(voltage)./denominator;
                deps=deps+weightsGH(q)*real(derivativeEnvelope.*carrier)./denominator;
            end
        end
    end
end

function [z,t,y]=preparecapture(c,meta,maxSamples)
validateattributes(c.Codes,{'numeric'},{'vector','finite'});
validateattributes(c.RF,{'numeric'},{'vector','real','finite'});
assert(all(real(c.Codes)==round(real(c.Codes))) && all(imag(c.Codes)==round(imag(c.Codes))), ...
    'Identification accepts actual integer DAC codes, not hidden analog TX nodes.');
known=repelem(c.Codes(:)*meta.DAC_LSB,meta.DAC_Hold);
known=fftfilt(meta.TX_FIR,known);
n=min(numel(known),numel(c.RF));
drop=numel(meta.TX_FIR)+meta.DAC_Hold*meta.DAC_Samples_Per_Symbol;
assert(n>drop+1000,'RF capture too short after nominal FIR settling.');
last=min(n,drop+maxSamples); index=(drop+1:last)';
z=known(index); t=c.Start_Time+(index-1)/meta.RF_Sample_Rate;
y=c.RF(index); y=y(:);
end
function [covariance,groups]=clustercovariance(X,residual,blockLength)
n=size(X,1); groups=ceil(n/blockLength);
scores=zeros(size(X,2),groups);
for k=1:groups
    index=(k-1)*blockLength+1:min(k*blockLength,n);
    scores(:,k)=X(index,:)'*residual(index);
end
scores=scores-mean(scores,2);
bread=pinv(X'*X);
factor=groups/max(groups-1,1)*(n-1)/max(n-size(X,2),1);
covariance=factor*bread*(scores*scores')*bread;
covariance=(covariance+covariance')/2;
end
function value=critical95(df)
% Cornish-Fisher t(.975) approximation, no Statistics Toolbox dependency.
z=1.95996398454005;
value=z+(z^3+z)/(4*df)+(5*z^5+16*z^3+3*z)/(96*df^2);
end
function value=getoption(options,name,fallback)
if isfield(options,name), value=options.(name); else, value=fallback; end
end
