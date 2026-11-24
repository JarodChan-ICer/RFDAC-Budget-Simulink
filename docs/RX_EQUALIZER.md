# Automatically fitted RX equalizer

The receiver now compensates the in-band amplitude drop of the TX reconstruction LPF, RX anti-alias LPF and physical DAC zero-order hold. The delivered LPFs use Blackman-windowed linear-phase FIRs. The equalizer is fitted from their actual prepared coefficients, rather than assuming a Butterworth response or a fixed cutoff.

The RX path is:

`RF downconversion → RX anti-alias LPF → decimate to DAC rate → Auto-fitted in-band equalizer → matched RRC → fractional timing correction → symbol selection`

The equalizer is a native frame-based Discrete FIR Filter. It runs at `DAC_Sample_Rate` and uses one real coefficient set for both components of the complex baseband signal. Its symmetric, even-order coefficients give a known delay of `RX_Equalizer_Order/2` DAC samples; that delay is included in the receiver's symbol selection, reference delay and flushing frames.

## Usage

```matlab
cfg = init_rfdac_model();
cfg.RX_Equalizer_Enable = true;           % enabled by default
cfg.RX_Equalizer_Order = 256;             % even; 257 taps
cfg.RX_Equalizer_Max_Boost_dB = 6;         % realized EQ gain ceiling
cfg.RX_Equalizer_Regularization = 1e-6;    % coefficient penalty
cfg.Plot_LPF_Response = true;             % includes EQ/combined responses
results = run_rfdac_simulation(cfg);

results.RX_Equalizer
results.metrics.RX_Inband_Ripple_Before_dB
results.metrics.RX_Inband_Ripple_After_dB
results.metrics.RX_Equalizer_Peak_Gain_dB
```

The occupied band is `−Baseband_Frequency/2` to `+Baseband_Frequency/2`. For the default 400 MHz total bandwidth, the fit covers DC through 200 MHz on the positive-frequency side. Intentional TX/RX RRC pulse shaping is excluded from the inverse target.

Preparation fits the nominal combined magnitude response using regularized least squares, gives high weight to the occupied band, and smoothly returns the target gain to unity outside it. Unity DC gain is preserved. The maximum boost is enforced on the realized FIR response over a dense frequency grid, in addition to limiting the desired inverse response. `Boost_Limited` and `Required_Boost_dB` report cases where the requested correction exceeds the available gain.

Changing LPF coefficients, their cutoff/order, occupied bandwidth, DAC rate or RF rate triggers a new fit. Automatic RF sampling resolution happens before fitting, so LPFs are evaluated at their actual RF sample rate while the equalizer remains at the DAC sample rate. Repeated preparation with the same linear path reuses the deterministic fit.

Measured serpentine LUT training and its mapped-point verification now share the same equalized RX observation before the matched RRC. The LUT training key includes the equalizer settings, so changing those settings invalidates older training observations. Quiet frame guards extend automatically to include the equalizer's settling support.

This is a known-model automatic fit, not an online LMS equalizer: payload symbols, TX nonlinearity estimates, I/Q impairment truth and instantaneous jitter do not enter the fit. It corrects nominal linear amplitude droop; it does not undo arbitrary unknown channel distortion, nonlinear compression, static I/Q imbalance, random jitter or information removed by a deep LPF stopband. An IIR/Butterworth plant would also require its denominator and phase/delay model to be integrated into the project; replacing a FIR block manually is not automatically detected.

## Comparing enabled and bypassed operation

```matlab
cfg = init_rfdac_model();
cfg.Make_Plots = false;
cfg.Save_Results = false;
on = run_rfdac_simulation(cfg);
cfg = on.cfg;
cfg.TX_Nonlinearity_Beta = on.TX_Beta; % keep the same physical TX
cfg.RX_Equalizer_Enable = false;
off = run_rfdac_simulation(cfg);
[off.metrics.EVM_Percent on.metrics.EVM_Percent]
```

Freezing beta matters because the default automatic TX calibration targets the EVM of the whole clean chain. Without freezing it, changing the RX equalizer can also recalibrate the physical TX compression. Disable/bypass uses coefficient `1`, with zero added delay. Existing DPD before/after comparisons keep the same equalizer configuration in both runs.

The coefficients are saved in `results.filters.RX_Equalizer_FIR`; response curves, fit settings and ripple diagnostics are saved in `results.RX_Equalizer`. The reported ripple describes the nominal LPF/ZOH magnitude response across the full occupied band, not a fitted or normalized data constellation.

## Validation

```matlab
setup_rfdac_project();
report = validate_rfdac_rx_equalizer();
```

The validation uses an actual SLX A/B run with an intentionally drooping linear path, unchanged TX codewords and disabled static/jitter impairments. It checks EVM improvement, in-band flatness, symmetry/DC gain, exact bypass timing, bounded gain, payload independence, refitting after LPF changes, automatic sampling at a 24 GHz LO, and invalid parameter rejection. A separate sample-stream calculation from the logged downconverted signal verifies the native equalizer, matched filter and symbol indexing across frame boundaries. Reports are written to `outputs/validation/rx_equalizer/`.
