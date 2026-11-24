function rfdac_qam_map(block)
% Level-2 MATLAB S-function: scalar random codeword -> Gray square QAM.
block.NumDialogPrms=1;
block.NumInputPorts=1; block.NumOutputPorts=1;
block.SetPreCompInpPortInfoToDynamic;
block.SetPreCompOutPortInfoToDynamic;
block.InputPort(1).Dimensions=1;
block.InputPort(1).DatatypeID=0;
block.InputPort(1).Complexity='Real';
block.InputPort(1).DirectFeedthrough=true;
block.OutputPort(1).Dimensions=1;
block.OutputPort(1).DatatypeID=0;
block.OutputPort(1).Complexity='Complex';
block.SampleTimes=[-1 0];
block.SimStateCompliance='DefaultSimState';
block.RegBlockMethod('Outputs',@output);
end
function output(b)
if b.InputPort(1).Data<0
    b.OutputPort(1).Data=complex(0);
else
    table=b.DialogPrm(1).Data;
    if isscalar(table) % older saved SLX compatibility
        b.OutputPort(1).Data=qammod(b.InputPort(1).Data,table,'gray','UnitAveragePower',true);
    else
        b.OutputPort(1).Data=table(b.InputPort(1).Data+1);
    end
end
end
