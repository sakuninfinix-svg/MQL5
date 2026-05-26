//+------------------------------------------------------------------+
//| AI/AIFeatureBuilder.mqh — v4.02                                  |
//| Feature engineering: 26-dim normalised vector for AI inference.  |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_FEATURE_BUILDER_MQH__
#define __AI_FEATURE_BUILDER_MQH__

#include "AITypes.mqh"
#include "../RegimeFilter.mqh"
#include "../../Infra/DataManager.mqh"
#include "../../Data/RegimeTypes.mqh"

#ifndef AI_FEATURE_DIM
  #define AI_FEATURE_DIM 26
#endif

struct FeatureVector
  {
   double f[AI_FEATURE_DIM];
   double ATR() const { return f[0]; } double Spread() const { return f[1]; }
   double SLMult() const { return f[2]; } double TimeOfDay() const { return f[3]; }
   double Volume() const { return f[4]; } double Momentum() const { return f[5]; }
   double ZoneProx() const { return f[6]; } double LossStreak() const { return f[7]; }
   double Noise() const { return f[8]; } double RSI() const { return f[9]; }
   double CandleBody() const { return f[10]; } double EMADist() const { return f[11]; }
   double Session() const { return f[12]; } double SRConfluence() const { return f[13]; }
   double CandleCode() const { return f[14]; } double VolProfile() const { return f[15]; }
   double HTFPosition() const { return f[16]; } double ADXStrength() const { return f[17]; }
   double SRProxBull() const { return f[18]; } double SRProxBear() const { return f[19]; }
   double UpperWick() const { return f[20]; } double LowerWick() const { return f[21]; }
   double HourSin() const { return f[22]; } double HourCos() const { return f[23]; }
   double HTFTrendH4() const { return f[24]; } double ATRPercentile() const { return f[25]; }
   void Clear() { ArrayInitialize(f, 0.5); }
   void ToFloatArray(float &out[]) const
     { ArrayResize(out, AI_FEATURE_DIM); for(int i=0;i<AI_FEATURE_DIM;i++) out[i]=(float)f[i]; }
   void ToNNInputs(double &out[]) const
     {
      ArrayResize(out, NN_INPUTS);
      out[0]=f[0]; out[1]=f[1]; out[2]=f[2]; out[3]=f[4]; out[4]=f[5]; out[5]=f[13];
      out[6]=f[17]; out[7]=f[18]; out[8]=f[19]; out[9]=f[22]; out[10]=f[24]; out[11]=f[25];
     }
   string ToString() const
     { return StringFormat("AI26 ATR=%.2f Spd=%.2f Mom=%.2f SRB=%.2f SRR=%.2f ADX=%.2f", f[0],f[1],f[5],f[18],f[19],f[17]); }
  };

struct FeatureStats
  {
   double mean[AI_FEATURE_DIM];
   double stddev[AI_FEATURE_DIM];
   int    sampleCount;
  };

class AIFeatureBuilder
  {
private:
   BarCache       m_cache;
   CRegimeFilter *m_regime;
   DataManager   *m_data;
   string         m_symbol;
   ENUM_TIMEFRAMES m_tf;
   datetime       m_lastUpdate;
   FeatureStats   m_baseline;
   bool           m_hasBaseline;

   static ENUM_TIMEFRAMES HigherTF(ENUM_TIMEFRAMES tf)
     {
      switch(tf)
        {
         case PERIOD_M1: return PERIOD_M5; case PERIOD_M5: return PERIOD_M15;
         case PERIOD_M15: return PERIOD_M30; case PERIOD_M30: return PERIOD_H1;
         case PERIOD_H1: return PERIOD_H4; case PERIOD_H4: return PERIOD_D1;
         default: return PERIOD_H1;
        }
     }

   string Sym() const { return (m_symbol == "") ? _Symbol : m_symbol; }
   ENUM_TIMEFRAMES Tf() const { return (m_tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : m_tf; }

public:
   AIFeatureBuilder() : m_regime(NULL), m_data(NULL), m_symbol(""), m_tf(PERIOD_CURRENT),
                        m_lastUpdate(0), m_hasBaseline(false)
     { m_cache.Init(); }

   bool Init(string sym = "", ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
     { m_symbol = sym; m_tf = tf; m_cache.Init(); m_lastUpdate = 0; return true; }

   bool Init(DataManager *data, CRegimeFilter *regime = NULL, string sym = "", ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
     { m_data = data; m_regime = regime; return Init(sym, tf); }

   void SetRegime(CRegimeFilter *r) { m_regime = r; }
   void SetData(DataManager *d) { m_data = d; }

   void RefreshCache()
     {
      string symbol = Sym(); ENUM_TIMEFRAMES tf = Tf();
      datetime barTime = iTime(symbol, tf, 1);
      if(barTime == m_lastUpdate && m_cache.initialized) return;
      m_lastUpdate = barTime;
      if(CopyRates(symbol, tf, 1, 14, m_cache.bars14) < 14) ArrayInitialize(m_cache.bars14, 0.0);
      if(CopyRates(symbol, tf, 1, 15, m_cache.bars15) < 15) ArrayInitialize(m_cache.bars15, 0.0);
      if(CopyRates(symbol, tf, 1, 20, m_cache.bars20) < 20) ArrayInitialize(m_cache.bars20, 0.0);
      if(CopyRates(symbol, tf, 1, 50, m_cache.bars50) < 50) ArrayInitialize(m_cache.bars50, 0.0);
      if(CopyRates(symbol, tf, 1, 60, m_cache.bars60) < 60) ArrayInitialize(m_cache.bars60, 0.0);
      if(CopyRates(symbol, PERIOD_H4, 1, 20, m_cache.barsH4_20) < 20) ArrayInitialize(m_cache.barsH4_20, 0.0);
      if(CopyRates(symbol, tf, 1, 1, m_cache.bar1) < 1) ArrayInitialize(m_cache.bar1, 0.0);
      MqlRates tmp[1];
      if(CopyRates(symbol, tf, 1, 1, tmp) == 1)
        { m_cache.current.open=tmp[0].open; m_cache.current.high=tmp[0].high; m_cache.current.low=tmp[0].low; m_cache.current.close=tmp[0].close; m_cache.current.volume=tmp[0].tick_volume; m_cache.current.valid=true; }
      ENUM_TIMEFRAMES htf = HigherTF(tf);
      if(CopyRates(symbol, htf, 1, 1, tmp) == 1)
        { m_cache.higher.open=tmp[0].open; m_cache.higher.high=tmp[0].high; m_cache.higher.low=tmp[0].low; m_cache.higher.close=tmp[0].close; m_cache.higher.volume=tmp[0].tick_volume; m_cache.higher.valid=true; }
      m_cache.initialized = true;
     }

   FeatureVector Build(const SignalDecision &signal, double atrPoints, double support,
                       double resistance, const SRZone &zones[], int zoneCount) const
     {
      FeatureVector v; v.Clear();
      double point = SymbolInfoDouble(Sym(), SYMBOL_POINT);
      double price = SymbolInfoDouble(Sym(), SYMBOL_BID);
      double atrPrice = MathMax(point, atrPoints * point);
      v.f[0]=NormalizeATR(atrPoints); v.f[1]=NormalizeSpread(); v.f[2]=NormalizeSL(signal.slMultiplier);
      v.f[3]=NormalizeTimeOfDay(); v.f[4]=NormalizeVolume(); v.f[5]=NormalizeMomentum();
      v.f[6]=NormalizeZone(signal.zonePrice, support, resistance); v.f[7]=NormalizeLossStreak();
      v.f[8]=NormalizeNoise(); v.f[9]=NormalizeRSI(); v.f[10]=NormalizeCandleBody(); v.f[11]=NormalizeEMADist();
      v.f[12]=NormalizeSession();
      double zonePrices[]; ArrayResize(zonePrices, MathMin(zoneCount,16));
      for(int i=0;i<ArraySize(zonePrices);i++) zonePrices[i]=zones[i].priceLevel;
      v.f[13]=NormalizeSRConfluence(price, zonePrices, ArraySize(zonePrices));
      v.f[14]=NormalizeCandleStructure(); v.f[15]=NormalizeVolProfile50(); v.f[16]=NormalizeHTFClosePosition();
      v.f[17]=NormalizeADX(); v.f[18]=NormalizeSRProxBull(price, support, atrPrice);
      v.f[19]=NormalizeSRProxBear(price, resistance, atrPrice); v.f[20]=NormalizeUpperWick(); v.f[21]=NormalizeLowerWick();
      v.f[22]=NormalizeHourSin(); v.f[23]=NormalizeHourCos(); v.f[24]=NormalizeHTFTrendH4(); v.f[25]=NormalizeATRPercentile60(atrPrice);
      if(m_regime != NULL && m_regime.IsReady()) v.f[17] = MathMax(v.f[17], MathMin(1.0, m_regime.GetADX()/50.0));
      return v;
     }

   void Build(EvalContext &ctx, const SignalDecision &signal, double atrPoints, double support, double resistance) const
     {
      SRZone emptyZones[]; ArrayResize(emptyZones,0);
      FeatureVector fv = Build(signal, atrPoints, support, resistance, emptyZones, 0);
      ctx.Reset();
      ctx.atrNorm=fv.f[0]; ctx.spreadNorm=fv.f[1]; ctx.slNorm=fv.f[2]; ctx.timeOfDayNorm=fv.f[3];
      ctx.volumeNorm=fv.f[4]; ctx.momentumNorm=fv.f[5]; ctx.zoneNorm=fv.f[6]; ctx.lossStreakNorm=fv.f[7];
      ctx.noiseNorm=fv.f[8]; ctx.rsiNorm=fv.f[9]; ctx.candleBodyRatio=fv.f[10]; ctx.emaDistNorm=fv.f[11];
      ctx.sessionNorm=fv.f[12]; ctx.regimeScore=fv.f[17]; ctx.volatilityScore=fv.f[0]; ctx.mtConfluenceNorm=fv.f[16];
      ctx.srProxBull=fv.f[18]; ctx.srProxBear=fv.f[19]; ctx.upperWickRatio=fv.f[20]; ctx.lowerWickRatio=fv.f[21];
      ctx.hourSin=fv.f[22]; ctx.hourCos=fv.f[23]; ctx.htfTrendH4=fv.f[24]; ctx.atrPercentile=fv.f[25];
     }

   int BuildFeatures(string symbol, ENUM_TIMEFRAMES tf, double &features[])
     {
      if(symbol != "") m_symbol = symbol;
      if(tf != PERIOD_CURRENT) m_tf = tf;
      RefreshCache();
      SignalDecision sig; ZeroMemory(sig);
      sig.slMultiplier = 1.0; sig.zonePrice = SymbolInfoDouble(Sym(), SYMBOL_BID);
      double atrPts = (m_data != NULL) ? m_data.GetATRPoints() : 100.0;
      double price = SymbolInfoDouble(Sym(), SYMBOL_BID);
      FeatureVector fv = Build(sig, atrPts, price - atrPts*SymbolInfoDouble(Sym(), SYMBOL_POINT),
                               price + atrPts*SymbolInfoDouble(Sym(), SYMBOL_POINT), NULL, 0);
      ArrayResize(features, AI_FEATURE_DIM);
      for(int i=0;i<AI_FEATURE_DIM;i++) features[i]=fv.f[i];
      return AI_FEATURE_DIM;
     }

   double NormalizeATR(double atrPoints) const { return (atrPoints<=0)?0.0:MathMin(1.0, atrPoints/200.0); }
   double NormalizeSpread() const { long sp=0; if(!SymbolInfoInteger(Sym(),SYMBOL_SPREAD,sp)||sp<=0) return 1.0; return MathMax(0.0,1.0-MathMin(1.0,(double)sp/30.0)); }
   double NormalizeSL(double slMult) const { return (slMult<=0)?0.0:MathMin(1.0, slMult/3.0); }
   double NormalizeZone(double zp,double s,double r) const { double rng=MathMax(SymbolInfoDouble(Sym(),SYMBOL_POINT),MathAbs(r-s)); return 1.0-MathMin(1.0,MathAbs(zp-(s+r)*0.5)/rng); }
   double NormalizeTimeOfDay() const { MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); int h=dt.hour; if((h>=8&&h<=11)||(h>=13&&h<=16)) return 1.0; if(h>=7&&h<=19) return 0.7; return 0.3; }
   double NormalizeVolume() const { if(!m_cache.initialized||ArraySize(m_cache.bars50)<50) return 0.5; double sum=0; for(int i=0;i<50;i++) sum+=(double)m_cache.bars50[i].tick_volume; double avg=sum/50.0; return (avg<=0)?0.5:MathMin(1.0,(double)m_cache.bars50[0].tick_volume/(avg*2.0)); }
   double NormalizeMomentum() const { if(!m_cache.initialized||ArraySize(m_cache.bars14)<14) return 0.5; double move=m_cache.bars14[0].close-m_cache.bars14[13].close; double range=0; for(int i=0;i<14;i++) range+=m_cache.bars14[i].high-m_cache.bars14[i].low; range/=14.0; return (range<=0)?0.5:MathMax(0.0,MathMin(1.0,0.5+move/(range*6.0))); }
   double NormalizeNoise() const { MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); return (dt.hour==8||dt.hour==13)?1.0:0.2; }
   double NormalizeLossStreak() const { if(m_data==NULL) return 0.5; return MathMax(0.0,1.0-MathMin(1.0,m_data.GetConsecutiveLosses()*0.1)); }
   double NormalizeRSI() const { if(!m_cache.initialized||ArraySize(m_cache.bars15)<15) return 0.5; double gains=0,losses=0; for(int i=0;i<14;i++){double d=m_cache.bars15[i].close-m_cache.bars15[i+1].close; if(d>0) gains+=d; else losses-=d;} double rs=(losses==0)?100.0:gains/losses; return (100.0-(100.0/(1.0+rs)))/100.0; }
   double NormalizeCandleBody() const { if(!m_cache.initialized||ArraySize(m_cache.bar1)<1) return 0.5; double rng=m_cache.bar1[0].high-m_cache.bar1[0].low; return (rng<=0)?0.5:MathMin(1.0,MathAbs(m_cache.bar1[0].close-m_cache.bar1[0].open)/rng); }
   double NormalizeEMADist() const { if(!m_cache.initialized||ArraySize(m_cache.bars20)<20) return 0.5; double ema=m_cache.bars20[19].close,k=2.0/21.0; for(int i=18;i>=0;i--) ema=m_cache.bars20[i].close*k+ema*(1.0-k); double atr=0; for(int i=0;i<20;i++) atr+=m_cache.bars20[i].high-m_cache.bars20[i].low; atr/=20.0; return (atr<=0)?0.5:MathMin(1.0,MathAbs(m_cache.bars20[0].close-ema)/(atr*2.0)); }
   double NormalizeSession() const { MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); int h=dt.hour; if(h>=13&&h<=21) return 1.0; if(h>=7&&h<=16) return 0.5; return 0.0; }
   double NormalizeSRConfluence(double price,const double &zones[],int count) const { if(count<=0) return 0.5; double atr=(m_data!=NULL)?m_data.GetATRPoints()*SymbolInfoDouble(Sym(),SYMBOL_POINT):SymbolInfoDouble(Sym(),SYMBOL_POINT)*100; double score=0,total=0; for(int i=0;i<count&&i<16;i++){double prox=MathMax(0.0,1.0-MathAbs(price-zones[i])/(atr*3.0)); double w=prox*prox; score+=prox*w; total+=w;} return (total>0)?MathMin(1.0,score/total):0.5; }
   double NormalizeCandleStructure() const { if(!m_cache.initialized||ArraySize(m_cache.bar1)<1) return 0.5; double body=MathAbs(m_cache.bar1[0].close-m_cache.bar1[0].open); double range=m_cache.bar1[0].high-m_cache.bar1[0].low; if(range<=0) return 0.5; double br=body/range; if(br<0.1) return 0.0; if(br<0.3) return 0.25; return MathMin(1.0,0.5+br*0.5); }
   double NormalizeVolProfile50() const { return NormalizeVolume(); }
   double NormalizeHTFClosePosition() const { if(!m_cache.higher.valid) return 0.5; double rng=m_cache.higher.high-m_cache.higher.low; return (rng<=0)?0.5:MathMax(0.0,MathMin(1.0,(m_cache.higher.close-m_cache.higher.low)/rng)); }
   double NormalizeADX() const { if(m_regime!=NULL&&m_regime.IsReady()) return MathMin(1.0,m_regime.GetADX()/50.0); return 0.5; }
   double NormalizeSRProxBull(double price,double support,double atrPrice) const { if(atrPrice<=0||support<=0) return 0.5; return MathMax(0.0,MathMin(1.0,1.0-MathMax(0.0,price-support)/(atrPrice*2.0))); }
   double NormalizeSRProxBear(double price,double resistance,double atrPrice) const { if(atrPrice<=0||resistance<=0) return 0.5; return MathMax(0.0,MathMin(1.0,1.0-MathMax(0.0,resistance-price)/(atrPrice*2.0))); }
   double NormalizeUpperWick() const { if(!m_cache.initialized||ArraySize(m_cache.bar1)<1) return 0.5; double rng=m_cache.bar1[0].high-m_cache.bar1[0].low; if(rng<=0) return 0.5; return MathMax(0.0,MathMin(1.0,(m_cache.bar1[0].high-MathMax(m_cache.bar1[0].open,m_cache.bar1[0].close))/rng)); }
   double NormalizeLowerWick() const { if(!m_cache.initialized||ArraySize(m_cache.bar1)<1) return 0.5; double rng=m_cache.bar1[0].high-m_cache.bar1[0].low; if(rng<=0) return 0.5; return MathMax(0.0,MathMin(1.0,(MathMin(m_cache.bar1[0].open,m_cache.bar1[0].close)-m_cache.bar1[0].low)/rng)); }
   double NormalizeHourSin() const { MqlDateTime dt; TimeToStruct(TimeGMT(),dt); double rad=2.0*M_PI*dt.hour/24.0; return (MathSin(rad)+1.0)/2.0; }
   double NormalizeHourCos() const { MqlDateTime dt; TimeToStruct(TimeGMT(),dt); double rad=2.0*M_PI*dt.hour/24.0; return (MathCos(rad)+1.0)/2.0; }
   double NormalizeHTFTrendH4() const { if(!m_cache.initialized||ArraySize(m_cache.barsH4_20)<20) return 0.5; double ema=m_cache.barsH4_20[19].close,k=2.0/21.0; for(int i=18;i>=0;i--) ema=m_cache.barsH4_20[i].close*k+ema*(1.0-k); double atr=0; for(int i=0;i<14;i++) atr+=m_cache.barsH4_20[i].high-m_cache.barsH4_20[i].low; atr/=14.0; if(atr<=0) return (m_cache.barsH4_20[0].close>ema)?0.75:0.25; return MathMax(0.0,MathMin(1.0,0.5+(m_cache.barsH4_20[0].close-ema)/(atr*3.0))); }
   double NormalizeATRPercentile60(double atrPrice) const { if(!m_cache.initialized||ArraySize(m_cache.bars60)<60||atrPrice<=0) return 0.5; int rank=0; for(int i=0;i<60;i++){double barATR=m_cache.bars60[i].high-m_cache.bars60[i].low; if(barATR<atrPrice) rank++;} return rank/60.0; }
   void SetBaseline(const FeatureStats &stats) { m_baseline=stats; m_hasBaseline=true; }
   double ComputeDrift(const FeatureVector &live) const { if(!m_hasBaseline||m_baseline.sampleCount<30) return 0.0; double maxDrift=0; for(int i=0;i<AI_FEATURE_DIM;i++){ if(m_baseline.stddev[i]<=0) continue; double z=MathAbs(live.f[i]-m_baseline.mean[i])/m_baseline.stddev[i]; maxDrift=MathMax(maxDrift,MathMin(1.0,z/3.0)); } return maxDrift; }
  };

#endif // __AI_FEATURE_BUILDER_MQH__
