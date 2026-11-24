# 7 GHz / 100 fs / 45 dB TX: measured 16,384-point LUT results

Run date: 2026-11-08. All nine tested IQ phase mismatches from 1° through 3° in 0.25° steps met the −40 dB (1%) EVM requirement after training a new LUT at each angle. No failure crossing was found in this tested range; a failure threshold outside this range was not measured.

The worst 4096-point serpentine mean-point EVM was **−49.3370 dB (0.34131%) at 1.5°**, giving **9.3370 dB margin**. The worst ordinary random-RRC payload EVM was **−54.4619 dB (0.18919%) at 1°**, giving **14.4619 dB margin**. Every case had zero observed errors among its 4096 averaged serpentine points and 16,384 payload symbols.

| IQ phase mismatch | 4096-point snake EVM (dB) | Random-RRC payload EVM (dB) | Both meet −40 dB |
|---:|---:|---:|:---:|
| 1.00° | −49.4150 | −54.4619 | Yes |
| 1.25° | −49.4909 | −54.5040 | Yes |
| 1.50° | −49.3370 | −54.5155 | Yes |
| 1.75° | −49.4127 | −54.5400 | Yes |
| 2.00° | −49.3964 | −54.5755 | Yes |
| 2.25° | −49.3647 | −54.6047 | Yes |
| 2.50° | −49.4093 | −54.5964 | Yes |
| 2.75° | −49.3749 | −54.6277 | Yes |
| 3.00° | −49.3861 | −54.6314 | Yes |

## Exact acquisition and mapping sequence

Each angle used exactly **16,384 distinct measured training coordinates**, arranged as a 128 × 128 DAC grid visited in serpentine order. Every point was held for 25 DAC samples; two complete frames were captured from the actual SLX RF chain with the requested static mismatch and jitter active. The RX observation included the configured equalizer before the matched RRC. Requested 512-sample zero guards extended to 954 samples to cover the actual filter support.

Only these measured responses supplied the linear forward interpolation. The mapper selected legal integer DAC inputs for all **4096 distinct target QAM points**. It then injected those already-mapped words into the actual RF chain in a 64 × 64 serpentine sequence and acquired a fresh output. Native DPD was bypassed during this second injection to prevent applying the precomputed mapping twice. Interpolated predictions were not used as measured verification outputs.

Interpolation evaluated 1,048,576 candidate 10-bit DAC input pairs. This is a derived software search/address space, not additional measured training points or a claim that the entire runtime address map occupies only 16,384 hardware words. Interpolation was explicitly authorized for this experiment.

The ordinary random 4096-QAM payload used the same trained map, with TX/RX RRC pulse shaping and RX equalization. Its EVM was measured separately at the symbol decisions. Both EVM measures removed one constant complex gain over the full record; no additional per-point receiver correction or post-reception IQ fit was applied.

## Frozen physical settings and meaning of 45 dB

- LO: 7 GHz; TX jitter: 100 fs RMS, white per RF sample; RX LO: ideal.
- Static mismatch: quadrature phase error only, retrained at each tested angle.
- TX: existing RF `atan` nonlinearity, calibrated once to −45 dB clean-chain EVM, then frozen at β ≈ 0.317698673 V⁻².
- 4096-QAM, 10-bit signed I/Q DACs, unit-average-power QAM scaled by 0.35.
- DAC/RF sampling: 8/80 GHz; symbol rate: 320 MBaud; total occupied bandwidth: 400 MHz.
- TX/RX LPFs: 500 MHz cutoff, order 1024; RRC rolloff 0.25, span 16; RX equalizer order 256, gain ceiling 6 dB.
- Training/verification/payload seeds: 1073/2073/73; each seed's TX jitter stream uses seed + 1.

The 45 dB setting is the project's EVM-equivalent calibration of deterministic clean-TX distortion. DPD can reduce that distortion, explaining why corrected EVM improves beyond −45 dB. This experiment did not introduce a separate 45 dB AWGN source. Point-averaged snake EVM and matched-symbol payload EVM have different filtering and averaging and are reported separately.

## Evidence and reproduction

```matlab
setup_rfdac_project();
cfg = rfdac_default_config();
report = run_rfdac_iq_mismatch_sweep(cfg, 1:0.25:3);
validation = validate_rfdac_iq_mismatch_sweep(report);
```

Saved artifacts are under `outputs/validation/iq_mismatch_7GHz_45dB_16k/`:

- `iq_mismatch_report.mat`, `iq_mismatch_metrics.csv`: complete measurements and sampled threshold conclusions.
- `iq_01p00.mat` through `iq_03p00.mat`: actual measured training responses, all 4096 mapped inputs and independently captured outputs, timing/seed evidence, and payload symbols.
- `iq_mismatch_evm.png`, `iq_mismatch_serpentine.png`: sweep and the three-stage measured constellation flow.
- `iq_mismatch_audit.mat`: independent saved-data audit; all nine cases passed. Maximum EVM recalculation difference was 1.42 × 10⁻¹⁴ dB. All 4096 saved interpolation predictions per case reconstructed from the 16,384 measured responses within 10⁻¹² V.

See [IQ_MISMATCH_SWEEP.md](IQ_MISMATCH_SWEEP.md) for the configuration and measurement definitions. These are finite-record results for the stated model and freshly trained LUT at each angle; they do not measure drift tolerance of one fixed LUT.
