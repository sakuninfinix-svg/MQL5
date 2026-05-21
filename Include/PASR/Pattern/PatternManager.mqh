//+------------------------------------------------------------------+
//| Pattern/PatternManager.mqh — v2.00                               |
//| Full Price-Action pattern detection engine.                      |
//| Replaces stub — implements: Pin Bar, Engulfing, Inside Bar,      |
//| Outside Bar, Morning/Evening Star, Tweezer, Fakey, 2B Reversal.  |
//+------------------------------------------------------------------+
#property strict
#ifndef __PATTERN_PATTERN_MANAGER_MQH__
#define __PATTERN_PATTERN_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "CandleUtils.mqh"

// Pattern type enum
enum ENUM_PA_PATTERN
  {
   PATTERN_NONE         = 0,
   PATTERN_PIN_BULL     = 1,
   PATTERN_PIN_BEAR     = 2,
   PATTERN_ENGULF_BULL  = 3,
   PATTERN_ENGULF_BEAR  = 4,
   PATTERN_INSIDE_BULL  = 5,
   PATTERN_INSIDE_BEAR  = 6,
   PATTERN_OUTSIDE_BULL = 7,
   PATTERN_OUTSIDE_BEAR = 8,
   PATTERN_MORN_STAR    = 9,
   PATTERN_EVE_STAR     = 10,
   PATTERN_TWEEZER_BULL = 11,
   PATTERN_TWEEZER_BEAR = 12,
   PATTERN_FAKEY_BULL   = 13,
   PATTERN_FAKEY_BEAR   = 14,
   PATTERN_2B_BULL      = 15,
   PATTERN_2B_BEAR      = 16
  };

// Detected pattern result
struct PatternResult
  {
   ENUM_PA_PATTERN pattern;
   double          confidence; // 0.0-1.0
   int             direction;  // +1 bull, -1 bear, 0 neutral
   datetime        time;
   string          name;

   void Clear() { pattern=PATTERN_NONE; confidence=0; direction=0; time=0; name=""; }
  };

//+------------------------------------------------------------------+
//| CPatternManager — full PA pattern detection                      |
//+------------------------------------------------------------------+
class CPatternManager : public IManager
  {
private:
   PatternResult  m_lastPattern;
   double         m_minBodyRatio;   // minimum body/range for engulf etc
   double         m_wickRatio;      // minimum wick ratio for pin bar
   int            m_lookback;       // bars to scan on new bar
   bool           m_patternReady;

   // ── Detection helpers ──────────────────────────────────────────

   bool DetectPinBar(const CandleData &c, PatternResult &out)
     {
      if(!c.IsHammer() && !c.IsShootingStar()) return false;
      if(c.IsHammer())
        {
         out.pattern    = PATTERN_PIN_BULL;
         out.direction  = 1;
         out.confidence = MathMin(1.0, c.lowerWick / (c.range * 0.7));
         out.name       = "PinBar_Bull";
        }
      else
        {
         out.pattern    = PATTERN_PIN_BEAR;
         out.direction  = -1;
         out.confidence = MathMin(1.0, c.upperWick / (c.range * 0.7));
         out.name       = "PinBar_Bear";
        }
      out.time = c.time;
      return (out.confidence >= 0.5);
     }

   bool DetectEngulfing(const CandleData &c, const CandleData &prev, PatternResult &out)
     {
      if(!c.Engulfs(prev)) return false;
      if(!c.IsLargeBody()) return false;
      double prevBody = prev.range > 0 ? prev.body / prev.range : 0;
      if(prevBody < 0.3) return false; // prev must have some body

      double engulfRatio = (c.range > 0) ? prev.body / c.body : 0;
      out.confidence = MathMin(1.0, 0.5 + (1.0 - engulfRatio) * 0.5);
      out.time       = c.time;

      if(c.IsBullish())
        { out.pattern=PATTERN_ENGULF_BULL; out.direction=1;  out.name="Engulf_Bull"; }
      else
        { out.pattern=PATTERN_ENGULF_BEAR; out.direction=-1; out.name="Engulf_Bear"; }
      return (out.confidence >= 0.5);
     }

   bool DetectInsideBar(const CandleData &c, const CandleData &mother, PatternResult &out)
     {
      // Inside bar: c is contained within mother
      if(c.high >= mother.high || c.low <= mother.low) return false;
      // Bias from where inside bar closes within mother range
      double pos = mother.range > 0 ? (c.close - mother.low) / mother.range : 0.5;
      out.time       = c.time;
      out.confidence = 0.6;
      if(pos >= 0.5)
        { out.pattern=PATTERN_INSIDE_BULL; out.direction=1;  out.name="InsideBar_Bull"; }
      else
        { out.pattern=PATTERN_INSIDE_BEAR; out.direction=-1; out.name="InsideBar_Bear"; }
      return true;
     }

   bool DetectOutsideBar(const CandleData &c, const CandleData &prev, PatternResult &out)
     {
      // Outside bar: c engulfs prev (higher high AND lower low)
      if(c.high <= prev.high || c.low >= prev.low) return false;
      double pos = c.range > 0 ? (c.close - c.low) / c.range : 0.5;
      out.time       = c.time;
      out.confidence = 0.65;
      if(pos >= 0.5)
        { out.pattern=PATTERN_OUTSIDE_BULL; out.direction=1;  out.name="OutsideBar_Bull"; }
      else
        { out.pattern=PATTERN_OUTSIDE_BEAR; out.direction=-1; out.name="OutsideBar_Bear"; }
      return true;
     }

   bool DetectMornEveStar(const CandleData &c0, const CandleData &c1, const CandleData &c2,
                           PatternResult &out)
     {
      // Morning Star: c2=bear large, c1=doji/small, c0=bull large closing > c2 midpoint
      double c2mid = (c2.open + c2.close) / 2.0;
      if(c2.IsBearish() && c2.IsLargeBody() && c1.IsDoji() &&
         c0.IsBullish() && c0.IsLargeBody() && c0.close > c2mid)
        {
         out.pattern=PATTERN_MORN_STAR; out.direction=1;
         out.confidence=0.80; out.name="MorningStar"; out.time=c0.time;
         return true;
        }
      // Evening Star: reverse
      double c2mid2 = (c2.open + c2.close) / 2.0;
      if(c2.IsBullish() && c2.IsLargeBody() && c1.IsDoji() &&
         c0.IsBearish() && c0.IsLargeBody() && c0.close < c2mid2)
        {
         out.pattern=PATTERN_EVE_STAR; out.direction=-1;
         out.confidence=0.80; out.name="EveningStar"; out.time=c0.time;
         return true;
        }
      return false;
     }

   bool DetectTweezer(const CandleData &c, const CandleData &prev, PatternResult &out)
     {
      double tolerance = _Point * 5;
      // Tweezer Top: both bearish, similar highs
      if(c.IsBearish() && prev.IsBullish() &&
         MathAbs(c.high - prev.high) <= tolerance)
        {
         out.pattern=PATTERN_TWEEZER_BEAR; out.direction=-1;
         out.confidence=0.70; out.name="TweezerTop"; out.time=c.time;
         return true;
        }
      // Tweezer Bottom: both bullish after bear, similar lows
      if(c.IsBullish() && prev.IsBearish() &&
         MathAbs(c.low - prev.low) <= tolerance)
        {
         out.pattern=PATTERN_TWEEZER_BULL; out.direction=1;
         out.confidence=0.70; out.name="TweezerBottom"; out.time=c.time;
         return true;
        }
      return false;
     }

   bool DetectFakey(const CandleData &c, const CandleData &prev,
                    const CandleData &mother, PatternResult &out)
     {
      // Fakey = Inside Bar followed by false breakout that reverses
      // prev must be inside mother; c must break out then reverse back
      if(prev.high >= mother.high || prev.low <= mother.low) return false;
      bool bullFakey = (prev.low < mother.low && c.close > mother.low && c.close < mother.high);
      bool bearFakey = (prev.high > mother.high && c.close < mother.high && c.close > mother.low);
      if(bullFakey)
        { out.pattern=PATTERN_FAKEY_BULL; out.direction=1;  out.confidence=0.75;
          out.name="Fakey_Bull"; out.time=c.time; return true; }
      if(bearFakey)
        { out.pattern=PATTERN_FAKEY_BEAR; out.direction=-1; out.confidence=0.75;
          out.name="Fakey_Bear"; out.time=c.time; return true; }
      return false;
     }

   bool Detect2B(const CandleData &c, const CandleData &prev, PatternResult &out)
     {
      // 2B Reversal: new high/low followed by immediate close back inside range
      double atrEst = m_data.GetATRPoints() * _Point;
      if(atrEst <= 0) return false;
      // Bearish 2B: c makes new high vs prev but closes below prev high
      if(c.high > prev.high && c.close < prev.high && (c.high - prev.high) < atrEst * 0.5)
        { out.pattern=PATTERN_2B_BEAR; out.direction=-1; out.confidence=0.72;
          out.name="2B_Bear"; out.time=c.time; return true; }
      // Bullish 2B: c makes new low vs prev but closes above prev low
      if(c.low < prev.low && c.close > prev.low && (prev.low - c.low) < atrEst * 0.5)
        { out.pattern=PATTERN_2B_BULL; out.direction=1; out.confidence=0.72;
          out.name="2B_Bull"; out.time=c.time; return true; }
      return false;
     }

public:
   CPatternManager()
      : IManager(), m_minBodyRatio(0.3), m_wickRatio(0.6),
        m_lookback(3), m_patternReady(false)
     { m_lastPattern.Clear(); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnNewBar() override
     {
      m_patternReady = false;
      m_lastPattern.Clear();

      CandleData c[4];
      for(int i=0;i<4;i++) c[i].Load(i+1);

      PatternResult res;
      res.Clear();

      // Priority: 3-candle patterns first, then 2-candle, then 1-candle
      if(DetectMornEveStar(c[0],c[1],c[2], res)) { m_lastPattern=res; m_patternReady=true; return; }
      if(DetectFakey(c[0],c[1],c[2],        res)) { m_lastPattern=res; m_patternReady=true; return; }
      if(DetectEngulfing(c[0],c[1],          res)) { m_lastPattern=res; m_patternReady=true; return; }
      if(DetectOutsideBar(c[0],c[1],         res)) { m_lastPattern=res; m_patternReady=true; return; }
      if(DetectInsideBar(c[0],c[1],          res)) { m_lastPattern=res; m_patternReady=true; return; }
      if(DetectTweezer(c[0],c[1],            res)) { m_lastPattern=res; m_patternReady=true; return; }
      if(Detect2B(c[0],c[1],                 res)) { m_lastPattern=res; m_patternReady=true; return; }
      if(DetectPinBar(c[0],                  res)) { m_lastPattern=res; m_patternReady=true; return; }

      if(m_debugMode) Print("[Pattern] No pattern on ", TimeToString(iTime(_Symbol,PERIOD_CURRENT,1)));
     }

   PatternResult  GetLastPattern()   const { return m_lastPattern; }
   bool           HasPattern()        const { return m_patternReady; }
   int            GetPatternDir()     const { return m_lastPattern.direction; }
   double         GetConfidence()     const { return m_lastPattern.confidence; }

   void SetMinBodyRatio(double v) { m_minBodyRatio = MathMax(0.1, MathMin(0.9, v)); }
   void SetWickRatio(double v)    { m_wickRatio    = MathMax(0.1, MathMin(0.9, v)); }
  };

typedef CPatternManager PatternManager;
#endif
