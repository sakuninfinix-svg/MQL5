#!/usr/bin/env python3
"""
export_onnx.py — Export a lightweight PASR sequence model placeholder
=====================================================================

Creates an ONNX model compatible with ONNXBridge.mqh sequence mode:
  input  shape: [1, 64, 12]
  output shape: [1, 2]   -> [direction, confidence]

This file is intentionally dependency-light and exports a simple deterministic
linear head over the flattened sequence tensor. Replace the generated graph with
an exported PyTorch/TensorFlow LSTM/Transformer later, but keep the same input
and output contract for MQL5 compatibility.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

SEQ_LEN = 64
FEAT_DIM = 12
FLAT_DIM = SEQ_LEN * FEAT_DIM
OUT_DIM = 2


def build_model(seed: int = 42) -> onnx.ModelProto:
    rng = np.random.default_rng(seed)
    weight = rng.normal(0.0, 0.01, size=(FLAT_DIM, OUT_DIM)).astype(np.float32)
    bias = np.array([0.0, 0.5], dtype=np.float32)

    input_tensor = helper.make_tensor_value_info("input", TensorProto.FLOAT, [1, SEQ_LEN, FEAT_DIM])
    output_tensor = helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, OUT_DIM])

    shape_const = numpy_helper.from_array(np.array([1, FLAT_DIM], dtype=np.int64), name="flat_shape")
    weight_const = numpy_helper.from_array(weight, name="linear_w")
    bias_const = numpy_helper.from_array(bias, name="linear_b")

    nodes = [
        helper.make_node("Reshape", ["input", "flat_shape"], ["flat"]),
        helper.make_node("MatMul", ["flat", "linear_w"], ["logits"]),
        helper.make_node("Add", ["logits", "linear_b"], ["output"]),
    ]

    graph = helper.make_graph(
        nodes,
        "PASRSequenceLinearHead",
        [input_tensor],
        [output_tensor],
        initializer=[shape_const, weight_const, bias_const],
    )
    model = helper.make_model(graph, producer_name="PASR export_onnx.py")
    model.opset_import[0].version = 13
    onnx.checker.check_model(model)
    return model


def main() -> int:
    parser = argparse.ArgumentParser(description="Export a PASR-compatible ONNX sequence model")
    parser.add_argument("--out", default="output/PASR_sequence.onnx", help="Output ONNX path")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    model = build_model(args.seed)
    onnx.save(model, out_path)
    print(f"[export_onnx] wrote {out_path}")
    print("[export_onnx] copy to MT5/MQL5/Files/ and set AI.OnnxModelFileName accordingly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
