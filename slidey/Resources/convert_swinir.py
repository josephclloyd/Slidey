"""
Convert SwinIR color JPEG artifact removal .pth → CoreML .mlpackage

Model:    006_colorCAR_DFWB_s126w7_SwinIR-M_jpeg40  (Apache-2.0)
Repo:     https://github.com/JingyunLiang/SwinIR
Weights:  piddnad/DDColor-models on HuggingFace (or direct GitHub releases page)

Input:    (1, 3, 126, 126) float32, RGB values in [0, 1]
Output:   (1, 3, 126, 126) float32, RGB artifact-removed, values in [0, 1]

Swift inference:
  Tile the source image into overlapping 126×126 patches, run inference on each,
  blend tiles with a Gaussian weight map, reassemble. The 126×126 size is the
  model's native training patch — tracing at other sizes triggers a coremltools
  slice-by-index error in the shift-mask computation.

Dependencies:
  pip install torch==2.2.0 coremltools==7.2 timm "numpy<2"
  git clone https://github.com/JingyunLiang/SwinIR

Usage:
  python convert_swinir_final.py \
      --repo /path/to/SwinIR \
      --ckpt /path/to/006_colorCAR_DFWB_s126w7_SwinIR-M_jpeg40.pth \
      --output SwinIR_color_jpeg40.mlpackage
"""
import argparse, sys, os, gc, warnings
warnings.filterwarnings('ignore')
import torch
import coremltools as ct

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--repo',   required=True, help='Path to cloned SwinIR repo')
    p.add_argument('--ckpt',   required=True, help='Path to .pth checkpoint')
    p.add_argument('--output', default='SwinIR_color_jpeg40.mlpackage')
    return p.parse_args()

def main():
    args = parse_args()
    sys.path.insert(0, args.repo)
    from models.network_swinir import SwinIR as net

    print(f"Loading {args.ckpt} ...")
    model = net(
        upscale=1, in_chans=3, img_size=126, window_size=7,
        img_range=255., depths=[6, 6, 6, 6, 6, 6],
        embed_dim=180, num_heads=[6, 6, 6, 6, 6, 6],
        mlp_ratio=2, upsampler='', resi_connection='1conv',
    )
    ckpt = torch.load(args.ckpt, map_location='cpu')
    key  = 'params' if 'params' in ckpt else next(iter(ckpt))
    model.load_state_dict(ckpt[key], strict=True)
    model.eval()
    del ckpt; gc.collect()
    print(f"  {sum(p.numel() for p in model.parameters()):,} params")

    print("Tracing at 126×126 ...")
    dummy  = torch.zeros(1, 3, 126, 126)
    traced = torch.jit.trace(model, dummy, check_trace=False)
    del model, dummy; gc.collect()

    print("Converting to CoreML (mlprogram) ...")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="image", shape=(1, 3, 126, 126))],
        outputs=[ct.TensorType(name="restored_image")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS13,
    )
    del traced; gc.collect()

    mlmodel.short_description = "SwinIR color JPEG artifact removal (q-40, 126×126 patch)"
    mlmodel.input_description["image"]           = "RGB 126×126 float32 [0,1]"
    mlmodel.output_description["restored_image"] = "Artifact-removed RGB 126×126 float32 [0,1]"

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
