# AI Video - Local Image Generation (Windows)

One-click local image generation using **Stable Diffusion 1.5 ONNX** on Windows. Works on CPU (no CUDA required).

## Quick Start

1. **Install Python 3.10+** from https://www.python.org/downloads/ (check "Add Python to PATH")
2. **Double-click `install.cmd`**

That's it. The installer will:
- Install Python dependencies (onnxruntime, diffusers, transformers, etc.)
- Download ONNX Runtime
- Set up local folders and Start Menu shortcuts
- Open the launcher menu

The **first time you generate an image**, the SD 1.5 ONNX model (~5 GB) will be downloaded automatically from Hugging Face.

## Usage

### From the launcher menu
After install, choose option `1) Generate Image (interactive)` to start generating.

### From command line
```powershell
# Interactive mode
python generate.py --interactive

# Single image
python generate.py --prompt "a cat sitting on a rainbow"

# Custom settings
python generate.py --prompt "cyberpunk city" --steps 30 --width 512 --height 512
```

### Re-run the launcher anytime
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Action Launcher
```

## What it does

- **`install.cmd`** → one-click entry point (double-click this)
- **`install.ps1`** → PowerShell installer/launcher with menu
- **`generate.py`** → actual image generation using SD 1.5 ONNX
- **`config/default-config.json`** → default settings (model, resolution, steps)
- **`config/apps.json`** → app launcher metadata

## Local folders (created in `%LOCALAPPDATA%\AI-Video`)

| Folder | Purpose |
|--------|---------|
| `outputs` | Generated images saved here |
| `models` | Model cache |
| `runtime` | ONNX Runtime files |
| `logs` | Install/runtime logs |

## Configuration

Edit `%LOCALAPPDATA%\AI-Video\config.json` to change:
- `generation.defaultPrompt` — default prompt text
- `generation.width` / `generation.height` — image dimensions (512x512 default)
- `generation.numInferenceSteps` — quality vs speed (25 default)
- `generation.guidanceScale` — how closely to follow the prompt (7.5 default)
- `sdOnnxModelId` — Hugging Face model ID (default: `runwayml/stable-diffusion-v1-5`)

## Requirements

- Windows 10/11
- Python 3.10+ (with pip)
- ~6 GB disk space (for model + runtime)
- No GPU required (runs on CPU via ONNX Runtime)

