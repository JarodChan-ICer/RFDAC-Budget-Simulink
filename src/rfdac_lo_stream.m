function rfdac_lo_stream(b)
% Streaming stationary Gaussian timing jitter: O(one frame) memory.
b.NumDialogPrms=2; b.NumInputPorts=0; b.NumOutputPorts=5;
b.SetPreCompOutPortInfoToDynamic;
N=b.DialogPrm(2).Data;
for k=1:5
    b.OutputPort(k).DatatypeID=0; b.OutputPort(k).Complexity='Real';
    if k<5, b.OutputPort(k).Dimensions=[N 1]; else, b.OutputPort(k).Dimensions=[3 1]; end
end
c=b.DialogPrm(1).Data;
b.SampleTimes=[1/c.Symbol_Rate 0]; b.SimStateCompliance='HasNoSimState';
b.RegBlockMethod('InitializeConditions',@initialize);
b.RegBlockMethod('Outputs',@output);
end
function initialize(b)
c=b.DialogPrm(1).Data;
d.TX=RandStream('mt19937ar','Seed',c.Random_Seed+1);
d.RX=RandStream('mt19937ar','Seed',c.Random_Seed+2);
d.a=exp(-2*pi*c.Jitter_Bandwidth/c.Sample_Rate);
d.txState=d.a*randn(d.TX); d.rxState=d.a*randn(d.RX);
d.time=-Inf; d.values=cell(1,5); set_param(b.BlockHandle,'UserData',d);
end
function output(b)
c=b.DialogPrm(1).Data; N=b.DialogPrm(2).Data; d=get_param(b.BlockHandle,'UserData');
if b.CurrentTime~=d.time
    [j,d.txState]=jitter(d.TX,N,c.Jitter_Mode,d.a,d.txState);
    tx=j*c.LO_RMS_Jitter*double(c.LO_Jitter_Enable);
    switch c.RX_LO_Mode
        case 'ideal', rx=zeros(N,1);
        case 'shared', rx=tx;
        case 'independent'
            [j,d.rxState]=jitter(d.RX,N,c.Jitter_Mode,d.a,d.rxState);
            rx=j*c.RX_LO_RMS_Jitter;
    end
    frame=round(b.CurrentTime*c.Symbol_Rate);
    t=(frame*N+(0:N-1)')/c.Sample_Rate;
    pt=2*pi*c.LO_Frequency*tx; pr=2*pi*c.RX_LO_Frequency*rx;
    d.values={2*pi*c.LO_Frequency*t+pt, ...
        2*pi*c.RX_LO_Frequency*t+pr+c.RX_LO_Phase,pt,pr, ...
        [mean(tx.^2);mean(rx.^2);mean((pt-pr).^2)]};
    d.time=b.CurrentTime; set_param(b.BlockHandle,'UserData',d);
end
for k=1:5, b.OutputPort(k).Data=d.values{k}; end
end
function [j,state]=jitter(s,N,mode,a,state)
if strcmp(mode,'white'), j=randn(s,N,1);
else, [j,state]=filter(sqrt(1-a*a),[1 -a],randn(s,N,1),state); end
end
