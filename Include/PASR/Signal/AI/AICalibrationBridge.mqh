//+------------------------------------------------------------------+
//| AI/AICalibrationBridge.mqh — v1.00                               |
//| Bridges AIInference output → AdaptiveConfig policy adjustments. |
//|                                                                  |
//| DESIGN:                                                          |
//|   AI confidence score [0,1] maps to dynamic policy overrides.   |
//|   High confidence expands TP and lot; low confidence             |
//|   tightens SL and reduces position size.                         |
//|                                                                  |
//|   CalibrationLog: ring buffer of 200 (score, outcome) pairs     |
//|   for offline Platt recalibration in Python pipeline.            |
//|   ExportCalibrationCSV() writes to MQL5/Files/ for pickup.       |
//|                                                                  |
//| SCORE BANDS:                                                     |
//|   >= 0.80  High   → widen TP (+20%), full lot                    |
//|   0.60-0.79 Med   → standard policy from AdaptiveConfig          |
//|   < 0.60   Low    → tighten SL (+10%), reduce lot 70%            |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 8 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_CALIBRATION_BRIDGE_MQH__
#define __AI_CALIBRATION_BRIDGE_MQH__

#include "../Infra/AdaptiveConfig.mqh"

#define CALIB_LOG_SIZE 200

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
   datetime openTime;
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

   // Score band thresholds
   double m_highThresh;   // default 0.80
   double m_medThresh;    // default 0.60

public:
   CAICalibrationBridge()
      : m_logHead(0), m_logCount(0),
        m_highThresh(0.80), m_medThresh(0.60),
        m_csvFile("PASR_calibration.csv")
     { ArrayInitialize(m_log, 0); }

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
   //+----------------------------------------------------------------+
   void LogTradeOpen(double score)
     {
      m_log[m_logHead].score    = score;
      m_log[m_logHead].outcome  = 0;  // pending
      m_log[m_logHead].rr       = 0.0;
      m_log[m_logHead].openTime = TimeCurrent();
      m_logHead  = (m_logHead + 1) % CALIB_LOG_SIZE;
      if(m_logCount < CALIB_LOG_SIZE) m_logCount++;
     }

   // Mark most recent pending entry as resolved
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
            return;
           }
        }
     }

   //+----------------------------------------------------------------+
   //| ExportCalibrationCSV — writes log to Files/ for Python pickup  |
   //+----------------------------------------------------------------+
   bool ExportCalibrationCSV() const
     {
      if(m_logCount == 0) return false;
      int h = FileOpen(m_csvFile,
                       FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(h == INVALID_HANDLE)
        { Print("[Calib] CSV export failed: ", GetLastError()); return false; }

      // Header
      FileWrite(h, "open_time", "score", "outcome", "rr");

      for(int i = 0; i < m_logCount; i++)
        {
         const CalibEntry &e = m_log[i];
         if(e.outcome == 0) continue;  // skip pending
         FileWrite(h,
                   TimeToString(e.openTime),
                   DoubleToString(e.score, 4),
                   IntegerToString(e.outcome),
                   DoubleToString(e.rr, 4));
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
  };

#endif // __AI_CALIBRATION_BRIDGE_MQH__
