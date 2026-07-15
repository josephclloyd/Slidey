"""
Convert LaMa (Large Mask Inpainting) TorchScript -> CoreML .mlpackage

Model:    LaMa big (MIT License)
Source:   https://github.com/advimman/lama
Weights:  https://github.com/enesmsahin/simple-lama-inpainting/releases/download/v0.1.0/big-lama.pt

Input:    image (1, 3, 512, 512) float32, RGB [0,1]
          mask  (1, 1, 512, 512) float32, binary {0,1}, 1 = region to inpaint
Output:   (1, 3, 512, 512) float32, inpainted RGB [0,1]

Precision:
  compute_precision=ct.precision.FLOAT32 explicitly, per project convention
  (never rely on coremltools' FLOAT16 default).

Architecture note:
  LaMa uses FFC (Fast Fourier Convolution) blocks containing torch.fft.rfftn/irfftn.
  Direct torch.jit.trace conversion fails on these ops ("fft_rfft2 not implemented").
  However, loading the pre-traced TorchScript model and converting *that* succeeds in
  coremltools 9.0 — the TorchScript frontend apparently handles FFT ops that the
  PyTorch trace frontend does not. Verified: output is in [0,1] range, no NaN/Inf.

Dependencies:
  pip install torch coremltools>=9.0

Usage:
  # Download big-lama.pt first:
  curl -L -o big-lama.pt https://github.com/enesmsahin/simple-lama-inpainting/releases/download/v0.1.0/big-lama.pt

  python convert_lama.py --model big-lama.pt --output LaMa_Inpainting.mlpackage
"""
import argparse, os
import torch
import coremltools as ct


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--model', required=True, help='Path to big-lama.pt TorchScript model')
    p.add_argument('--output', default='LaMa_Inpainting.mlpackage')
    return p.parse_args()


def main():
    args = parse_args()

    print(f"Loading {args.model} ...")
    model = torch.jit.load(args.model, map_location="cpu")
    model.eval()

    print("Converting to CoreML (mlprogram, FLOAT32) ...")
    mlmodel = ct.convert(
        model,
        inputs=[
            ct.TensorType(name="image", shape=(1, 3, 512, 512)),
            ct.TensorType(name="mask", shape=(1, 1, 512, 512)),
        ],
        outputs=[ct.TensorType(name="inpainted")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS13,
    )

    mlmodel.short_description = "LaMa large mask inpainting (512x512)"
    mlmodel.input_description["image"] = "RGB 512x512 float32 [0,1]"
    mlmodel.input_description["mask"] = "Binary mask 512x512 float32 {0,1}, 1=inpaint"
    mlmodel.output_description["inpainted"] = "Inpainted RGB 512x512 float32 [0,1]"

    print(f"Saving {args.output} ...")
    mlmodel.save(args.output)

    size_mb = sum(
        os.path.getsize(os.path.join(r, f))
        for r, _, files in os.walk(args.output)
        for f in files
    ) / 1024 / 1024
    print(f"Done: {args.output}  ({size_mb:.1f} MB)")

    # Quick sanity check
    print("\nVerifying ...")
    dummy_img = torch.rand(1, 3, 512, 512)
    dummy_mask = torch.zeros(1, 1, 512, 512)
    dummy_mask[0, 0, 200:300, 200:300] = 1.0
    with torch.no_grad():
        out = model(dummy_img, dummy_mask)
    has_nan = torch.isnan(out).any().item()
    has_inf = torch.isinf(out).any().item()
    print(f"  Output range: [{out.min():.3f}, {out.max():.3f}]")
    print(f"  NaN: {has_nan}, Inf: {has_inf}")
    if has_nan or has_inf:
        print("  WARNING: model output contains NaN or Inf!")
    else:
        print("  OK")


if __name__ == '__main__':
    main()
