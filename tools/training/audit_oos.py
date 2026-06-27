# audit_oos.py
import pandas as pd, numpy as np, joblib
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score

DATA = "/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools/output/AI_Training_Data_Processed_v4.csv"
df = pd.read_csv(DATA)
X = df[[f"f{i}" for i in range(34)]].values.astype(np.float32)
y = (df["label"].values == 1).astype(int)
ts = df["timestamp"].values

# split 80/20 chronological (last 20% as OOS)
cut = int(len(X) * 0.8)
X_tr, X_oos = X[:cut], X[cut:]
y_tr, y_oos = y[:cut], y[cut:]

# retrain balanced GBR (same as training script)
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.utils.class_weight import compute_sample_weight

sc = StandardScaler()
Xs_tr = sc.fit_transform(X_tr)
Xs_oos = sc.transform(X_oos)

sw = compute_sample_weight(class_weight='balanced', y=y_tr)
clr = GradientBoostingClassifier(n_estimators=120, max_depth=4, learning_rate=0.1, random_state=42)
clr.fit(Xs_tr, y_tr, sample_weight=sw)

pred_oos = clr.predict(Xs_oos)
proba_oos = clr.predict_proba(Xs_oos)[:,1]
acc_oos = accuracy_score(y_oos, pred_oos)
f1_oos  = f1_score(y_oos, pred_oos)
auc_oos = roc_auc_score(y_oos, proba_oos)
print("[oOS]  acc=%.4f f1=%.4f auc=%.4f" % (acc_oos, f1_oos, auc_oos))

# baseline: random classifier for sanity
import numpy as np
np.random.seed(0)
rand = np.random.randint(0,2,size=len(y_oos))
print("[rand] acc=%.4f f1=%.4f auc=0.5" % (accuracy_score(y_oos, rand), f1_score(y_oos, rand)))
