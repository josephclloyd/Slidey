"""
Convert CodeFormer .pth checkpoint → Core ML .mlpackage
Loads arch files directly (bypasses basicsr's heavy data/model __init__ chain).
"""
import sys, os, types, importlib.util
import torch, torch.nn as nn
import coremltools as ct

REPO = '/tmp/codeformer-convert/repo'

# ── Stubs for basicsr infrastructure used only at class-registration time ──────
def _pkg(name):
    m = types.ModuleType(name); m.__path__ = []; m.__package__ = name
    sys.modules[name] = m; return m
def _mod(name):
    m = types.ModuleType(name); sys.modules[name] = m; return m

_logger = type('L', (), {'info': print, 'warning': print, 'debug': lambda *a: None})()
class _Reg:
    def register(self, *a, **kw): return lambda cls: cls

_pkg('basicsr'); _pkg('basicsr.utils'); _pkg('basicsr.archs')
_mod('basicsr.utils.registry').ARCH_REGISTRY = _Reg()
sys.modules['basicsr.utils'].get_root_logger = lambda: _logger

def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m

_load('basicsr.archs.vqgan_arch',      f'{REPO}/basicsr/archs/vqgan_arch.py')
_load('basicsr.archs.codeformer_arch', f'{REPO}/basicsr/archs/codeformer_arch.py')

from basicsr.archs.codeformer_arch import CodeFormer  # noqa
from basicsr.archs import codeformer_arch as _cfmod

# ── Patch: str(x.shape[-1]) → str(int(x.shape[-1])) so trace works ───────────
# During torch.jit.trace, tensor.shape returns ints already at trace-time for
# fixed-size inputs, but str() on them can produce "tensor(32)". Using int()
# first normalises them to plain Python ints before stringification.
import types as _types

_orig_cf_forward = CodeFormer.forward

def _patched_cf_forward(self, x, w=0, detach_16=True, code_only=False, adain=False):
    enc_feat_dict = {}
    out_list = [self.fuse_encoder_block[f_size] for f_size in self.connect_list]
    for i, block in enumerate(self.encoder.blocks):
        x = block(x)
        if i in out_list:
            enc_feat_dict[str(int(x.shape[-1]))] = x.clone()   # <-- int() fix

    lq_feat = x
    pos_emb = self.position_emb.unsqueeze(1).repeat(1, x.shape[0], 1)
    feat_emb = self.feat_emb(lq_feat.flatten(2).permute(2, 0, 1))
    query_emb = feat_emb
    for layer in self.ft_layers:
        query_emb = layer(query_emb, query_pos=pos_emb)
    logits = self.idx_pred_layer(query_emb)
    logits = logits.permute(1, 0, 2)

    if code_only:
        return logits, lq_feat

    soft_one_hot = torch.nn.functional.softmax(logits, dim=2)
    _, top_idx = torch.topk(soft_one_hot, 1, dim=2)
    quant_feat = self.quantize.get_codebook_feat(top_idx, shape=[x.shape[0], 16, 16, 256])

    if detach_16:
        quant_feat = quant_feat.detach()
    if adain:
        from basicsr.archs.codeformer_arch import adaptive_instance_normalization
        quant_feat = adaptive_instance_normalization(quant_feat, lq_feat)

    x = quant_feat
    fuse_list = [self.fuse_generator_block[f_size] for f_size in self.connect_list]
    for i, block in enumerate(self.generator.blocks):
        x = block(x)
        if i in fuse_list:
            f_size = str(int(x.shape[-1]))                       # <-- int() fix
            if w > 0:
                x = self.fuse_convs_dict[f_size](enc_feat_dict[f_size].detach(), x, w)
    return x, logits, lq_feat

CodeFormer.forward = _patched_cf_forward

CHECKPOINT = '/tmp/codeformer-convert/codeformer.pth'
OUTPUT     = '/tmp/codeformer-convert/CodeFormer.mlpackage'

# ── 1. Load model ─────────────────────────────────────────────────────────────
print("Loading CodeFormer checkpoint...")
net = CodeFormer(
    dim_embd=512, codebook_size=1024, n_head=8, n_layers=9,
    connect_list=['32', '64', '128', '256'],
).eval()

ckpt = torch.load(CHECKPOINT, map_location='cpu', weights_only=False)
params = ckpt.get('params_ema', ckpt.get('params', ckpt))
net.load_state_dict(params)
print("Checkpoint loaded.")

# ── 2. Wrapper ────────────────────────────────────────────────────────────────
class CodeFormerWrapper(nn.Module):
    def __init__(self, model):
        super().__init__(); self.model = model
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        out, _, _ = self.model(x, w=1.0, adain=True)
        return out

wrapped = CodeFormerWrapper(net).eval()

# ── 3. Trace ──────────────────────────────────────────────────────────────────
print("Tracing model with 512×512 dummy input...")
dummy = torch.randn(1, 3, 512, 512)
with torch.no_grad():
    traced = torch.jit.trace(wrapped, dummy)
print("Trace complete.")

# ── 4. Convert to Core ML ─────────────────────────────────────────────────────
print("Converting to Core ML (takes ~1-2 min)...")
mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="face", shape=(1, 3, 512, 512))],
    outputs=[ct.TensorType(name="restored_face")],
    minimum_deployment_target=ct.target.macOS13,
    compute_units=ct.ComputeUnit.ALL,
)
mlmodel.short_description = "CodeFormer face restoration (w=1.0)"
mlmodel.input_description["face"] = \
    "512×512 face crop, RGB floats in [-1,1], shape (1,3,512,512)"
mlmodel.output_description["restored_face"] = \
    "512×512 restored face, RGB floats in [-1,1]"

print(f"Saving to {OUTPUT}...")
mlmodel.save(OUTPUT)

size_mb = sum(
    os.path.getsize(os.path.join(dp, f))
    for dp, _, files in os.walk(OUTPUT) for f in files
) / 1e6
print(f"Done. Package size: {size_mb:.1f} MB")
