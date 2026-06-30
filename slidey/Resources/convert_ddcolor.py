"""
Convert DDColor paper_tiny .pth → CoreML .mlpackage

Model:    DDColor paper-tiny (Apache-2.0)
Repo:     https://github.com/piddnad/DDColor
Weights:  piddnad/DDColor-models on HuggingFace → ddcolor_paper_tiny.pth

Input:    (1, 3, 512, 512) float32
          Grayscale-encoded RGB: extract Lab L-channel from source image,
          replicate to (L, L, L), convert to RGB float32 in [0, 1].
          The model applies ImageNet normalisation internally (do_normalize=False
          means the OUTPUT is not denormalised; the input IS normalised inside).

Output:   (1, 2, 512, 512) float32
          AB channels in Lab colorspace (raw, not rescaled).

Swift inference procedure:
  1. Convert source image to Lab (CIFilter or vImage).
  2. Extract L channel; replicate to (L_norm, L_norm, L_norm) where L_norm = L/100.
  3. Run model → ab_tensor shape [1, 2, 512, 512].
  4. Upsample ab_tensor to (original_height, original_width).
  5. Combine (original_L, ab[0], ab[1]) in Lab → RGB.

Dependencies:
  pip install torch==2.2.0 coremltools==7.2 einops "numpy<2"
  git clone https://github.com/piddnad/DDColor

Usage:
  python convert_ddcolor_final.py \
      --repo /path/to/DDColor \
      --ckpt /path/to/ddcolor_paper_tiny.pth \
      --output DDColor_paper_tiny.mlpackage
"""
import argparse, sys, os, gc, warnings
warnings.filterwarnings('ignore')
import torch
import coremltools as ct

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--repo',   required=True, help='Path to cloned DDColor repo')
    p.add_argument('--ckpt',   required=True, help='Path to .pth checkpoint')
    p.add_argument('--output', default='DDColor_paper_tiny.mlpackage')
    return p.parse_args()

def main():
    args = parse_args()
    sys.path.insert(0, args.repo)
    from basicsr.archs.ddcolor_arch import DDColor

    print(f"Loading {args.ckpt} ...")
    model = DDColor(
        encoder_name='convnext-t',
        decoder_name='MultiScaleColorDecoder',
        input_size=[512, 512],
        num_output_channels=2,
        last_norm='Spectral',
        do_normalize=False,
        num_queries=100,
        num_scales=3,
        dec_layers=9,
    )
    ckpt = torch.load(args.ckpt, map_location='cpu')
    model.load_state_dict(ckpt['params'], strict=False)
    model.eval()
    del ckpt; gc.collect()
    print(f"  {sum(p.numel() for p in model.parameters()):,} params")

    print("Tracing at 512×512 ...")
    dummy  = torch.zeros(1, 3, 512, 512)
    traced = torch.jit.trace(model, dummy, check_trace=False)
    del model, dummy; gc.collect()

    print("Converting to CoreML (mlprogram) ...")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="gray_rgb", shape=(1, 3, 512, 512))],
        outputs=[ct.TensorType(name="ab_channels")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS13,
    )
    del traced; gc.collect()

    mlmodel.short_description = "DDColor paper-tiny B&W photo colorization (512×512)"
    mlmodel.input_description["gray_rgb"]     = "Grayscale-encoded RGB float32 [0,1], 512×512"
    mlmodel.output_description["ab_channels"] = "AB Lab channels float32, 512×512"

    print(f"Saving {args.output} (ANE compilation may take 30–60 min) ...")
    mlmodel.save(args.output)

    size_mb = sum(
        os.path.getsize(os.path.join(r, f))
        for r, _, files in os.walk(args.output)
        for f in files
    ) / 1024 / 1024
    print(f"Done: {args.output}  ({size_mb:.1f} MB)")

if __name__ == '__main__':
    main()
