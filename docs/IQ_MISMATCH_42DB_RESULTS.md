# 42 dB TX comparison: measured 16,384-point LUT

Measured on 2026-11-08 at IQ phase mismatches **1°, 2°, and 3°**. Every checked angle passed the −40 dB EVM requirement after fresh 16,384-point serpentine training and interpolation-based mapping. This comparison checks three angles; the earlier 45 dB study used nine angles.

| IQ phase mismatch | 42 dB TX: snake EVM | 42 dB TX: payload EVM | 45 dB TX: snake EVM | 45 dB TX: payload EVM |
|---:|---:|---:|---:|---:|
| 1° | −49.2861 dB | −54.5275 dB | −49.4150 dB | −54.4619 dB |
| 2° | −49.4622 dB | −54.6074 dB | −49.3964 dB | −54.5755 dB |
| 3° | −49.4021 dB | −54.6603 dB | −49.3861 dB | −54.6314 dB |

The worst measured 42 dB serpentine EVM was **−49.2861 dB (0.34332%)**, giving **9.2861 dB margin** to the 1% EVM target. The worst payload EVM was **−54.5275 dB (0.18777%)**, giving **14.5275 dB margin**. All cases had zero observed errors over 4096 averaged serpentine points and 16,384 random-RRC payload symbols each. No failure crossing was found at the three tested angles.

All settings other than the clean-TX distortion calibration match the 45 dB study: 7 GHz LO, 100 fs RMS white TX jitter, ideal RX LO, 4096-QAM, 10-bit DACs, input amplitude 0.35, 8/80 GHz DAC/RF rates, the same RRC/LPFs, enabled RX equalizer, and the same training/verification/payload seeds. Training uses 128 × 128 distinct measured DAC coordinates, 25 samples per point, and two full serpentine frames. Mapping comes only from those measured responses; all 4096 mapped input words are then sent through the actual RF chain for a fresh verification capture. The equalized observation and timing/guard rules are identical to the 45 dB experiment.

The TX was calibrated once to −42 dB clean-chain EVM and frozen at β ≈ 0.470973361 V⁻² across all three cases. This replaces the 45 dB plant's β ≈ 0.317698673 V⁻². In this project, TX SNR describes deterministic `atan` distortion calibrated by clean-chain EVM. The LUT can compensate that distortion; the results do not represent a separate 42 dB AWGN source. Small non-monotonic changes after correction reflect the remaining quantization, interpolation, filtering and jitter interactions.

Use the factory configuration to reproduce the 7 GHz comparison.

```matlab
setup_rfdac_project();
cfg = rfdac_default_config();
cfg.TX_Target_EVM_dB = -42;
report42 = run_rfdac_iq_mismatch_sweep(cfg, [1 2 3]);
validation42 = validate_rfdac_iq_mismatch_sweep(report42);
```

Measurements, paired training/mapping/capture data, figures and audit are saved under `outputs/validation/iq_mismatch_7GHz_42dB_16k/`. The independent saved-data audit checks the physical settings, reconstruction from the measured training points, EVM/SER and threshold conclusions. The original 45 dB data are preserved separately.

See [the workflow](IQ_MISMATCH_SWEEP.md) and [the 45 dB results](IQ_MISMATCH_RESULTS.md) for definitions and comparison settings.
