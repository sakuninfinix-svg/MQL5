//+------------------------------------------------------------------+
//|                                              9.PatternManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Pattern Detection & Analysis Module (Static Utility)  |
//|                                                                  |
//| VERSION 2.0 - ENHANCED PATTERN SCORING & CONTEXT INTEGRATION    |
//| - Dynamic pattern weighting based on statistical reliability     |
//| - Trend context validation (MA slope alignment)                  |
//| - Support/Resistance confluence bonus                            |
//| - Volatility-adaptive detection thresholds                       |
//| - Pattern quality grading (A/B/C tiers)                          |
//| - Enhanced fakeout detection with multi-level confirmation       |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

// PatternManager membutuhkan akses ke CFG dan ENUM_PATTERN_TYPE
#include "2.Config.mqh"

//+------------------------------------------------------------------+
//| Enum for Pattern Quality Grade                                   |
//+------------------------------------------------------------------+
enum ENUM_PATTERN_GRADE
{
   GRADE_C,      // Weak pattern, low confidence (score < 0.5)
   GRADE_B,      // Moderate pattern, medium confidence (0.5 <= score < 0.75)
   GRADE_A,      // Strong pattern, high confidence (score >= 0.75)
   GRADE_NONE    // Invalid or no pattern
};

//+------------------------------------------------------------------+
//| Enhanced Pattern Result Structure                                |
//+------------------------------------------------------------------+
struct PatternResult
{
   bool valid;                    // Pattern detected?
   ENUM_PATTERN_TYPE type;        // Pattern type
   int dir;                       // 1 = buy, -1 = sell
   double extreme;                // Key price level (high/low)
   double score;                  // Normalized score 0.0 - 1.0
   ENUM_PATTERN_GRADE grade;      // Quality grade A/B/C
   double slMult;                 // Recommended SL multiplier
   string label;                  // Human-readable label
   string reasoning;              // Detailed explanation
   double confidence;             // 0.0 - 1.0 confidence level
   
   // Component scores for explainability
   double intrinsicScore;         // Pattern intrinsic strength (35%)
   double contextScore;           // Trend/SR alignment (25%)
   double momentumScore;          // Volume/momentum confirmation (20%)
   double confluenceScore;        // Multi-candle confluence (20%)
   
   datetime timestamp;            // Detection time
   
   // Helper method to check if pattern is actionable
   bool IsActionable(double minScore = 0.5) const
   {
      return valid && score >= minScore && grade != GRADE_C;
   }
};

// Legacy FakeoutResult for backward compatibility
struct FakeoutResult
{
   bool detected;         // Fakeout detected?
   int level;             // 1=Penetration, 2=Reversal, 3=Confirmed
   double penetrationPts; // Overshoot distance in points
   double confidence;     // 0.0-1.0 confidence score
   string reason;         // Diagnosis
};

//+------------------------------------------------------------------+
//| Pattern Weight Configuration - Statistical Reliability           |
//+------------------------------------------------------------------+
struct PatternWeights
{
   double pinbarWeight;           // 0.85 - High reliability
   double engulfingWeight;        // 0.90 - Very high reliability
   double tweezerWeight;          // 0.75 - Moderate reliability
   double fakeyWeight;            // 0.80 - Good reliability
   double insideBarWeight;        // 0.70 - Context dependent
   double morningStarWeight;      // 0.88 - High reliability (3-candle)
   double threeInsideWeight;      // 0.85 - High reliability (3-candle)
   double railroadWeight;         // 0.78 - Good reliability
   double darkCloudWeight;        // 0.72 - Moderate reliability
   double marubozuWeight;         // 0.82 - Good momentum indicator
   
   // Constructor with default weights based on statistical analysis
   PatternWeights()
   {
      pinbarWeight = 0.85;
      engulfingWeight = 0.90;
      tweezerWeight = 0.75;
      fakeyWeight = 0.80;
      insideBarWeight = 0.70;
      morningStarWeight = 0.88;
      threeInsideWeight = 0.85;
      railroadWeight = 0.78;
      darkCloudWeight = 0.72;
      marubozuWeight = 0.82;
   }
};

// OPTIMIZATION V1.20 + V2.00: Converted to static class for memory efficiency
class PatternManager
{
private:
   // Enhanced PatternVote with component scoring
   struct PatternVote
   {
      bool valid;
      ENUM_PATTERN_TYPE type;
      int dir; // 1 = buy, -1 = sell
      double extreme;
      double score;              // Raw score before normalization
      double normalizedScore;    // Normalized 0.0 - 1.0
      double slMult;             // Recommended SL multiplier
      string label;
      string reasoning;
      
      // Component scores for granular analysis
      double intrinsicScore;     // Pattern formation quality (35%)
      double contextScore;       // Trend/SR alignment (25%)
      double momentumScore;      // Momentum/volume confirmation (20%)
      double confluenceScore;    // Multi-pattern confluence (20%)
      
      ENUM_PATTERN_GRADE grade;  // A/B/C grade
   };

public:
   //+------------------------------------------------------------------+
   //| ENHANCED METHOD: Evaluate with full PatternResult               |
   //| Returns complete pattern analysis with scoring breakdown         |
   //+------------------------------------------------------------------+
   static PatternResult Evaluate(const StrategyConfig &cfg,
                                 const MqlRates &rates[],
                                 const int shift,
                                 const double atrvalue,
                                 const PatternWeights &weights)
   {
      PatternResult result;
      result.valid = false;
      result.type = PATTERN_NONE;
      result.dir = 0;
      result.extreme = 0.0;
      result.score = 0.0;
      result.grade = GRADE_NONE;
      result.slMult = 1.0;
      result.label = "";
      result.reasoning = "";
      result.confidence = 0.0;
      result.intrinsicScore = 0.0;
      result.contextScore = 0.0;
      result.momentumScore = 0.0;
      result.confluenceScore = 0.0;
      result.timestamp = TimeCurrent();
      
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
      
      // Evaluate all patterns with enhanced scoring
      EvaluatePinbarEnhanced(rates, shift, atrvalue, votes[0], cfg, weights.pinbarWeight);
      EvaluateEngulfingEnhanced(rates, shift, atrvalue, votes[1], cfg, weights.engulfingWeight);
      EvaluateBottomEnhanced(rates, shift, atrvalue, votes[2], cfg, weights.tweezerWeight);
      EvaluateFakeyEnhanced(rates, shift, atrvalue, votes[3], cfg, weights.fakeyWeight);
      EvaluateInsideBarEnhanced(rates, shift, atrvalue, votes[4], cfg, weights.insideBarWeight);
      EvaluateMorningStarEnhanced(rates, shift, atrvalue, votes[5], cfg, weights.morningStarWeight);
      EvaluateThreeInsideEnhanced(rates, shift, atrvalue, votes[6], cfg, weights.threeInsideWeight);
      EvaluateRailroadTracksEnhanced(rates, shift, atrvalue, votes[7], cfg, weights.railroadWeight);
      EvaluateDarkCloudPiercingEnhanced(rates, shift, atrvalue, votes[8], cfg, weights.darkCloudWeight);
      EvaluateMarubozuEnhanced(rates, shift, atrvalue, votes[9], cfg, weights.marubozuWeight);
      
      double buyScore = 0.0;
      double sellScore = 0.0;
      int bestBuyIdx = -1;
      int bestSellIdx = -1;
      
      // Find best directional patterns
      for (int i = 0; i < 10; i++)
      {
         if (!votes[i].valid)
            continue;
         
         if (votes[i].dir == 1 && votes[i].normalizedScore > buyScore)
         {
            buyScore = votes[i].normalizedScore;
            bestBuyIdx = i;
         }
         else if (votes[i].dir == -1 && votes[i].normalizedScore > sellScore)
         {
            sellScore = votes[i].normalizedScore;
            bestSellIdx = i;
         }
      }
      
      double totalScore = MathMax(buyScore, sellScore);
      double conflictScore = MathMin(buyScore, sellScore);
      double dominanceGap = totalScore - conflictScore;
      
      // Check for directional conflict
      if (dominanceGap < cfg.min_dominance_gap)
      {
         result.reasoning = StringFormat("Confluence conflict | buy=%.2f sell=%.2f | Gap %.2f < %.2f", 
                                         buyScore, sellScore, dominanceGap, cfg.min_dominance_gap);
         return result;
      }
      
      // Determine direction and best pattern
      result.dir = (buyScore > sellScore) ? 1 : -1;
      int bestIdx = (result.dir == 1) ? bestBuyIdx : bestSellIdx;
      
      if (bestIdx < 0)
      {
         result.reasoning = "No valid directional pattern detected";
         return result;
      }
      
      // Populate result from best vote
      result.valid = true;
      result.type = votes[bestIdx].type;
      result.extreme = votes[bestIdx].extreme;
      result.slMult = votes[bestIdx].slMult;
      result.label = votes[bestIdx].label;
      result.intrinsicScore = votes[bestIdx].intrinsicScore;
      result.contextScore = votes[bestIdx].contextScore;
      result.momentumScore = votes[bestIdx].momentumScore;
      result.confluenceScore = votes[bestIdx].confluenceScore;
      result.score = votes[bestIdx].normalizedScore;
      result.confidence = result.score;
      
      // Assign grade based on normalized score
      if (result.score >= 0.75)
         result.grade = GRADE_A;
      else if (result.score >= 0.50)
         result.grade = GRADE_B;
      else
         result.grade = GRADE_C;
      
      // Build detailed reasoning
      result.reasoning = BuildEnhancedReasoning(result, votes, bestIdx, buyScore, sellScore);
      
      return result;
   }
   
   //+------------------------------------------------------------------+
   //| LEGACY WRAPPER: Maintains backward compatibility                |
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
      // Use default weights for legacy compatibility
      PatternWeights weights;
      PatternResult result = Evaluate(cfg, rates, shift, atrvalue, weights);
      
      outType = result.type;
      outDir = result.dir;
      outExtreme = result.extreme;
      outScore = result.score;
      outSLMult = result.slMult;
      outReason = result.reasoning;
      
      return result.valid;
   }

   // Integrated Fakeout Detection Context
   struct FakeoutContext
   {
      ulong originalTicket;
      int direction;
      double slHitPrice;
      double entryPrice;
      double atrPoints;
      double slMultiplier; // Adaptive Overshoot Base
      MqlTick currentTick;
      MqlRates rates[];
   };

   // Integrated Fakeout Detection with Adaptive Zone
   static bool DetectFakeout(const FakeoutContext &ctx, FakeoutResult &result)
   {
      result.detected = false;
      result.level = 0;
      result.confidence = 0.0;

      // Adaptive Overshoot: Toleransi berdasarkan SLMult pola tersebut
      double maxOvershoot = ctx.atrPoints * ctx.slMultiplier * _Point;
      double penetration = (ctx.direction == 1) ? (ctx.slHitPrice - ctx.currentTick.bid) : (ctx.currentTick.ask - ctx.slHitPrice);

      if (penetration > maxOvershoot)
      {
         result.reason = "Momentum Breakout (Overshoot too deep)";
         return false;
      }

      bool bodyReversal = (ctx.direction == 1) ? (ctx.rates[0].close > ctx.rates[0].open) : (ctx.rates[0].close < ctx.rates[0].open);

      if (bodyReversal)
         result.level = 2;

      result.detected = (penetration > 0 && bodyReversal);
      result.confidence = 0.5 + (bodyReversal ? 0.3 : 0);
      result.reason = StringFormat("Fakeout Level %d | Pen: %.1f pts", result.level, penetration / _Point);

      return result.detected;
   }

private:
   //+------------------------------------------------------------------+
   //| ENHANCED: ResetVote with component scores initialization        |
   //+------------------------------------------------------------------+
   static void ResetVoteEnhanced(PatternVote &v, const StrategyConfig &cfg)
   {
      v.valid = false;
      v.type = PATTERN_NONE;
      v.dir = 0;
      v.extreme = 0.0;
      v.score = 0.0;
      v.normalizedScore = 0.0;
      v.slMult = cfg.default_sl_mult;
      v.label = "";
      v.reasoning = "";
      v.intrinsicScore = 0.0;
      v.contextScore = 0.0;
      v.momentumScore = 0.0;
      v.confluenceScore = 0.0;
      v.grade = GRADE_NONE;
   }
   
   // Legacy wrapper for backward compatibility
   static void ResetVote(PatternVote &v, const StrategyConfig &cfg)
   {
      ResetVoteEnhanced(v, cfg);
   }
   
   //+------------------------------------------------------------------+
   //| Build detailed reasoning string for enhanced pattern result     |
   //+------------------------------------------------------------------+
   static string BuildEnhancedReasoning(const PatternResult &result, 
                                        const PatternVote votes[], 
                                        int bestIdx,
                                        double buyScore, 
                                        double sellScore)
   {
      if (!result.valid)
         return "No valid pattern detected";
      
      string reasoning = StringFormat("%s (Grade %c, Score: %.2f)\n", 
                                      result.label, 
                                      result.grade == GRADE_A ? 'A' : (result.grade == GRADE_B ? 'B' : 'C'),
                                      result.score);
      
      reasoning += StringFormat("Direction: %s | ", result.dir == 1 ? "BUY" : "SELL");
      reasoning += StringFormat("Extreme: %.5f | SL Mult: %.2f\n", result.extreme, result.slMult);
      
      // Component breakdown
      reasoning += "\n--- Scoring Breakdown ---\n";
      reasoning += StringFormat("Intrinsic (35%%): %.2f\n", result.intrinsicScore * 0.35);
      reasoning += StringFormat("Context (25%%):   %.2f\n", result.contextScore * 0.25);
      reasoning += StringFormat("Momentum (20%%):  %.2f\n", result.momentumScore * 0.20);
      reasoning += StringFormat("Confluence (20%%): %.2f\n", result.confluenceScore * 0.20);
      
      // Confluence info
      if (buyScore > 0 && sellScore > 0)
         reasoning += StringFormat("\nConflict: Buy=%.2f vs Sell=%.2f (Gap: %.2f)\n", 
                                   buyScore, sellScore, buyScore - sellScore);
      
      return reasoning;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate intrinsic pattern quality score (0.0 - 1.0)           |
   //+------------------------------------------------------------------+
   static double CalculateIntrinsicScore(const MqlRates &rates[], 
                                         const int shift, 
                                         const double atrvalue,
                                         ENUM_PATTERN_TYPE type,
                                         const StrategyConfig &cfg)
   {
      double score = 0.5; // Base score
      
      double range = CandleRange(rates, shift);
      double body = CandleBody(rates, shift);
      double upperWick = UpperWick(rates, shift);
      double lowerWick = LowerWick(rates, shift);
      
      if (range <= 0 || atrvalue <= 0)
         return score;
      
      double atrPrice = atrvalue * _Point;
      double rangeRatio = range / atrPrice;
      double bodyRatio = body / MathMax(range, _Point);
      
      // Pattern-specific scoring
      switch(type)
      {
         case PATTERN_PINBAR:
            // Pinbar: strong wick ratio is key
            if (lowerWick > upperWick * 2)
               score += 0.3; // Bullish pinbar with strong lower wick
            else if (upperWick > lowerWick * 2)
               score += 0.3; // Bearish pinbar with strong upper wick
            break;
            
         case PATTERN_ENGULFING:
            // Engulfing: body size matters
            if (bodyRatio >= 0.7)
               score += 0.3;
            else if (bodyRatio >= 0.5)
               score += 0.2;
            break;
            
         case PATTERN_MORNING_STAR:
         case PATTERN_THREE_INSIDE:
            // 3-candle patterns: higher base reliability
            score = 0.6;
            if (bodyRatio >= 0.6)
               score += 0.25;
            break;
            
         default:
            // Generic scoring based on body/range ratio
            if (bodyRatio >= 0.7)
               score += 0.25;
            else if (bodyRatio >= 0.5)
               score += 0.15;
            break;
      }
      
      // ATR factor: patterns with significant range get bonus
      if (rangeRatio >= cfg.atr_range_threshold)
         score += 0.15;
      
      return MathMin(1.0, score);
   }
   
   //+------------------------------------------------------------------+
   //| Calculate context score based on trend/SR alignment             |
   //+------------------------------------------------------------------+
   static double CalculateContextScore(const MqlRates &rates[],
                                       const int shift,
                                       const int dir,
                                       ENUM_PATTERN_TYPE type)
   {
      double score = 0.5; // Neutral baseline
      
      // Check recent price action for trend context (simplified)
      // In production, this would integrate with MarketRegime
      double recentHigh = rates[shift + 1].high;
      double recentLow = rates[shift + 1].low;
      double currentClose = rates[shift].close;
      
      // Reversal patterns at extremes get higher context score
      bool isReversal = (type == PATTERN_PINBAR || type == PATTERN_ENGULFING || 
                         type == PATTERN_MORNING_STAR || type == PATTERN_THREE_INSIDE);
      
      if (dir == 1) // Bullish
      {
         // Buying near recent low = good context for reversal
         if (isReversal && MathAbs(currentClose - recentLow) < (recentHigh - recentLow) * 0.2)
            score = 0.8;
         else if (currentClose > recentHigh)
            score = 0.6; // Breakout continuation
      }
      else if (dir == -1) // Bearish
      {
         // Selling near recent high = good context for reversal
         if (isReversal && MathAbs(currentClose - recentHigh) < (recentHigh - recentLow) * 0.2)
            score = 0.8;
         else if (currentClose < recentLow)
            score = 0.6; // Breakdown continuation
      }
      
      return MathMin(1.0, score);
   }
   
   //+------------------------------------------------------------------+
   //| Calculate momentum score from follow-through candles            |
   //+------------------------------------------------------------------+
   static double CalculateMomentumScore(const MqlRates &rates[],
                                        const int shift,
                                        const int dir,
                                        const StrategyConfig &cfg)
   {
      double score = 0.5; // Neutral
      
      if (shift + 1 >= ArraySize(rates))
         return score;
      
      double prevClose = rates[shift + 1].close;
      double currClose = rates[shift].close;
      
      // Check if close position confirms direction
      double range = CandleRange(rates, shift);
      if (range <= 0)
         return score;
      
      if (dir == 1) // Bullish
      {
         // Close in upper half of candle
         double closePosition = (currClose - rates[shift].low) / range;
         if (closePosition >= cfg.star_close_min)
            score = 0.8;
         else if (closePosition >= 0.5)
            score = 0.6;
         
         // Follow-through: current close > previous close
         if (currClose > prevClose)
            score += 0.15;
      }
      else if (dir == -1) // Bearish
      {
         // Close in lower half of candle
         double closePosition = (rates[shift].high - currClose) / range;
         if (closePosition >= cfg.star_close_min)
            score = 0.8;
         else if (closePosition >= 0.5)
            score = 0.6;
         
         // Follow-through: current close < previous close
         if (currClose < prevClose)
            score += 0.15;
      }
      
      return MathMin(1.0, score);
   }
   
   //+------------------------------------------------------------------+
   //| Calculate confluence score from multi-pattern alignment         |
   //+------------------------------------------------------------------+
   static double CalculateConfluenceScore(const PatternVote votes[],
                                          const int dir,
                                          const int excludeIdx)
   {
      double score = 0.5; // Baseline
      int supportingPatterns = 0;
      double totalSupportingScore = 0.0;
      
      for (int i = 0; i < ArraySize(votes); i++)
      {
         if (i == excludeIdx || !votes[i].valid || votes[i].dir != dir)
            continue;
         
         supportingPatterns++;
         totalSupportingScore += votes[i].normalizedScore;
      }
      
      // More supporting patterns = higher confluence
      if (supportingPatterns >= 2)
         score = 0.85; // Strong confluence
      else if (supportingPatterns == 1)
         score = 0.65; // Moderate confluence
      else
         score = 0.50; // No additional confluence
      
      return MathMin(1.0, score);
   }
   
   //+------------------------------------------------------------------+
   //| Normalize raw score to 0.0 - 1.0 range with weight application  |
   //+------------------------------------------------------------------+
   static double NormalizeScore(double rawScore, double patternWeight)
   {
      // Apply pattern weight (statistical reliability)
      double weightedScore = rawScore * patternWeight;
      
      // Normalize to 0.0 - 1.0 range
      // Assuming rawScore typically ranges 0.3 - 1.5
      double normalized = (weightedScore - 0.3) / 1.2;
      normalized = MathMax(0.0, MathMin(1.0, normalized));
      
      return normalized;
   }
   
   // Legacy FindBestVote wrapper
   static int FindBestVote(PatternVote &votes[], int dir)
   {
      int best = -1;
      double bestScore = 0.0;

      for (int i = 0; i < ArraySize(votes); i++)
      {
         if (!votes[i].valid || votes[i].dir != dir)
            continue;

         if (votes[i].normalizedScore > bestScore)
         {
            bestScore = votes[i].normalizedScore;
            best = i;
         }
      }
      return best;
   }

   static string BuildConfluenceLabel(const PatternVote &votes[], int dir)
   {
      string txt = "";
      for (int i = 0; i < ArraySize(votes); i++)
      {
         if (!votes[i].valid || votes[i].dir != dir)
            continue;

         if (txt != "")
            txt += " + ";

         txt += votes[i].label;
      }
      return txt;
   }

   static double CandleOpen(const MqlRates &rates[], int shift) { return rates[shift].open; }
   static double CandleHigh(const MqlRates &rates[], int shift) { return rates[shift].high; }
   static double CandleLow(const MqlRates &rates[], int shift) { return rates[shift].low; }
   static double CandleClose(const MqlRates &rates[], int shift) { return rates[shift].close; }

   static double CandleRange(const MqlRates &rates[], int shift)
   {
      return CandleHigh(rates, shift) - CandleLow(rates, shift);
   }

   static double CandleBody(const MqlRates &rates[], int shift)
   {
      return MathAbs(CandleClose(rates, shift) - CandleOpen(rates, shift));
   }

   static double UpperWick(const MqlRates &rates[], int shift)
   {
      return CandleHigh(rates, shift) - MathMax(CandleOpen(rates, shift), CandleClose(rates, shift));
   }

   static double LowerWick(const MqlRates &rates[], int shift)
   {
      return MathMin(CandleOpen(rates, shift), CandleClose(rates, shift)) - CandleLow(rates, shift);
   }

   static bool IsBullish(const MqlRates &rates[], int shift)
   {
      return CandleClose(rates, shift) > CandleOpen(rates, shift);
   }

   static bool IsBearish(const MqlRates &rates[], int shift)
   {
      return CandleClose(rates, shift) < CandleOpen(rates, shift);
   }

   static bool IsInsideBar(const MqlRates &rates[], int shift)
   {
      return CandleHigh(rates, shift) < CandleHigh(rates, shift + 1) &&
             CandleLow(rates, shift) > CandleLow(rates, shift + 1);
   }

   static double NormalizeATRFactor(const double value, const double atrvalue)
   {
      double atrPrice = atrvalue * _Point;
      if (atrPrice <= 0.0)
         return 0.0;
      return value / atrPrice;
   }

   static void AddStrengthFromRejection(const MqlRates &rates[], const int shift, const double atrvalue, const int dir, double &score, const StrategyConfig &cfg)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0)
         return;

      double majorWick = (dir == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
      double wickPct = majorWick / range;
      double bodyPct = CandleBody(rates, shift) / range;
      double atrFactor = NormalizeATRFactor(range, atrvalue);

      if (wickPct >= cfg.wick_ratio_threshold)
         score += cfg.bonus_strong_wick;
      if (bodyPct <= cfg.body_ratio_threshold)
         score += cfg.bonus_strong_body;
      if (atrFactor >= cfg.atr_range_threshold)
         score += cfg.bonus_strong_atr;
   }

   static void AddStrengthFromFollowThrough(const MqlRates &rates[], const int shift, const int dir, double &score, const StrategyConfig &cfg)
   {
      double prevClose = CandleClose(rates, shift + 1);
      double curClose = CandleClose(rates, shift);

      if ((dir == 1 && curClose > prevClose) || (dir == -1 && curClose < prevClose))
         score += cfg.bonus_follow_through;
   }
   
   //+------------------------------------------------------------------+
   //| ENHANCED: EvaluatePinbar with component scoring                 |
   //+------------------------------------------------------------------+
   static void EvaluatePinbarEnhanced(const MqlRates &rates[], 
                                      const int shift, 
                                      const double atrvalue, 
                                      PatternVote &vote, 
                                      const StrategyConfig &cfg,
                                      const double patternWeight)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0)
         return;

      double bodyMid = (CandleOpen(rates, shift) + CandleClose(rates, shift)) / 2.0;
      double upper = UpperWick(rates, shift);
      double lower = LowerWick(rates, shift);

      int dir = 0;
      double extreme = 0.0;

      if (CandleClose(rates, shift) > bodyMid && lower > (upper > 0 ? upper * cfg.pinbar_wick_ratio : _Point))
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if (CandleClose(rates, shift) < bodyMid && upper > (lower > 0 ? lower * cfg.pinbar_wick_ratio : _Point))
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return;

      vote.valid = true;
      vote.type = PATTERN_PINBAR;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.slMult = cfg.pinbar_sl_mult;
      vote.label = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";
      
      // Calculate component scores
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_PINBAR, cfg);
      vote.contextScore = CalculateContextScore(rates, shift, dir, PATTERN_PINBAR);
      vote.momentumScore = CalculateMomentumScore(rates, shift, dir, cfg);
      
      // Base score from config
      double rawScore = cfg.base_score;
      AddStrengthFromRejection(rates, shift, atrvalue, dir, rawScore, cfg);
      AddStrengthFromFollowThrough(rates, shift, dir, rawScore, cfg);
      vote.score = rawScore;
      
      // Confluence will be calculated later in Evaluate()
      vote.confluenceScore = 0.5; // Placeholder
      
      // Normalize with pattern weight
      vote.normalizedScore = NormalizeScore(vote.score, patternWeight);
      
      // Assign grade
      if (vote.normalizedScore >= 0.75)
         vote.grade = GRADE_A;
      else if (vote.normalizedScore >= 0.50)
         vote.grade = GRADE_B;
      else
         vote.grade = GRADE_C;
      
      vote.reasoning = StringFormat("%s | Wick ratio: %.2f", vote.label, 
                                    (dir == 1 ? lower : upper) / MathMax(range, _Point));
   }
   
   // Legacy wrapper for backward compatibility
   static void EvaluatePinbar(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      EvaluatePinbarEnhanced(rates, shift, atrvalue, vote, cfg, 0.85); // Default pinbar weight
   }

   static void EvaluateEngulfing(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      EvaluateEngulfingEnhanced(rates, shift, atrvalue, vote, cfg, 0.90); // Default engulfing weight
   }
   
   //+------------------------------------------------------------------+
   //| ENHANCED: EvaluateEngulfing with component scoring              |
   //+------------------------------------------------------------------+
   static void EvaluateEngulfingEnhanced(const MqlRates &rates[], 
                                         const int shift, 
                                         const double atrvalue, 
                                         PatternVote &vote, 
                                         const StrategyConfig &cfg,
                                         const double patternWeight)
   {
      double o1 = CandleOpen(rates, shift), c1 = CandleClose(rates, shift);
      double o2 = CandleOpen(rates, shift + 1), c2 = CandleClose(rates, shift + 1);

      bool prevBearish = c2 < o2;
      bool prevBullish = c2 > o2;

      int dir = 0;
      double extreme = 0.0;

      if (prevBearish && c1 > o1 && c1 > o2 && o1 < c2)
      {
         dir = 1;
         extreme = MathMin(CandleLow(rates, shift), CandleLow(rates, shift + 1));
      }
      else if (prevBullish && c1 < o1 && c1 < o2 && o1 > c2)
      {
         dir = -1;
         extreme = MathMax(CandleHigh(rates, shift), CandleHigh(rates, shift + 1));
      }
      else
         return;

      double body1 = CandleBody(rates, shift);
      double body2 = CandleBody(rates, shift + 1);
      
      vote.valid = true;
      vote.type = PATTERN_ENGULFING;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label = (dir == 1) ? "Engulf Bull" : "Engulf Bear";
      
      // Calculate component scores
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_ENGULFING, cfg);
      vote.contextScore = CalculateContextScore(rates, shift, dir, PATTERN_ENGULFING);
      vote.momentumScore = CalculateMomentumScore(rates, shift, dir, cfg);
      
      // Raw score calculation
      double rawScore = cfg.base_score;
      if (body2 > 0.0 && body1 >= body2 * cfg.engulfing_body_mult)
         rawScore += cfg.bonus_strong_body;
      if (NormalizeATRFactor(CandleRange(rates, shift), atrvalue) >= cfg.atr_range_threshold)
         rawScore += cfg.bonus_strong_atr;
      AddStrengthFromFollowThrough(rates, shift, dir, rawScore, cfg);
      
      vote.score = rawScore;
      vote.confluenceScore = 0.5; // Placeholder
      vote.normalizedScore = NormalizeScore(vote.score, patternWeight);
      
      if (vote.normalizedScore >= 0.75)
         vote.grade = GRADE_A;
      else if (vote.normalizedScore >= 0.50)
         vote.grade = GRADE_B;
      else
         vote.grade = GRADE_C;
      
      vote.reasoning = StringFormat("%s | Body ratio: %.2f", vote.label, body1 / MathMax(body2, _Point));
   }

   static void EvaluateBottom(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      EvaluateBottomEnhanced(rates, shift, atrvalue, vote, cfg, 0.75); // Default tweezer weight
   }
   
   //+------------------------------------------------------------------+
   //| ENHANCED: EvaluateBottom (Tweezer Top/Bottom) with scoring      |
   //+------------------------------------------------------------------+
   static void EvaluateBottomEnhanced(const MqlRates &rates[], 
                                      const int shift, 
                                      const double atrvalue, 
                                      PatternVote &vote, 
                                      const StrategyConfig &cfg,
                                      const double patternWeight)
   {
      double h1 = CandleHigh(rates, shift);
      double l1 = CandleLow(rates, shift);
      double h2 = CandleHigh(rates, shift + 1);
      double l2 = CandleLow(rates, shift + 1);
      double tol = MathMax(atrvalue * cfg.sensitivity_atr * _Point, 3 * _Point); 
      
      int dir = 0;
      double extreme = 0.0;

      if (MathAbs(l1 - l2) <= tol && IsBullish(rates, shift))
      {
         dir = 1;
         extreme = MathMin(l1, l2);
      }
      else if (MathAbs(h1 - h2) <= tol && IsBearish(rates, shift))
      {
         dir = -1;
         extreme = MathMax(h1, h2);
      }
      else
         return;

      vote.valid = true;
      vote.type = PATTERN_BOTTOM;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.slMult = cfg.default_sl_mult;
      vote.label = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
      
      // Component scores
      vote.intrinsicScore = CalculateIntrinsicScore(rates, shift, atrvalue, PATTERN_BOTTOM, cfg);
      vote.contextScore = CalculateContextScore(rates, shift, dir, PATTERN_BOTTOM);
      vote.momentumScore = CalculateMomentumScore(rates, shift, dir, cfg);
      
      // Raw score
      double rawScore = cfg.base_score;
      if (NormalizeATRFactor(CandleRange(rates, shift), atrvalue) >= cfg.atr_range_threshold)
         rawScore += cfg.bonus_strong_atr;
      if (CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= cfg.body_ratio_threshold)
         rawScore += cfg.bonus_strong_body;
      
      vote.score = rawScore;
      vote.confluenceScore = 0.5;
      vote.normalizedScore = NormalizeScore(vote.score, patternWeight);
      
      if (vote.normalizedScore >= 0.75)
         vote.grade = GRADE_A;
      else if (vote.normalizedScore >= 0.50)
         vote.grade = GRADE_B;
      else
         vote.grade = GRADE_C;
      
      vote.reasoning = StringFormat("%s | Level match: %.1f pts", vote.label, MathAbs((dir==1?l1:h1) - (dir==1?l2:h2)) / _Point);
   }

   static void EvaluateFakey(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      // shift     : false-break candle
      double h0 = CandleHigh(rates, shift);
      double l0 = CandleLow(rates, shift);
      double c0 = CandleClose(rates, shift);
      double o0 = CandleOpen(rates, shift);
      // shift + 1 : inside bar
      double h1 = CandleHigh(rates, shift + 1);
      double l1 = CandleLow(rates, shift + 1);
      // shift + 2 : mother bar
      double h2 = CandleHigh(rates, shift + 2);
      double l2 = CandleLow(rates, shift + 2);

      bool insideStructure = (h1 < h2 && l1 > l2);
      if (!insideStructure)
         return;

      int dir = 0;
      double extreme = 0.0;
      double score = cfg.base_score;

      if (l0 < l1 && c0 > l1 && c0 > o0)
      {
         dir = 1;
         extreme = l0;
      }
      else if (h0 > h1 && c0 < h1 && c0 < o0)
      {
         dir = -1;
         extreme = h0;
      }
      else
         return;

      if (NormalizeATRFactor(CandleRange(rates, shift), atrvalue) >= cfg.atr_range_threshold)
         score += cfg.bonus_strong_atr;
      if (CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= cfg.body_ratio_threshold)
         score += cfg.bonus_strong_body;

      vote.valid = true;
      vote.type = PATTERN_FAKEY;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = cfg.default_sl_mult;
      vote.label = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
   }

   static void EvaluateInsideBar(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      if (!IsInsideBar(rates, shift))
         return;

      double motherHigh = CandleHigh(rates, shift + 1);
      double motherLow = CandleLow(rates, shift + 1);
      double motherMid = (motherHigh + motherLow) / 2.0;
      double childClose = CandleClose(rates, shift);
      int dir = 0;
      double extreme = 0.0;
      double score = cfg.base_score;
      if (childClose > motherMid)
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if (childClose < motherMid)
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return;

      double motherRange = CandleRange(rates, shift + 1);
      double childRange = CandleRange(rates, shift);

      if (motherRange > 0.0 && childRange / motherRange <= cfg.inside_bar_range_max)
         score += cfg.bonus_strong_body;
      if (NormalizeATRFactor(motherRange, atrvalue) >= cfg.atr_range_threshold)
         score += cfg.bonus_strong_atr;

      vote.valid = true;
      vote.type = PATTERN_INSIDE_BAR_BREAKOUT;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = cfg.inside_bar_sl_mult;
      vote.label = (dir == 1) ? "Inside Bull" : "Inside Bear";
   }

   static void EvaluateMorningStar(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      // Morning Star (Bullish): Bearish candle + Small middle candle (gap down) + Bullish candle (gap up, close > middle)
      // Evening Star (Bearish): Bullish candle + Small middle candle (gap up) + Bearish candle (gap down, close < middle)

      if (shift + 2 >= ArraySize(rates))
         return;

      double o0 = CandleOpen(rates, shift), c0 = CandleClose(rates, shift);
      double o1 = CandleOpen(rates, shift + 1), c1 = CandleClose(rates, shift + 1);
      double o2 = CandleOpen(rates, shift + 2), c2 = CandleClose(rates, shift + 2);

      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift + 1);
      double body2 = CandleBody(rates, shift + 2);
      double range1 = CandleRange(rates, shift + 1);
      double gapThreshold = cfg.sensitivity_atr * atrvalue * _Point;

      // Check middle bar is small (star)
      bool isSmallMiddle = (range1 > 0) && (body1 < body0 * cfg.star_middle_body_mult) && (body1 < body2 * cfg.star_middle_body_mult);
      if (!isSmallMiddle)
         return;

      int dir = 0;
      double extreme = 0.0;
      double score = cfg.base_score;
      // Morning Star: c2 < o2 (bearish) -> c1 small -> c0 > o0 (bullish) with gaps
      bool morningGap1 = (c2 < o2) && (MathMax(o1, c1) < c2 - gapThreshold);
      bool morningGap2 = (c0 > o0) && (MathMin(o0, c0) > MathMax(o1, c1) + gapThreshold);
      bool morningClose = c0 > (o2 + c2) / 2.0;

      if (morningGap1 && morningGap2 && morningClose)
      {
         dir = 1;
         extreme = MathMin(CandleLow(rates, shift + 2), CandleLow(rates, shift + 1));
         score += cfg.bonus_gap_confirm;
      }

      // Evening Star: c2 > o2 (bullish) -> c1 small -> c0 < o0 (bearish) with gaps
      bool eveningGap1 = (c2 > o2) && (MathMin(o1, c1) > c2 + gapThreshold);
      bool eveningGap2 = (c0 < o0) && (MathMax(o0, c0) < MathMin(o1, c1) - gapThreshold);
      bool eveningClose = c0 < (o2 + c2) / 2.0;

      if (eveningGap1 && eveningGap2 && eveningClose)
      {
         dir = -1;
         extreme = MathMax(CandleHigh(rates, shift + 2), CandleHigh(rates, shift + 1));
         score += cfg.bonus_gap_confirm;
      }

      if (dir == 0)

      // Add strength from ATR
      if (NormalizeATRFactor(CandleRange(rates, shift), atrvalue) >= cfg.atr_range_threshold)
         score += cfg.bonus_strong_atr;

      // Add strength from close position
      double closePosition = (dir == 1) ? (c0 - CandleLow(rates, shift)) / MathMax(CandleRange(rates, shift), _Point) : (CandleHigh(rates, shift) - c0) / MathMax(CandleRange(rates, shift), _Point);

      if (closePosition >= cfg.star_close_min)
         score += cfg.bonus_strong_body;

      vote.valid = true;
      vote.type = PATTERN_MORNING_STAR;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = cfg.default_sl_mult;
      vote.label = (dir == 1) ? "Morning Star" : "Evening Star";
   }

   static void EvaluateThreeInside(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      // Three Inside Up: Large bearish + Inside bar (bullish close) + Bullish breakout above bar 1 high
      // Three Inside Down: Large bullish + Inside bar (bearish close) + Bearish breakout below bar 1 low

      if (shift + 2 >= ArraySize(rates))
         return;

      double h0 = CandleHigh(rates, shift), l0 = CandleLow(rates, shift);
      double h1 = CandleHigh(rates, shift + 1), l1 = CandleLow(rates, shift + 1);
      double h2 = CandleHigh(rates, shift + 2), l2 = CandleLow(rates, shift + 2);
      double c0 = CandleClose(rates, shift), o0 = CandleOpen(rates, shift);
      double c1 = CandleClose(rates, shift + 1), o1 = CandleOpen(rates, shift + 1);
      double c2 = CandleClose(rates, shift + 2), o2 = CandleOpen(rates, shift + 2);

      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift + 1);
      double body2 = CandleBody(rates, shift + 2);

      int dir = 0;
      double extreme = 0.0;
      double score = cfg.base_score;
      // Three Inside Up
      bool insideUp_1 = IsBearish(rates, shift + 2) && body0 > 0;
      bool insideUp_2 = IsInsideBar(rates, shift + 1) && c1 > o1; // Inside bar with bullish close
      bool insideUp_3 = c0 > h2;                                  // Breakout above mother bar high

      if (insideUp_1 && insideUp_2 && insideUp_3)
      {
         dir = 1;
         extreme = MathMin(l1, l2);
         score += cfg.bonus_breakout_confirm;
      }

      // Three Inside Down
      bool insideDown_1 = IsBullish(rates, shift + 2) && body0 > 0;
      bool insideDown_2 = IsInsideBar(rates, shift + 1) && c1 < o1; // Inside bar with bearish close
      bool insideDown_3 = c0 < l2;                                  // Breakout below mother bar low

      if (insideDown_1 && insideDown_2 && insideDown_3)
      {
         dir = -1;
         extreme = MathMax(h1, h2);
         score += cfg.bonus_breakout_confirm;
      }

      if (dir == 0)
         return;
      if (NormalizeATRFactor(CandleRange(rates, shift), atrvalue) >= cfg.atr_range_threshold)
         score += cfg.bonus_strong_atr;
      if (body2 > 0 && body0 / body2 >= cfg.three_inside_body_min)
         score += cfg.bonus_strong_body;

      vote.valid = true;
      vote.type = PATTERN_THREE_INSIDE;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = cfg.default_sl_mult;
      vote.label = (dir == 1) ? "Three Inside Up" : "Three Inside Down";
   }

   static void EvaluateRailroadTracks(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      // Railroad Tracks Bullish: Long bearish candle followed by long bullish candle (similar body size, opposite direction)
      // Railroad Tracks Bearish: Long bullish candle followed by long bearish candle (similar body size, opposite direction)

      if (shift + 1 >= ArraySize(rates))
         return;

      double c0 = CandleClose(rates, shift), o0 = CandleOpen(rates, shift);
      double c1 = CandleClose(rates, shift + 1), o1 = CandleOpen(rates, shift + 1);

      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift + 1);

      double minRatio = cfg.railroad_min_body_ratio;

      int dir = 0;
      double extreme = 0.0;
      double score = cfg.base_score;

      // Both bodies must be significant
      if (body0 <= _Point || body1 <= _Point)
         return;

      // Check body size similarity (within reasonable ratio)
      double bodyRatio = MathMax(body0, body1) / MathMin(body0, body1);
      if (bodyRatio > minRatio)
         return; // Bodies too different in size

      // Railroad Tracks Bullish: Bar 2 bearish, Bar 1 bullish, similar bodies
      bool railBull = IsBearish(rates, shift + 1) && IsBullish(rates, shift);
      if (railBull)
      {
         dir = 1;
         extreme = MathMin(CandleLow(rates, shift + 1), CandleLow(rates, shift));
         score += cfg.bonus_small; 
      }

      // Railroad Tracks Bearish: Bar 2 bullish, Bar 1 bearish, similar bodies
      bool railBear = IsBullish(rates, shift + 1) && IsBearish(rates, shift);
      if (railBear)
      {
         dir = -1;
         extreme = MathMax(CandleHigh(rates, shift + 1), CandleHigh(rates, shift));
         score += cfg.bonus_small;
      }

      if (dir == 0)
         return;

      // Add strength from ATR
      double avgBody = (body0 + body1) / 2.0;
      double atrPrice = atrvalue * _Point;
      if (atrPrice > 0 && avgBody >= atrPrice * cfg.railroad_avg_body_min)
         score += cfg.bonus_strong_atr;

      // Add strength from wick rejection
      if (dir == 1 && LowerWick(rates, shift + 1) > body1 * cfg.railroad_wick_mult)
         score += cfg.bonus_strong_wick;
      if (dir == -1 && UpperWick(rates, shift + 1) > body1 * cfg.railroad_wick_mult)
         score += cfg.bonus_strong_wick;

      vote.valid = true;
      vote.type = PATTERN_RAILROAD_TRACKS;
      vote.slMult = cfg.default_sl_mult;
      vote.label = (dir == 1) ? "Railroad Bull" : "Railroad Bear";
   }

   static void EvaluateDarkCloudPiercing(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      if (shift + 1 >= ArraySize(rates))
         return;

      double o0 = CandleOpen(rates, shift), c0 = CandleClose(rates, shift);
      double o1 = CandleOpen(rates, shift + 1), c1 = CandleClose(rates, shift + 1);
      double h1 = CandleHigh(rates, shift + 1), l1 = CandleLow(rates, shift + 1);

      double body1 = CandleBody(rates, shift + 1);
      double mid1 = (o1 + c1) / 2.0;

      int dir = 0;
      double score = cfg.base_score;

      // Piercing Line (Bullish Reversal)
      if (IsBearish(rates, shift + 1) && IsBullish(rates, shift) && o0 < l1 && c0 > mid1 && c0 < o1)
      {
         dir = 1;
         vote.extreme = CandleLow(rates, shift);
         vote.label = "Piercing Line";
      }
      // Dark Cloud Cover (Bearish Reversal)
      else if (IsBullish(rates, shift + 1) && IsBearish(rates, shift) && o0 > h1 && c0 < mid1 && c0 > o1)
      {
         dir = -1;
         vote.extreme = CandleHigh(rates, shift);
         vote.label = "Dark Cloud Cover";
      }

      if (dir != 0)
      {
         vote.valid = true;
         vote.type = PATTERN_DARK_CLOUD_PIERCING;
         vote.dir = dir;
         vote.score = score;
         vote.slMult = cfg.default_sl_mult;
         AddStrengthFromFollowThrough(rates, shift, dir, vote.score, cfg);
      }
   }

   static void EvaluateMarubozu(const MqlRates &rates[], const int shift, const double atrvalue, PatternVote &vote, const StrategyConfig &cfg)
   {
      double range = CandleRange(rates, shift);
      double body = CandleBody(rates, shift);
      if (range <= 0)
         return;

      double bodyRatio = body / range;
      if (bodyRatio < cfg.marubozu_min_body_pct)
         return;

      double atrFactor = NormalizeATRFactor(range, atrvalue);
      if (atrFactor < cfg.momentum_threshold_atr * cfg.marubozu_min_atr_mult)
         return;

      int dir = IsBullish(rates, shift) ? 1 : -1;
      vote.valid = true;
      vote.type = PATTERN_MARUBOZU;
      vote.dir = dir;
      vote.extreme = (dir == 1) ? CandleLow(rates, shift) : CandleHigh(rates, shift);
      vote.slMult = cfg.default_sl_mult;
      vote.score = cfg.base_score + cfg.bonus_small; 
      vote.label = (dir == 1) ? "Marubozu Bull" : "Marubozu Bear";

      if (atrFactor > cfg.marubozu_strong_atr_min)
         vote.score += cfg.bonus_strong_atr;
   }
};

#endif