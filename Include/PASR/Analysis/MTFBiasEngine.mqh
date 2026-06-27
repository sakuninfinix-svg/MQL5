//+------------------------------------------------------------------+
//| Analysis/MTFBiasEngine.mqh — v1.10 (Price Action pure)           |
//| Cross-timeframe bias via higher-high/lower-low sequence + body    |
//| persistence. No EMA/MACD/RSI. Strength gate uses ATR ratio.       |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_MTF_BIAS_ENGINE_MQH__
#define __ANALYSIS_MTF_BIAS_ENGINE_MQH__

// ponytail: structure chosen so PASR keeps its price-action foundation
// (see PASR docs Artificial_Inteligent_Development.md). EMA path was
// deleted because user's original EA used only price action + ATR + SR.
// Upgrade fallbacks when adding MR / divergence library.

struct SMTFBiasConfig
  {
   bool              enabled;
   ENUM_TIMEFRAMES   htfPeriod;
   ENUM_TIMEFRAMES   midPeriod;
   int               sequenceBars;       // bars used for HH/LL scan
   int               bodyBars;           // bars used for body persistence
   int               atrPeriod;          // ATR handle period (HTF)
   double            atrStrengthMin;     // min avg body/ATR ratio
   double            vetoConfidence;     // min confidence to veto counter-trade
   bool              logOnly;            // if true, never veto, just print
  };

struct SMTFBiasSnapshot
  {
   bool              valid;
   datetime          lastBar;
   int               htfSequenceScore;   // +N ups, -N dns
   int               htfSequenceLegs;    // bars scanned
   double            htfBodyPersistence; // -1..1
   double            htfAtrStrength;     // avg body/atr
   double            htfBias;            // -1..1 (composite HTF)
   int               midSequenceScore;
   int               midSequenceLegs;
   double            midBodyPersistence;
   double            midAtrStrength;
   double            midBias;
   double            compositeBias;      // 0.6*htf + 0.4*mid
   ENUM_SIGNAL_DIR   verdict;
   bool              blockBuys;
   bool              blockSells;
   string            reason;
  };

class CMTFBiasEngine
  {
private:
   SMTFBiasConfig    m_cfg;
   SMTFBiasSnapshot  m_snap;
   int               m_hHTFAtr;
   int               m_hMidAtr;
   datetime          m_lastRefresh;

   double BufAt(int handle, int buffer, int shift) const
     {
      if(handle == INVALID_HANDLE) return 0.0;
      double buf[1];
      if(CopyBuffer(handle, buffer, shift, 1, buf) <= 0) return 0.0;
      return buf[0];
     }

   bool TFValid(ENUM_TIMEFRAMES tf) const
     {
      return (iBars(_Symbol, tf) > 0 && iClose(_Symbol, tf, 0) > 0.0);
     }

   double Clamp(double v, double lo, double hi) const
     {
      return MathMax(lo, MathMin(hi, v));
     }

   // higher-high + higher-low scan over `legs` bars
   // returns int: +N = bullish HH/HL pairs detected, -N = bearish LH/LL pairs
   int SequenceScore(ENUM_TIMEFRAMES tf, int legs) const
     {
      int bars = iBars(_Symbol, tf);
      if(legs < 2 || bars < legs + 1) return 0;
      int up = 0;
      int dn = 0;
      // bars[shift] is newer than bars[shift+1]; loop from oldest pair up
      for(int i = legs; i >= 1; i--)
        {
         double h0 = iHigh(_Symbol, tf, i);
         double l0 = iLow (_Symbol, tf, i);
         double h1 = iHigh(_Symbol, tf, i - 1);
         double l1 = iLow (_Symbol, tf, i - 1);
         if(h0 <= 0.0 || l0 <= 0.0 || h1 <= 0.0 || l1 <= 0.0) continue;
         bool hh = h0 > h1;
         bool hl = l0 > l1;
         bool lh = h0 < h1;
         bool ll = l0 < l1;
         // bullish sequence: higher-high AND higher-low
         if(hh && hl) up++;
         // bearish sequence: lower-high AND lower-low
         if(lh && ll) dn++;
        }
      return up - dn;
     }

   // -1..1 derived from int score in [-legs..+legs]
   double NormalizeSequence(int score, int legs) const
     {
      if(legs <= 0) return 0.0;
      return Clamp((double)score / (double)legs, -1.0, 1.0);
     }

   // body persistence: (closes-up - closes-down) over `count` bars / count
   double BodyPersistence(ENUM_TIMEFRAMES tf, int count) const
     {
      if(count <= 0) return 0.0;
      int up = 0, dn = 0;
      for(int i = 0; i < count; i++)
        {
         double close = iClose(_Symbol, tf, i);
         double prev  = iClose(_Symbol, tf, i + 1);
         if(close <= 0.0 || prev <= 0.0) continue;
         if(close > prev) up++;
         else if(close < prev) dn++;
        }
      if(up + dn == 0) return 0.0;
      return (double)(up - dn) / (double)(up + dn);
     }

   // avg body/ATR ratio in [0..1+] (clamped 1.0 for snapshot only)
   double ATrStrength(int handle, ENUM_TIMEFRAMES tf, int count) const
     {
      if(handle == INVALID_HANDLE || count <= 0) return 0.0;
      double sumRatio = 0.0;
      int    valid = 0;
      for(int i = 0; i < count; i++)
        {
         double atr  = BufAt(handle, 0, i);
         double open  = iOpen (_Symbol, tf, i);
         double close = iClose(_Symbol, tf, i);
         if(atr <= 0.0 || open <= 0.0 || close <= 0.0) continue;
         double body = MathAbs(close - open);
         sumRatio += body / atr;
         valid++;
        }
      if(valid == 0) return 0.0;
      return sumRatio / (double)valid;
     }

   ENUM_TIMEFRAMES HTF() const { return m_cfg.htfPeriod; }
   ENUM_TIMEFRAMES MID() const { return m_cfg.midPeriod; }

   double TFCompositeBias(int seqScore, int legs, double body, double atrStr) const
     {
      double seqNorm = NormalizeSequence(seqScore, legs);
      double bodyN  = Clamp(body, -1.0, 1.0);
      double composite = seqNorm * 0.6 + bodyN * 0.4;
      return Clamp(composite, -1.0, 1.0);
     }

public:
   CMTFBiasEngine()
      : m_hHTFAtr(INVALID_HANDLE),
        m_hMidAtr(INVALID_HANDLE),
        m_lastRefresh(0)
     {
      m_cfg.htfPeriod       = PERIOD_H4;
      m_cfg.midPeriod       = PERIOD_H1;
      m_cfg.sequenceBars    = 3;
      m_cfg.bodyBars        = 3;
      m_cfg.atrPeriod       = 14;
      m_cfg.atrStrengthMin  = 0.20;
      m_cfg.vetoConfidence  = 0.40;
      m_cfg.logOnly         = false;
      m_cfg.enabled         = true;
      ResetSnap();
     }

   ~CMTFBiasEngine()
     {
      ReleaseHandles();
     }

   void ReleaseHandles()
     {
      if(m_hHTFAtr != INVALID_HANDLE) { IndicatorRelease(m_hHTFAtr); m_hHTFAtr = INVALID_HANDLE; }
      if(m_hMidAtr != INVALID_HANDLE) { IndicatorRelease(m_hMidAtr); m_hMidAtr = INVALID_HANDLE; }
     }

   void ResetSnap()
     {
      m_snap.valid             = false;
      m_snap.lastBar           = 0;
      m_snap.htfSequenceScore  = 0;
      m_snap.htfSequenceLegs   = 0;
      m_snap.htfBodyPersistence= 0.0;
      m_snap.htfAtrStrength    = 0.0;
      m_snap.htfBias           = 0.0;
      m_snap.midSequenceScore  = 0;
      m_snap.midSequenceLegs   = 0;
      m_snap.midBodyPersistence= 0.0;
      m_snap.midAtrStrength    = 0.0;
      m_snap.midBias           = 0.0;
      m_snap.compositeBias     = 0.0;
      m_snap.verdict           = SIGNAL_NONE;
      m_snap.blockBuys         = false;
      m_snap.blockSells        = false;
      m_snap.reason            = "";
     }

   bool Init(const SMTFBiasConfig &cfg)
     {
      ResetSnap();
      m_cfg = cfg;
      ReleaseHandles();
      if(!m_cfg.enabled) { m_snap.valid = false; return true; }

      int need = MathMax(m_cfg.sequenceBars, m_cfg.bodyBars) + 2;
      if(!TFValid(m_cfg.htfPeriod) || iBars(_Symbol, m_cfg.htfPeriod) < need ||
         !TFValid(m_cfg.midPeriod) || iBars(_Symbol, m_cfg.midPeriod) < need)
        {
         PrintFormat("[MTFBias] Not enough bars for %s (htf/mid). Disabling.", _Symbol);
         m_cfg.enabled = false;
         return false;
        }
      m_hHTFAtr = iATR(_Symbol, m_cfg.htfPeriod, m_cfg.atrPeriod);
      m_hMidAtr = iATR(_Symbol, m_cfg.midPeriod, m_cfg.atrPeriod);
      if(m_hHTFAtr == INVALID_HANDLE || m_hMidAtr == INVALID_HANDLE)
        {
         PrintFormat("[MTFBias] ATR handle init failed (htf=%d mid=%d). Disabling.",
                     m_hHTFAtr, m_hMidAtr);
         ReleaseHandles();
         m_cfg.enabled = false;
         return false;
        }
      return true;
     }

   // Lightweight refresh: only recompute on new bar of HTF bar index 0
   bool Refresh()
     {
      if(!m_cfg.enabled) { m_snap.valid = false; return false; }
      datetime htfBar = iTime(_Symbol, m_cfg.htfPeriod, 0);
      if(htfBar == 0) return false;
      if(htfBar == m_lastRefresh && m_snap.valid) return true;
      m_lastRefresh = htfBar;

      int legs = MathMax(2, m_cfg.sequenceBars);
      int body = MathMax(2, m_cfg.bodyBars);

      // HTF sequence + body + atr strength
      m_snap.htfSequenceScore = SequenceScore(m_cfg.htfPeriod, legs);
      m_snap.htfSequenceLegs  = legs;
      m_snap.htfBodyPersistence = BodyPersistence(m_cfg.htfPeriod, body);
      m_snap.htfAtrStrength   = ATrStrength(m_hHTFAtr, m_cfg.htfPeriod, body);
      m_snap.htfBias = TFCompositeBias(m_snap.htfSequenceScore, legs,
                                       m_snap.htfBodyPersistence,
                                       m_snap.htfAtrStrength);

      // Mid same logic
      m_snap.midSequenceScore = SequenceScore(m_cfg.midPeriod, legs);
      m_snap.midSequenceLegs  = legs;
      m_snap.midBodyPersistence = BodyPersistence(m_cfg.midPeriod, body);
      m_snap.midAtrStrength   = ATrStrength(m_hMidAtr, m_cfg.midPeriod, body);
      m_snap.midBias = TFCompositeBias(m_snap.midSequenceScore, legs,
                                       m_snap.midBodyPersistence,
                                       m_snap.midAtrStrength);

      // Composite HTF/Mid
      m_snap.compositeBias = Clamp(m_snap.htfBias * 0.6 + m_snap.midBias * 0.4, -1.0, 1.0);
      m_snap.lastBar = htfBar;

      bool strengthOk = (m_snap.htfAtrStrength >= m_cfg.atrStrengthMin);
      m_snap.blockBuys  = (!strengthOk) ? false : (m_snap.compositeBias < -0.20);
      m_snap.blockSells = (!strengthOk) ? false : (m_snap.compositeBias >  0.20);
      m_snap.verdict = (m_snap.compositeBias >  0.15) ? SIGNAL_BUY :
                       (m_snap.compositeBias < -0.15) ? SIGNAL_SELL :
                       SIGNAL_NONE;
      m_snap.reason = StringFormat("htfSeq=%+d/%d htfBody=%.2f htfAtr=%.2f | midSeq=%+d/%d midBody=%.2f | comp=%.2f %s",
                                   m_snap.htfSequenceScore, m_snap.htfSequenceLegs,
                                   m_snap.htfBodyPersistence, m_snap.htfAtrStrength,
                                   m_snap.midSequenceScore, m_snap.midSequenceLegs,
                                   m_snap.midBodyPersistence,
                                   m_snap.compositeBias,
                                   strengthOk ? "STR" : "CHOP");
      m_snap.valid = true;
      return true;
     }

   bool ShouldVeto(ENUM_SIGNAL_DIR dir) const
     {
      if(!m_cfg.enabled || !m_snap.valid || m_cfg.logOnly) return false;
      if(MathAbs(m_snap.compositeBias) < 0.20) return false;
      if(dir == SIGNAL_BUY  && m_snap.blockBuys)  return true;
      if(dir == SIGNAL_SELL && m_snap.blockSells) return true;
      return false;
     }

   SMTFBiasSnapshot GetSnapshot() const { return m_snap; }
   SMTFBiasConfig   GetConfig()   const { return m_cfg; }
   bool             IsReady()     const { return m_cfg.enabled && m_snap.valid; }
  };

#endif // __ANALYSIS_MTF_BIAS_ENGINE_MQH__
