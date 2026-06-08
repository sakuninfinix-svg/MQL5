#!/usr/bin/env python3
"""
export_onnx.py — Validate ONNX export contract for PASR Transformer runtime.

Checks that an ONNX model matches the MQL5 ONNXBridge v2 sequence contract:
  input shape:  [1, AI_SEQ_LEN, AI_SEQ_FEATURE_DIM]  ->  [1, 64, 12]
  output shape: [1, 2]  (direction, confidence) recommended

Usage:
    python export_onnx.py --onnx path/to/model.onnx
"""

from __future__ import annotations

import argparse
import sys

AI_SEQ_LEN = 64
AI_SEQ_FEATURE_DIM = 12
EXPECTED_INPUT_SHAPE = (1, AI_SEQ_LEN, AI_SEQ_FEATURE_DIM)
RECOMMENDED_OUTPUT_LEN = 2


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate PASR ONNX sequence contract")
    parser.add_argument("--onnx", required=True, help="Path to ONNX model file")
    args = parser.parse_args()

    try:
        import onnx
        from onnx import numpy_helper
    except ImportError:
        print("[export_onnx] Install dependencies: pip install onnx")
        return 2

    model = onnx.load(args.onnx)
    graph = model.graph

    if len(graph.input) < 1 or len(graph.output) < 1:
        print("[export_onnx] FAIL: model must have at least one input and one output")
        return 1

    inp = graph.input[0]
    out = graph.output[0]

    def tensor_shape(tensor) -> list:
        dims = []
        for d in tensor.type.tensor_type.shape.dim:
            if d.dim_value > 0:
                dims.append(int(d.dim_value))
            else:
                dims.append(-1)
        return dims

    in_shape = tuple(tensor_shape(inp))
    out_shape = tuple(tensor_shape(out))

    print(f"[export_onnx] input name={inp.name} shape={in_shape}")
    print(f"[export_onnx] output name={out.name} shape={out_shape}")

    ok = True
    if len(in_shape) == 3 and tuple(in_shape) != EXPECTED_INPUT_SHAPE:
        if in_shape[1] != AI_SEQ_LEN or in_shape[2] != AI_SEQ_FEATURE_DIM:
            print(f"[export_onnx] WARN: input shape {in_shape} != {EXPECTED_INPUT_SHAPE}")
            ok = False
    elif len(in_shape) == 2:
        if tuple(in_shape) != (AI_SEQ_LEN, AI_SEQ_FEATURE_DIM):
            print(f"[export_onnx] WARN: 2D input {in_shape} expected ({AI_SEQ_LEN}, {AI_SEQ_FEATURE_DIM})")
            ok = False
    else:
        print(f"[export_onnx] WARN: unexpected input rank {len(in_shape)}")
        ok = False

    if len(out_shape) >= 1:
        out_len = out_shape[-1] if out_shape[-1] > 0 else RECOMMENDED_OUTPUT_LEN
        if out_len < 1:
            print("[export_onnx] WARN: output length could not be determined")
            ok = False
        elif out_len < RECOMMENDED_OUTPUT_LEN:
            print(f"[export_onnx] WARN: output length {out_len} < recommended {RECOMMENDED_OUTPUT_LEN}")

    if ok:
        print("[export_onnx] PASS: ONNX contract compatible with PASR ONNXBridge v2")
        return 0

    print("[export_onnx] FAIL: contract mismatch")
    return 1


if __name__ == "__main__":
    sys.exit(main())
