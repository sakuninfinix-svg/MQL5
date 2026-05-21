//+------------------------------------------------------------------+
//| AI/OnlineLearningGuard.mqh — v1.00                                |
//| Safety wrapper for online weight updates in live trading.        |
//|                                                                  |
//| PROBLEM:                                                         |
//|   Unrestricted online learning in live trading is dangerous:     |
//|   - Learning from a losing streak = learning wrong patterns      |
//|   - High LR during drawdown = model diverges rapidly             |
//|   - Too few samples = overfitting noise                          |
//|                                                                  |
//| GATES (all must pass for update to proceed):                     |
//|   1. DrawdownGate    : DD% < threshold (default 5%)              |
//|   2. LosingStreakGate: < 3 consec losses (3-5 = LR halved)       |
//|   3. MinSampleGate   : >= 20 labeled samples in buffer           |
//|   4. CooldownGate    : >= 10 trades since last update            |
//|                                                                  |
//| LR SCHEDULER:                                                    |
//|   Cosine annealing: LR = baseLR * 0.5*(1+cos(pi*step/maxStep))  |
//|   Resets every updateCycle trades.                               |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 8 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ONLINE_LEARNING_GUARD_MQH__
#define __AI_ONLINE_LEARNING_GUARD_MQH__

enum ENUM_BLOCK_REASON
  {
   BLOCK_NONE       = 0,
   BLOCK_DRAWDOWN   = 1,
   BLOCK_LOSING     = 2,
   BLOCK_MIN_SAMPLE = 3,
   BLOCK_COOLDOWN   = 4
  };

struct LearningStatus
  {
   bool               allowed;
   ENUM_BLOCK_REASON  reason;
   double             effectiveLR;
   int                sampleCount;
   int                tradesSinceUpdate;
  };

class COnlineLearningGuard
  {
private:
   // Config
   double m_maxDDPct;        // DrawdownGate threshold
   int    m_maxConsecLoss;   // LosingStreakGate hard block
   int    m_lrHalfLossCount; // streak count to halve LR
   int    m_minSamples;      // MinSampleGate
   int    m_cooldownTrades;  // CooldownGate
   double m_baseLR;          // base learning rate
   int    m_lrCycleLen;      // trades per cosine cycle

   // State
   int    m_sampleCount;
   int    m_consecLoss;
   int    m_tradesSinceUpdate;
   int    m_totalUpdateSteps;
   double m_currentDD;

public:
   COnlineLearningGuard()
      : m_maxDDPct(5.0), m_maxConsecLoss(5), m_lrHalfLossCount(3),
        m_minSamples(20), m_cooldownTrades(10), m_baseLR(0.001),
        m_lrCycleLen(50), m_sampleCount(0), m_consecLoss(0),
        m_tradesSinceUpdate(0), m_totalUpdateSteps(0), m_currentDD(0.0)
     {}

   // Config setters
   void SetMaxDD(double pct)         { m_maxDDPct        = pct;   }
   void SetMaxConsecLoss(int n)      { m_maxConsecLoss   = n;     }
   void SetMinSamples(int n)         { m_minSamples      = n;     }
   void SetCooldown(int trades)      { m_cooldownTrades  = trades;}
   void SetBaseLR(double lr)         { m_baseLR          = lr;    }
   void SetLRCycleLen(int n)         { m_lrCycleLen      = n;     }

   // Update state after each trade
   void RecordTrade(bool win, double drawdownPct)
     {
      m_currentDD = drawdownPct;
      m_tradesSinceUpdate++;
      m_sampleCount++;
      if(win)  m_consecLoss = 0;
      else     m_consecLoss++;
     }

   // Composite gate check — returns full status
   LearningStatus Check() const
     {
      LearningStatus s;
      s.sampleCount        = m_sampleCount;
      s.tradesSinceUpdate  = m_tradesSinceUpdate;
      s.effectiveLR        = ComputeLR();
      s.allowed            = true;
      s.reason             = BLOCK_NONE;

      // Gate 1: Drawdown
      if(m_currentDD >= m_maxDDPct)
        { s.allowed=false; s.reason=BLOCK_DRAWDOWN; return s; }

      // Gate 2: Losing streak (hard block at maxConsecLoss)
      if(m_consecLoss >= m_maxConsecLoss)
        { s.allowed=false; s.reason=BLOCK_LOSING; return s; }

      // Gate 3: Min samples
      if(m_sampleCount < m_minSamples)
        { s.allowed=false; s.reason=BLOCK_MIN_SAMPLE; return s; }

      // Gate 4: Cooldown
      if(m_tradesSinceUpdate < m_cooldownTrades)
        { s.allowed=false; s.reason=BLOCK_COOLDOWN; return s; }

      // Reduce LR if mild losing streak (3-5)
      if(m_consecLoss >= m_lrHalfLossCount)
         s.effectiveLR *= 0.5;

      return s;
     }

   // Call after a successful weight update
   void OnUpdateComplete()
     {
      m_tradesSinceUpdate = 0;
      m_totalUpdateSteps++;
     }

   // Cosine annealing LR
   double ComputeLR() const
     {
      int step = m_totalUpdateSteps % MathMax(1, m_lrCycleLen);
      double cosVal = MathCos(M_PI * step / m_lrCycleLen);
      return m_baseLR * 0.5 * (1.0 + cosVal);
     }

   void LogStatus() const
     {
      LearningStatus s = Check();
      PrintFormat("[OLGuard] allowed=%s reason=%d effectiveLR=%.6f "
                  "DD=%.1f%% consecLoss=%d samples=%d cooldown=%d/%d",
                  s.allowed?"YES":"NO", s.reason, s.effectiveLR,
                  m_currentDD, m_consecLoss, m_sampleCount,
                  m_tradesSinceUpdate, m_cooldownTrades);
     }

   // Accessors
   bool   IsLearningAllowed() const { return Check().allowed; }
   double GetEffectiveLR()    const { return Check().effectiveLR; }
   int    GetConsecLoss()     const { return m_consecLoss;       }
   double GetCurrentDD()      const { return m_currentDD;        }
  };

#endif // __AI_ONLINE_LEARNING_GUARD_MQH__
