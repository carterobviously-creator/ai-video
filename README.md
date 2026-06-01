# AI Video (Windows-first local bootstrap shell)

This repository is a **Windows-first, local-only bootstrap shell** for building a one-click AI image/video workflow around **Stable Diffusion ONNX**.

## What this repo does today

- Provides a root one-click entry point: `install.cmd`
- Runs a PowerShell bootstrap/launcher: `install.ps1`
- Creates local folders under `%LOCALAPPDATA%\\AI-Video`:
  - `models`
  - `runtime`
  - `outputs`
  - `agent-data`
  - `shortcuts`
  - `logs`
- Creates and persists `config.json` and `apps.json`
- Creates Start Menu shortcuts when possible
- Provides a local PowerShell menu launcher for:
  - AI Video Studio
  - Local Agent
  - open model folder
  - open outputs folder
  - open PowerShell
  - open CMD
  - open WSL (if installed)

## Important constraints

- No Python is used in this repository.
- No Rust/Node application stack is used in this iteration.
- This is an installer/launcher/config scaffold, not a full inference engine implementation.

## SD ONNX direction

The target runtime direction is **Stable Diffusion ONNX + ONNX Runtime** for local Windows use (including older hardware direction such as GTX 1070-class systems).

`install.ps1` includes a download/configuration flow for:
- SD ONNX model package URL (`sdOnnxModelUrl` in config)
- ONNX Runtime bundle URL (`onnxRuntimeUrl` in config)

If URLs are placeholders, the script clearly reports that and tells you to update config first.

## What is placeholder vs real

### Real now
- Installer/bootstrap behavior
- App home/folder setup
- Config persistence
- Start Menu shortcuts
- PowerShell launcher menu
- Local app launch hooks (from `apps.json`)

### Placeholder for next integration step
- Actual native inference executable integration
- Final model/runtime package URLs
- End-to-end frame/video generation pipeline execution

## Run

1. On Windows, double-click `install.cmd`.
2. Or from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

After the first run, update `%LOCALAPPDATA%\\AI-Video\\config.json` with your SD ONNX model/runtime URLs and set `%LOCALAPPDATA%\\AI-Video\\apps.json` executable paths for your local runtime binaries.
