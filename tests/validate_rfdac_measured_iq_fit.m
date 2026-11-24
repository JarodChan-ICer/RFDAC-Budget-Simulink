function validation=validate_rfdac_measured_iq_fit()
% Direction-only estimation must be invariant to arbitrary radial gain.
[i,q]=ndgrid(linspace(-1,1,128)); u=complex(i(:),q(:));
rotation=[cos(.4) -sin(.4);sin(.4) cos(.4)]; errors=zeros(3,1);
angles=[0 1 3];
for k=1:numel(angles)
    M=rotation*[1 -sind(angles(k));0 cosd(angles(k))];
    z=complex(M(1,1)*real(u)+M(1,2)*imag(u),M(2,1)*real(u)+M(2,2)*imag(u));
    a=rfdac_fit_measured_iq(u,z./(1+.8*abs(z).^2));
    b=rfdac_fit_measured_iq(u,(.2+.7./sqrt(1+abs(z).^4)).*z);
    errors(k)=norm(a.Matrix-M,'fro');
    assert(errors(k)<1e-12 && norm(a.Matrix-b.Matrix,'fro')<1e-12);
    assert(abs(a.Phase_Error_Deg-angles(k))<1e-10);
end
phase=3; gain=1.1;
M=rotation*[1 -gain*sind(phase);0 gain*cosd(phase)];
z=complex(M(1,1)*real(u)+M(1,2)*imag(u),M(2,1)*real(u)+M(2,2)*imag(u));
estimate=rfdac_fit_measured_iq(u,z./(1+.8*abs(z).^2),'i_branch');
assert(norm(estimate.Matrix-M,'fro')<1e-12);
assert(abs(estimate.Relative_Q_to_I_Gain-gain)<1e-12);
assert(abs(estimate.Phase_Error_Deg-phase)<1e-10);
validation=struct('All_Passed',true,'Maximum_Matrix_Error',max(errors), ...
    'Radial_Response_Invariance',true,'Nominal_I_Reference_Preserves_Q_Gain',true);
disp(validation);
end
