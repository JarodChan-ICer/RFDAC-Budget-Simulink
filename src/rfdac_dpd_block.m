function rfdac_dpd_block(b)
% Real I/Q frame interface: N-bit input words -> inverse -> N-bit output words.
b.NumDialogPrms=2; b.NumInputPorts=2; b.NumOutputPorts=7;
b.SetPreCompInpPortInfoToDynamic; b.SetPreCompOutPortInfoToDynamic;
N=b.DialogPrm(2).Data;
for k=1:2
    b.InputPort(k).Dimensions=[N 1]; b.InputPort(k).DatatypeID=0;
    b.InputPort(k).Complexity='Real'; b.InputPort(k).DirectFeedthrough=true;
    b.OutputPort(k).Dimensions=[N 1]; b.OutputPort(k).DatatypeID=0;
    b.OutputPort(k).Complexity='Real';
end
b.OutputPort(3).Dimensions=[16 1]; b.OutputPort(3).DatatypeID=0;
b.OutputPort(3).Complexity='Real';
for k=4:7
    b.OutputPort(k).Dimensions=[N 1]; b.OutputPort(k).DatatypeID=0;
    b.OutputPort(k).Complexity='Real';
end
b.SampleTimes=[-1 0]; b.SimStateCompliance='HasNoSimState';
b.RegBlockMethod('Outputs',@output);
end
function output(b)
u=complex(b.InputPort(1).Data,b.InputPort(2).Data);
[v,ideal,inputCodes,stats]=rfdac_dpd_codewords(u,b.DialogPrm(1).Data);
b.OutputPort(1).Data=real(v); b.OutputPort(2).Data=imag(v);
b.OutputPort(3).Data=stats;
b.OutputPort(4).Data=real(ideal); b.OutputPort(5).Data=imag(ideal);
b.OutputPort(6).Data=real(inputCodes); b.OutputPort(7).Data=imag(inputCodes);
end
