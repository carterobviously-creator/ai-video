"""
AI Video Studio - Image Generation using Stable Diffusion ONNX
Generates images locally using ONNX Runtime (no CUDA required, works on CPU).
"""

import argparse
import json
import os
import sys
from pathlib import Path

MAX_FILENAME_LENGTH = 50
DEFAULT_PROMPT = "a photo of an astronaut riding a horse on mars"


def get_config():
    """Load config from the standard app home location."""
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    if local_app_data:
        config_path = Path(local_app_data) / "AI-Video" / "config.json"
    else:
        config_path = Path(__file__).parent / "local-ai-video" / "config.json"

    if not config_path.exists():
        print(f"[ERROR] Config not found at {config_path}")
        print("Run install.cmd first to set up the environment.")
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def generate_image(prompt, output_dir, width=512, height=512, steps=25, guidance=7.5, model_id=None, revision=None):
    """Generate an image using OnnxStableDiffusionPipeline."""
    try:
        from diffusers import OnnxStableDiffusionPipeline
    except ImportError:
        print("[ERROR] diffusers is not installed. Run install.cmd or:")
        print("  pip install diffusers transformers onnxruntime numpy Pillow")
        sys.exit(1)

    if model_id is None:
        model_id = "runwayml/stable-diffusion-v1-5"
    if revision is None:
        revision = "onnx"

    print(f"[AI-VIDEO] Loading model: {model_id} (revision: {revision})")
    print("[AI-VIDEO] First run will download the model (~5 GB). Please wait...")

    pipe = OnnxStableDiffusionPipeline.from_pretrained(
        model_id,
        revision=revision,
        provider="CPUExecutionProvider",
    )

    print(f"[AI-VIDEO] Generating: \"{prompt}\"")
    print(f"[AI-VIDEO] Size: {width}x{height}, Steps: {steps}, Guidance: {guidance}")

    result = pipe(
        prompt,
        height=height,
        width=width,
        num_inference_steps=steps,
        guidance_scale=guidance,
    )

    image = result.images[0]

    os.makedirs(output_dir, exist_ok=True)

    from datetime import datetime
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_prompt = "".join(c if c.isalnum() or c in " _-" else "" for c in prompt)[:MAX_FILENAME_LENGTH].strip()
    filename = f"{timestamp}_{safe_prompt}.png"
    output_path = Path(output_dir) / filename

    image.save(str(output_path))
    print(f"[AI-VIDEO] Saved: {output_path}")

    return str(output_path)


def interactive_mode(config):
    """Run in interactive mode, prompting for input."""
    gen_config = config.get("generation", {})
    output_dir = config.get("outputPath", "outputs")
    model_id = config.get("sdOnnxModelId", "runwayml/stable-diffusion-v1-5")
    revision = config.get("sdOnnxModelRevision", "onnx")

    print("")
    print("=" * 50)
    print("  AI Video Studio - Image Generator")
    print("  Using Stable Diffusion 1.5 ONNX (CPU)")
    print("=" * 50)
    print("")
    print(f"  Output folder: {output_dir}")
    print(f"  Model: {model_id}")
    print("")

    while True:
        default_prompt = gen_config.get("defaultPrompt", DEFAULT_PROMPT)
        prompt = input(f"Enter prompt (or 'quit' to exit)\n[default: {default_prompt}]\n> ").strip()

        if prompt.lower() in ("quit", "exit", "q"):
            print("[AI-VIDEO] Goodbye!")
            break

        if not prompt:
            prompt = default_prompt

        generate_image(
            prompt=prompt,
            output_dir=output_dir,
            width=gen_config.get("width", 512),
            height=gen_config.get("height", 512),
            steps=gen_config.get("numInferenceSteps", 25),
            guidance=gen_config.get("guidanceScale", 7.5),
            model_id=model_id,
            revision=revision,
        )
        print("")


def main():
    parser = argparse.ArgumentParser(description="AI Video Studio - Generate images with SD ONNX")
    parser.add_argument("--prompt", "-p", type=str, help="Text prompt for image generation")
    parser.add_argument("--output", "-o", type=str, help="Output directory (overrides config)")
    parser.add_argument("--width", type=int, help="Image width (default: 512)")
    parser.add_argument("--height", type=int, help="Image height (default: 512)")
    parser.add_argument("--steps", type=int, help="Number of inference steps (default: 25)")
    parser.add_argument("--guidance", type=float, help="Guidance scale (default: 7.5)")
    parser.add_argument("--interactive", "-i", action="store_true", help="Run in interactive mode")
    args = parser.parse_args()

    config = get_config()
    gen_config = config.get("generation", {})

    if args.interactive or args.prompt is None:
        interactive_mode(config)
    else:
        output_dir = args.output or config.get("outputPath", "outputs")
        generate_image(
            prompt=args.prompt,
            output_dir=output_dir,
            width=args.width or gen_config.get("width", 512),
            height=args.height or gen_config.get("height", 512),
            steps=args.steps or gen_config.get("numInferenceSteps", 25),
            guidance=args.guidance or gen_config.get("guidanceScale", 7.5),
            model_id=config.get("sdOnnxModelId"),
            revision=config.get("sdOnnxModelRevision"),
        )


if __name__ == "__main__":
    main()
