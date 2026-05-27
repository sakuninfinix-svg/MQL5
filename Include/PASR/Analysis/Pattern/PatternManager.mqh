//+------------------------------------------------------------------+
//| Analysis/Pattern/PatternManager.mqh — v2.04                      |
//| Pattern manager with canonical IManager lifecycle                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

#include "../../Core/IManager.mqh"
#include "../../Data/RegimeTypes.mqh"
#include "../MarketRegimeDetector.mqh"
#include "PatternTypes.mqh"
#include <Arrays/ArrayObj.mqh>

struct SPatternVote
  {
   bool              valid;
   ENUM_PATTERN_TYPE type;
   int               dir;
   double            extreme;
   double            score;
   double            regimeWeight;
   string            label;

   void Reset()
     {
      valid = false;
      type = PATTERN_NONE;
      dir = 0;
      extreme = 0.0;
      score = 0.0;
      regimeWeight = 1.0;
      label = "";
     }

   double TotalScore() const { return score * regimeWeight; }
  };

struct SPatternResult
  {
   bool              found;
   ENUM_PATTERN_TYPE type;
   int               direction;
   double            extreme;
   double            confluenceScore;
   string            reason;
   datetime          barTime;

   void Clear()
     {
      found = false;
      type = PATTERN_NONE;
      direction = 0;
      extreme = 0.0;
      confluenceScore = 0.0;
      reason = "";
      barTime = 0;
     }
  };

class CPatternRecord : public CObject
  {
public:
   SPatternResult data;
   CPatternRecord(const SPatternResult &r) { data = r; }
  };

class CPatternManager : public IManager
  {
private:
   CArrayObj      m_patternHistory;
   SPatternResult m_lastResult;
   datetime       m_lastScanBarTime;
   int            m_totalPatternsDetected;
   int            m_totalValidSignals;
   double         m_minConfluenceScore;
   double         m_minDominanceGap;
   double         m_regimeBoostFactor;

   void ResetVote(SPatternVote &v) { v.Reset(); }

   int FindBestVote(const SPatternVote &votes[], int dir)
     {
      int best = -1;
      double bestScore = 0.0;
      for(int i = 0; i < ArraySize(votes); i++)
        {
         if(!votes[i].valid || votes[i].dir != dir) continue;
         double score = votes[i].TotalScore();
         if(score > bestScore) { bestScore = score; best = i; }
        }
      return best;
     }

   string BuildConfluenceLabel(const SPatternVote &votes[], int dir)
     {
      string txt = "";
      for(int i = 0; i < ArraySize(votes); i++)
        {
         if(!votes[i].valid || votes[i].dir != dir) continue;
         if(txt != "") txt += " + ";
         txt += votes[i].label;
        }
      return txt;
     }

   double CandleOpen(const MqlRates &r[], int s)  const { return r[s].open; }
   double CandleHigh(const MqlRates &r[], int s)  const { return r[s].high; }
   double CandleLow(const MqlRates &r[], int s)   const { return r[s].low; }
   double CandleClose(const MqlRates &r[], int s) const { return r[s].close; }
   double CandleRange(const MqlRates &r[], int s) const { return CandleHigh(r,s) - CandleLow(r,s); }
   double CandleBody(const MqlRates &r[], int s)  const { return MathAbs(CandleClose(r,s) - CandleOpen(r,s)); }
   double UpperWick(const MqlRates &r[], int s)   const { return CandleHigh(r,s) - MathMax(CandleOpen(r,s), CandleClose(r,s)); }
   double LowerWick(const MqlRates &r[], int s)   const { return MathMin(CandleOpen(r,s), CandleClose(r,s)) - CandleLow(r,s); }
   bool   IsBullish(const MqlRates &r[], int s)   const { return CandleClose(r,s) > CandleOpen(r,s); }
   bool   IsBearish(const MqlRates &r[], int s)   const { return CandleClose(r,s) < CandleOpen(r,s); }
   bool   IsInsideBar(const MqlRates &r[], int s) const { return CandleHigh(r,s) < CandleHigh(r,s+1) && CandleLow(r,s) > CandleLow(r,s+1); }

   double NormalizeATRFactor(const double value, const double atrPoints) const
     {
      double atrPrice = atrPoints * _Point;
      return (atrPrice <= 0.0) ? 0.0 : value / atrPrice;
     }

   void AddStrengthFromRejection(const MqlRates &r[], int s, double atr, int dir, double &score)
     {
      double range = CandleRange(r, s);
      if(range <= 0.0) return;
      double wick = (dir == 1) ? LowerWick(r, s) : UpperWick(r, s);
      double wickPct = wick / range;
      double bodyPct = CandleBody(r, s) / range;
      double atrFactor = NormalizeATRFactor(range, atr);
      if(wickPct >= 0.50) score += 0.20;
      if(wickPct >= 0.60) score += 0.10;
      if(bodyPct <= 0.35) score += 0.10;
      if(atrFactor >= 0.60) score += 0.10;
     }

   void AddStrengthFromFollowThrough(const MqlRates &r[], int s, int dir, double &score)
     {
      double prevClose = CandleClose(r, s + 1);
      double curClose = CandleClose(r, s);
      if(dir == 1 && curClose > prevClose) score += 0.10;
      if(dir == -1 && curClose < prevClose) score += 0.10;
     }

   double CalculateRegimeWeight(const EMarketRegime regime, ENUM_PATTERN_TYPE pattern, int dir) const
     {
      double weight = 1.0;
      if(regime == REGIME_RANGE || regime == REGIME_TRANSITION)
        {
         if(pattern == PATTERN_PINBAR || pattern == PATTERN_ENGULFING || pattern == PATTERN_FAKEY)
            weight += m_regimeBoostFactor;
        }
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN)
        {
         if(pattern == PATTERN_INSIDE_BAR_BREAKOUT) weight += m_regimeBoostFactor;
         if((regime == REGIME_TREND_UP && dir == 1) || (regime == REGIME_TREND_DOWN && dir == -1))
            weight += m_regimeBoostFactor * 0.5;
        }
      if(regime == REGIME_VOLATILE || regime == REGIME_CRASH) weight -= 0.15;
      return MathMax(0.5, weight);
     }

   void StorePatternHistory(const SPatternResult &result)
     {
      if(m_patternHistory.Total() >= 200) m_patternHistory.Delete(0);
      CPatternRecord *rec = new CPatternRecord(result);
      if(rec != NULL) m_patternHistory.Add(rec);
     }

   void EvaluatePinbar(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      double range = CandleRange(r, s);
      if(range <= 0.0) return;
      double bodyMid = (CandleOpen(r, s) + CandleClose(r, s)) / 2.0;
      double upper = UpperWick(r, s);
      double lower = LowerWick(r, s);
      int dir = 0;
      double extreme = 0.0;
      if(CandleClose(r, s) > bodyMid && lower > (upper > 0.0 ? upper * 2.0 : _Point)) { dir = 1; extreme = CandleLow(r, s); }
      else if(CandleClose(r, s) < bodyMid && upper > (lower > 0.0 ? lower * 2.0 : _Point)) { dir = -1; extreme = CandleHigh(r, s); }
      else return;
      vote.valid = true; vote.type = PATTERN_PINBAR; vote.dir = dir; vote.extreme = extreme;
      vote.score = 1.0; vote.label = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";
      AddStrengthFromRejection(r, s, atr, dir, vote.score);
      AddStrengthFromFollowThrough(r, s, dir, vote.score);
     }

   void EvaluateEngulfing(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      double o1 = CandleOpen(r, s), c1 = CandleClose(r, s);
      double o2 = CandleOpen(r, s + 1), c2 = CandleClose(r, s + 1);
      bool prevBear = (c2 < o2), prevBull = (c2 > o2);
      int dir = 0;
      double extreme = 0.0, score = 1.0;
      if(prevBear && c1 > o1 && c1 > o2 && o1 < c2) { dir = 1; extreme = CandleLow(r, s); }
      else if(prevBull && c1 < o1 && c1 < o2 && o1 > c2) { dir = -1; extreme = CandleHigh(r, s); }
      else return;
      double b1 = CandleBody(r, s), b2 = CandleBody(r, s + 1);
      if(b2 > 0.0 && b1 >= b2 * 1.20) score += 0.20;
      if(NormalizeATRFactor(CandleRange(r, s), atr) >= 0.70) score += 0.15;
      vote.valid = true; vote.type = PATTERN_ENGULFING; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.label = (dir == 1) ? "Engulf Bull" : "Engulf Bear";
      AddStrengthFromFollowThrough(r, s, dir, vote.score);
     }

   void EvaluateTweezer(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      double h1 = CandleHigh(r, s), l1 = CandleLow(r, s);
      double h2 = CandleHigh(r, s + 1), l2 = CandleLow(r, s + 1);
      double tol = MathMax(atr * 0.10 * _Point, 3.0 * _Point);
      int dir = 0;
      double extreme = 0.0, score = 1.0;
      if(MathAbs(l1 - l2) <= tol && IsBullish(r, s)) { dir = 1; extreme = MathMin(l1, l2); }
      else if(MathAbs(h1 - h2) <= tol && IsBearish(r, s)) { dir = -1; extreme = MathMax(h1, h2); }
      else return;
      if(NormalizeATRFactor(CandleRange(r, s), atr) >= 0.50) score += 0.10;
      if(CandleBody(r, s) / MathMax(CandleRange(r, s), _Point) >= 0.35) score += 0.10;
      vote.valid = true; vote.type = PATTERN_BOTTOM; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.label = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
     }

   void EvaluateFakey(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      double h0 = CandleHigh(r, s), l0 = CandleLow(r, s), c0 = CandleClose(r, s), o0 = CandleOpen(r, s);
      double h1 = CandleHigh(r, s + 1), l1 = CandleLow(r, s + 1), h2 = CandleHigh(r, s + 2), l2 = CandleLow(r, s + 2);
      if(!(h1 < h2 && l1 > l2)) return;
      int dir = 0;
      double extreme = 0.0, score = 1.0;
      if(l0 < l1 && c0 > l1 && c0 > o0) { dir = 1; extreme = l0; }
      else if(h0 > h1 && c0 < h1 && c0 < o0) { dir = -1; extreme = h0; }
      else return;
      if(NormalizeATRFactor(CandleRange(r, s), atr) >= 0.60) score += 0.15;
      if(CandleBody(r, s) / MathMax(CandleRange(r, s), _Point) >= 0.40) score += 0.10;
      vote.valid = true; vote.type = PATTERN_FAKEY; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.label = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
     }

   void EvaluateInsideBar(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      if(!IsInsideBar(r, s)) return;
      double motherHigh = CandleHigh(r, s + 1), motherLow = CandleLow(r, s + 1);
      double mid = (motherHigh + motherLow) / 2.0;
      double close = CandleClose(r, s);
      int dir = 0;
      double extreme = 0.0, score = 1.0;
      if(close > mid) { dir = 1; extreme = CandleLow(r, s); }
      else if(close < mid) { dir = -1; extreme = CandleHigh(r, s); }
      else return;
      double motherRange = CandleRange(r, s + 1), childRange = CandleRange(r, s);
      if(motherRange > 0.0 && childRange / motherRange <= 0.65) score += 0.15;
      if(NormalizeATRFactor(motherRange, atr) >= 0.70) score += 0.10;
      vote.valid = true; vote.type = PATTERN_INSIDE_BAR_BREAKOUT; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.label = (dir == 1) ? "Inside Bull" : "Inside Bear";
     }

public:
   CPatternManager()
      : IManager(), m_lastScanBarTime(0), m_totalPatternsDetected(0),
        m_totalValidSignals(0), m_minConfluenceScore(1.60),
        m_minDominanceGap(0.35), m_regimeBoostFactor(0.20)
     {
      m_lastResult.Clear();
     }

   ~CPatternManager() { m_patternHistory.Clear(); }

   virtual string HandlerName() const override { return "PatternManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_patternHistory.Clear();
      m_lastResult.Clear();
      m_lastScanBarTime = 0;
      m_totalPatternsDetected = 0;
      m_totalValidSignals = 0;
      Print("[PatternManager] v2.04 Init OK");
      return true;
     }

   virtual void Deinit() override
     {
      m_patternHistory.Clear();
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_NEW_BAR:
            m_lastScanBarTime = 0;
            if(m_cfgDirty && m_data != NULL) RefreshConfig();
            break;
         case EVENT_ID_CONFIG_RELOAD:
            m_cfgDirty = true;
            break;
         default:
            break;
        }
     }

   bool Detect(const MqlRates &rates[], const int shift, const double atrPoints,
               const EMarketRegime currentRegime, SPatternResult &outResult)
     {
      outResult.Clear();
      if(shift < 1 || atrPoints <= 0.0) { outResult.reason = "Invalid shift/ATR"; return false; }
      if(shift + 2 >= ArraySize(rates)) { outResult.reason = "Insufficient bars"; return false; }

      datetime curTime = rates[shift].time;
      if(curTime == m_lastScanBarTime && m_lastResult.found) { outResult = m_lastResult; return outResult.found; }

      SPatternVote votes[5];
      for(int i = 0; i < 5; i++) votes[i].Reset();
      EvaluatePinbar(rates, shift, atrPoints, votes[0]);
      EvaluateEngulfing(rates, shift, atrPoints, votes[1]);
      EvaluateTweezer(rates, shift, atrPoints, votes[2]);
      EvaluateFakey(rates, shift, atrPoints, votes[3]);
      EvaluateInsideBar(rates, shift, atrPoints, votes[4]);

      for(int i = 0; i < 5; i++)
         if(votes[i].valid) votes[i].regimeWeight = CalculateRegimeWeight(currentRegime, votes[i].type, votes[i].dir);

      double buyScore = 0.0, sellScore = 0.0;
      for(int i = 0; i < 5; i++)
        {
         if(!votes[i].valid) continue;
         double score = votes[i].TotalScore();
         if(votes[i].dir == 1) buyScore += score;
         else if(votes[i].dir == -1) sellScore += score;
        }

      double totalScore = MathMax(buyScore, sellScore);
      double conflictScore = MathMin(buyScore, sellScore);
      double dominanceGap = totalScore - conflictScore;

      m_totalPatternsDetected++;
      m_lastScanBarTime = curTime;

      if(totalScore < m_minConfluenceScore)
        {
         outResult.reason = StringFormat("Confluence weak | buy=%.2f sell=%.2f", buyScore, sellScore);
         m_lastResult = outResult;
         return false;
        }
      if(dominanceGap < m_minDominanceGap)
        {
         outResult.reason = StringFormat("Confluence conflict | buy=%.2f sell=%.2f", buyScore, sellScore);
         m_lastResult = outResult;
         return false;
        }

      int direction = (buyScore > sellScore) ? 1 : -1;
      int bestIdx = FindBestVote(votes, direction);
      if(bestIdx < 0)
        {
         outResult.reason = "No dominant pattern";
         m_lastResult = outResult;
         return false;
        }

      outResult.found = true;
      outResult.type = votes[bestIdx].type;
      outResult.direction = direction;
      outResult.extreme = votes[bestIdx].extreme;
      outResult.confluenceScore = totalScore;
      outResult.barTime = curTime;
      outResult.reason = votes[bestIdx].label + StringFormat(" | Confluence %.2f | %s",
                         totalScore, BuildConfluenceLabel(votes, direction));

      m_lastResult = outResult;
      m_totalValidSignals++;
      StorePatternHistory(outResult);
      return true;
     }

   bool Detect(const MqlRates &rates[], const int shift, const double atrPoints,
               ENUM_PATTERN_TYPE &outType, int &outDir, double &outPrice, string &outReason)
     {
      SPatternResult result;
      bool found = Detect(rates, shift, atrPoints, REGIME_RANGE, result);
      outType = result.type;
      outDir = result.direction;
      outPrice = result.extreme;
      outReason = result.reason;
      return found;
     }

   int GetTotalDetected() const { return m_totalPatternsDetected; }
   int GetTotalValidSignals() const { return m_totalValidSignals; }
   double GetSuccessRate() const
     {
      if(m_totalPatternsDetected == 0) return 0.0;
      return (double)m_totalValidSignals / (double)m_totalPatternsDetected * 100.0;
     }
   const SPatternResult& GetLastResult() const { return m_lastResult; }
   int GetHistoryCount() const { return m_patternHistory.Total(); }
   bool GetHistoryAt(int idx, SPatternResult &out) const
     {
      if(idx < 0 || idx >= m_patternHistory.Total()) return false;
      CPatternRecord *rec = (CPatternRecord*)m_patternHistory.At(idx);
      if(rec == NULL) return false;
      out = rec.data;
      return true;
     }
  };

#endif // __PATTERN_MANAGER_MQH__
