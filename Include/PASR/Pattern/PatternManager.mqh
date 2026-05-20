//+------------------------------------------------------------------+
//|  Pattern/PatternManager.mqh                                      |
//|  PASR Framework — Pattern Orchestrator                           |
//|  Single Responsibility: orchestrate the 10-evaluator vote loop,  |
//|  resolve conflicts, build final PatternResult.                   |
//|                                                                  |
//|  Dependency graph (no cycles):                                   |
//|    Config.Types ← PatternTypes ← CandleUtils ← ScoreEngine      |
//|                                              ← Evaluators        |
//|                              ← FakeoutDetector                   |
//|                  PatternManager (this file) ← all above          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property strict

#ifndef __PATTERN_MANAGER_NEW_MQH__
#define __PATTERN_MANAGER_NEW_MQH__

#include "PatternTypes.mqh"
#include "CandleUtils.mqh"
#include "ScoreEngine.mqh"
#include "Evaluators.mqh"
#include "FakeoutDetector.mqh"

class PatternManager
{
public:
   //+------------------------------------------------------------------+
   //| Main entry: run all 10 evaluators, resolve conflict, return best  |
   //+------------------------------------------------------------------+
   static PatternResult Evaluate(const StrategyConfig &cfg,
                                 const MqlRates &rates[],
                                 const int shift,
                                 const double atrvalue,
                                 const PatternWeights &weights)
   {
      PatternResult result;
      _InitResult(result);

      if (atrvalue <= 0)
      {
         result.reasoning = "Invalid ATR parameter (<=0)";
         return result;
      }

      // PM-BUG-4 guard: worst-case access is rates[shift+2] for 3-bar patterns
      if (shift < 2 || (shift + 2) >= ArraySize(rates))
      {
         result.reasoning = StringFormat(
            "Insufficient bar history (shift=%d, size=%d, need shift>=2 and shift+2<size)",
            shift, ArraySize(rates));
         return result;
      }

      // --- Pass 1: run all evaluators --------------------------------
      PatternVote votes[10];
      for (int i = 0; i < 10; i++) ScoreEngine::ResetVote(votes[i], cfg);

      Evaluators::Pinbar(          rates, shift, atrvalue, votes[0], cfg, weights.pinbarWeight);
      Evaluators::Engulfing(       rates, shift, atrvalue, votes[1], cfg, weights.engulfingWeight);
      Evaluators::Tweezer(         rates, shift, atrvalue, votes[2], cfg, weights.tweezerWeight);
      Evaluators::Fakey(           rates, shift, atrvalue, votes[3], cfg, weights.fakeyWeight);
      Evaluators::InsideBar(       rates, shift, atrvalue, votes[4], cfg, weights.insideBarWeight);
      Evaluators::MorningStar(     rates, shift, atrvalue, votes[5], cfg, weights.morningStarWeight);
      Evaluators::ThreeInside(     rates, shift, atrvalue, votes[6], cfg, weights.threeInsideWeight);
      Evaluators::RailroadTracks(  rates, shift, atrvalue, votes[7], cfg, weights.railroadWeight);
      Evaluators::DarkCloudPiercing(rates, shift, atrvalue, votes[8], cfg, weights.darkCloudWeight);
      Evaluators::Marubozu(        rates, shift, atrvalue, votes[9], cfg, weights.marubozuWeight);

      // --- Pass 2: confluence scores now that all votes exist --------
      for (int i = 0; i < 10; i++)
         if (votes[i].valid)
            votes[i].confluenceScore = ScoreEngine::Confluence(votes, votes[i].dir, i);

      // --- Pass 3: find best directional vote -----------------------
      double buyScore = 0.0, sellScore = 0.0;
      int bestBuyIdx  = -1,  bestSellIdx = -1;

      for (int i = 0; i < 10; i++)
      {
         if (!votes[i].valid) continue;
         if (votes[i].dir == 1 && votes[i].normalizedScore > buyScore)
         { buyScore = votes[i].normalizedScore; bestBuyIdx = i; }
         else if (votes[i].dir == -1 && votes[i].normalizedScore > sellScore)
         { sellScore = votes[i].normalizedScore; bestSellIdx = i; }
      }

      // --- Conflict filter ------------------------------------------
      double dominanceGap = MathMax(buyScore, sellScore) - MathMin(buyScore, sellScore);
      if (dominanceGap < cfg.min_dominance_gap)
      {
         result.reasoning = StringFormat(
            "Confluence conflict | buy=%.2f sell=%.2f | Gap %.2f < min %.2f",
            buyScore, sellScore, dominanceGap, cfg.min_dominance_gap);
         return result;
      }

      result.dir  = (buyScore > sellScore) ? 1 : -1;
      int bestIdx = (result.dir == 1) ? bestBuyIdx : bestSellIdx;

      if (bestIdx < 0)
      {
         result.reasoning = "No valid directional pattern detected";
         return result;
      }

      // --- Assemble result ------------------------------------------
      result.valid           = true;
      result.type            = votes[bestIdx].type;
      result.extreme         = votes[bestIdx].extreme;
      result.slMult          = votes[bestIdx].slMult;
      result.label           = votes[bestIdx].label;
      result.intrinsicScore  = votes[bestIdx].intrinsicScore;
      result.contextScore    = votes[bestIdx].contextScore;
      result.momentumScore   = votes[bestIdx].momentumScore;
      result.confluenceScore = votes[bestIdx].confluenceScore;
      result.score           = votes[bestIdx].normalizedScore;
      result.confidence      = result.score;

      if      (result.score >= 0.75) result.grade = GRADE_A;
      else if (result.score >= 0.50) result.grade = GRADE_B;
      else                           result.grade = GRADE_C;

      result.reasoning = _BuildReasoning(result, votes, bestIdx, buyScore, sellScore);
      return result;
   }

   //+------------------------------------------------------------------+
   //| Legacy wrapper — preserves API for existing callers             |
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
   //| Fakeout pass-through (keeps API surface consistent)             |
   //+------------------------------------------------------------------+
   static bool DetectFakeout(const FakeoutDetector::Context &ctx, FakeoutResult &result)
   {
      return FakeoutDetector::Detect(ctx, result);
   }

private:
   static void _InitResult(PatternResult &r)
   {
      r.valid           = false;
      r.type            = PATTERN_NONE;
      r.dir             = 0;
      r.extreme         = 0.0;
      r.score           = 0.0;
      r.grade           = GRADE_NONE;
      r.slMult          = 1.0;
      r.label           = "";
      r.reasoning       = "";
      r.confidence      = 0.0;
      r.intrinsicScore  = 0.0;
      r.contextScore    = 0.0;
      r.momentumScore   = 0.0;
      r.confluenceScore = 0.0;
      r.timestamp       = TimeCurrent();
   }

   static string _BuildReasoning(const PatternResult &r,
                                  const PatternVote votes[],
                                  int bestIdx,
                                  double buyScore, double sellScore)
   {
      if (!r.valid) return "No valid pattern detected";
      string s = StringFormat("%s (Grade %c, Score: %.2f)\n",
                              r.label,
                              r.grade == GRADE_A ? 'A' : (r.grade == GRADE_B ? 'B' : 'C'),
                              r.score);
      s += StringFormat("Dir: %s | Extreme: %.5f | SLMult: %.2f\n",
                        r.dir == 1 ? "BUY" : "SELL", r.extreme, r.slMult);
      s += "--- Scoring Breakdown ---\n";
      s += StringFormat("Intrinsic  (35%%): %.3f\n", r.intrinsicScore  * 0.35);
      s += StringFormat("Context    (25%%): %.3f\n", r.contextScore    * 0.25);
      s += StringFormat("Momentum   (20%%): %.3f\n", r.momentumScore   * 0.20);
      s += StringFormat("Confluence (20%%): %.3f\n", r.confluenceScore * 0.20);
      if (buyScore > 0 && sellScore > 0)
         s += StringFormat("Conflict: Buy=%.2f Sell=%.2f Gap=%.2f\n",
                           buyScore, sellScore, buyScore - sellScore);
      return s;
   }
};

#endif // __PATTERN_MANAGER_NEW_MQH__
