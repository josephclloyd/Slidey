"""
Convert Restormer real-denoising .pth -> CoreML .mlpackage

Model:    Restormer real_denoising (MIT)
Repo:     https://github.com/swz30/Restormer
Weights:  official Google Drive link in Denoising/README.md (real_denoising.pth)

Input:    (1, 3, 256, 256) float32, RGB values in [0, 1]
Output:   (1, 3, 256, 256) float32, denoised RGB, values in [0, 1] (small overshoot possible)

Why Restormer over NAFNet-SIDD:
  NAFNet-SIDD (both width32 and width64, official weights) is numerically unstable
  on very low-variance/flat dark image patches -- common in real nighttime photos,
  exactly this feature's target use case. Confirmed at the raw untraced PyTorch level
  (not a CoreML/conversion artifact): output blows up to values like [-10, 15] or
  worse on flat dark crops that should stay near [0, 1]. Restormer's real_denoising
  checkpoint was tested against the same crops and stayed stable (worst observed
  range [-0.89, 1.02] across a full real nighttime photo's tile grid, vs. NAFNet's
  catastrophic blowups on the same tiles). See #253 for the full investigation.

Precision:
  compute_precision=ct.precision.FLOAT32 explicitly, per the same lesson as SwinIR (#251)
  and NAFNet -- never rely on coremltools' FLOAT16 default for this project.

Tile size:
  256x256. Restormer has no internal padding logic (unlike NAFNet's check_image_size),
  so the tile size must already be compatible with its downsampling stages -- 256 was
  one of the actual progressive-training patch sizes used (see
  Denoising/Options/RealDenoising_Restormer.yml's gt_sizes), so this isn't a guess.

Dependencies:
  pip install torch==2.2.0 coremltools==7.2 einops "numpy<2"
  git clone https://github.com/swz30/Restormer

Usage:
  python convert_restormer.py \
      --repo /path/to/Restormer \
      --ckpt /path/to/real_denoising.pth \
      --output Restormer_real_denoising.mlpackage
"""
import argparse, sys, os, gc, warnings, importlib.util
warnings.filterwarnings('ignore')
import torch
import coremltools as ct

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--repo',   required=True, help='Path to cloned Restormer repo')
    p.add_argument('--ckpt',   required=True, help='Path to .pth checkpoint')
    p.add_argument('--output', default='Restormer_real_denoising.mlpackage')
    return p.parse_args()

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

def main():
    args = parse_args()
    arch_path = os.path.join(args.repo, 'basicsr', 'models', 'archs', 'restormer_arch.py')
    net = load_module('restormer_arch', arch_path).Restormer

    # BiasFree_LayerNorm / WithBias_LayerNorm call x.var(-1, ...), which coremltools 7.2's
    # torch frontend has no converter for ("PyTorch convert function for op 'var' not
    # implemented"). Patch in the equivalent manual population-variance computation
    # (mean of squared deviations) -- mathematically identical to unbiased=False.
    layer_norm_mod = sys.modules['restormer_arch']

    def _biasfree_forward(self, x):
        mu = x.mean(-1, keepdim=True)
        sigma = ((x - mu) ** 2).mean(-1, keepdim=True)
        return x / torch.sqrt(sigma + 1e-5) * self.weight
    layer_norm_mod.BiasFree_LayerNorm.forward = _biasfree_forward

    def _withbias_forward(self, x):
        mu = x.mean(-1, keepdim=True)
        sigma = ((x - mu) ** 2).mean(-1, keepdim=True)
        return (x - mu) / torch.sqrt(sigma + 1e-5) * self.weight + self.bias
    layer_norm_mod.WithBias_LayerNorm.forward = _withbias_forward

    print(f"Loading {args.ckpt} ...")
    model = net(
        inp_channels=3, out_channels=3, dim=48,
        num_blocks=[4, 6, 6, 8], num_refinement_blocks=4,
        heads=[1, 2, 4, 8], ffn_expansion_factor=2.66,
        bias=False, LayerNorm_type='BiasFree', dual_pixel_task=False,
    )
    ckpt = torch.load(args.ckpt, map_location='cpu', weights_only=True)
    model.load_state_dict(ckpt['params'], strict=True)
    model.eval()
    del ckpt; gc.collect()
    print(f"  {sum(p.numel() for p in model.parameters()):,} params")

    print("Tracing at 256x256 ...")
    dummy = torch.zeros(1, 3, 256, 256)
    traced = torch.jit.trace(model, dummy, check_trace=False)
    del model, dummy; gc.collect()

    print("Converting to CoreML (mlprogram) ...")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="image", shape=(1, 3, 256, 256))],
        outputs=[ct.TensorType(name="denoised_image")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT32,
    )
    del traced; gc.collect()

    mlmodel.short_description = "Restormer real-noise denoising (256x256 patch)"
    mlmodel.input_description["image"] = "RGB 256x256 float32 [0,1]"
    mlmodel.output_description["denoised_image"] = "Denoised RGB 256x256 float32 (clamp to [0,1] downstream)"

    print(f"Saving {args.output} ...")
    mlmodel.save(args.output)

    size_mb = sum(
        os.path.getsize(os.path.join(r, f))
        for r, _, files in os.walk(args.output)
        for f in files
    ) / 1024 / 1024
    print(f"Done: {args.output}  ({size_mb:.1f} MB)")

if __name__ == '__main__':
    main()
