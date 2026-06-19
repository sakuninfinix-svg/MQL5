# AIOrchestrator Follow-up Patch Plan

Current branch intentionally applies a safer first-stage runtime fix:

- `AIFeatureBuilder.Build(out)` now becomes MTF-aware when `cfg.Signal.UseMTF` is true.
- `AISignalSource` no longer performs AI prediction during `SignalStage`.

For a fuller GBR-specific late-fusion architecture, patch `CAIOrchestrator::Predict()` later as follows:

```mql5
// Replace the current GBR block:
// if(m_gbr.Predict(fv, gbr_score, gbr_conf)) ...

SAIFeatureVector mtf_fv[4];
ENUM_TIMEFRAMES mtf_tfs[4] = { PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5 };
bool mtf_ready = true;

for(int i = 0; i < 4; i++)
  {
   mtf_fv[i].Reset();
   if(!m_feat.Build(mtf_fv[i], mtf_tfs[i]))
     {
      mtf_ready = false;
      break;
     }
  }

SGBRMTFResult mtf_result;
if(mtf_ready && m_gbr.PredictMTF(mtf_fv, mtf_result))
  {
   gbr_score = mtf_result.score;
   gbr_conf  = mtf_result.confidence;
   gbr_used  = true;
   if(m_debugMode)
      PrintFormat("[AIOrchestrator] GBR MTF prediction: %.4f (conf=%.4f)", gbr_score, gbr_conf);
  }
else if(m_gbr.Predict(fv, gbr_score, gbr_conf))
  {
   gbr_used = true;
   if(m_debugMode)
      PrintFormat("[AIOrchestrator] GBR single-TF fallback: %.4f (conf=%.4f)", gbr_score, gbr_conf);
  }
```

This follow-up needs a careful full-file edit of `AIOrchestrator.mqh` because that file is large and contains several interconnected responsibilities.
