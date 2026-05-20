//+------------------------------------------------------------------+
//|                                              9.PatternManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Pattern Detection & Analysis Module (Static Utility)  |
//|                                                                  |
//| VERSION 2.01 - BUG FIXES                                         |
//| PM-BUG-1: EvaluateMorningStar: added missing `return;` after     |
//|   `if (dir == 0)` — previously fell through into vote assignment  |
//|   with dir=0, producing corrupt vote entries on every bar.        |
//| PM-BUG-2: EvaluateFakeyEnhanced() was called in Evaluate() but   |
//|   never implemented — Fakey always had normalizedScore=0. Fixed.  |
//| PM-BUG-3: EvaluateRailroadTracksEnhanced() same issue. Fixed.     |
//|   Old EvaluateRailroadTracks() never set vote.dir or score.       |
//| ADDED: InsideBarEnhanced, DarkCloudPiercingEnhanced,             |
//|   MarubozuEnhanced to complete the Enhanced family.              |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.01"
#property strict

#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

#include "2.Config.Types.mqh"
#include "2.Config.Manager.mqh"

//+------------------------------------------------------------------+
//| Enum for Pattern Quality Grade                                   |
//+------------------------------------------------------------------+
enum ENUM_PATTERN_GRADE
{
   GRADE_C,
   GRADE_B,
   GRADE_A,
   GRADE_NONE
};

//+------------------------------------------------------------------+
//| Enhanced Pattern Result Structure                                |
//+------------------------------------------------------------------+
struct PatternResult
{
   bool valid;
   ENUM_PATTERN_TYPE type;
   int dir;
   double extreme;
   double score;
   ENUM_PATTERN_GRADE grade;
   double slMult;
   string label;
   string reasoning;
   double confidence;
   double intrinsicScore;
   double contextScore;
   double momentumScore;
   double confluenceScore;
   datetime timestamp;

   bool IsActionable(double minScore = 0.5) const
   {
      return valid && score >= minScore && grade != GRADE_C;
   }
};

struct FakeoutResult
{
   bool detected;
   int level;
   double penetrationPts;
   double confidence;
   string reason;
};

//+------------------------------------------------------------------+
//| Pattern Weight Configuration                                     |
//+------------------------------------------------------------------+
struct PatternWeights
{
   double pinbarWeight;
   double engulfingWeight;
   double tweezerWeight;
   double fakeyWeight;
   double insideBarWeight;
   double morningStarWeight;
   double threeInsideWeight;
   double railroadWeight;
   double darkCloudWeight;
   double marubozuWeight;

   PatternWeights()
   {
      pinbarWeight     = 0.85;
      engulfingWeight  = 0.90;
      tweezerWeight    = 0.75;
      fakeyWeight      = 0.80;
      insideBarWeight  = 0.70;
      morningStarWeight= 0.88;
      threeInsideWeight= 0.85;
      railroadWeight   = 0.78;
      darkCloudWeight  = 0.72;
      marubozuWeight   = 0.82;
   }
};

//+------------------------------------------------------------------+
//| PatternManager — static utility class                           |
//+------------------------------------------------------------------+
class PatternManager
{
private:
   struct PatternVote
   {
      bool valid;
      ENUM_PATTERN_TYPE type;
      int dir;
      double extreme;
      double score;
      double normalizedScore;
      double slMult;
      string label;
      string reasoning;
      double intrinsicScore;
      double contextScore;
      double momentumScore;
      double confluenceScore;
      ENUM_PATTERN_GRADE grade;
   };

public:
   //+------------------------------------------------------------------+
   //| Main entry: full Enhanced evaluation                            |
   //+------------------------------------------------------------------+
   static PatternResult Evaluate(const StrategyConfig &cfg,
                                 const MqlRates &rates[],
                                 const int shift,
                                 const double atrvalue,
                                 const PatternWeights &weights)
   {
      PatternResult result;
      result.valid         = false;
      result.type          = PATTERN_NONE;
      result.dir           = 0;
      result.extreme       = 0.0;
      result.score         = 0.0;
      result.grade         = GRADE_NONE;
      result.slMult        = 1.0;
      result.label         = "";
      result.reasoning     = "";
      result.confidence    = 0.0;
      result.intrinsicScore= 0.0;
      result.contextScore  = 0.0;
      result.momentumScore = 0.0;
      result.confluenceScore= 0.0;
      result.timestamp     = TimeCurrent();

      if (shift < 1 || atrvalue <= 0)
      {
         result.reasoning = "Invalid shift/ATR parameters";
         return result;
      }
      if (shift + 3 >= ArraySize(rates))
      {
         result.reasoning = "Insufficient bar history (need at least 4 bars)";
         return result;
      }

      PatternVote votes[10];
      for (int i = 0; i < 10; i++)
         ResetVoteEnhanced(votes[i], cfg);

      EvaluatePinbarEnhanced(          rates, shift, atrvalue, votes[0], cfg, weights.pinbarWeight);
      EvaluateEngulfingEnhanced(       rates, shift, atrvalue, votes[1], cfg, weights.engulfingWeight);
      EvaluateBottomEnhanced(          rates, shift, atrvalue, votes[2], cfg, weights.tweezerWeight);
      EvaluateFakeyEnhanced(           rates, shift, atrvalue, votes[3], cfg, weights.fakeyWeight);      // PM-BUG-2 FIX
      EvaluateInsideBarEnhanced(       rates, shift, atrvalue, votes[4], cfg, weights.insideBarWeight);
      EvaluateMorningStarEnhanced(     rates, shift, atrvalue, votes[5], cfg, weights.morningStarWeight);
      EvaluateThreeInsideEnhanced(     rates, shift, atrvalue, votes[6], cfg, weights.threeInsideWeight);
      EvaluateRailroadTracksEnhanced(  rates, shift, atrvalue, votes[7], cfg, weights.railroadWeight);   // PM-BUG-3 FIX
      EvaluateDarkCloudPiercingEnhanced(rates, shift, atrvalue, votes[8], cfg, weights.darkCloudWeight);
      EvaluateMarubozuEnhanced(        rates, shift, atrvalue, votes[9], cfg, weights.marubozuWeight);

      // --- Pass 2: compute confluence scores now that all votes exist ---
      for (int i = 0; i < 10; i++)
      {
         if (votes[i].valid)
            votes[i].confluenceScore = CalculateConfluenceScore(votes, votes[i].dir, i);
      }

      double buyScore  = 0.0;
      double sellScore = 0.0;
      int bestBuyIdx   = -1;
      int bestSellIdx  = -1;

      for (int i = 0; i < 10; i++)
      {
         if (!votes[i].valid) continue;
         if (votes[i].dir == 1 && votes[i].normalizedScore > buyScore)
         { buyScore = votes[i].normalizedScore; bestBuyIdx = i; }
         else if (votes[i].dir == -1 && votes[i].normalizedScore > sellScore)
         { sellScore = votes[i].normalizedScore; bestSellIdx = i; }
      }

      double dominanceGap = MathMax(buyScore, sellScore) - MathMin(buyScore, sellScore);
      if (dominanceGap < cfg.min_dominance_gap)
      {
         result.reasoning = StringFormat("Confluence conflict | buy=%.2f sell=%.2f | Gap %.2f < %.2f",
                                         buyScore, sellScore, dominanceGap, cfg.min_dominance_gap);
         return result;
      }

      result.dir    = (buyScore > sellScore) ? 1 : -1;
      int bestIdx   = (result.dir == 1) ? bestBuyIdx : bestSellIdx;

      if (bestIdx < 0)
      {
         result.reasoning = "No valid directional pattern detected";
         return result;
      }

      result.valid          = true;
      result.type           = votes[bestIdx].type;
      result.extreme        = votes[bestIdx].extreme;
      result.slMult         = votes[bestIdx].slMult;
      result.label          = votes[bestIdx].label;
      result.intrinsicScore = votes[bestIdx].intrinsicScore;
      result.contextScore   = votes[bestIdx].contextScore;
      result.momentumScore  = votes[bestIdx].momentumScore;
      result.confluenceScore= votes[bestIdx].confluenceScore;
      result.score          = votes[bestIdx].normalizedScore;
      result.confidence     = result.score;

      if      (result.score >= 0.75) result.grade = GRADE_A;
      else if (result.score >= 0.50) result.grade = GRADE_B;
      else                           result.grade = GRADE_C;

      result.reasoning = BuildEnhancedReasoning(result, votes, bestIdx, buyScore, sellScore);
      return result;
   }

   //+------------------------------------------------------------------+
   //| Legacy wrapper                                                   |
   //+------------------------------------------------------------------+
   static bool Detect(ENUM_PATTERN_TYPE &outType,
                      const StrategyConfig &cfg,
                      const MqlRates &rates[],
                      const int shift,
                      const double atrvalue,
                      int &outDir,
                      double &outExtreme,
                      double &outScore,
                      double &outSLMult,
                      string &outReason)
   {
      PatternWeights weights;
      PatternResult result = Evaluate(cfg, rates, shift, atrvalue, weights);
      outType    = result.type;
      outDir     = result.dir;
      outExtreme = result.extreme;
      outScore   = result.score;
      outSLMult  = result.slMult;
      outReason  = result.reasoning;
      return result.valid;
   }

   //+------------------------------------------------------------------+
   //| Fakeout detection                                                |
   //+------------------------------------------------------------------+
   struct FakeoutContext
   {
      ulong originalTicket;
      int direction;
      double slHitPrice;
      double entryPrice;
      double atrPoints;
      double slMultiplier;
      MqlTick currentTick;
      MqlRates rates[];
   };

   static bool DetectFakeout(const FakeoutContext &ctx, FakeoutResult &result)
   {
      result.detected   = false;
      result.level      = 0;
      result.confidence = 0.0;

      double maxOvershoot = ctx.atrPoints * ctx.slMultiplier * _Point;
      double penetration  = (ctx.direction == 1)
                            ? (ctx.slHitPrice - ctx.currentTick.bid)
                            : (ctx.currentTick.ask - ctx.slHitPrice);

      if (penetration > maxOvershoot)
      { result.reason = "Momentum Breakout (Overshoot too deep)"; return false; }

      bool bodyReversal = (ctx.direction == 1)
                          ? (ctx.rates[0].close > ctx.rates[0].open)
                          : (ctx.rates[0].close < ctx.rates[0].open);

      if (bodyReversal) result.level = 2;
      result.detected   = (penetration > 0 && bodyReversal);
      result.confidence = 0.5 + (bodyReversal ? 0.3 : 0.0);
      result.reason     = StringFormat("Fakeout Level %d | Pen: %.1f pts",
                                       result.level, penetration / _Point);
      return result.detected;
   }

private:
   //--- Reset helpers ---------------------------------------------------
   static void ResetVoteEnhanced(PatternVote &v, const StrategyConfig &cfg)
   {
      v.valid          = false;
      v.type           = PATTERN_NONE;
      v.dir            = 0;
      v.extreme        = 0.0;
      v.score          = 0.0;
      v.normalizedScore= 0.0;
      v.slMult         = cfg.default_sl_mult;
      v.label          = "";
      v.reasoning      = "";
      v.intrinsicScore = 0.0;
      v.contextScore   = 0.0;
      v.momentumScore  = 0.0;
      v.confluenceScore= 0.0;
      v.grade          = GRADE_NONE;
   }

   static void AssignGrade(PatternVote &v)
   {
      if      (v.normalizedScore >= 0.75) v.grade = GRADE_A;
      else if (v.normalizedScore >= 0.50) v.grade = GRADE_B;
      else                                v.grade = GRADE_C;
   }

   //--- Reasoning builder -----------------------------------------------
   static string BuildEnhancedReasoning(const PatternResult &r,
                                        const PatternVote votes[],
                                        int bestIdx,
                                        double buyScore,
                                        double sellScore)
   {
      if (!r.valid) return "No valid pattern detected";
      string s = StringFormat("%s (Grade %c, Score: %.2f)\n",
                              r.label,
                              r.grade == GRADE_A ? 'A' : (r.grade == GRADE_B ? 'B' : 'C'),
                              r.score);
      s += StringFormat("Dir: %s | Extreme: %.5f | SLMult: %.2f\n",
                        r.dir == 1 ? "BUY" : "SELL", r.extreme, r.slMult);
      s += "--- Scoring ---\n";
      s += StringFormat("Intrinsic(35%%): %.2f\n", r.intrinsicScore * 0.35);
      s += StringFormat("Context  (25%%): %.2f\n", r.contextScore   * 0.25);
      s += StringFormat("Momentum (20%%): %.2f\n", r.momentumScore  * 0.20);
      s += StringFormat("Confluence(20%%):%.2f\n", r.confluenceScore* 0.20);
      if (buyScore > 0 && sellScore > 0)
         s += StringFormat("Conflict: Buy=%.2f Sell=%.2f Gap=%.2f\n",
                           buyScore, sellScore, buyScore - sellScore);
      return s;
   }

   //--- Component score calculators ------------------------------------
   static double CalculateIntrinsicScore(const MqlRates &rates[], int shift,
                                         double atrvalue, ENUM_PATTERN_TYPE type,
                                         const StrategyConfig &cfg)
   {
      double score     = 0.5;
      double range     = CandleRange(rates, shift);
      double body      = CandleBody(rates, shift);
      double upperWick = UpperWick(rates, shift);
      double lowerWick = LowerWick(rates, shift);
      if (range <= 0 || atrvalue <= 0) return score;

      double atrPrice   = atrvalue * _Point;
      double rangeRatio = range / atrPrice;
      double bodyRatio  = body / MathMax(range, _Point);

      switch (type)
      {
         case PATTERN_PINBAR:
            if      (lowerWick > upperWick * 2) score += 0.3;
            else if (upperWick > lowerWick * 2) score += 0.3;
            break;
         case PATTERN_ENGULFING:
            if      (bodyRatio >= 0.7) score += 0.3;
            else if (bodyRatio >= 0.5) score += 0.2;
            break;
         case PATTERN_MORNING_STAR:
         case PATTERN_THREE_INSIDE:
            score = 0.6;
            if (bodyRatio >= 0.6) score += 0.25;
            break;
         default:
            if      (bodyRatio >= 0.7) score += 0.25;
            else if (bodyRatio >= 0.5) score += 0.15;
            break;
      }
      if (rangeRatio >= cfg.atr_range_threshold) score += 0.15;
      return MathMin(1.0, score);
   }

   static double CalculateContextScore(const MqlRates &rates[], int shift,
                                       int dir, ENUM_PATTERN_TYPE type)
   {
      double score      = 0.5;
      double recentHigh = rates[shift + 1].high;
      double recentLow  = rates[shift + 1].low;
      double curClose   = rates[shift].close;
      bool   isReversal = (type == PATTERN_PINBAR || type == PATTERN_ENGULFING ||
                           type == PATTERN_MORNING_STAR || type == PATTERN_THREE_INSIDE);
      if (dir == 1)
      {
         if (isReversal && MathAbs(curClose - recentLow) < (recentHigh - recentLow) * 0.2)
            score = 0.8;
         else if (curClose > recentHigh)
            score = 0.6;
      }
      else if (dir == -1)
      {
         if (isReversal && MathAbs(curClose - recentHigh) < (recentHigh - recentLow) * 0.2)
            score = 0.8;
         else if (curClose < recentLow)
            score = 0.6;
      }
      return MathMin(1.0, score);
   }

   static double CalculateMomentumScore(const MqlRates &rates[], int shift,
                                        int dir, const StrategyConfig &cfg)
   {
      double score = 0.5;
      if (shift + 1 >= ArraySize(rates)) return score;
      double prevClose = rates[shift + 1].close;
      double currClose = rates[shift].close;
      double range     = CandleRange(rates, shift);
      if (range <= 0) return score;

      if (dir == 1)
      {
         double pos = (currClose - rates[shift].low) / range;
         if      (pos >= cfg.star_close_min) score = 0.8;
         else if (pos >= 0.5)               score = 0.6;
         if (currClose > prevClose)          score += 0.15;
      }
      else if (dir == -1)
      {
         double pos = (rates[shift].high - currClose) / range;
         if      (pos >= cfg.star_close_min) score = 0.8;
         else if (pos >= 0.5)               score = 0.6;
         if (currClose < prevClose)          score += 0.15;
      }
      return MathMin(1.0, score);
   }

   static double CalculateConfluenceScore(const PatternVote votes[], int dir, int excludeIdx)
   {
      int supportingPatterns = 0;
      for (int i = 0; i < 10; i++)
      {
         if (i == excludeIdx || !votes[i].valid || votes[i].dir != dir) continue;
         supportingPatterns++;
      }
      if      (supportingPatterns >= 2) return 0.85;
      else if (supportingPatterns == 1) return 0.65;
      return 0.50;
   }

   static double NormalizeScore(double rawScore, double patternWeight)
   {
      double normalized = (rawScore * patternWeight - 0.3) / 1.2;
      return MathMax(0.0, MathMin(1.0, normalized));
   }

   //--- Candle helpers --------------------------------------------------
   static double CandleOpen (const MqlRates &r[], int s) { return r[s].open;  }
   static double CandleHigh (const MqlRates &r[], int s) { return r[s].high;  }
   static double CandleLow  (const MqlRates &r[], int s) { return r[s].low;   }
   static double CandleClose(const MqlRates &r[], int s) { return r[s].close; }
   static double CandleRange(const MqlRates &r[], int s) { return r[s].high - r[s].low; }
   static double CandleBody (const MqlRates &r[], int s) { return MathAbs(r[s].close - r[s].open); }
   static double UpperWick  (const MqlRates &r[], int s) { return r[s].high - MathMax(r[s].open, r[s].close); }
   static double LowerWick  (const MqlRates &r[], int s) { return MathMin(r[s].open, r[s].close) - r[s].low; }
   static bool   IsBullish  (const MqlRates &r[], int s) { return r[s].close > r[s].open; }
   static bool   IsBearish  (const MqlRates &r[], int s) { return r[s].close < r[s].open; }
   static bool   IsInsideBar(const MqlRates &r[], int s)
   { return r[s].high < r[s+1].high && r[s].low > r[s+1].low; }

   static double NormalizeATRFactor(double value, double atrvalue)
   {
      double p = atrvalue * _Point;
      return (p <= 0.0) ? 0.0 : value / p;
   }

   static void AddStrengthFromRejection(const MqlRates &rates[], int shift, double atrvalue,
                                        int dir, double &score, const StrategyConfig &cfg)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0) return;
      double majorWick = (dir == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
      if (majorWick / range          >= cfg.wick_ratio_threshold) score += cfg.bonus_strong_wick;
      if (CandleBody(rates, shift) / range <= cfg.body_ratio_threshold) score += cfg.bonus_strong_body;
      if (NormalizeATRFactor(range, atrvalue) >= cfg.atr_range_threshold) score += cfg.bonus_strong_atr;
   }

   static void AddStrengthFromFollowThrough(const MqlRates &rates[], int shift,
                                            int dir, double &score, const StrategyConfig &cfg)
   {
      double prev = CandleClose(rates, shift + 1);
      double cur  = CandleClose(rates, shift);
      if ((dir == 1 && cur > prev) || (dir == -1 && cur < prev))
         score += cfg.bonus_follow_through;
   }

   //====================================================================
   //  ENHANCED EVALUATORS
   //====================================================================

   //--- Pinbar ----------------------------------------------------------
   static void EvaluatePinbarEnhanced(const MqlRates &rates[], int shift,
                                      double atrvalue, PatternVote &vote,
                                      const StrategyConfig &cfg, double w)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0) return;
      double bodyMid = (CandleOpen(rates, shift) + CandleClose(rates, shift)) / 2.0;
      double upper   = UpperWick(rates, shift);
      double lower   = LowerWick(rates, shift);
      int    dir     = 0;
      double extreme = 0.0;
      if (CandleClose(rates, shift) > bodyMid && lower > (upper > 0 ? upper * cfg.pinbar_wick_ratio : _Point))
      { dir = 1;  extreme = CandleLow(rates, shift); }
      else if (CandleClose(rates, shift) < bodyMid && upper > (lower > 0 ? lower * cfg.pinbar_wick_ratio : _Point))
      { dir = -1; extreme = CandleHigh(rates, shift); }
      else return;

      vote.valid = true; vote.type = PATTERN_PINBAR; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.pinbar_sl_mult;
      vote.label  = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_PINBAR, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_PINBAR);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      double raw = cfg.base_score;
      AddStrengthFromRejection(rates, shift, atrvalue, dir, raw, cfg);
      AddStrengthFromFollowThrough(rates, shift, dir, raw, cfg);
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
      vote.reasoning = StringFormat("%s | Wick ratio: %.2f", vote.label,
                                    (dir == 1 ? lower : upper) / MathMax(range, _Point));
   }

   static void EvaluatePinbar(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluatePinbarEnhanced(r, s, a, v, c, 0.85); }

   //--- Engulfing -------------------------------------------------------
   static void EvaluateEngulfingEnhanced(const MqlRates &rates[], int shift,
                                         double atrvalue, PatternVote &vote,
                                         const StrategyConfig &cfg, double w)
   {
      double o1 = CandleOpen(rates, shift),  c1 = CandleClose(rates, shift);
      double o2 = CandleOpen(rates, shift+1),c2 = CandleClose(rates, shift+1);
      int dir = 0; double extreme = 0.0;
      if (c2 < o2 && c1 > o1 && c1 > o2 && o1 < c2)
      { dir = 1;  extreme = MathMin(CandleLow(rates,shift), CandleLow(rates,shift+1)); }
      else if (c2 > o2 && c1 < o1 && c1 < o2 && o1 > c2)
      { dir = -1; extreme = MathMax(CandleHigh(rates,shift),CandleHigh(rates,shift+1)); }
      else return;

      double body1 = CandleBody(rates, shift);
      double body2 = CandleBody(rates, shift+1);
      vote.valid = true; vote.type = PATTERN_ENGULFING; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label  = (dir == 1) ? "Engulf Bull" : "Engulf Bear";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_ENGULFING, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_ENGULFING);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      double raw = cfg.base_score;
      if (body2 > 0.0 && body1 >= body2 * cfg.engulfing_body_mult) raw += cfg.bonus_strong_body;
      if (NormalizeATRFactor(CandleRange(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      AddStrengthFromFollowThrough(rates, shift, dir, raw, cfg);
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
      vote.reasoning = StringFormat("%s | Body ratio: %.2f", vote.label, body1 / MathMax(body2, _Point));
   }

   static void EvaluateEngulfing(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateEngulfingEnhanced(r, s, a, v, c, 0.90); }

   //--- Tweezer Bottom/Top ----------------------------------------------
   static void EvaluateBottomEnhanced(const MqlRates &rates[], int shift,
                                      double atrvalue, PatternVote &vote,
                                      const StrategyConfig &cfg, double w)
   {
      double tol = MathMax(atrvalue * cfg.sensitivity_atr * _Point, 3 * _Point);
      int dir = 0; double extreme = 0.0;
      if (MathAbs(CandleLow(rates,shift) - CandleLow(rates,shift+1)) <= tol && IsBullish(rates,shift))
      { dir = 1;  extreme = MathMin(CandleLow(rates,shift), CandleLow(rates,shift+1)); }
      else if (MathAbs(CandleHigh(rates,shift) - CandleHigh(rates,shift+1)) <= tol && IsBearish(rates,shift))
      { dir = -1; extreme = MathMax(CandleHigh(rates,shift),CandleHigh(rates,shift+1)); }
      else return;

      vote.valid = true; vote.type = PATTERN_BOTTOM; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label  = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_BOTTOM, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_BOTTOM);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      double raw = cfg.base_score;
      if (NormalizeATRFactor(CandleRange(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      if (CandleBody(rates,shift) / MathMax(CandleRange(rates,shift), _Point) >= cfg.body_ratio_threshold) raw += cfg.bonus_strong_body;
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
   }

   static void EvaluateBottom(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateBottomEnhanced(r, s, a, v, c, 0.75); }

   //--- Fakey (PM-BUG-2 FIX: was missing, now properly implemented) ----
   static void EvaluateFakeyEnhanced(const MqlRates &rates[], int shift,
                                     double atrvalue, PatternVote &vote,
                                     const StrategyConfig &cfg, double w)
   {
      if (shift + 2 >= ArraySize(rates)) return;
      double h0 = CandleHigh(rates, shift),   l0 = CandleLow(rates, shift);
      double c0 = CandleClose(rates, shift),  o0 = CandleOpen(rates, shift);
      double h1 = CandleHigh(rates, shift+1), l1 = CandleLow(rates, shift+1);
      double h2 = CandleHigh(rates, shift+2), l2 = CandleLow(rates, shift+2);

      if (!(h1 < h2 && l1 > l2)) return; // shift+1 must be inside bar of shift+2

      int dir = 0; double extreme = 0.0;
      if      (l0 < l1 && c0 > l1 && c0 > o0) { dir =  1; extreme = l0; }
      else if (h0 > h1 && c0 < h1 && c0 < o0) { dir = -1; extreme = h0; }
      else return;

      vote.valid = true; vote.type = PATTERN_FAKEY; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label  = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_FAKEY, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_FAKEY);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      double raw = cfg.base_score;
      if (NormalizeATRFactor(CandleRange(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      if (CandleBody(rates,shift) / MathMax(CandleRange(rates,shift), _Point) >= cfg.body_ratio_threshold) raw += cfg.bonus_strong_body;
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
      vote.reasoning = StringFormat("%s | False break: %.1f pts", vote.label,
                                    (dir == 1 ? l1 - l0 : h0 - h1) / _Point);
   }

   static void EvaluateFakey(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateFakeyEnhanced(r, s, a, v, c, 0.80); }

   //--- Inside Bar ------------------------------------------------------
   static void EvaluateInsideBarEnhanced(const MqlRates &rates[], int shift,
                                         double atrvalue, PatternVote &vote,
                                         const StrategyConfig &cfg, double w)
   {
      if (!IsInsideBar(rates, shift)) return;
      double motherMid = (CandleHigh(rates,shift+1) + CandleLow(rates,shift+1)) / 2.0;
      double childClose = CandleClose(rates, shift);
      int dir = 0; double extreme = 0.0;
      if      (childClose > motherMid) { dir =  1; extreme = CandleLow(rates,shift); }
      else if (childClose < motherMid) { dir = -1; extreme = CandleHigh(rates,shift); }
      else return;

      double motherRange = CandleRange(rates, shift+1);
      double childRange  = CandleRange(rates, shift);
      vote.valid = true; vote.type = PATTERN_INSIDE_BAR_BREAKOUT; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.inside_bar_sl_mult;
      vote.label  = (dir == 1) ? "Inside Bull" : "Inside Bear";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_INSIDE_BAR_BREAKOUT, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_INSIDE_BAR_BREAKOUT);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      double raw = cfg.base_score;
      if (motherRange > 0.0 && childRange / motherRange <= cfg.inside_bar_range_max) raw += cfg.bonus_strong_body;
      if (NormalizeATRFactor(motherRange, atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
   }

   static void EvaluateInsideBar(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateInsideBarEnhanced(r, s, a, v, c, 0.70); }

   //--- Morning Star / Evening Star (PM-BUG-1 FIX: missing return added) ---
   static void EvaluateMorningStarEnhanced(const MqlRates &rates[], int shift,
                                           double atrvalue, PatternVote &vote,
                                           const StrategyConfig &cfg, double w)
   {
      if (shift + 2 >= ArraySize(rates)) return;
      double o0=CandleOpen(rates,shift),  c0=CandleClose(rates,shift);
      double o1=CandleOpen(rates,shift+1),c1=CandleClose(rates,shift+1);
      double o2=CandleOpen(rates,shift+2),c2=CandleClose(rates,shift+2);
      double body0=CandleBody(rates,shift), body1=CandleBody(rates,shift+1), body2=CandleBody(rates,shift+2);
      double range1 = CandleRange(rates, shift+1);
      double gap    = cfg.sensitivity_atr * atrvalue * _Point;

      bool isSmallMiddle = (range1 > 0)
                         && (body1 < body0 * cfg.star_middle_body_mult)
                         && (body1 < body2 * cfg.star_middle_body_mult);
      if (!isSmallMiddle) return;

      int dir = 0; double extreme = 0.0;
      double raw = cfg.base_score;

      bool mGap1  = (c2 < o2) && (MathMax(o1,c1) < c2 - gap);
      bool mGap2  = (c0 > o0) && (MathMin(o0,c0) > MathMax(o1,c1) + gap);
      bool mClose = c0 > (o2 + c2) / 2.0;
      if (mGap1 && mGap2 && mClose)
      { dir = 1; extreme = MathMin(CandleLow(rates,shift+2), CandleLow(rates,shift+1)); raw += cfg.bonus_gap_confirm; }

      bool eGap1  = (c2 > o2) && (MathMin(o1,c1) > c2 + gap);
      bool eGap2  = (c0 < o0) && (MathMax(o0,c0) < MathMin(o1,c1) - gap);
      bool eClose = c0 < (o2 + c2) / 2.0;
      if (eGap1 && eGap2 && eClose)
      { dir = -1; extreme = MathMax(CandleHigh(rates,shift+2), CandleHigh(rates,shift+1)); raw += cfg.bonus_gap_confirm; }

      if (dir == 0) return;  // PM-BUG-1 FIX: was missing, execution fell through

      if (NormalizeATRFactor(CandleRange(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      double closePos = (dir == 1)
                        ? (c0 - CandleLow(rates,shift))  / MathMax(CandleRange(rates,shift), _Point)
                        : (CandleHigh(rates,shift) - c0) / MathMax(CandleRange(rates,shift), _Point);
      if (closePos >= cfg.star_close_min) raw += cfg.bonus_strong_body;

      vote.valid = true; vote.type = PATTERN_MORNING_STAR; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label  = (dir == 1) ? "Morning Star" : "Evening Star";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_MORNING_STAR, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_MORNING_STAR);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
   }

   static void EvaluateMorningStar(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateMorningStarEnhanced(r, s, a, v, c, 0.88); }

   //--- Three Inside Up/Down --------------------------------------------
   static void EvaluateThreeInsideEnhanced(const MqlRates &rates[], int shift,
                                           double atrvalue, PatternVote &vote,
                                           const StrategyConfig &cfg, double w)
   {
      if (shift + 2 >= ArraySize(rates)) return;
      double h0=CandleHigh(rates,shift), l0=CandleLow(rates,shift);
      double h2=CandleHigh(rates,shift+2),l2=CandleLow(rates,shift+2);
      double c0=CandleClose(rates,shift),o0=CandleOpen(rates,shift);
      double c1=CandleClose(rates,shift+1),o1=CandleOpen(rates,shift+1);
      double body0=CandleBody(rates,shift), body2=CandleBody(rates,shift+2);
      int dir = 0; double extreme = 0.0; double raw = cfg.base_score;

      bool upOk = IsBearish(rates,shift+2) && body0 > 0
               && IsInsideBar(rates,shift+1) && c1 > o1 && CandleClose(rates,shift) > h2;
      if (upOk)  { dir =  1; extreme = MathMin(CandleLow(rates,shift+1), l2); raw += cfg.bonus_breakout_confirm; }

      bool dnOk = IsBullish(rates,shift+2) && body0 > 0
               && IsInsideBar(rates,shift+1) && c1 < o1 && CandleClose(rates,shift) < l2;
      if (dnOk)  { dir = -1; extreme = MathMax(CandleHigh(rates,shift+1),CandleHigh(rates,shift+2)); raw += cfg.bonus_breakout_confirm; }

      if (dir == 0) return;
      if (NormalizeATRFactor(CandleRange(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      if (body2 > 0 && body0 / body2 >= cfg.three_inside_body_min) raw += cfg.bonus_strong_body;

      vote.valid = true; vote.type = PATTERN_THREE_INSIDE; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label  = (dir == 1) ? "Three Inside Up" : "Three Inside Down";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_THREE_INSIDE, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_THREE_INSIDE);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
   }

   static void EvaluateThreeInside(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateThreeInsideEnhanced(r, s, a, v, c, 0.85); }

   //--- Railroad Tracks (PM-BUG-3 FIX: was missing, now properly implemented) ---
   static void EvaluateRailroadTracksEnhanced(const MqlRates &rates[], int shift,
                                              double atrvalue, PatternVote &vote,
                                              const StrategyConfig &cfg, double w)
   {
      if (shift + 1 >= ArraySize(rates)) return;
      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift+1);
      if (body0 <= _Point || body1 <= _Point) return;
      if (MathMax(body0,body1) / MathMin(body0,body1) > cfg.railroad_min_body_ratio) return;

      int dir = 0; double extreme = 0.0; double raw = cfg.base_score;
      if (IsBearish(rates,shift+1) && IsBullish(rates,shift))
      { dir =  1; extreme = MathMin(CandleLow(rates,shift+1), CandleLow(rates,shift)); raw += cfg.bonus_small; }
      else if (IsBullish(rates,shift+1) && IsBearish(rates,shift))
      { dir = -1; extreme = MathMax(CandleHigh(rates,shift+1),CandleHigh(rates,shift)); raw += cfg.bonus_small; }
      if (dir == 0) return;

      double avgBody  = (body0 + body1) / 2.0;
      double atrPrice = atrvalue * _Point;
      if (atrPrice > 0 && avgBody >= atrPrice * cfg.railroad_avg_body_min) raw += cfg.bonus_strong_atr;
      if (dir ==  1 && LowerWick(rates,shift+1) > body1 * cfg.railroad_wick_mult) raw += cfg.bonus_strong_wick;
      if (dir == -1 && UpperWick(rates,shift+1) > body1 * cfg.railroad_wick_mult) raw += cfg.bonus_strong_wick;

      vote.valid = true; vote.type = PATTERN_RAILROAD_TRACKS; vote.dir = dir; vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label  = (dir == 1) ? "Railroad Bull" : "Railroad Bear";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_RAILROAD_TRACKS, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_RAILROAD_TRACKS);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
      vote.reasoning = StringFormat("%s | Body ratio: %.2f", vote.label, MathMax(body0,body1)/MathMin(body0,body1));
   }

   static void EvaluateRailroadTracks(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateRailroadTracksEnhanced(r, s, a, v, c, 0.78); }

   //--- Dark Cloud Cover / Piercing Line --------------------------------
   static void EvaluateDarkCloudPiercingEnhanced(const MqlRates &rates[], int shift,
                                                 double atrvalue, PatternVote &vote,
                                                 const StrategyConfig &cfg, double w)
   {
      if (shift + 1 >= ArraySize(rates)) return;
      double o0=CandleOpen(rates,shift),  c0=CandleClose(rates,shift);
      double o1=CandleOpen(rates,shift+1),c1=CandleClose(rates,shift+1);
      double h1=CandleHigh(rates,shift+1),l1=CandleLow(rates,shift+1);
      double mid1 = (o1 + c1) / 2.0;
      int dir = 0; double raw = cfg.base_score;

      if (IsBearish(rates,shift+1) && IsBullish(rates,shift) && o0 < l1 && c0 > mid1 && c0 < o1)
      { dir = 1;  vote.extreme = CandleLow(rates,shift);  vote.label = "Piercing Line"; }
      else if (IsBullish(rates,shift+1) && IsBearish(rates,shift) && o0 > h1 && c0 < mid1 && c0 > o1)
      { dir = -1; vote.extreme = CandleHigh(rates,shift); vote.label = "Dark Cloud Cover"; }
      if (dir == 0) return;

      AddStrengthFromFollowThrough(rates, shift, dir, raw, cfg);
      vote.valid = true; vote.type = PATTERN_DARK_CLOUD_PIERCING; vote.dir = dir;
      vote.slMult = cfg.default_sl_mult;
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_DARK_CLOUD_PIERCING, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_DARK_CLOUD_PIERCING);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
   }

   static void EvaluateDarkCloudPiercing(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateDarkCloudPiercingEnhanced(r, s, a, v, c, 0.72); }

   //--- Marubozu --------------------------------------------------------
   static void EvaluateMarubozuEnhanced(const MqlRates &rates[], int shift,
                                        double atrvalue, PatternVote &vote,
                                        const StrategyConfig &cfg, double w)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0) return;
      if (CandleBody(rates,shift) / range < cfg.marubozu_min_body_pct) return;
      double atrFactor = NormalizeATRFactor(range, atrvalue);
      if (atrFactor < cfg.momentum_threshold_atr * cfg.marubozu_min_atr_mult) return;

      int dir = IsBullish(rates, shift) ? 1 : -1;
      double raw = cfg.base_score + cfg.bonus_small;
      if (atrFactor > cfg.marubozu_strong_atr_min) raw += cfg.bonus_strong_atr;

      vote.valid = true; vote.type = PATTERN_MARUBOZU; vote.dir = dir;
      vote.extreme  = (dir == 1) ? CandleLow(rates,shift) : CandleHigh(rates,shift);
      vote.slMult   = cfg.default_sl_mult;
      vote.label    = (dir == 1) ? "Marubozu Bull" : "Marubozu Bear";
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_MARUBOZU, cfg);
      vote.contextScore   = CalculateContextScore(rates, shift, dir, PATTERN_MARUBOZU);
      vote.momentumScore  = CalculateMomentumScore(rates, shift, dir, cfg);
      vote.score = raw;
      vote.normalizedScore = NormalizeScore(raw, w);
      AssignGrade(vote);
   }

   static void EvaluateMarubozu(const MqlRates &r[], int s, double a, PatternVote &v, const StrategyConfig &c)
   { EvaluateMarubozuEnhanced(r, s, a, v, c, 0.82); }

   //--- Legacy helpers (kept for backward compat) ----------------------
   static int FindBestVote(PatternVote &votes[], int dir)
   {
      int best = -1; double best_s = 0.0;
      for (int i = 0; i < ArraySize(votes); i++)
      {
         if (!votes[i].valid || votes[i].dir != dir) continue;
         if (votes[i].normalizedScore > best_s) { best_s = votes[i].normalizedScore; best = i; }
      }
      return best;
   }

   static string BuildConfluenceLabel(const PatternVote &votes[], int dir)
   {
      string txt = "";
      for (int i = 0; i < ArraySize(votes); i++)
      {
         if (!votes[i].valid || votes[i].dir != dir) continue;
         if (txt != "") txt += " + ";
         txt += votes[i].label;
      }
      return txt;
   }
};

#endif // __PATTERN_MANAGER_MQH__
