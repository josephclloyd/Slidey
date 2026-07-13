"""
Convert NAFNet SIDD real-denoising .pth -> CoreML .mlpackage

Model:    NAFNet-SIDD-width32 (MIT)
Repo:     https://github.com/megvii-research/NAFNet
Weights:  official Google Drive link in docs/SIDD.md (NAFNet-SIDD-width32.pth)

Input:    (1, 3, 256, 256) float32, RGB values in [0, 1]
Output:   (1, 3, 256, 256) float32, RGB denoised, values in [0, 1] (unclamped -- residual add)

Swift inference:
  Tile the source image into overlapping 256x256 patches, run inference on each,
  blend tiles with a weighted overlap, reassemble. 256 is the exact SIDD training
  patch size (options/train/SIDD/NAFNet-width32.yml: gt_size: 256) and is evenly
  divisible by the network's padder_size (2^4 = 16 downsampling stages), so tracing
  at this size hits no internal padding branch and matches training-time statistics
  for the "Simplified Channel Attention" global-average-pool exactly -- no need for
  the repo's NAFNetLocal/TLC local-statistics correction, which exists specifically
  for whole-image (non-tiled) inference at sizes that DON'T match the training crop.

Precision:
  compute_precision=ct.precision.FLOAT32 is required. coremltools defaults mlprogram
  conversion to FLOAT16; see #251 for the SwinIR NaN bug this caused (that model
  scaled activations 255x internally and overflowed fp16's ~65504 max). NAFNet has
  no such extreme internal scaling, but there's no reason to take the risk given we
  already know the default is unsafe for this class of model on this stack.

Dependencies:
  pip install torch==2.2.0 coremltools==7.2 "numpy<2"
  git clone https://github.com/megvii-research/NAFNet

Usage:
  python convert_nafnet.py \
      --repo /path/to/NAFNet \
      --ckpt /path/to/NAFNet-SIDD-width32.pth \
      --output NAFNet_SIDD_width32.mlpackage
"""
import argparse, sys, os, gc, warnings, importlib.util, types
warnings.filterwarnings('ignore')
import torch
import coremltools as ct

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--repo',   required=True, help='Path to cloned NAFNet repo')
    p.add_argument('--ckpt',   required=True, help='Path to .pth checkpoint')
    p.add_argument('--output', default='NAFNet_SIDD_width32.mlpackage')
    return p.parse_args()

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

def main():
    args = parse_args()
    # Load only the arch files directly -- importing through basicsr's real
    # package __init__ chain drags in lmdb/cv2 (used by unrelated data-prep
    # code) that NAFNet_arch.py itself never touches.
    for pkg in ('basicsr', 'basicsr.models', 'basicsr.models.archs'):
        sys.modules.setdefault(pkg, types.ModuleType(pkg))
    # arch_util.py imports get_root_logger but only calls it in a commented-out
    # line -- stub it rather than pulling in the full basicsr.utils package.
    utils_stub = types.ModuleType('basicsr.utils')
    utils_stub.get_root_logger = lambda *a, **k: None
    sys.modules['basicsr.utils'] = utils_stub
    archs_dir = os.path.join(args.repo, 'basicsr', 'models', 'archs')
    arch_util = load_module('basicsr.models.archs.arch_util', os.path.join(archs_dir, 'arch_util.py'))
    load_module('basicsr.models.archs.local_arch', os.path.join(archs_dir, 'local_arch.py'))
    net = load_module('basicsr.models.archs.NAFNet_arch', os.path.join(archs_dir, 'NAFNet_arch.py')).NAFNet

    # LayerNorm2d wraps a custom torch.autograd.Function (LayerNormFunction),
    # kept only for training-time backward efficiency. torch.jit.trace records
    # that as an opaque prim::PythonOp node coremltools' torch frontend can't
    # convert. Inference doesn't need a custom backward, so patch in the
    # identical forward math as plain ops -- this traces to normal aten ops.
    def _layernorm2d_forward(self, x):
        _, c, _, _ = x.size()
        mu = x.mean(1, keepdim=True)
        var = (x - mu).pow(2).mean(1, keepdim=True)
        y = (x - mu) / (var + self.eps).sqrt()
        return self.weight.view(1, c, 1, 1) * y + self.bias.view(1, c, 1, 1)
    arch_util.LayerNorm2d.forward = _layernorm2d_forward

    print(f"Loading {args.ckpt} ...")
    model = net(
        img_channel=3, width=32,
        enc_blk_nums=[2, 2, 4, 8], middle_blk_num=12, dec_blk_nums=[2, 2, 2, 2],
    )
    ckpt = torch.load(args.ckpt, map_location='cpu', weights_only=True)
    key  = 'params' if 'params' in ckpt else next(iter(ckpt))
    model.load_state_dict(ckpt[key], strict=True)
    model.eval()
    del ckpt; gc.collect()
    print(f"  {sum(p.numel() for p in model.parameters()):,} params")

    print("Tracing at 256x256 ...")
    dummy  = torch.zeros(1, 3, 256, 256)
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

    mlmodel.short_description = "NAFNet SIDD real-noise denoising (width32, 256x256 patch)"
    mlmodel.input_description["image"]            = "RGB 256x256 float32 [0,1]"
    mlmodel.output_description["denoised_image"]  = "Denoised RGB 256x256 float32 (clamp to [0,1] downstream)"

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
