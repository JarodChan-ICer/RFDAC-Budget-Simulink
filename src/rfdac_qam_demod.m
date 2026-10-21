function rfdac_qam_demod(block)
% Online receiver: known-reference running one-tap training, then qamdemod.
% Final offline metrics refit one complex scalar over the complete record.
block.NumDialogPrms=1;
block.NumInputPorts=2; block.NumOutputPorts=2;
block.SetPreCompInpPortInfoToDynamic;
block.SetPreCompOutPortInfoToDynamic;
for k=1:2
    block.InputPort(k).Dimensions=1;
    block.InputPort(k).DatatypeID=0;
    block.InputPort(k).Complexity='Complex';
    block.InputPort(k).DirectFeedthrough=true;
    block.OutputPort(k).Dimensions=1;
    block.OutputPort(k).DatatypeID=0;
end
block.OutputPort(1).Complexity='Real';
block.OutputPort(2).Complexity='Complex';
block.SampleTimes=[-1 0];
block.SimStateCompliance='DefaultSimState';
block.RegBlockMethod('PostPropagationSetup',@setup_state);
block.RegBlockMethod('InitializeConditions',@initialize);
block.RegBlockMethod('Outputs',@output);
block.RegBlockMethod('Update',@update);
end
function setup_state(b)
b.NumDworks=2;
for k=1:2
    b.Dwork(k).Name=['sum' num2str(k)];
    b.Dwork(k).Dimensions=1; b.Dwork(k).DatatypeID=0;
    b.Dwork(k).Complexity='Complex'; b.Dwork(k).UsedAsDiscState=true;
end
end
function initialize(b)
b.Dwork(1).Data=complex(0); b.Dwork(2).Data=complex(0);
end
function output(b)
y=b.InputPort(1).Data; r=b.InputPort(2).Data;
g=(b.Dwork(1).Data+conj(r)*y)/max(real(b.Dwork(2).Data)+abs(r)^2,eps);
if abs(g)<eps, g=1; end
z=y/g;
b.OutputPort(1).Data=double(qamdemod(z,b.DialogPrm(1).Data,'gray','UnitAveragePower',true));
b.OutputPort(2).Data=z;
end
function update(b)
y=b.InputPort(1).Data; r=b.InputPort(2).Data;
b.Dwork(1).Data=b.Dwork(1).Data+conj(r)*y;
b.Dwork(2).Data=b.Dwork(2).Data+abs(r)^2;
end
