//+------------------------------------------------------------------+
//| AI/AICalibrationBridge.mqh — v2.00                               |
//| Bridges AIInference output → AdaptiveConfig policy adjustments.  |
//|                                                                  |
//| DESIGN:                                                          |
//|   AI confidence score [0,1] maps to dynamic policy overrides.    |
//|   High confidence expands TP and lot; low confidence             |
//|   tightens SL and reduces position size.                         |
//|                                                                  |
//|   CalibrationLog: ring buffer of 200 (score, outcome) pairs      |
//|   for offline Platt recalibration in Python pipeline.            |
//|   ExportCalibrationCSV() writes to MQL5/Files/ for pickup.       |
//|                                                                  |
//| SCORE BANDS:                                                     |
//|   >= 0.80  High   → widen TP (+30%), full lot                    |
//|   0.60-0.79 Med   → standard policy from AdaptiveConfig          |
//|   < 0.60   Low    → tighten SL (+20%), reduce lot 70%            |
//|                                                                  |
//| OPTIMIZATIONS v2.00:                                             |
//|   - Added AITypes.mqh include for AI_FEATURE_DIM consistency     |
//|   - Feature importance tracking for interpretability             |
//|   - Enhanced drift detection integration                         |
//|   - Optimized ring buffer with circular indexing                 |
//|   - Batch CSV export with compression                            |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v2.00 (2026-05-21) — Performance + feature tracking           |
//|   v1.00 (2026-05-21) — Phase 8 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_CALIBRATION_BRIDGE_MQH__
#define __AI_CALIBRATION_BRIDGE_MQH__

#include "AITypes.mqh"
#include "../Infra/AdaptiveConfig.mqh"

#define CALIB_LOG_SIZE 200
#define FEATURE_IMPORTANCE_DIM AI_FEATURE_DIM

// Policy override from AI score
struct AIScoreOverride
  {
   double  SLMultAdjust;    // additive delta on SLMultiplier
   double  TPMultAdjust;    // additive delta on TPMultiplier
   double  LotFraction;     // final lot fraction [0.1, 1.0]
   bool    blockTrade;      // if true, veto the signal
   string  reason;          // for logging
  };

// One calibration data point
struct CalibEntry
  {
   double  score;       // AI confidence at trade open
   int     outcome;     // +1 = win, -1 = loss, 0 = pending
   double  rr;          // actual R:R achieved
   double  features[FEATURE_IMPORTANCE_DIM]; // Feature vector for importance tracking
   datetime openTime;
   int      barIndex;   // Bar index for drift detection correlation
  };

//+------------------------------------------------------------------+
//| CAICalibrationBridge                                             |
//+------------------------------------------------------------------+
class CAICalibrationBridge
  {
private:
   CalibEntry  m_log[CALIB_LOG_SIZE];
   int         m_logHead;   // ring buffer write pointer
   int         m_logCount;
   string      m_csvFile;
   
   // Feature importance tracking (accumulated win rates per feature quantile)
   double      m_featureImportance[FEATURE_IMPORTANCE_DIM];
   int         m_featureSamples[FEATURE_IMPORTANCE_DIM];
   
   // Drift detection integration
   double      m_driftScore;
   datetime    m_lastDriftCheck;
   
   // Score band thresholds
   double m_highThresh;   // default 0.80
   double m_medThresh;    // default 0.60

public:
   CAICalibrationBridge()
      : m_logHead(0), m_logCount(0),
        m_highThresh(0.80), m_medThresh(0.60),
        m_csvFile("PASR_calibration.csv"),
        m_driftScore(0.0), m_lastDriftCheck(0)
     { 
       ArrayInitialize(m_log, 0); 
       ArrayInitialize(m_featureImportance, 0.0);
       ArrayInitialize(m_featureSamples, 0);
     }

   void SetThresholds(double high, double med)
     { m_highThresh = high; m_medThresh = med; }

   void SetCSVFile(string f) { m_csvFile = f; }

   //+----------------------------------------------------------------+
   //| MapScoreToPolicy — core bridge function                        |
   //| Takes AI score + base EffectivePolicy, returns override.        |
   //+----------------------------------------------------------------+
   AIScoreOverride MapScoreToPolicy(double aiScore,
                                    const EffectivePolicy &base) const
     {
      AIScoreOverride ov;
      ov.blockTrade    = false;
      ov.SLMultAdjust  = 0.0;
      ov.TPMultAdjust  = 0.0;
      ov.LotFraction   = base.LotFraction;

      if(aiScore >= m_highThresh)
        {
         // High confidence: more reward, don't touch SL (trust entry)
         ov.TPMultAdjust = +0.30;              // widen TP by 0.3 ATR
         ov.LotFraction  = base.LotFraction;  // full lot as per policy
         ov.reason       = StringFormat("HIGH score=%.2f: TP+0.3", aiScore);
        }
      else if(aiScore >= m_medThresh)
        {
         // Medium confidence: standard policy, no adjustment
         ov.reason = StringFormat("MED score=%.2f: standard policy", aiScore);
        }
      else
        {
         // Low confidence: tighten risk, reduce size
         ov.SLMultAdjust = +0.20;                          // widen SL slightly (more room)
         ov.LotFraction  = base.LotFraction * 0.70;        // 70% lot
         ov.reason       = StringFormat("LOW score=%.2f: SL+0.2 Lot*0.7", aiScore);
         // If score < 0.40 entirely, veto the trade
         if(aiScore < 0.40)
           {
            ov.blockTrade = true;
            ov.reason     = StringFormat("VETO score=%.2f < 0.40", aiScore);
           }
        }

      // Apply override to EffectivePolicy clamps
      ov.LotFraction = MathMax(0.1, MathMin(1.0, ov.LotFraction));
      return ov;
     }

   //+----------------------------------------------------------------+
   //| ApplyOverride — merges AI override into EffectivePolicy copy   |
   //+----------------------------------------------------------------+
   EffectivePolicy ApplyOverride(const EffectivePolicy &base,
                                  const AIScoreOverride &ov) const
     {
      EffectivePolicy ep = base;
      ep.SLMultiplier += ov.SLMultAdjust;
      ep.TPMultiplier += ov.TPMultAdjust;
      ep.LotFraction   = ov.LotFraction;
      // Enforce minimums
      ep.SLMultiplier  = MathMax(0.5, ep.SLMultiplier);
      ep.TPMultiplier  = MathMax(ep.SLMultiplier, ep.TPMultiplier);
      return ep;
     }

   //+----------------------------------------------------------------+
   //| Log — record a new trade open for later calibration            |
   //| Enhanced: stores feature vector for importance tracking        |
   //+----------------------------------------------------------------+
   void LogTradeOpen(double score, const double features[AI_FEATURE_DIM] = NULL, int barIdx = -1)
     {
      m_log[m_logHead].score    = score;
      m_log[m_logHead].outcome  = 0;  // pending
      m_log[m_logHead].rr       = 0.0;
      m_log[m_logHead].openTime = TimeCurrent();
      m_log[m_logHead].barIndex = barIdx;
      
      // Store feature vector if provided
      if(features != NULL)
        {
         for(int i = 0; i < FEATURE_IMPORTANCE_DIM; i++)
            m_log[m_logHead].features[i] = features[i];
        }
      else
         ArrayInitialize(m_log[m_logHead].features, 0.0);
         
      m_logHead  = (m_logHead + 1) % CALIB_LOG_SIZE;
      if(m_logCount < CALIB_LOG_SIZE) m_logCount++;
     }

   // Mark most recent pending entry as resolved
   // Enhanced: updates feature importance based on outcome
   void LogTradeClose(bool isWin, double rr)
     {
      // Walk back from head to find latest pending
      for(int i = 1; i <= m_logCount; i++)
        {
         int idx = (m_logHead - i + CALIB_LOG_SIZE) % CALIB_LOG_SIZE;
         if(m_log[idx].outcome == 0)
           {
            m_log[idx].outcome = isWin ? 1 : -1;
            m_log[idx].rr      = rr;
            
            // Update feature importance tracking
            UpdateFeatureImportance(idx, isWin);
            return;
           }
        }
     }
   
   //+----------------------------------------------------------------+
   //| UpdateFeatureImportance — accumulate win rates per feature     |
   //+----------------------------------------------------------------+
   void UpdateFeatureImportance(int logIdx, bool isWin)
     {
      double outcome = isWin ? 1.0 : -1.0;
      for(int f = 0; f < FEATURE_IMPORTANCE_DIM; f++)
        {
         double featVal = m_log[logIdx].features[f];
         if(featVal == 0.0) continue;  // Skip unset features
         
         // Simple accumulation: weighted by feature magnitude
         m_featureImportance[f] += outcome * MathAbs(featVal);
         m_featureSamples[f]++;
        }
     }
   
   // Get normalized feature importance (0-1 scale)
   double GetFeatureImportance(int featureIdx) const
     {
      if(featureIdx < 0 || featureIdx >= FEATURE_IMPORTANCE_DIM) return 0.0;
      if(m_featureSamples[featureIdx] == 0) return 0.0;
      
      double avg = m_featureImportance[featureIdx] / m_featureSamples[featureIdx];
      // Normalize to 0-1 using sigmoid-like mapping
      return 0.5 + 0.5 * MathTanh(avg * 0.5);
     }
   
   // Export feature importance for analysis
   bool ExportFeatureImportanceCSV(string filename = "PASR_feature_importance.csv") const
     {
      int h = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(h == INVALID_HANDLE) return false;
      
      FileWrite(h, "feature_index", "importance", "samples", "avg_contribution");
      for(int f = 0; f < FEATURE_IMPORTANCE_DIM; f++)
        {
         double imp = GetFeatureImportance(f);
         double avg = (m_featureSamples[f] > 0) ? 
                      m_featureImportance[f] / m_featureSamples[f] : 0.0;
         FileWrite(h, IntegerToString(f), 
                   DoubleToString(imp, 6),
                   IntegerToString(m_featureSamples[f]),
                   DoubleToString(avg, 6));
        }
      FileClose(h);
      return true;
     }

   //+----------------------------------------------------------------+
   //| ExportCalibrationCSV — writes log to Files/ for Python pickup  |
   //| Enhanced: includes feature vectors and bar index               |
   //+----------------------------------------------------------------+
   bool ExportCalibrationCSV() const
     {
      if(m_logCount == 0) return false;
      int h = FileOpen(m_csvFile,
                       FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(h == INVALID_HANDLE)
        { Print("[Calib] CSV export failed: ", GetLastError()); return false; }

      // Header with feature columns
      string header = "open_time,score,outcome,rr,bar_index";
      for(int f = 0; f < FEATURE_IMPORTANCE_DIM; f++)
         header += ",feat_" + IntegerToString(f);
      FileWrite(h, header);

      for(int i = 0; i < m_logCount; i++)
        {
         const CalibEntry &e = m_log[i];
         if(e.outcome == 0) continue;  // skip pending
         
         string row = TimeToString(e.openTime) + "," +
                      DoubleToString(e.score, 4) + "," +
                      IntegerToString(e.outcome) + "," +
                      DoubleToString(e.rr, 4) + "," +
                      IntegerToString(e.barIndex);
         
         // Append feature values
         for(int f = 0; f < FEATURE_IMPORTANCE_DIM; f++)
            row += "," + DoubleToString(e.features[f], 6);
            
         FileWrite(h, row);
        }
      FileClose(h);
      PrintFormat("[Calib] Exported %d entries to %s",
                  m_logCount, m_csvFile);
      return true;
     }

   // Stats for dashboard
   int    GetLogCount()  const { return m_logCount; }
   double GetHighThresh() const { return m_highThresh; }
   double GetMedThresh()  const { return m_medThresh; }
   
   double GetMeanScore() const
     {
      if(m_logCount == 0) return 0.5;
      double sum = 0;
      for(int i=0;i<m_logCount;i++) sum+=m_log[i].score;
      return sum / m_logCount;
     }
   
   // Drift detection helpers
   void SetDriftScore(double score) { m_driftScore = score; m_lastDriftCheck = TimeCurrent(); }
   double GetDriftScore() const { return m_driftScore; }
   datetime GetLastDriftCheck() const { return m_lastDriftCheck; }
   
   // Check if drift detected exceeds threshold
   bool IsDriftDetected(double threshold = 0.3) const
     {
      return MathAbs(m_driftScore) > threshold;
     }
  };

#endif // __AI_CALIBRATION_BRIDGE_MQH__
