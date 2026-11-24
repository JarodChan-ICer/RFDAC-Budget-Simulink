# Four-phase LO mismatch at 15 GHz

The four LO phases are `[0, 90+Mp, 180+Md, 270+Mp+Md]` degrees. Their normalized amplitudes are `[1, 1+MA, 1, 1+MA]`. `LO_Quadrature_Error_Deg`, `LO_Differential_Phase_Error_Deg` and `LO_Quadrature_Amplitude_Mismatch` set `Mp`, `Md` and `MA`. Simulink applies these phases and gains before computing `(LO0−LO180)/2` and `(LO270−LO90)/2`.

The experiment uses 15 GHz LO, 100 fs RMS jitter, 42 dB clean-TX SNR, `Mp = 1°, 2°, 3°`, `Md = 0.8°` and `MA = +0.10`. Both Q legs have amplitude 1.10. With this phase pattern, the two differential outputs acquire a common 0.4° phase rotation and a common factor of `cos(0.4°)`. Their relative phase error remains `Mp` and the Q/I amplitude ratio is 1.10.

RF sampling resolves to 160 GHz with 2048th-order RF low-pass filters. The clean TX calibration gives β ≈ 0.470975853 V⁻². Each angle has two captured 128 × 128 serpentine training frames using 25 DAC samples per point. Each mode maps all 4096 QAM targets and independently transmits the corresponding 64 × 64 sequence. A separate 16384-symbol RRC payload run measures ordinary symbol decisions. The I/Q-only mode uses the measured directions to fit relative I/Q geometry and sets nominal I-branch gain to one.

```matlab
cfg = init_rfdac_model();
joint = run_rfdac_iq_mismatch_sweep(cfg, [1 2 3]);
options = struct('Calibration_Mode','iq_only', ...
    'Plant_Calibration',joint.TX_Calibration, ...
    'Training_Directory',joint.Output_Directory);
iq = run_rfdac_iq_mismatch_sweep(joint.Configuration, [1 2 3], options);
validate_rfdac_iq_mismatch_sweep(joint);
validate_rfdac_iq_mismatch_sweep(iq);
```

The recorded sweep used causal FFT overlap-add for the three long RF FIRs. A paired native-filter run at the same 160 GHz settings verified the DAC codes and recovered symbols. The maximum logged waveform difference was 4.48 × 10⁻¹⁶ V. The saved Simulink model uses the native FIR blocks.

| Mp | I/Q-only snake EVM | I/Q-only payload EVM / SER | Joint snake EVM | Joint payload EVM / SER |
|---:|---:|---:|---:|---:|
| 1° | −41.135 dB | −41.948 dB / 0.952% | −49.054 dB | −54.301 dB / 0% |
| 2° | −41.142 dB | −41.957 dB / 0.964% | −49.167 dB | −54.363 dB / 0% |
| 3° | −41.140 dB | −41.967 dB / 0.952% | −49.057 dB | −54.372 dB / 0% |

All six cases meet −40 dB in both measurements. The worst serpentine margin is 1.14 dB for I/Q-only correction and 9.05 dB for joint correction. Joint correction had zero observed symbol errors in each 16,384-symbol payload. Both saved-data audits passed.

Training records, configuration, mapped vectors, fresh RF verification, payload symbols and the audits are under `outputs/validation/iq_mismatch_15GHz_42dB_16k/` and `outputs/validation/iq_mismatch_15GHz_42dB_16k_iq_only/`.
