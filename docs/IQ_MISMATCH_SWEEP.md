# 16,384-point measured LUT and static IQ mismatch sweep

The sweep uses the configured LO frequency, jitter, and static LO mismatches. Each case trains its LUT from 16,384 distinct DAC input points and measures a fresh 4096-point constellation. The current configuration uses 15 GHz, 100 fs RMS, and 42 dB clean-TX SNR, with 0.8° differential phase error and +10% gain on both Q legs.

The four-leg LO definitions and 15 GHz results are in [LO_15GHZ_LUT_DPD.md](LO_15GHZ_LUT_DPD.md).

The 7 GHz, 45 dB run on 2026-11-08 passed −40 dB at all nine angles. Its table and acquisition evidence are in [IQ_MISMATCH_RESULTS.md](IQ_MISMATCH_RESULTS.md).

Use the factory configuration to reproduce the earlier 7 GHz, 42 dB comparison.

```matlab
setup_rfdac_project();
cfg = rfdac_default_config();
cfg.TX_Target_EVM_dB = -42;
report42 = run_rfdac_iq_mismatch_sweep(cfg, [1 2 3]);
validation42 = validate_rfdac_iq_mismatch_sweep(report42);
```

The historical 42 dB results use `outputs/validation/iq_mismatch_7GHz_42dB_16k/`.
The completed three-angle comparison is recorded in [IQ_MISMATCH_42DB_RESULTS.md](IQ_MISMATCH_42DB_RESULTS.md).

For I/Q-only correction while retaining the 42 dB TX distortion, set `cfg.DPD_Nonlinearity_Enable=false`. The measured direction-fit method, separate output directory and completed results are documented in [IQ_ONLY_CALIBRATION.md](IQ_ONLY_CALIBRATION.md).

## Run the experiment

```matlab
cfg = init_rfdac_model();
joint = run_rfdac_iq_mismatch_sweep(cfg, [1 2 3]);
options = struct('Calibration_Mode','iq_only', ...
    'Training_Directory',joint.Output_Directory, ...
    'Plant_Calibration',joint.TX_Calibration);
iq = run_rfdac_iq_mismatch_sweep(joint.Configuration, [1 2 3], options);
validation = validate_rfdac_iq_mismatch_sweep(iq);
```

The angle vector selects the actual simulated cases. A smaller step can locate a crossing more closely. The report compares measured EVM with −40 dB, equivalent to 1% RMS EVM. A result at or below −40 dB passes. If all sampled angles pass, the experiment establishes that no failure was observed at those angles; it does not identify a failure threshold beyond the tested range or prove that every intermediate angle passes.

The sweep holds the physical TX compression strength fixed after calibrating it once at the requested clean-TX target. It retrains the measured LUT for each static IQ mismatch. Consequently, this evaluates the calibration capability at each mismatch, rather than the drift tolerance of a single LUT calibrated at another angle.

## Measured training and mapping

The experiment follows this sequence for every angle:

1. Generate a 128 × 128 DAC grid, visiting its 16,384 distinct input points in serpentine order. A zero prefix and suffix isolate each frame. Each point is held for the configured DAC dwell time, and complete frames may be repeated to average the observation.
2. Apply those input words to the actual Simulink RF chain with DPD bypassed. Recover and align the received complex envelope. The paired input words and measured responses form the complete measured training dataset.
3. Interpolate the measured forward response and map each desired 4096-QAM point to an input word whose interpolated response is nearest to that target. DAC inputs retain the existing signed 10-bit format and obey the legal DAC range.
4. Arrange the 4096 mapped input points in the corresponding 64 × 64 serpentine sequence. Send them through the actual RF chain and capture their received output. This second RF acquisition measures the final 4096-point output; interpolated training responses are not substituted for it.

The user-authorized interpolation derives all values from the 16,384 measured nodes. The existing implementation can evaluate a 1024 × 1024 grid of legal 10-bit DAC word pairs and a corresponding inverse address map. Those 1,048,576 derived values are computational interpolation and mapping data, not additional measured training points. They do require additional software memory. A physical implementation limited to exactly 16,384 stored hardware words would need a specified interpolator and address architecture; the software's derived address map should not be described as a 16,384-word hardware memory.

No analytic inverse, known IQ error, true compressor coefficient, or instantaneous jitter trace supplies the DPD correction. The simulator uses the configured physical parameters to produce RF observations. Training capture and the inverse mapping use the observed responses. The clean-TX calibration sets the physical plant and is kept separate from constructing the measured LUT.

## Interpreting the two EVM measurements

`Snake_EVM_dB` scores the actual 4096-point serpentine output. Each held point is recovered from a window inside its dwell interval; repeated frames can be averaged. This is a characterization of the measured constellation transfer. It is affected by dwell time, filter settling, observation windows, and averaging.

`Payload_EVM_dB` scores an ordinary random 4096-QAM payload with TX/RX RRC pulse shaping, the configured RX equalizer, and the same frozen measured DPD map. It measures the communication waveform at the receiver's symbol decisions. This provides a separate check of performance under continuous pulse-shaped operation.

The point-averaged snake measurement and the pulse-shaped payload measurement have different filtering and averaging. Their EVM and SER can differ. The report preserves both values and separate −40 dB pass flags. Point-averaged capture EVM should not be presented as the payload's unaveraged symbol EVM.

Both measurements remove only one fitted constant complex gain over the full valid record before calculating EVM. They do not refit IQ imbalance, nonlinearity, or an independent gain for each constellation point. The reported static mismatch is the configured quadrature **phase error in degrees**; the experiment does not introduce a separate I/Q gain imbalance.

The requested 45 dB TX SNR follows the project's existing definition: an EVM-equivalent clean-chain target implemented by calibrating the RF `atan` compression model with ideal quadrature and jitter disabled. It does not add a separate 45 dB AWGN source. The actual mismatch sweep retains the requested IQ error and 100 fs jitter.

## Saved outputs

The report table contains the configured mismatch, snake and payload EVM, finite-record SER, and the separate −40 dB pass flags. Per-case files preserve the 16,384 training responses, 4096 target points, mapped DAC input words, and actual captured output so the mapping can be inspected.

`validate_rfdac_iq_mismatch_sweep` independently recalculates EVM/SER from the saved received points, checks the frozen physical configuration, verifies all training and mapped DAC words, reconstructs all 4096 interpolation predictions from the measured 128 × 128 dataset, and checks the reported threshold conclusion. It does not rerun RF simulation or refit the TX.

`plot_rfdac_iq_mismatch_sweep(report)` saves:

- `iq_mismatch_evm.png`: EVM and measured SER versus static IQ phase mismatch, with the −40 dB target shown explicitly.
- `iq_mismatch_serpentine.png`: measured 16,384-point training responses, mapped 4096 inputs, and the actual recovered 4096-point output for the worst available snake-EVM case.

These figures distinguish the measured training dataset, the derived input mapping, and the final RF observation. The 4096-point output image uses the same single scalar gain normalization as its EVM score.
