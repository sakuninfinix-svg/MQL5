//+------------------------------------------------------------------+
//| Analysis/Pattern/PatternManager.mqh — v1.0                       |
//| Copyright 2026                                                   |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

#include "../../Core/IManager.mqh"
#include "../../Data/RegimeTypes.mqh"
#include "../MarketRegimeDetector.mqh"
#include "../../Analysis/CNNPatternRecognizer.mqh"
#include "PatternTypes.mqh"

#define PATTERN_HISTORY_CAPACITY 200
#define PATTERN_TRAINABLE_COUNT 5
#define PATTERN_FEATURE_COUNT 5
#define PATTERN_WEIGHT_FILE "PASR_pattern_weights.bin"
#define PATTERN_WEIGHT_MAGIC 20260608.0
#define PATTERN_WEIGHT_VERSION 1.0

#define PATTERN_IDX_PINBAR   0
#define PATTERN_IDX_ENGULF   1
#define PATTERN_IDX_TWEEZER  2
#define PATTERN_IDX_FAKEY    3
#define PATTERN_IDX_INSIDE   4

struct SPatternFeatureSnapshot
  {
   double buyProb;
   double sellProb;
   double conflict;
   double dominanceGap;
   double rejectionQuality;
   double trapQuality;
   double reclaimQuality;
   double followThrough;

   void Clear()
     {
      buyProb = 0.0;
      sellProb = 0.0;
      conflict = 0.0;
      dominanceGap = 0.0;
      rejectionQuality = 0.0;
      trapQuality = 0.0;
      reclaimQuality = 0.0;
      followThrough = 0.0;
     }
  };

struct SPatternVote
  {
   bool              valid;
   ENUM_PATTERN_TYPE type;
   int               dir;
   double            extreme;
   double            score;
   double            regimeWeight;
   double            rejectionQuality;
   double            trapQuality;
   double            reclaimQuality;
   double            followThrough;
   string            label;

   void Reset()
     {
      valid = false;
      type = PATTERN_NONE;
      dir = 0;
      extreme = 0.0;
      score = 0.0;
      regimeWeight = 1.0;
      rejectionQuality = 0.0;
      trapQuality = 0.0;
      reclaimQuality = 0.0;
      followThrough = 0.0;
      label = "";
     }

   double TotalScore() const
     {
      return MathMax(0.0, MathMin(0.99, score * MathMax(0.30, MathMin(1.50, regimeWeight))));
     }
  };

struct SPatternResult
  {
   bool              found;
   ENUM_PATTERN_TYPE type;
   int               direction;
   double            extreme;
   double            confluenceScore;
   double            conflictScore;
   double            dominanceGap;
   string            reason;
   datetime          barTime;

   void Clear()
     {
      found = false;
      type = PATTERN_NONE;
      direction = 0;
      extreme = 0.0;
      confluenceScore = 0.0;
      conflictScore = 0.0;
      dominanceGap = 0.0;
      reason = "";
      barTime = 0;
     }
  };

class CPatternManager : public IManager
  {
private:
   SPatternResult m_history[PATTERN_HISTORY_CAPACITY];
   int            m_historyHead;
   int            m_historyCount;
   SPatternResult m_lastResult;
   SPatternFeatureSnapshot m_lastFeatures;
   datetime       m_lastScanBarTime;
   int            m_totalPatternsDetected;
   int            m_totalValidSignals;
   double         m_minConfluenceScore;
   double         m_minDominanceGap;
   double         m_regimeBoostFactor;
   double         m_pinBarRatio;
   double         m_engulfMultiplier;
   bool           m_requireConfirmation;
   bool           m_externalWeightsLoaded;
   string         m_weightsFile;
   CCNNPatternRecognizer *m_cnnRecognizer;
   double         m_cnnWeight;

   double         m_bias[PATTERN_TRAINABLE_COUNT];
   double         m_w[PATTERN_TRAINABLE_COUNT][PATTERN_FEATURE_COUNT];

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }
   double SafeDiv(double a, double b) const { return (MathAbs(b) <= DBL_EPSILON) ? 0.0 : a / b; }
   double Sigmoid(double x) const { return 1.0 / (1.0 + MathExp(-x)); }

   void SetPatternWeights(int idx, double bias, double w0, double w1, double w2, double w3, double w4)
     {
      if(idx < 0 || idx >= PATTERN_TRAINABLE_COUNT) return;
      m_bias[idx] = bias;
      m_w[idx][0] = w0;
      m_w[idx][1] = w1;
      m_w[idx][2] = w2;
      m_w[idx][3] = w3;
      m_w[idx][4] = w4;
     }

   void InitDefaultWeights()
     {
      // Nilai default ini mereproduksi skor gaya regresi manual sebelumnya.
      SetPatternWeights(PATTERN_IDX_PINBAR,  -2.20, 2.80, 1.30, 1.00, 0.70, 1.10); // wick, smallBody, atr, follow, protrusion
      SetPatternWeights(PATTERN_IDX_ENGULF,  -2.05, 2.20, 1.25, 1.25, 0.80, 1.15); // bodyRatio, closePower, atr, follow, volSurge
      SetPatternWeights(PATTERN_IDX_TWEEZER, -2.10, 2.60, 1.40, 1.00, 0.65, 0.95); // equality, body, atr, follow, wickPct
      SetPatternWeights(PATTERN_IDX_FAKEY,   -2.00, 2.00, 1.65, 1.15, 0.90, 0.85); // trap, reclaim, body, atr, follow
      SetPatternWeights(PATTERN_IDX_INSIDE,  -2.15, 2.40, 1.55, 1.20, 0.55, 1.05); // compression, closeBias, motherATR, follow, volDecline
      m_externalWeightsLoaded = false;
      m_weightsFile = "";
     }

   double ScorePattern(const int idx, const double f0, const double f1, const double f2, const double f3, const double f4 = 0.0) const
     {
      if(idx < 0 || idx >= PATTERN_TRAINABLE_COUNT) return 0.0;
      double z = m_bias[idx] + m_w[idx][0] * f0 + m_w[idx][1] * f1 + m_w[idx][2] * f2 + m_w[idx][3] * f3 + m_w[idx][4] * f4;
      return Clamp01(Sigmoid(z));
     }

   bool ReadFloatChecked(const int handle, double &outValue)
     {
      if(FileIsEnding(handle)) return false;
      outValue = (double)FileReadFloat(handle);
      return true;
     }

   bool LoadPatternWeights(const string filename)
     {
      int handle = FileOpen(filename, FILE_READ | FILE_BIN);
      if(handle == INVALID_HANDLE)
         return false;

      double magic = 0.0, version = 0.0, nPatterns = 0.0, nFeatures = 0.0;
      bool ok = ReadFloatChecked(handle, magic) && ReadFloatChecked(handle, version) &&
                ReadFloatChecked(handle, nPatterns) && ReadFloatChecked(handle, nFeatures);
      if(!ok || MathRound(magic) != (int)PATTERN_WEIGHT_MAGIC ||
         (int)MathRound(nPatterns) != PATTERN_TRAINABLE_COUNT ||
         (int)MathRound(nFeatures) != PATTERN_FEATURE_COUNT)
        {
         FileClose(handle);
         PrintFormat("[PatternManager] header bobot pola tidak valid di '%s'", filename);
         return false;
        }

      double bias = 0.0, w0 = 0.0, w1 = 0.0, w2 = 0.0, w3 = 0.0, w4 = 0.0;
      for(int p = 0; p < PATTERN_TRAINABLE_COUNT && ok; p++)
        {
         ok = ReadFloatChecked(handle, bias) && ReadFloatChecked(handle, w0) && ReadFloatChecked(handle, w1) &&
              ReadFloatChecked(handle, w2) && ReadFloatChecked(handle, w3) && ReadFloatChecked(handle, w4);
         if(ok) SetPatternWeights(p, bias, w0, w1, w2, w3, w4);
        }
      FileClose(handle);
      if(!ok)
        {
         PrintFormat("[PatternManager] bobot pola terpotong di '%s'; menggunakan nilai default", filename);
         InitDefaultWeights();
         return false;
        }
      m_externalWeightsLoaded = true;
      m_weightsFile = filename;
      PrintFormat("[PatternManager] berhasil memuat bobot pola yang dapat dilatih dari '%s'", filename);
      return true;
     }

   void ApplyConfig()
     {
      m_pinBarRatio = MathMax(1.0, m_cfg.Pattern.PinBarRatio);
      m_engulfMultiplier = MathMax(0.1, m_cfg.Pattern.EngulfMultiplier);
      m_requireConfirmation = m_cfg.Pattern.RequireConfirmation;
      if(!m_cfg.Pattern.EnablePatterns)
        {
         m_minConfluenceScore = 2.0;
         return;
        }
      m_minConfluenceScore = Clamp01(m_cfg.Pattern.MinPatternScore / 100.0);
      m_minDominanceGap = Clamp01(m_cfg.Pattern.MinDominanceGap);
     }

   void ClearHistory()
     {
      for(int i = 0; i < PATTERN_HISTORY_CAPACITY; i++)
         m_history[i].Clear();
      m_historyHead = 0;
      m_historyCount = 0;
     }

   int HistoryPhysicalIndex(int newestOffset) const
     {
      if(newestOffset < 0 || newestOffset >= m_historyCount) return -1;
      return (m_historyHead - 1 - newestOffset + PATTERN_HISTORY_CAPACITY) % PATTERN_HISTORY_CAPACITY;
     }

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
         txt += StringFormat("%s:%.2f", votes[i].label, votes[i].TotalScore());
        }
      return txt;
     }

   double AggregateProbability(const SPatternVote &votes[], int dir) const
     {
      double survive = 1.0;
      for(int i = 0; i < ArraySize(votes); i++)
        {
         if(!votes[i].valid || votes[i].dir != dir) continue;
         double p = votes[i].TotalScore();
         survive *= (1.0 - p);
        }
      return Clamp01(1.0 - survive);
     }

   double AggregateFeature(const SPatternVote &votes[], int dir, int featureId) const
     {
      double weighted = 0.0;
      double total = 0.0;
      for(int i = 0; i < ArraySize(votes); i++)
        {
         if(!votes[i].valid || votes[i].dir != dir) continue;
         double w = votes[i].TotalScore();
         double v = 0.0;
         if(featureId == 0)      v = votes[i].rejectionQuality;
         else if(featureId == 1) v = votes[i].trapQuality;
         else if(featureId == 2) v = votes[i].reclaimQuality;
         else if(featureId == 3) v = votes[i].followThrough;
         weighted += v * w;
         total += w;
        }
      return (total > 0.0) ? Clamp01(weighted / total) : 0.0;
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
      return Clamp01((atrPrice <= 0.0) ? 0.0 : value / atrPrice);
     }

   double FollowThroughScore(const MqlRates &r[], int s, int dir) const
     {
      double prevClose = CandleClose(r, s + 1);
      double curClose = CandleClose(r, s);
      if(dir == 1)  return Clamp01(SafeDiv(curClose - prevClose, MathMax(CandleRange(r, s), _Point)) + 0.5);
      if(dir == -1) return Clamp01(SafeDiv(prevClose - curClose, MathMax(CandleRange(r, s), _Point)) + 0.5);
      return 0.5;
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
      return MathMax(0.50, MathMin(1.40, weight));
     }

   void StorePatternHistory(const SPatternResult &result)
     {
      m_history[m_historyHead] = result;
      m_historyHead = (m_historyHead + 1) % PATTERN_HISTORY_CAPACITY;
      if(m_historyCount < PATTERN_HISTORY_CAPACITY) m_historyCount++;
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
      if(CandleClose(r, s) > bodyMid && lower > (upper > 0.0 ? upper * m_pinBarRatio : _Point * m_pinBarRatio)) { dir = 1; extreme = CandleLow(r, s); }
      else if(CandleClose(r, s) < bodyMid && upper > (lower > 0.0 ? lower * m_pinBarRatio : _Point * m_pinBarRatio)) { dir = -1; extreme = CandleHigh(r, s); }
      else return;

      double wickPct = Clamp01(((dir == 1) ? lower : upper) / range);
      double smallBody = Clamp01(1.0 - CandleBody(r, s) / range);
      double atrQuality = NormalizeATRFactor(range, atr);
      double follow = FollowThroughScore(r, s, dir);
      double protrusion = (dir == 1) ? SafeDiv(r[s+1].low - r[s].low, atr * _Point)
                                     : SafeDiv(r[s].high - r[s+1].high, atr * _Point);
      double score = ScorePattern(PATTERN_IDX_PINBAR, wickPct, smallBody, atrQuality, follow, Clamp01(protrusion));

      vote.valid = true; vote.type = PATTERN_PINBAR; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.rejectionQuality = wickPct; vote.trapQuality = 0.0;
      vote.reclaimQuality = Clamp01((dir == 1) ? SafeDiv(CandleClose(r,s) - bodyMid, MathMax(range * 0.5, _Point))
                                               : SafeDiv(bodyMid - CandleClose(r,s), MathMax(range * 0.5, _Point)));
      vote.followThrough = follow; vote.label = (dir == 1) ? "Pinbar Bullish" : "Pinbar Bearish";
      vote.trapQuality = Clamp01(protrusion); // Simpan ke trapQuality agar muncul di log/UI sebagai "trap"
     }

   void EvaluateEngulfing(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      double o1 = CandleOpen(r, s), c1 = CandleClose(r, s);
      double o2 = CandleOpen(r, s + 1), c2 = CandleClose(r, s + 1);
      bool prevBear = (c2 < o2), prevBull = (c2 > o2);
      int dir = 0;
      double extreme = 0.0;
      if(prevBear && c1 > o1 && c1 > o2 && o1 < c2) { dir = 1; extreme = CandleLow(r, s); }
      else if(prevBull && c1 < o1 && c1 < o2 && o1 > c2) { dir = -1; extreme = CandleHigh(r, s); }
      else return;

      double b1 = CandleBody(r, s), b2 = CandleBody(r, s + 1);
      double bodyRatio = Clamp01(b2 > 0.0 ? b1 / (b2 * MathMax(0.1, m_engulfMultiplier)) : 0.0);
      double atrQuality = NormalizeATRFactor(CandleRange(r, s), atr);
      double closePower = (dir == 1) ? SafeDiv(c1 - CandleLow(r, s), MathMax(CandleRange(r, s), _Point))
                                     : SafeDiv(CandleHigh(r, s) - c1, MathMax(CandleRange(r, s), _Point));
      double follow = FollowThroughScore(r, s, dir);
      double volSurge = Clamp01(SafeDiv((double)r[s].tick_volume, (double)r[s+1].tick_volume * 1.5));
      double score = ScorePattern(PATTERN_IDX_ENGULF, bodyRatio, Clamp01(closePower), atrQuality, follow, volSurge);

      vote.valid = true; vote.type = PATTERN_ENGULFING; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.rejectionQuality = bodyRatio; vote.trapQuality = volSurge;
      vote.reclaimQuality = Clamp01(closePower); vote.followThrough = follow;
      vote.label = (dir == 1) ? "Engulfing Bullish" : "Engulfing Bearish";
     }

   void EvaluateTweezer(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      double h1 = CandleHigh(r, s), l1 = CandleLow(r, s);
      double h2 = CandleHigh(r, s + 1), l2 = CandleLow(r, s + 1);
      double tol = MathMax(atr * 0.10 * _Point, 3.0 * _Point);
      int dir = 0;
      double extreme = 0.0, distance = 0.0;
      if(MathAbs(l1 - l2) <= tol && IsBullish(r, s)) { dir = 1; extreme = MathMin(l1, l2); distance = MathAbs(l1 - l2); }
      else if(MathAbs(h1 - h2) <= tol && IsBearish(r, s)) { dir = -1; extreme = MathMax(h1, h2); distance = MathAbs(h1 - h2); }
      else return;

      double equality = Clamp01(1.0 - distance / MathMax(tol, _Point));
      double bodyPct = Clamp01(CandleBody(r, s) / MathMax(CandleRange(r, s), _Point));
      double atrQuality = NormalizeATRFactor(CandleRange(r, s), atr);
      double follow = FollowThroughScore(r, s, dir);
      double wickPct = Clamp01(((dir == 1) ? LowerWick(r, s) : UpperWick(r, s)) / MathMax(CandleRange(r, s), _Point));
      double score = ScorePattern(PATTERN_IDX_TWEEZER, equality, bodyPct, atrQuality, follow, wickPct);

      vote.valid = true; vote.type = PATTERN_BOTTOM; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.rejectionQuality = equality; vote.trapQuality = wickPct;
      vote.reclaimQuality = bodyPct; vote.followThrough = follow;
      vote.label = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
     }

   void EvaluateFakey(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      double h0 = CandleHigh(r, s), l0 = CandleLow(r, s), c0 = CandleClose(r, s), o0 = CandleOpen(r, s);
      double h1 = CandleHigh(r, s + 1), l1 = CandleLow(r, s + 1), h2 = CandleHigh(r, s + 2), l2 = CandleLow(r, s + 2);
      if(!(h1 < h2 && l1 > l2)) return;
      int dir = 0;
      double extreme = 0.0, trapDepth = 0.0;
      if(l0 < l1 && c0 > l1 && c0 > o0) { dir = 1; extreme = l0; trapDepth = l1 - l0; }
      else if(h0 > h1 && c0 < h1 && c0 < o0) { dir = -1; extreme = h0; trapDepth = h0 - h1; }
      else return;

      double insideRange = MathMax(h1 - l1, _Point);
      double trapQuality = Clamp01(trapDepth / insideRange);
      double reclaimQuality = (dir == 1) ? Clamp01((c0 - l1) / insideRange) : Clamp01((h1 - c0) / insideRange);
      double atrQuality = NormalizeATRFactor(CandleRange(r, s), atr);
      double bodyPct = Clamp01(CandleBody(r, s) / MathMax(CandleRange(r, s), _Point));
      double follow = FollowThroughScore(r, s, dir);
      double score = ScorePattern(PATTERN_IDX_FAKEY, trapQuality, reclaimQuality, bodyPct, atrQuality, follow);

      vote.valid = true; vote.type = PATTERN_FAKEY; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.rejectionQuality = bodyPct; vote.trapQuality = trapQuality;
      vote.reclaimQuality = reclaimQuality; vote.followThrough = FollowThroughScore(r, s, dir);
      vote.label = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
     }

   void EvaluateInsideBar(const MqlRates &r[], int s, double atr, SPatternVote &vote)
     {
      if(!IsInsideBar(r, s)) return;
      double motherHigh = CandleHigh(r, s + 1), motherLow = CandleLow(r, s + 1);
      double motherRange = MathMax(motherHigh - motherLow, _Point);
      double childRange = CandleRange(r, s);
      double mid = (motherHigh + motherLow) / 2.0;
      double close = CandleClose(r, s);
      int dir = 0;
      double extreme = 0.0;
      if(close > mid) { dir = 1; extreme = CandleLow(r, s); }
      else if(close < mid) { dir = -1; extreme = CandleHigh(r, s); }
      else return;

      double compression = Clamp01(1.0 - childRange / motherRange);
      double closeBias = (dir == 1) ? Clamp01((close - mid) / (motherRange * 0.5)) : Clamp01((mid - close) / (motherRange * 0.5));
      double motherATR = NormalizeATRFactor(motherRange, atr);
      double follow = FollowThroughScore(r, s, dir);
      double volDecline = Clamp01(SafeDiv((double)r[s+1].tick_volume - (double)r[s].tick_volume, (double)r[s+1].tick_volume));
      double score = ScorePattern(PATTERN_IDX_INSIDE, compression, closeBias, motherATR, follow, volDecline);

      vote.valid = true; vote.type = PATTERN_INSIDE_BAR_BREAKOUT; vote.dir = dir; vote.extreme = extreme;
      vote.score = score; vote.rejectionQuality = compression; vote.trapQuality = volDecline;
      vote.reclaimQuality = closeBias; vote.followThrough = follow;
      vote.label = (dir == 1) ? "Inside Bar Bullish" : "Inside Bar Bearish";
     }

public:
   CPatternManager()
      : IManager(), m_historyHead(0), m_historyCount(0),
        m_lastScanBarTime(0), m_totalPatternsDetected(0), m_totalValidSignals(0),
        m_minConfluenceScore(0.40), m_minDominanceGap(0.05), m_regimeBoostFactor(0.20),
        m_pinBarRatio(2.0), m_engulfMultiplier(1.1), m_requireConfirmation(true),
        m_externalWeightsLoaded(false), m_weightsFile(""),
        m_cnnRecognizer(NULL), m_cnnWeight(0.25)
     {
      InitDefaultWeights();
      ClearHistory();
      m_lastResult.Clear();
      m_lastFeatures.Clear();
     }

   ~CPatternManager() {}

   void SetCNNPatternRecognizer(CCNNPatternRecognizer *recognizer, double weight = 0.25)
     {
      m_cnnRecognizer = recognizer;
      m_cnnWeight = MathMax(0.0, MathMin(1.0, weight));
     }

   virtual string HandlerName() const override { return "PatternManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      InitDefaultWeights();
      LoadPatternWeights(PATTERN_WEIGHT_FILE);
      ApplyConfig();
      ClearHistory();
      m_lastResult.Clear();
      m_lastFeatures.Clear();
      m_lastScanBarTime = 0;
      m_totalPatternsDetected = 0;
      m_totalValidSignals = 0;
      PrintFormat("[PatternManager] v3.30 Inisialisasi OK bobot_latih=%s", m_externalWeightsLoaded ? "true" : "false");
      return true;
     }

   virtual void Deinit() override
     {
      ClearHistory();
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
            if(m_cfgDirty && m_data != NULL)
              {
               RefreshConfig();
               ApplyConfig();
              }
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
      m_lastFeatures.Clear();
      int scanShift = shift;
      if(m_requireConfirmation && scanShift < 1) scanShift = 1;
      if(scanShift < 0 || atrPoints <= 0.0) { outResult.reason = "Shift/ATR tidak valid"; return false; }
      if(scanShift + 2 >= ArraySize(rates)) { outResult.reason = "Bar tidak mencukupi"; return false; }

      datetime curTime = rates[scanShift].time;
      if(curTime == m_lastScanBarTime)
        {
         outResult = m_lastResult;
         return outResult.found;
        }

      SPatternVote votes[5];
      for(int i = 0; i < 5; i++) votes[i].Reset();
      EvaluatePinbar(rates, scanShift, atrPoints, votes[0]);
      EvaluateEngulfing(rates, scanShift, atrPoints, votes[1]);
      EvaluateTweezer(rates, scanShift, atrPoints, votes[2]);
      EvaluateFakey(rates, scanShift, atrPoints, votes[3]);
      EvaluateInsideBar(rates, scanShift, atrPoints, votes[4]);

      // Augmentasi pengenalan pola CNN opsional
      double cnnBuyScore = 0.0;
      double cnnSellScore = 0.0;
      if(m_cnnRecognizer != NULL && m_cnnRecognizer.IsBufferFilled())
        {
         CNNPatternOutput cnnOutput;
         if(m_cnnRecognizer.RecognizePattern(rates, scanShift, cnnOutput) && cnnOutput.confidence > 0.5)
           {
            ENUM_PATTERN_TYPE cnnPattern = m_cnnRecognizer.GetPatternType(cnnOutput.dominant_pattern);
            if(cnnPattern != PATTERN_NONE)
              {
               // Memetakan pola CNN ke arah pergerakan
               int cnnDir = (cnnPattern == PATTERN_PINBAR || cnnPattern == PATTERN_ENGULFING ||
                             cnnPattern == PATTERN_INSIDE_BAR_BREAKOUT) ? 1 : -1;
               // Untuk bottom/tweezer, periksa apakah bullish atau bearish berdasarkan pola dominan
               // Untuk penyederhanaan, gunakan tingkat kepercayaan pola sebagai pengubah skor
               if(cnnDir == 1)
                 cnnBuyScore = cnnOutput.confidence;
               else
                 cnnSellScore = cnnOutput.confidence;
              }
           }
        }

      for(int i = 0; i < 5; i++)
         if(votes[i].valid) votes[i].regimeWeight = CalculateRegimeWeight(currentRegime, votes[i].type, votes[i].dir);

      int validVotes = 0;
      for(int i = 0; i < 5; i++) if(votes[i].valid) validVotes++;

      double buyScore = AggregateProbability(votes, 1);
      double sellScore = AggregateProbability(votes, -1);

      // Campurkan skor CNN dengan skor berbasis aturan
      if(cnnBuyScore > 0.0 || cnnSellScore > 0.0)
        {
         buyScore = Clamp01(buyScore * (1.0 - m_cnnWeight) + cnnBuyScore * m_cnnWeight);
         sellScore = Clamp01(sellScore * (1.0 - m_cnnWeight) + cnnSellScore * m_cnnWeight);
        }
      double totalScore = MathMax(buyScore, sellScore);
      double conflictScore = MathMin(buyScore, sellScore);
      double dominanceGap = totalScore - conflictScore;
      double finalScore = Clamp01(totalScore * (1.0 - conflictScore * 0.50));
      int featureDir = (buyScore >= sellScore) ? 1 : -1;

      m_lastFeatures.buyProb = buyScore;
      m_lastFeatures.sellProb = sellScore;
      m_lastFeatures.conflict = conflictScore;
      m_lastFeatures.dominanceGap = dominanceGap;
      m_lastFeatures.rejectionQuality = AggregateFeature(votes, featureDir, 0);
      m_lastFeatures.trapQuality = AggregateFeature(votes, featureDir, 1);
      m_lastFeatures.reclaimQuality = AggregateFeature(votes, featureDir, 2);
      m_lastFeatures.followThrough = AggregateFeature(votes, featureDir, 3);

      if(validVotes > 0) m_totalPatternsDetected++;
      m_lastScanBarTime = curTime;

      if(finalScore < m_minConfluenceScore)
        {
         outResult.reason = StringFormat("Regresi pola lemah | beli=%.2f jual=%.2f akhir=%.2f", buyScore, sellScore, finalScore);
         m_lastResult = outResult;
         return false;
        }
      if(dominanceGap < m_minDominanceGap)
        {
         outResult.reason = StringFormat("Konflik regresi pola | beli=%.2f jual=%.2f selisih=%.2f", buyScore, sellScore, dominanceGap);
         m_lastResult = outResult;
         return false;
        }

      int direction = (buyScore > sellScore) ? 1 : -1;
      int bestIdx = FindBestVote(votes, direction);
      if(bestIdx < 0)
        {
         outResult.reason = "Tidak ada pola dominan";
         m_lastResult = outResult;
         return false;
        }

      outResult.found = true;
      outResult.type = votes[bestIdx].type;
      outResult.direction = direction;
      outResult.extreme = votes[bestIdx].extreme;
      outResult.confluenceScore = finalScore;
      outResult.conflictScore = conflictScore;
      outResult.dominanceGap = dominanceGap;
      outResult.barTime = curTime;
      outResult.reason = votes[bestIdx].label + StringFormat(" | SkorPola %.2f selisih %.2f konflik %.2f | rej %.2f trap %.2f reclaim %.2f ft %.2f | %s%s%s",
                         finalScore, dominanceGap, conflictScore,
                         m_lastFeatures.rejectionQuality, m_lastFeatures.trapQuality,
                         m_lastFeatures.reclaimQuality, m_lastFeatures.followThrough,
                         BuildConfluenceLabel(votes, direction),
                         m_externalWeightsLoaded ? " | terlatih" : " | cadangan",
                         (m_cnnRecognizer != NULL && (cnnBuyScore > 0.0 || cnnSellScore > 0.0)) ? " | cnn" : "");

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

   bool HasExternalWeights() const { return m_externalWeightsLoaded; }
   string GetWeightsFile() const { return m_weightsFile; }
   SPatternResult GetLastResult() const { return m_lastResult; }
   SPatternFeatureSnapshot GetLastFeatureSnapshot() const { return m_lastFeatures; }
   void GetLastResult(SPatternResult &out) const { out = m_lastResult; }
   void GetLastFeatureSnapshot(SPatternFeatureSnapshot &out) const { out = m_lastFeatures; }

   int GetHistoryCount() const { return m_historyCount; }
   bool GetHistoryAt(int idx, SPatternResult &out) const
     {
      int physical = HistoryPhysicalIndex(idx);
      if(physical < 0) return false;
      out = m_history[physical];
      return true;
     }
  };

#endif // __PATTERN_MANAGER_MQH__
