//+------------------------------------------------------------------+
//|                                             AIFeatureBuilder.mqh |
//|          Pure stateless feature normalisation for AI subsystem   |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property version   "3.00"
#property strict

#ifndef __AI_FEATURE_BUILDER_MQH__
#define __AI_FEATURE_BUILDER_MQH__

#include "AITypes.mqh"
#include "../IManager.mqh"
#include "../12.MarketRegime.mqh"

/// Pure helper — no IManager inheritance, no event subscriptions.
/// Holds only a bar cache and a pointer to the regime filter.
/// All methods are const or operate solely on the cache.
class AIFeatureBuilder
{
private:
   BarCache           m_cache;
   MarketRegimeFilter *m_regime;    // non-owning
   DataManager        *m_data;      // non-owning
   datetime           m_lastUpdate;

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
         case PERIOD_D1:  return PERIOD_W1;
         default:         return PERIOD_H1;
      }
   }

public:
   AIFeatureBuilder() : m_regime(NULL), m_data(NULL), m_lastUpdate(0)
   { m_cache.Init(); }

   void SetRegime(MarketRegimeFilter *r) { m_regime = r; }
   void SetData(DataManager *d)          { m_data   = d; }

   //--- Refresh bar cache once per new bar (guard inside)
   void RefreshCache()
   {
      datetime barTime = iTime(_Symbol, _Period, 1);
      if(barTime == m_lastUpdate && m_cache.initialized) return;
      m_lastUpdate = barTime;

      if(CopyRates(_Symbol, _Period, 1, 14, m_cache.bars14) < 14) ArrayInitialize(m_cache.bars14, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 15, m_cache.bars15) < 15) ArrayInitialize(m_cache.bars15, 0.0);
      if(CopyRates(_Symbol, _Period, 1, 20, m_cache.bars20) < 20) ArrayInitialize(m_cache.bars20, 0.0);
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
   }

   //--- Build a full EvalContext from cached data + signal
   void Build(EvalContext &ctx, const SignalDecision &signal,
              double atrPoints, double support, double resistance) const
   {
      ctx.atrNorm        = NormalizeATR(atrPoints);
      ctx.spreadNorm     = NormalizeSpread();
      ctx.slNorm         = NormalizeSL(signal.slMultiplier);
      ctx.timeOfDayNorm  = NormalizeTimeOfDay();
      ctx.volumeNorm     = NormalizeVolume();
      ctx.momentumNorm   = NormalizeMomentum();
      ctx.zoneNorm       = NormalizeZone(signal.zonePrice, support, resistance);
      ctx.lossStreakNorm  = NormalizeLossStreak();
      ctx.noiseNorm      = NormalizeNoise();
      ctx.rsiNorm         = NormalizeRSI();
      ctx.candleBodyRatio = NormalizeCandleBody();
      ctx.emaDistNorm     = NormalizeEMADist();
      ctx.sessionNorm     = NormalizeSession();

      if(CheckPointer(m_regime) != POINTER_INVALID)
      {
         const RegimeResult &r = m_regime.GetResult();
         ctx.regimeScore      = r.regimeScore;
         ctx.volatilityScore  = r.volatilityScore;
         ctx.mtConfluenceNorm = r.mtfConfirmed ? 1.0 : (double)r.tfAlignment / 3.0;
      }
      else
      {
         ctx.regimeScore      = NormalizeVolatilityFallback();
         ctx.volatilityScore  = ctx.regimeScore;
         ctx.mtConfluenceNorm = NormalizeMTFFallback(signal);
      }
   }

   // ─── Individual normalizers (const — no side effects) ─────────

   double NormalizeATR(double atrPoints) const
   { return (atrPoints <= 0) ? 0.0 : MathMin(1.0, atrPoints / 20.0); }

   double NormalizeSpread() const
   {
      long sp = 0;
      if(!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, sp) || sp <= 0) return 1.0;
      return MathMax(0.0, 1.0 - MathMin(1.0, (double)sp / 10.0));
   }

   double NormalizeSL(double slMultiplier) const
   { return (slMultiplier <= 0) ? 0.0 : MathMin(1.0, slMultiplier / 3.0); }

   double NormalizeZone(double zonePrice, double support, double resistance) const
   {
      double dist  = MathAbs(zonePrice - (support + resistance) / 2.0);
      double range = MathMax(1.0, MathAbs(resistance - support));
      return 1.0 - MathMin(1.0, dist / range);
   }

   double NormalizeTimeOfDay() const
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if((h >= 8 && h <= 11) || (h >= 13 && h <= 16)) return 1.0;
      if(h >= 7 && h <= 19)                            return 0.7;
      return 0.3;
   }

   double NormalizeVolume() const
   {
      if(m_cache.current.valid && m_cache.higher.valid)
      {
         long avgVol = (m_cache.current.volume + m_cache.higher.volume) / 2;
         if(avgVol == 0) return 0.5;
         return MathMax(0.0, MathMin(2.0, (double)m_cache.current.volume / avgVol));
      }
      long vol[20];
      if(CopyTickVolume(_Symbol, _Period, 1, 20, vol) < 20) return 0.5;
      long sum = 0; for(int i=0;i<20;i++) sum+=vol[i];
      long avg = sum / 20;
      return (avg == 0) ? 0.5 : MathMax(0.0, MathMin(2.0, (double)vol[0]/avg));
   }

   double NormalizeMomentum() const
   {
      if(m_cache.initialized && ArraySize(m_cache.bars14) >= 14)
      {
         double momentum = m_cache.bars14[0].close - m_cache.bars14[13].close;
         double maxMove  = 0;
         for(int i=1;i<14;i++) maxMove = MathMax(maxMove, MathAbs(m_cache.bars14[i].close - m_cache.bars14[0].close));
         return (maxMove == 0) ? 0.5 : 0.5 + (momentum / maxMove) * 0.5;
      }
      return 0.5;
   }

   double NormalizeNoise() const
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return (dt.hour == 8 || dt.hour == 13) ? 1.0 : 0.2;
   }

   double NormalizeLossStreak() const
   {
      if(CheckPointer(m_data) == POINTER_INVALID) return 0.0;
      return MathMax(0.0, 1.0 - MathMin(1.0, m_data.GetConsecutiveLosses() * 0.1));
   }

   double NormalizeRSI() const
   {
      if(m_cache.initialized && ArraySize(m_cache.bars15) >= 15)
      {
         double gains=0, losses=0;
         for(int i=0;i<14;i++)
         {
            double diff = m_cache.bars15[i].close - m_cache.bars15[i+1].close;
            if(diff > 0) gains+=diff; else losses-=diff;
         }
         double rs = (losses==0) ? 100.0 : gains/losses;
         return (100.0 - (100.0/(1.0+rs))) / 100.0;
      }
      return 0.5;
   }

   double NormalizeCandleBody() const
   {
      if(m_cache.initialized && ArraySize(m_cache.bar1) >= 1)
      {
         double body  = MathAbs(m_cache.bar1[0].close - m_cache.bar1[0].open);
         double range = m_cache.bar1[0].high - m_cache.bar1[0].low;
         return (range==0) ? 0.5 : MathMin(1.0, body/range);
      }
      return 0.5;
   }

   double NormalizeEMADist() const
   {
      if(m_cache.initialized && ArraySize(m_cache.bars20) >= 20)
      {
         double ema=m_cache.bars20[19].close, k=2.0/21.0;
         for(int i=18;i>=0;i--) ema = m_cache.bars20[i].close*k + ema*(1.0-k);
         double dist=MathAbs(m_cache.bars20[0].close - ema), atrEst=0;
         for(int i=0;i<20;i++) atrEst += m_cache.bars20[i].high - m_cache.bars20[i].low;
         atrEst /= 20.0;
         return (atrEst==0) ? 0.5 : MathMin(1.0, dist/(atrEst*2.0));
      }
      return 0.5;
   }

   double NormalizeSession() const
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if(h >= 13 && h <= 21) return 1.0;
      if(h >= 7  && h <= 16) return 0.5;
      return 0.0;
   }

   double NormalizeVolatilityFallback() const
   {
      if(m_cache.initialized && ArraySize(m_cache.bars20) >= 20)
      {
         double avg=0; for(int i=0;i<20;i++) avg+=m_cache.bars20[i].close; avg/=20;
         double sumSq=0; for(int i=0;i<20;i++){double d=m_cache.bars20[i].close-avg;sumSq+=d*d;}
         return MathMin(1.0, MathSqrt(sumSq/20) / (SymbolInfoDouble(_Symbol,SYMBOL_POINT)*100));
      }
      return 0.5;
   }

   double NormalizeMTFFallback(const SignalDecision &signal) const
   {
      ENUM_TIMEFRAMES htf = HigherTF((ENUM_TIMEFRAMES)Period());
      MqlRates bars[10];
      if(CopyRates(_Symbol, htf, 1, 10, bars) >= 10)
      {
         double hi=bars[0].high, lo=bars[0].low;
         for(int i=1;i<10;i++){hi=MathMax(hi,bars[i].high);lo=MathMin(lo,bars[i].low);}
         double rng = hi - lo;
         if(rng==0) return 0.5;
         double minDist = MathMin(MathAbs(bars[0].close-hi), MathAbs(bars[0].close-lo));
         return MathMax(0.3, 1.0 - MathMin(1.0, minDist/(rng*0.3)));
      }
      return 0.5;
   }
};

#endif // __AI_FEATURE_BUILDER_MQH__
