//+------------------------------------------------------------------+
//| AI/AIFeatureBuilder.mqh — v4.01-p1-features                      |
//| Feature engineering: 26-dim normalised vector for AI inference.  |
//|                                                                  |
//| FEATURE MAP (F01–F18 unchanged from v4.00):                      |
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
//| NEW FEATURES v4.01 (Priority-1 feature engineering):             |
//|  F19  SR Proximity Bull     — (price-support)/ATR [0,1]          |
//|  F20  SR Proximity Bear     — (resistance-price)/ATR [0,1]       |
//|  F21  Upper Wick Ratio      — rejection wick/range [0,1]         |
//|  F22  Lower Wick Ratio      — support wick/range [0,1]           |
//|  F23  Hour Sin              — cyclical hour sin→[0,1]            |
//|  F24  Hour Cos              — cyclical hour cos→[0,1]            |
//|  F25  HTF Trend H4          — H4 EMA-20 alignment [0,1]          |
//|  F26  ATR Percentile Rank   — ATR rank vs 60-bar hist [0,1]      |
//|                                                                  |
//| FEATURE HYGIENE RULES:                                           |
//|  1. ALL features computed from bar[1+] (no lookahead)            |
//|  2. All outputs in [0,1] — ONNX input tensor expects float[26]   |
//|  3. Run feature importance audit every 200 trades                |
//|  4. Sin/Cos encoding for hour: avoids 23→0 discontinuity         |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v4.01 (2026-05-21) — Priority-1 feature engineering            |
//|                         F19-F26 added, BarCache expanded,        |
//|                         FeatureVector 18→26 dims                 |
//|   v4.00 (2026-05-21) — Phase 8: F14-F18, drift detector          |
//|   v3.01 (2026-05-21) — FIX volume clamp + momentum anchor        |
//|   v3.00 (2026-05-20) — regime + MTF confluence features          |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_FEATURE_BUILDER_MQH__
#define __AI_FEATURE_BUILDER_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"

// Confirm dim matches AITypes.mqh
#ifndef AI_FEATURE_DIM
  #define AI_FEATURE_DIM 26
#endif

// Named feature vector — maps directly to ONNX input tensor
// All values in [0,1] after normalization
struct FeatureVector
  {
   double f[AI_FEATURE_DIM];

   //--- Named accessors (F01–F18, unchanged)
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
   //--- Named accessors (F19–F26, v4.01 Priority-1)
   double SRProxBull()    const { return f[18]; }  // F19
   double SRProxBear()    const { return f[19]; }  // F20
   double UpperWick()     const { return f[20]; }  // F21
   double LowerWick()     const { return f[21]; }  // F22
   double HourSin()       const { return f[22]; }  // F23
   double HourCos()       const { return f[23]; }  // F24
   double HTFTrendH4()    const { return f[24]; }  // F25
   double ATRPercentile() const { return f[25]; }  // F26

   void Clear() { ArrayInitialize(f, 0.5); }

   // Export to float array for ONNX input
   void ToFloatArray(float &out[]) const
     {
      ArrayResize(out, AI_FEATURE_DIM);
      for(int i = 0; i < AI_FEATURE_DIM; i++)
         out[i] = (float)f[i];
     }

   // First 12 dims → NN_INPUTS for linear model / small NN
   void ToNNInputs(double &out[]) const
     {
      ArrayResize(out, NN_INPUTS);
      // Map: ATR, Spread, SLMult, Volume, Momentum, SRConfl,
      //      ADX, SRProxBull, SRProxBear, HourSin, HTFTrendH4, ATRPercentile
      out[0]  = f[0];   // ATR
      out[1]  = f[1];   // Spread
      out[2]  = f[2];   // SL mult
      out[3]  = f[4];   // Volume
      out[4]  = f[5];   // Momentum
      out[5]  = f[13];  // SR confluence
      out[6]  = f[17];  // ADX
      out[7]  = f[18];  // SR prox bull  [v4.01]
      out[8]  = f[19];  // SR prox bear  [v4.01]
      out[9]  = f[22];  // Hour sin      [v4.01]
      out[10] = f[24];  // HTF trend H4  [v4.01]
      out[11] = f[25];  // ATR percentile[v4.01]
     }

   string ToString() const
     {
      return StringFormat(
         "[v4.01|26D] "
         "ATR=%.2f Spd=%.2f SL=%.2f Tod=%.2f Vol=%.2f Mom=%.2f "
         "Zn=%.2f LS=%.2f Nz=%.2f RSI=%.2f Cb=%.2f EMA=%.2f "
         "Ses=%.2f SRC=%.2f CC=%.2f VP=%.2f HTF=%.2f ADX=%.2f | "
         "SRB=%.2f SRR=%.2f UW=%.2f LW=%.2f "
         "hSin=%.2f hCos=%.2f H4T=%.2f ATRPct=%.2f",
         f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7],
         f[8], f[9], f[10],f[11],f[12],f[13],f[14],f[15],
         f[16],f[17],
         f[18],f[19],f[20],f[21],f[22],f[23],f[24],f[25]);
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
//| AIFeatureBuilder v4.01                                           |
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

   void Init(string sym = "", ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
     { m_cache.Init(); }  // symbol/tf stored via _Symbol/_Period

   void SetRegime(MarketRegimeFilter *r) { m_regime = r; }
   void SetData(DataManager *d)          { m_data   = d; }

   //+----------------------------------------------------------------+
   //| RefreshCache — called once per new bar (bar[1] safe)           |
   //| v4.01: adds bars60[] (60-bar ATR history) + barsH4_20[]        |
   //+----------------------------------------------------------------+
   void RefreshCache()
     {
      datetime barTime = iTime(_Symbol, _Period, 1);
      if(barTime == m_lastUpdate && m_cache.initialized) return;
      m_lastUpdate = barTime;

      if(CopyRates(_Symbol, _Period, 1, 14, m_cache.bars14) < 14) ArrayInitialize(m_cache.bars14, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 15, m_cache.bars15) < 15) ArrayInitialize(m_cache.bars15, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 20, m_cache.bars20) < 20) ArrayInitialize(m_cache.bars20, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 50, m_cache.bars50) < 50) ArrayInitialize(m_cache.bars50, 0.0);
      // v4.01: 60-bar ATR history for percentile rank
      if(CopyRates(_Symbol, _Period, 1, 60, m_cache.bars60) < 60) ArrayInitialize(m_cache.bars60, 0.0);
      // v4.01: 20 H4 bars for HTF EMA-20 trend direction
      if(CopyRates(_Symbol, PERIOD_H4, 1, 20, m_cache.barsH4_20) < 20)
         ArrayInitialize(m_cache.barsH4_20, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 1,  m_cache.bar1) < 1)
         ArrayInitialize(m_cache.bar1, 0.0);

      MqlRates tmp[1];
      if(CopyRates(_Symbol, _Period, 1, 1, tmp) == 1)
        { m_cache.current.open   = tmp[0].open;        m_cache.current.high  = tmp[0].high;
          m_cache.current.low    = tmp[0].low;         m_cache.current.close = tmp[0].close;
          m_cache.current.volume = tmp[0].tick_volume; m_cache.current.valid = true; }
      ENUM_TIMEFRAMES htf = HigherTF((ENUM_TIMEFRAMES)Period());
      if(CopyRates(_Symbol, htf, 1, 1, tmp) == 1)
        { m_cache.higher.open   = tmp[0].open;        m_cache.higher.high  = tmp[0].high;
          m_cache.higher.low    = tmp[0].low;         m_cache.higher.close = tmp[0].close;
          m_cache.higher.volume = tmp[0].tick_volume; m_cache.higher.valid = true; }
      m_cache.initialized = true;
     }

   //+----------------------------------------------------------------+
   //| Build — full 26-dim FeatureVector                              |
   //| IMPORTANT: call RefreshCache() before Build() on each new bar  |
   //+----------------------------------------------------------------+
   FeatureVector Build(const SignalDecision &signal,
                       double atrPoints,
                       double support,
                       double resistance,
                       const SRZone &zones[],
                       int    zoneCount) const
     {
      FeatureVector v;

      // ── F01–F18 (unchanged from v4.00) ──────────────────────────
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

      // Build double[] zone prices for F14
      double zonePrices[];
      ArrayResize(zonePrices, MathMin(zoneCount, 16));
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      for(int i = 0; i < ArraySize(zonePrices); i++)
         zonePrices[i] = zones[i].priceLevel;

      v.f[13] = NormalizeSRConfluence(price, zonePrices, ArraySize(zonePrices));
      v.f[14] = NormalizeCandleStructure();
      v.f[15] = NormalizeVolProfile50();
      v.f[16] = NormalizeHTFClosePosition();
      v.f[17] = NormalizeADX();

      // ── F19–F26 (v4.01 Priority-1 new features) ─────────────────
      double atrPrice = atrPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      // F19: SR Proximity Bull — how far above support (normalized)
      // High value (close to 1.0) = price hugging support = bullish entry zone
      v.f[18] = NormalizeSRProxBull(price, support, atrPrice);

      // F20: SR Proximity Bear — how far below resistance (normalized)
      // High value = price hugging resistance = bearish entry zone
      v.f[19] = NormalizeSRProxBear(price, resistance, atrPrice);

      // F21: Upper wick ratio — rejection at highs (bearish signal)
      v.f[20] = NormalizeUpperWick();

      // F22: Lower wick ratio — support wick (bullish signal)
      v.f[21] = NormalizeLowerWick();

      // F23: Hour Sin — cyclical encoding, avoids 23→0 discontinuity
      v.f[22] = NormalizeHourSin();

      // F24: Hour Cos — cyclical pair with sin
      v.f[23] = NormalizeHourCos();

      // F25: HTF H4 Trend — EMA-20 on H4 alignment to current price
      v.f[24] = NormalizeHTFTrendH4();

      // F26: ATR Percentile Rank — current ATR vs 60-bar history
      // 0=lowest volatility period, 1=highest → regime context
      v.f[25] = NormalizeATRPercentile60(atrPrice);

      // Regime override on F01 (unchanged)
      if(CheckPointer(m_regime) != POINTER_INVALID)
        {
         const RegimeResult &r = m_regime.GetResult();
         v.f[0] = MathMax(v.f[0], r.volatilityScore);
        }

      return v;
     }

   // Legacy EvalContext build (backward compat — extended for new fields)
   void Build(EvalContext &ctx, const SignalDecision &signal,
              double atrPoints, double support, double resistance) const
     {
      SRZone emptyZones[];
      ArrayResize(emptyZones, 0);
      FeatureVector fv = Build(signal, atrPoints, support, resistance, emptyZones, 0);
      ctx.atrNorm         = fv.f[0];  ctx.spreadNorm     = fv.f[1];
      ctx.slNorm          = fv.f[2];  ctx.timeOfDayNorm  = fv.f[3];
      ctx.volumeNorm      = fv.f[4];  ctx.momentumNorm   = fv.f[5];
      ctx.zoneNorm        = fv.f[6];  ctx.lossStreakNorm  = fv.f[7];
      ctx.noiseNorm       = fv.f[8];  ctx.rsiNorm        = fv.f[9];
      ctx.candleBodyRatio = fv.f[10]; ctx.emaDistNorm    = fv.f[11];
      ctx.sessionNorm     = fv.f[12];
      // v4.01: populate new EvalContext fields
      ctx.srProxBull      = fv.f[18]; ctx.srProxBear     = fv.f[19];
      ctx.upperWickRatio  = fv.f[20]; ctx.lowerWickRatio  = fv.f[21];
      ctx.hourSin         = fv.f[22]; ctx.hourCos        = fv.f[23];
      ctx.htfTrendH4      = fv.f[24]; ctx.atrPercentile  = fv.f[25];
      if(CheckPointer(m_regime) != POINTER_INVALID)
        { const RegimeResult &r = m_regime.GetResult();
          ctx.regimeScore      = r.regimeScore;
          ctx.volatilityScore  = r.volatilityScore;
          ctx.mtConfluenceNorm = r.mtfConfirmed ? 1.0 : (double)r.tfAlignment/3.0; }
      else
        { ctx.regimeScore      = NormalizeVolatilityFallback();
          ctx.volatilityScore  = ctx.regimeScore;
          ctx.mtConfluenceNorm = NormalizeMTFFallback(signal); }
     }

   // ─── Normalizers F01–F18 (unchanged from v4.00) ──────────────────

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

   // F14: SR Confluence
   double NormalizeSRConfluence(double price, const double &zones[], int count) const
     {
      if(count <= 0) return 0.5;
      double atr = (m_data!=NULL) ? m_data.GetATRPoints()*SymbolInfoDouble(_Symbol,SYMBOL_POINT) : 0.001;
      double score=0, totalWeight=0;
      for(int i=0;i<count&&i<16;i++)
        { double dist=MathAbs(price-zones[i]);
          double prox=MathMax(0.0,1.0-dist/(atr*3.0));
          double w=prox*prox;
          score+=prox*w; totalWeight+=w; }
      return (totalWeight>0)?MathMin(1.0,score/totalWeight):0.5;
     }

   // F15: Candle structure
   double NormalizeCandleStructure() const
     {
      if(!m_cache.initialized||ArraySize(m_cache.bar1)<1) return 0.5;
      double open=m_cache.bar1[0].open, close=m_cache.bar1[0].close;
      double high=m_cache.bar1[0].high, low=m_cache.bar1[0].low;
      double body=MathAbs(close-open), range=high-low;
      if(range<SymbolInfoDouble(_Symbol,SYMBOL_POINT)) return 0.5;
      double bodyRatio=body/range;
      if(bodyRatio<0.10) return 0.0;
      double upperWick=high-MathMax(open,close);
      double lowerWick=MathMin(open,close)-low;
      if(bodyRatio<0.30&&(upperWick>body*2||lowerWick>body*2)) return 0.25;
      if(ArraySize(m_cache.bars15)>=2)
        { double prevBody=MathAbs(m_cache.bars15[1].close-m_cache.bars15[1].open);
          if(body>prevBody*1.5) return 1.0; }
      if(ArraySize(m_cache.bars15)>=2)
        if(high<=m_cache.bars15[1].high&&low>=m_cache.bars15[1].low) return 0.5;
      return 0.75;
     }

   // F16: Volume profile proxy
   double NormalizeVolProfile50() const
     {
      if(!m_cache.initialized||ArraySize(m_cache.bars50)<50) return 0.5;
      double sum=0;
      for(int i=0;i<50;i++) sum+=(double)m_cache.bars50[i].tick_volume;
      double avg=sum/50.0; if(avg<=0) return 0.5;
      return MathMax(0.0,MathMin(1.0,(double)m_cache.bars50[0].tick_volume/avg/2.0));
     }

   // F17: HTF close position
   double NormalizeHTFClosePosition() const
     {
      if(!m_cache.higher.valid) return 0.5;
      double rng=m_cache.higher.high-m_cache.higher.low;
      if(rng<SymbolInfoDouble(_Symbol,SYMBOL_POINT)) return 0.5;
      return MathMax(0.0,MathMin(1.0,(m_cache.higher.close-m_cache.higher.low)/rng));
     }

   // F18: ADX trend strength
   double NormalizeADX() const
     {
      if(!m_cache.initialized||ArraySize(m_cache.bars14)<14) return 0.5;
      double trSum=0,dmPlus=0,dmMinus=0;
      for(int i=0;i<13;i++)
        { double tr=MathMax(m_cache.bars14[i].high-m_cache.bars14[i].low,
                   MathMax(MathAbs(m_cache.bars14[i].high-m_cache.bars14[i+1].close),
                           MathAbs(m_cache.bars14[i].low -m_cache.bars14[i+1].close)));
          double up=m_cache.bars14[i].high-m_cache.bars14[i+1].high;
          double dn=m_cache.bars14[i+1].low-m_cache.bars14[i].low;
          trSum+=tr;
          dmPlus +=(up>dn&&up>0)?up:0;
          dmMinus+=(dn>up&&dn>0)?dn:0; }
      if(trSum<=0) return 0.5;
      double diP=(dmPlus/trSum)*100, diM=(dmMinus/trSum)*100;
      double dx=(diP+diM>0)?MathAbs(diP-diM)/(diP+diM)*100:0;
      return MathMax(0.0,MathMin(1.0,dx/50.0));
     }

   // ─── NEW Normalizers F19–F26 (v4.01 Priority-1) ─────────────────

   // F19: SR Proximity Bull
   // Measures how close price is to nearest support, normalized by ATR
   // 1.0 = price touching support (ideal bull entry)
   // 0.0 = price far above support (chasing)
   double NormalizeSRProxBull(double price, double support, double atrPrice) const
     {
      if(atrPrice <= 0 || support <= 0) return 0.5;
      double dist = price - support;   // positive = above support
      // Clamp: within 1 ATR of support = high score, 3+ ATR = low score
      double norm = 1.0 - MathMin(1.0, MathMax(0.0, dist) / (atrPrice * 2.0));
      return MathMax(0.0, MathMin(1.0, norm));
     }

   // F20: SR Proximity Bear
   // 1.0 = price touching resistance (ideal bear entry)
   // 0.0 = price far below resistance
   double NormalizeSRProxBear(double price, double resistance, double atrPrice) const
     {
      if(atrPrice <= 0 || resistance <= 0) return 0.5;
      double dist = resistance - price;  // positive = below resistance
      double norm = 1.0 - MathMin(1.0, MathMax(0.0, dist) / (atrPrice * 2.0));
      return MathMax(0.0, MathMin(1.0, norm));
     }

   // F21: Upper Wick Ratio
   // High value = strong upper rejection = bearish signal
   // Uses bar[1] (closed bar, no lookahead)
   double NormalizeUpperWick() const
     {
      if(!m_cache.initialized || ArraySize(m_cache.bar1) < 1) return 0.5;
      double high  = m_cache.bar1[0].high;
      double low   = m_cache.bar1[0].low;
      double open  = m_cache.bar1[0].open;
      double close = m_cache.bar1[0].close;
      double range = high - low;
      if(range < SymbolInfoDouble(_Symbol, SYMBOL_POINT)) return 0.5;
      double upperWick = high - MathMax(open, close);
      return MathMax(0.0, MathMin(1.0, upperWick / range));
     }

   // F22: Lower Wick Ratio
   // High value = strong lower wick = bullish support rejection
   double NormalizeLowerWick() const
     {
      if(!m_cache.initialized || ArraySize(m_cache.bar1) < 1) return 0.5;
      double high  = m_cache.bar1[0].high;
      double low   = m_cache.bar1[0].low;
      double open  = m_cache.bar1[0].open;
      double close = m_cache.bar1[0].close;
      double range = high - low;
      if(range < SymbolInfoDouble(_Symbol, SYMBOL_POINT)) return 0.5;
      double lowerWick = MathMin(open, close) - low;
      return MathMax(0.0, MathMin(1.0, lowerWick / range));
     }

   // F23: Hour Sin — cyclical encoding
   // sin(2π * hour / 24), shifted from [-1,1] → [0,1]
   // Prevents artificial 23→0 discontinuity that raw hour integer causes
   double NormalizeHourSin() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);  // GMT for session-neutral encoding
      double rad = 2.0 * M_PI * dt.hour / 24.0;
      return (MathSin(rad) + 1.0) / 2.0;  // [0,1]
     }

   // F24: Hour Cos — cyclical pair
   // cos(2π * hour / 24), shifted from [-1,1] → [0,1]
   double NormalizeHourCos() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      double rad = 2.0 * M_PI * dt.hour / 24.0;
      return (MathCos(rad) + 1.0) / 2.0;  // [0,1]
     }

   // F25: HTF Trend H4 — EMA-20 alignment on H4 timeframe
   // Uses barsH4_20[] cached on new bar
   // 1.0 = price above H4 EMA-20 (bullish structure)
   // 0.0 = price below H4 EMA-20 (bearish structure)
   // 0.5 = H4 cache unavailable
   double NormalizeHTFTrendH4() const
     {
      if(!m_cache.initialized || ArraySize(m_cache.barsH4_20) < 20) return 0.5;
      // Compute EMA-20 on H4 from oldest to newest (Wilder-style)
      double ema = m_cache.barsH4_20[19].close;
      double k   = 2.0 / 21.0;
      for(int i = 18; i >= 0; i--)
         ema = m_cache.barsH4_20[i].close * k + ema * (1.0 - k);
      double currentH4Close = m_cache.barsH4_20[0].close;
      // Price vs EMA: normalize distance
      // > 0 = bullish, < 0 = bearish
      double atrH4 = 0;
      for(int i = 0; i < 14 && i < ArraySize(m_cache.barsH4_20); i++)
         atrH4 += m_cache.barsH4_20[i].high - m_cache.barsH4_20[i].low;
      atrH4 /= MathMax(1, MathMin(14, ArraySize(m_cache.barsH4_20)));
      if(atrH4 <= 0) return (currentH4Close > ema) ? 0.75 : 0.25;
      double diff   = currentH4Close - ema;
      double scaled = diff / (atrH4 * 1.5);   // +1.5 ATR = max bullish = 1.0
      return MathMax(0.0, MathMin(1.0, 0.5 + scaled * 0.5));
     }

   // F26: ATR Percentile Rank — rolling 60 bars
   // 0.0 = current ATR is lowest in 60 bars (compression = breakout risk)
   // 1.0 = current ATR is highest in 60 bars (expansion = trending)
   // Uses atrPrice (current bar ATR in price units)
   double NormalizeATRPercentile60(double atrPrice) const
     {
      if(!m_cache.initialized || ArraySize(m_cache.bars60) < 60 || atrPrice <= 0)
         return 0.5;
      int rank = 0;
      for(int i = 0; i < 60; i++)
        {
         double barATR = m_cache.bars60[i].high - m_cache.bars60[i].low;
         if(barATR < atrPrice) rank++;
        }
      return rank / 60.0;  // [0.0, 1.0]
     }

   // ─── Feature Drift Detection ────────────────────────────────────
   void SetBaseline(const FeatureStats &stats) { m_baseline=stats; m_hasBaseline=true; }

   // Returns drift score [0,1] — > 0.3 = warning, > 0.6 = critical
   // Uses max z-score across all 26 dims
   double ComputeDrift(const FeatureVector &live) const
     {
      if(!m_hasBaseline || m_baseline.sampleCount < 30) return 0.0;
      double maxDrift = 0;
      for(int i = 0; i < AI_FEATURE_DIM; i++)
        {
         if(m_baseline.stddev[i] <= 0) continue;
         double z = MathAbs(live.f[i] - m_baseline.mean[i]) / m_baseline.stddev[i];
         maxDrift = MathMax(maxDrift, MathMin(1.0, z / 3.0));
        }
      return maxDrift;
     }
  };

#endif // __AI_FEATURE_BUILDER_MQH__
