#!/usr/bin/env python3
"""train_gbr_onnx_balanced.py
Train GradientBoosting with class_weight='balanced' and stratified split.
Outputs:
 - MQL5/tools/output/PASR_gbr_m0_balanced.onnx
 - MQL5/tools/output/PASR_gbr_m0_balanced_scaler.bin
"""
import pandas as pd, numpy as np, os, joblib
from sklearn.model_selection import train_test_split
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

DATA_CSV = "/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools/output/AI_Training_Data_Processed_v4.csv"
OUT_DIR = "/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools/output"

print("[train] load data")
df = pd.read_csv(DATA_CSV)
X = df[[f"f{i}" for i in range(34)]].values.astype(np.float32)
y = df["label"].values
# map -1->0, 0->1, 1->2 (to have three classes, but we focus on BUY vs NON‑BUY)
# for binary classification we treat label==1 as positive, else negative
binary = (y == 1).astype(int)

# stratified split
X_train, X_test, y_train, y_test = train_test_split(X, binary, test_size=0.2, random_state=42, stratify=binary)

# scaler
sc = StandardScaler()
X_train_s = sc.fit_transform(X_train)
X_test_s  = sc.transform(X_test)

print("[train] fit GBR (balanced)")
# compute sample weight for imbalance
from sklearn.utils.class_weight import compute_sample_weight
sample_weight = compute_sample_weight(class_weight='balanced', y=y_train)

clf = GradientBoostingClassifier(n_estimators=120, max_depth=4, learning_rate=0.1, random_state=42)
clf.fit(X_train_s, y_train, sample_weight=sample_weight)

pred = clf.predict(X_test_s)
proba = clf.predict_proba(X_test_s)[:,1]
print("[train] metrics test: acc=%.4f f1=%.4f auc=%.4f" % (
    accuracy_score(y_test, pred), f1_score(y_test, pred), roc_auc_score(y_test, proba)))

# export onnx
initial_type = [('float_input', FloatTensorType([None, X.shape[1]]))]
onnx_model = convert_sklearn(clf, initial_types=initial_type)
onnx_path = os.path.join(OUT_DIR, "PASR_gbr_m0_balanced.onnx")
with open(onnx_path, "wb") as f:
    f.write(onnx_model.SerializeToString())
print("[train] ONNX saved:", onnx_path)
# save scaler (mean & scale as float32)
scaler_path = os.path.join(OUT_DIR, "PASR_gbr_m0_balanced_scaler.bin")
with open(scaler_path, "wb") as f:
    # write mean then scale as float32 (little endian)
    for v in sc.mean_.astype(np.float32):
        f.write(v.tobytes())
    for v in sc.scale_.astype(np.float32):
        f.write(v.tobytes())
print("[train] scaler saved:", scaler_path)
