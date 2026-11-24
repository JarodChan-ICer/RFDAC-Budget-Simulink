function estimate=rfdac_fit_measured_iq(drive,observed,scaleReference)
%RFDAC_FIT_MEASURED_IQ Estimate a real 2x2 IQ map from measured directions.
% A memoryless radial compressor changes magnitude but not complex angle.
% Fit cross(y,M*u)=0 using unit directions; do not invert measured radii.
% No true IQ angle, nonlinear coefficient or jitter trace is an input.
if nargin<3, scaleReference='mean'; end
scaleReference=validatestring(scaleReference,{'mean','i_branch'});
drive=drive(:); observed=observed(:);
assert(numel(drive)==numel(observed) && all(isfinite(drive)) && all(isfinite(observed)));
valid=abs(drive)>.1*max(abs(drive)) & abs(observed)>eps;
assert(nnz(valid)>=16,'rfdac:IQFitPoints','Insufficient nonzero IQ observations.');
u=drive(valid)./abs(drive(valid)); y=observed(valid)./abs(observed(valid));
X=[-imag(y).*real(u),-imag(y).*imag(u),real(y).*real(u),real(y).*imag(u)];
[~,S,V]=svd(X,0); v=V(:,end); M=[v(1) v(2);v(3) v(4)];
pred=complex(M(1,1)*real(u)+M(1,2)*imag(u),M(2,1)*real(u)+M(2,2)*imag(u));
if real(pred'*y)<0, M=-M; end
% The I branch is the nominal unity amplitude reference for the new LO model.
% Retain the historical mean normalization for earlier saved estimates.
if strcmp(scaleReference,'i_branch'), scale=norm(M(:,1));
else, scale=sqrt(mean(sum(M.^2,1))); end
M=M/scale;
assert(det(M)>1e-3,'rfdac:IQFitSingular','Measured IQ geometry is singular or has reversed handedness.');
pred=complex(M(1,1)*real(u)+M(1,2)*imag(u),M(2,1)*real(u)+M(2,2)*imag(u));
angleError=angle(y./pred);
cosine=dot(M(:,1),M(:,2))/(norm(M(:,1))*norm(M(:,2)));
estimate=struct('Matrix',M,'Inverse_Matrix',inv(M), ...
    'Phase_Error_Deg',asind(min(max(-cosine,-1),1)), ...
    'Relative_Q_to_I_Gain',norm(M(:,2))/norm(M(:,1)), ...
    'Direction_RMS_Error_Deg',sqrt(mean(angleError.^2))*180/pi, ...
    'Singular_Values',diag(S),'Num_Points',numel(drive),'Num_Fitted_Points',nnz(valid), ...
    'Scale_Reference',scaleReference, ...
    'Method','Measured direction-only homogeneous 2x2 fit with nominal unity reference gain', ...
    'Assumption','Static IQ map followed by angle-preserving radial compression');
end
