//+------------------------------------------------------------------+
//| AI/AIFeatureBuilder.mqh — v4.00                                  |
//| Feature engineering: 18-dim normalised vector for AI inference.  |
//|                                                                  |
//| FEATURE MAP:                                                      |
//|  F01  ATR norm              — volatility magnitude [0,1]         |
//|  F02  Spread norm           — execution cost [0,1]               |
//|  F03  SL multiplier norm    — risk distance [0,1]                |
//|  F04  Time of day norm      — session quality [0,1]              |
//|  F05  Volume norm           — tick vol vs avg [0,1]              |
//|  F06  Momentum norm         — 14-bar price momentum [0,1]        |
//|  F07  Zone proximity norm   — distance to SR zone [0,1]          |
//|  F08  Loss streak norm      — inverted consec loss [0,1]         |
//|  F09  Noise norm            — session open proximity [0,1]       |
//|  F10  RSI norm              — overbought/oversold [0,1]          |
//|  F11  Candle body ratio     — body/range strength [0,1]          |
//|  F12  EMA distance norm     — price vs EMA20 [0,1]               |
//|  F13  Session norm          — session quality [0,1]              |
//|  F14  SR confluence score   — multi-zone weighted proximity[0,1] |
//|  F15  Candle structure code — pattern type encoded [0,1]         |
//|  F16  Vol profile proxy     — vol vs 50-bar avg [0,1]            |
//|  F17  HTF close position    — position in HTF bar range [0,1]    |
//|  F18  ADX trend strength    — trend vs range strength [0,1]      |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v4.00 (2026-05-21) — Phase 8: F14-F18, FeatureVector struct,   |
//|                         FeatureDrift detector                    |
//|   v3.01 (2026-05-21) — FIX volume clamp + momentum anchor       |
//|   v3.00 (2026-05-20) — regime + MTF confluence features          |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_FEATURE_BUILDER_MQH__
#define __AI_FEATURE_BUILDER_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"
#include "../Data/MarketRegime.mqh"

#define AI_FEATURE_DIM 18

// Named feature vector — maps directly to ONNX input tensor
struct FeatureVector
  {
   double f[AI_FEATURE_DIM];
   // Named accessors for readability
   double ATR()           const { return f[0];  }
   double Spread()        const { return f[1];  }
   double SLMult()        const { return f[2];  }
   double TimeOfDay()     const { return f[3];  }
   double Volume()        const { return f[4];  }
   double Momentum()      const { return f[5];  }
   double ZoneProx()      const { return f[6];  }
   double LossStreak()    const { return f[7];  }
   double Noise()         const { return f[8];  }
   double RSI()           const { return f[9];  }
   double CandleBody()    const { return f[10]; }
   double EMADist()       const { return f[11]; }
   double Session()       const { return f[12]; }
   double SRConfluence()  const { return f[13]; }
   double CandleCode()    const { return f[14]; }
   double VolProfile()    const { return f[15]; }
   double HTFPosition()   const { return f[16]; }
   double ADXStrength()   const { return f[17]; }

   void Clear() { ArrayInitialize(f, 0.5); }

   // Export to float array for ONNX input
   void ToFloatArray(float &out[]) const
     {
      ArrayResize(out, AI_FEATURE_DIM);
      for(int i = 0; i < AI_FEATURE_DIM; i++)
         out[i] = (float)f[i];
     }

   string ToString() const
     {
      return StringFormat(
         "ATR=%.2f Spd=%.2f SL=%.2f Tod=%.2f Vol=%.2f Mom=%.2f "
         "Zn=%.2f LS=%.2f Nz=%.2f RSI=%.2f Cb=%.2f EMA=%.2f "
         "Ses=%.2f SRC=%.2f CC=%.2f VP=%.2f HTF=%.2f ADX=%.2f",
         f[0],f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8],f[9],
         f[10],f[11],f[12],f[13],f[14],f[15],f[16],f[17]);
     }
  };

// Feature baseline stats (from backtest) for drift detection
struct FeatureStats
  {
   double mean[AI_FEATURE_DIM];
   double stddev[AI_FEATURE_DIM];
   int    sampleCount;
  };

//+------------------------------------------------------------------+
//| AIFeatureBuilder v4.00                                           |
//+------------------------------------------------------------------+
class AIFeatureBuilder
  {
private:
   BarCache            m_cache;
   MarketRegimeFilter *m_regime;
   DataManager        *m_data;
   datetime            m_lastUpdate;
   // Drift detection baseline
   FeatureStats        m_baseline;
   bool                m_hasBaseline;

   static ENUM_TIMEFRAMES HigherTF(ENUM_TIMEFRAMES tf)
     {
      switch(tf)
        {
         case PERIOD_M1:  return PERIOD_M5;
         case PERIOD_M5:  return PERIOD_M15;
         case PERIOD_M15: return PERIOD_M30;
         case PERIOD_M30: return PERIOD_H1;
         case PERIOD_H1:  return PERIOD_H4;
         case PERIOD_H4:  return PERIOD_D1;
         default:         return PERIOD_H1;
        }
     }

public:
   AIFeatureBuilder()
      : m_regime(NULL), m_data(NULL), m_lastUpdate(0), m_hasBaseline(false)
     { m_cache.Init(); }

   void SetRegime(MarketRegimeFilter *r) { m_regime = r; }
   void SetData(DataManager *d)          { m_data   = d; }

   void RefreshCache()
     {
      datetime barTime = iTime(_Symbol, _Period, 1);
      if(barTime == m_lastUpdate && m_cache.initialized) return;
      m_lastUpdate = barTime;
      if(CopyRates(_Symbol, _Period, 1, 14, m_cache.bars14) < 14) ArrayInitialize(m_cache.bars14, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 15, m_cache.bars15) < 15) ArrayInitialize(m_cache.bars15, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 20, m_cache.bars20) < 20) ArrayInitialize(m_cache.bars20, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 50, m_cache.bars50) < 50) ArrayInitialize(m_cache.bars50, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 1,  m_cache.bar1)   < 1)  ArrayInitialize(m_cache.bar1,   0.0);
      MqlRates tmp[1];
      if(CopyRates(_Symbol, _Period, 1, 1, tmp) == 1)
        { m_cache.current.open=tmp[0].open; m_cache.current.high=tmp[0].high;
          m_cache.current.low=tmp[0].low;   m_cache.current.close=tmp[0].close;
          m_cache.current.volume=tmp[0].tick_volume; m_cache.current.valid=true; }
      ENUM_TIMEFRAMES htf = HigherTF((ENUM_TIMEFRAMES)Period());
      if(CopyRates(_Symbol, htf, 1, 1, tmp) == 1)
        { m_cache.higher.open=tmp[0].open; m_cache.higher.high=tmp[0].high;
          m_cache.higher.low=tmp[0].low;   m_cache.higher.close=tmp[0].close;
          m_cache.higher.volume=tmp[0].tick_volume; m_cache.higher.valid=true; }
      m_cache.initialized = true;
     }

   //+----------------------------------------------------------------+
   //| Build full 18-dim FeatureVector                                |
   //+----------------------------------------------------------------+
   FeatureVector Build(const SignalDecision &signal,
                       double atrPoints,
                       double support,
                       double resistance,
                       const double &srZones[],
                       int    zoneCount) const
     {
      FeatureVector v;
      v.f[0]  = NormalizeATR(atrPoints);
      v.f[1]  = NormalizeSpread();
      v.f[2]  = NormalizeSL(signal.slMultiplier);
      v.f[3]  = NormalizeTimeOfDay();
      v.f[4]  = NormalizeVolume();
      v.f[5]  = NormalizeMomentum();
      v.f[6]  = NormalizeZone(signal.zonePrice, support, resistance);
      v.f[7]  = NormalizeLossStreak();
      v.f[8]  = NormalizeNoise();
      v.f[9]  = NormalizeRSI();
      v.f[10] = NormalizeCandleBody();
      v.f[11] = NormalizeEMADist();
      v.f[12] = NormalizeSession();
      // NEW Phase 8 features
      v.f[13] = NormalizeSRConfluence(signal.zonePrice, srZones, zoneCount);
      v.f[14] = NormalizeCandleStructure();
      v.f[15] = NormalizeVolProfile50();
      v.f[16] = NormalizeHTFClosePosition();
      v.f[17] = NormalizeADX();

      if(CheckPointer(m_regime) != POINTER_INVALID)
        {
         const RegimeResult &r = m_regime.GetResult();
         // Override F00 with regime-aware volatility score
         v.f[0] = MathMax(v.f[0], r.volatilityScore);
        }
      return v;
     }

   // Legacy EvalContext build for backward compatibility
   void Build(EvalContext &ctx, const SignalDecision &signal,
              double atrPoints, double support, double resistance) const
     {
      double zones[];
      ArrayResize(zones, 0);
      FeatureVector fv = Build(signal, atrPoints, support, resistance, zones, 0);
      ctx.atrNorm        = fv.f[0];  ctx.spreadNorm    = fv.f[1];
      ctx.slNorm         = fv.f[2];  ctx.timeOfDayNorm = fv.f[3];
      ctx.volumeNorm     = fv.f[4];  ctx.momentumNorm  = fv.f[5];
      ctx.zoneNorm       = fv.f[6];  ctx.lossStreakNorm = fv.f[7];
      ctx.noiseNorm      = fv.f[8];  ctx.rsiNorm       = fv.f[9];
      ctx.candleBodyRatio= fv.f[10]; ctx.emaDistNorm   = fv.f[11];
      ctx.sessionNorm    = fv.f[12];
      if(CheckPointer(m_regime) != POINTER_INVALID)
        { const RegimeResult &r = m_regime.GetResult();
          ctx.regimeScore = r.regimeScore; ctx.volatilityScore = r.volatilityScore;
          ctx.mtConfluenceNorm = r.mtfConfirmed?1.0:(double)r.tfAlignment/3.0; }
      else
        { ctx.regimeScore = NormalizeVolatilityFallback();
          ctx.volatilityScore = ctx.regimeScore;
          ctx.mtConfluenceNorm = NormalizeMTFFallback(signal); }
     }

   // ─── Existing normalizers (v3 — unchanged) ──────────────────────
   double NormalizeATR(double atrPoints) const
     { return (atrPoints<=0)?0.0:MathMin(1.0, atrPoints/20.0); }

   double NormalizeSpread() const
     { long sp=0; if(!SymbolInfoInteger(_Symbol,SYMBOL_SPREAD,sp)||sp<=0) return 1.0;
       return MathMax(0.0, 1.0-MathMin(1.0,(double)sp/10.0)); }

   double NormalizeSL(double slMult) const
     { return (slMult<=0)?0.0:MathMin(1.0, slMult/3.0); }

   double NormalizeZone(double zp, double s, double r) const
     { double dist=MathAbs(zp-(s+r)/2.0), rng=MathMax(1.0,MathAbs(r-s));
       return 1.0-MathMin(1.0,dist/rng); }

   double NormalizeTimeOfDay() const
     { MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); int h=dt.hour;
       if((h>=8&&h<=11)||(h>=13&&h<=16)) return 1.0;
       if(h>=7&&h<=19) return 0.7; return 0.3; }

   double NormalizeVolume() const
     { if(m_cache.current.valid&&m_cache.higher.valid)
         { long avg=(m_cache.current.volume+m_cache.higher.volume)/2;
           if(avg==0) return 0.5;
           return MathMax(0.0,MathMin(1.0,(double)m_cache.current.volume/avg)); }
       long vol[20]; if(CopyTickVolume(_Symbol,_Period,1,20,vol)<20) return 0.5;
       long sum=0; for(int i=0;i<20;i++) sum+=vol[i]; long avg=sum/20;
       return (avg==0)?0.5:MathMax(0.0,MathMin(1.0,(double)vol[0]/avg)); }

   double NormalizeMomentum() const
     { if(m_cache.initialized&&ArraySize(m_cache.bars14)>=14)
         { double momentum=m_cache.bars14[0].close-m_cache.bars14[13].close;
           double ref=m_cache.bars14[13].close, maxMove=0;
           for(int i=0;i<14;i++) maxMove=MathMax(maxMove,MathAbs(m_cache.bars14[i].close-ref));
           return (maxMove==0)?0.5:0.5+(momentum/maxMove)*0.5; }
       return 0.5; }

   double NormalizeNoise() const
     { MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
       return (dt.hour==8||dt.hour==13)?1.0:0.2; }

   double NormalizeLossStreak() const
     { if(CheckPointer(m_data)==POINTER_INVALID) return 0.0;
       return MathMax(0.0,1.0-MathMin(1.0,m_data.GetConsecutiveLosses()*0.1)); }

   double NormalizeRSI() const
     { if(m_cache.initialized&&ArraySize(m_cache.bars15)>=15)
         { double gains=0,losses=0;
           for(int i=0;i<14;i++){double d=m_cache.bars15[i].close-m_cache.bars15[i+1].close;
             if(d>0) gains+=d; else losses-=d;}
           double rs=(losses==0)?100.0:gains/losses;
           return (100.0-(100.0/(1.0+rs)))/100.0; }
       return 0.5; }

   double NormalizeCandleBody() const
     { if(m_cache.initialized&&ArraySize(m_cache.bar1)>=1)
         { double body=MathAbs(m_cache.bar1[0].close-m_cache.bar1[0].open);
           double rng=m_cache.bar1[0].high-m_cache.bar1[0].low;
           return (rng==0)?0.5:MathMin(1.0,body/rng); }
       return 0.5; }

   double NormalizeEMADist() const
     { if(m_cache.initialized&&ArraySize(m_cache.bars20)>=20)
         { double ema=m_cache.bars20[19].close,k=2.0/21.0;
           for(int i=18;i>=0;i--) ema=m_cache.bars20[i].close*k+ema*(1.0-k);
           double dist=MathAbs(m_cache.bars20[0].close-ema),atrEst=0;
           for(int i=0;i<20;i++) atrEst+=m_cache.bars20[i].high-m_cache.bars20[i].low;
           atrEst/=20.0;
           return (atrEst==0)?0.5:MathMin(1.0,dist/(atrEst*2.0)); }
       return 0.5; }

   double NormalizeSession() const
     { MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); int h=dt.hour;
       if(h>=13&&h<=21) return 1.0; if(h>=7&&h<=16) return 0.5; return 0.0; }

   double NormalizeVolatilityFallback() const
     { if(m_cache.initialized&&ArraySize(m_cache.bars20)>=20)
         { double avg=0; for(int i=0;i<20;i++) avg+=m_cache.bars20[i].close; avg/=20;
           double sumSq=0; for(int i=0;i<20;i++){double d=m_cache.bars20[i].close-avg;sumSq+=d*d;}
           return MathMin(1.0,MathSqrt(sumSq/20)/(SymbolInfoDouble(_Symbol,SYMBOL_POINT)*100)); }
       return 0.5; }

   double NormalizeMTFFallback(const SignalDecision &signal) const
     { ENUM_TIMEFRAMES htf=HigherTF((ENUM_TIMEFRAMES)Period()); MqlRates bars[10];
       if(CopyRates(_Symbol,htf,1,10,bars)>=10)
         { double hi=bars[0].high,lo=bars[0].low;
           for(int i=1;i<10;i++){hi=MathMax(hi,bars[i].high);lo=MathMin(lo,bars[i].low);}
           double rng=hi-lo; if(rng==0) return 0.5;
           double minDist=MathMin(MathAbs(bars[0].close-hi),MathAbs(bars[0].close-lo));
           return MathMax(0.3,1.0-MathMin(1.0,minDist/(rng*0.3))); }
       return 0.5; }

   // ─── NEW Phase 8 normalizers ──────────────────────────────────

   // F14: SR Confluence — weighted proximity to multiple SR zones
   // Zones closer to current price contribute more weight
   double NormalizeSRConfluence(double price,
                                 const double &zones[],
                                 int count) const
     {
      if(count <= 0) return 0.5;
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double atr   = (m_data!=NULL) ? m_data.GetATRPoints()*point : 0.001;
      double score = 0, totalWeight = 0;
      for(int i = 0; i < count && i < 16; i++)
        {
         double dist = MathAbs(price - zones[i]);
         double prox = MathMax(0.0, 1.0 - dist / (atr * 3.0));
         double w    = prox * prox;  // square: nearby zones weight more
         score       += prox * w;
         totalWeight += w;
        }
      return (totalWeight > 0) ? MathMin(1.0, score/totalWeight) : 0.5;
     }

   // F15: Candle structure encoding
   // 0=doji, 0.25=hammer/star, 0.5=inside bar, 0.75=outside bar, 1.0=engulf
   double NormalizeCandleStructure() const
     {
      if(!m_cache.initialized || ArraySize(m_cache.bar1)<1) return 0.5;
      double open  = m_cache.bar1[0].open,  close = m_cache.bar1[0].close;
      double high  = m_cache.bar1[0].high,  low   = m_cache.bar1[0].low;
      double body  = MathAbs(close - open);
      double range = high - low;
      if(range < SymbolInfoDouble(_Symbol, SYMBOL_POINT)) return 0.5;
      double bodyRatio = body / range;
      // Doji: body < 10% of range
      if(bodyRatio < 0.10) return 0.0;
      // Hammer/shooting star: body < 30%, one long wick
      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;
      if(bodyRatio < 0.30 && (upperWick > body*2 || lowerWick > body*2)) return 0.25;
      // Engulfing: compare with previous bar
      if(ArraySize(m_cache.bars15) >= 2)
        {
         double prevBody = MathAbs(m_cache.bars15[1].close - m_cache.bars15[1].open);
         if(body > prevBody * 1.5) return 1.0;  // engulf
        }
      // Inside bar check: fits inside previous bar range
      if(ArraySize(m_cache.bars15) >= 2)
        {
         if(high <= m_cache.bars15[1].high && low >= m_cache.bars15[1].low) return 0.5;
        }
      return 0.75;  // strong body candle
     }

   // F16: Volume profile proxy — current vol vs 50-bar average
   double NormalizeVolProfile50() const
     {
      if(!m_cache.initialized || ArraySize(m_cache.bars50) < 50) return 0.5;
      double sum = 0;
      for(int i = 0; i < 50; i++) sum += (double)m_cache.bars50[i].tick_volume;
      double avg = sum / 50.0;
      if(avg <= 0) return 0.5;
      double ratio = (double)m_cache.bars50[0].tick_volume / avg;
      return MathMax(0.0, MathMin(1.0, ratio / 2.0));  // 2x avg = full score
     }

   // F17: HTF close position — where did HTF bar close in its range?
   // 0 = bottom, 1 = top, 0.5 = middle
   double NormalizeHTFClosePosition() const
     {
      if(!m_cache.higher.valid) return 0.5;
      double rng = m_cache.higher.high - m_cache.higher.low;
      if(rng < SymbolInfoDouble(_Symbol, SYMBOL_POINT)) return 0.5;
      return MathMax(0.0, MathMin(1.0,
             (m_cache.higher.close - m_cache.higher.low) / rng));
     }

   // F18: ADX trend strength [0,1]
   // Manual Wilder ADX calculation over 14 bars
   double NormalizeADX() const
     {
      if(!m_cache.initialized || ArraySize(m_cache.bars14) < 14) return 0.5;
      double trSum=0, dmPlus=0, dmMinus=0;
      for(int i = 0; i < 13; i++)
        {
         double tr = MathMax(m_cache.bars14[i].high - m_cache.bars14[i].low,
                    MathMax(MathAbs(m_cache.bars14[i].high - m_cache.bars14[i+1].close),
                            MathAbs(m_cache.bars14[i].low  - m_cache.bars14[i+1].close)));
         double upMove   = m_cache.bars14[i].high - m_cache.bars14[i+1].high;
         double downMove = m_cache.bars14[i+1].low  - m_cache.bars14[i].low;
         trSum   += tr;
         dmPlus  += (upMove > downMove && upMove > 0) ? upMove   : 0;
         dmMinus += (downMove > upMove && downMove > 0) ? downMove : 0;
        }
      if(trSum <= 0) return 0.5;
      double diPlus  = (dmPlus  / trSum) * 100.0;
      double diMinus = (dmMinus / trSum) * 100.0;
      double diDiff  = MathAbs(diPlus - diMinus);
      double diSum   = diPlus + diMinus;
      double dx      = (diSum > 0) ? (diDiff / diSum) * 100.0 : 0;
      // ADX 0-25 = weak, 25-50 = moderate, 50+ = strong trend
      return MathMax(0.0, MathMin(1.0, dx / 50.0));
     }

   // ─── Feature Drift Detection ────────────────────────────────────
   void SetBaseline(const FeatureStats &stats) { m_baseline=stats; m_hasBaseline=true; }

   // Returns drift score [0,1] — > 0.3 = warning, > 0.6 = critical
   double ComputeDrift(const FeatureVector &live) const
     {
      if(!m_hasBaseline || m_baseline.sampleCount < 30) return 0.0;
      double maxDrift = 0;
      for(int i = 0; i < AI_FEATURE_DIM; i++)
        {
         if(m_baseline.stddev[i] <= 0) continue;
         double z = MathAbs(live.f[i] - m_baseline.mean[i]) / m_baseline.stddev[i];
         maxDrift = MathMax(maxDrift, MathMin(1.0, z / 3.0));  // 3-sigma = full drift
        }
      return maxDrift;
     }
  };

#endif // __AI_FEATURE_BUILDER_MQH__
