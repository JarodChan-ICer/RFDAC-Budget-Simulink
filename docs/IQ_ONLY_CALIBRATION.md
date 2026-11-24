# Measured I/Q-only calibration with TX distortion retained

Use I/Q-only calibration to remove the static quadrature geometry while retaining the same physical TX compression, LO jitter, DACs, filters and RX equalizer:

```matlab
setup_rfdac_project();
cfg = rfdac_default_config();
cfg.TX_Target_EVM_dB = -42;
cfg.DPD_IQ_Enable = true;
cfg.DPD_Nonlinearity_Enable = false;
report = run_rfdac_iq_mismatch_sweep(cfg, [1 2 3]);
validation = validate_rfdac_iq_mismatch_sweep(report);
```

The sweep can also select this mode explicitly with `options.Calibration_Mode='iq_only'`. Results go to `outputs/validation/iq_mismatch_7GHz_42dB_16k_iq_only/`, separately from joint-calibration results. The daily default remains joint I/Q/nonlinearity correction.

## Measured 42 dB results, 2026-11-08

The physical TX coefficient was frozen at the same verified 42 dB value, β ≈ 0.470973361 V⁻². LO 7 GHz, 100 fs jitter, 10-bit DACs, RRC filters, RX equalizer, data and seeds were unchanged. Each row uses a fitted I/Q-only LUT and fresh RF verification/output data.

| IQ phase error | Fitted phase error | 4096-point snake EVM | Payload EVM | Payload symbol errors |
|---:|---:|---:|---:|---:|
| 1° | 1.00004993° | −41.1057 dB | −41.9408 dB | 149 / 16384 = 0.9094% |
| 2° | 2.00005041° | −41.1909 dB | −41.9580 dB | 149 / 16384 = 0.9094% |
| 3° | 3.00005067° | −41.2401 dB | −41.9696 dB | 150 / 16384 = 0.9155% |

All three angles meet the −40 dB EVM requirement. Worst margin is **1.1057 dB** for the point-averaged snake and **1.9408 dB** for the payload. Mean-point snake SER was 1.4160%, 1.1719% and 1.3672%, respectively; meeting the EVM requirement does not establish error-free demodulation.

The independently simulated ideal-I/Q, DPD-off baseline gave **−41.99 dB payload EVM** with the same TX distortion and jitter. All I/Q-only payload results lie within **0.050 dB** of that floor. Joint I/Q/nonlinearity correction at the same 42 dB physical operating point previously gave −54.53 to −54.66 dB payload EVM; its additional improvement came from correcting the TX distortion as well.

The saved-data audit, synthetic radial-invariance test and joint/IQ-only cache-switch regression passed. Original measured training responses remain unchanged; linear-I/Q mapping predictions are stored separately. Baseline and regression evidence are in `uncorrected_tx_ideal_iq_baseline.mat`, `iq_mismatch_audit.mat` and `iq_only_mode_regression.mat` in the result directory.

## How the I/Q component is separated

The original measured LUT inverts the whole observed response, including TX compression. Disabling a status flag on that frozen map would still correct compression. The I/Q-only mode instead uses a linear 2 × 2 geometry fitted from the directions of the measured input/output pairs.

Under this project's model, static I/Q mixing is a real linear transformation followed by angle-preserving radial compression of the complex RF fundamental. Measured directions identify I/Q geometry up to a common scale. The fit sets the nominal I-branch gain to one so changing the Q-branch gain does not set the common scale. Historical saved fits use mean branch gain as their scale reference. The estimator takes the DAC input coordinates and observed complex outputs.

The actual 16,384-point measured serpentine response remains saved unchanged. A separate `Mapping_Training_Output` contains the fitted linear I/Q response on those 128 × 128 input coordinates. Interpolation and nearest-output lookup use that I/Q-only map, so no amplitude-dependent TX inverse is introduced. All mapped DAC words remain legal integer 10-bit words. The resulting 4096-point sequence is sent through the actual RF chain again, with the original TX compression active.

The direction fit assumes the project's static I/Q geometry, nominal common branch gain and radial RF compression. Arbitrary AM/PM conversion, frequency-dependent I/Q mismatch, or an uncalibrated common gain would require additional identification. The fit's direction residual is recorded in `IQ_Estimate`.

## Training reuse and validation

The comparison can reuse previously acquired 16,384-point RF observations when their complete physical/stimulus fingerprint matches. I/Q-only and joint correction have identical uncorrected training acquisitions. Reuse changes only the fitted calibration map; verification outputs and payloads are newly captured. The physical TX coefficient remains frozen at the verified 42 dB operating point.

`validate_rfdac_measured_iq_fit` checks recovery of known I/Q geometries under different arbitrary radial compression laws. `validate_rfdac_iq_mismatch_sweep` recomputes the fit from saved measured points, reconstructs mapping predictions, and verifies that every selected input inverts one fixed linear map within DAC rounding. This bound rejects additional radial predistortion. It also checks the native nonlinearity-calibration flag is disabled, the physical TX coefficient is unchanged, and EVM/SER agree with saved received outputs.

The independently captured ideal-I/Q, DPD-off baseline is saved as `uncorrected_tx_ideal_iq_baseline.mat`; it retains the same TX compression, jitter and equalizer. Comparing it with I/Q-only payload EVM shows the TX distortion floor that remains after I/Q correction.
