//+------------------------------------------------------------------+
//|  Pattern/ScoreEngine.mqh                                         |
//|  PASR Framework — Scoring & Normalisation Layer                  |
//|  Single Responsibility: compute the four score components and    |
//|  normalise raw accumulated scores to [0..1].                     |
//|  Depends only on: PatternTypes, CandleUtils, Config.Types        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property strict

#ifndef __SCORE_ENGINE_MQH__
#define __SCORE_ENGINE_MQH__

#include "PatternTypes.mqh"
#include "CandleUtils.mqh"

class ScoreEngine
{
public:
   //------------------------------------------------------------------
   //  IntrinsicScore — how structurally strong is the candle itself?
   //------------------------------------------------------------------
   static double Intrinsic(const MqlRates &rates[], int shift,
                           double atrvalue, ENUM_PATTERN_TYPE type,
                           const StrategyConfig &cfg)
   {
      double range = CandleUtils::Range(rates, shift);
      double body  = CandleUtils::Body(rates, shift);
      if (range <= 0 || atrvalue <= 0) return 0.5;

      double atrPrice   = atrvalue * _Point;
      double rangeRatio = range / atrPrice;
      double bodyRatio  = body  / MathMax(range, _Point);
      double score      = 0.5;

      switch (type)
      {
         case PATTERN_PINBAR:
         {
            double up = CandleUtils::UpperWick(rates, shift);
            double lo = CandleUtils::LowerWick(rates, shift);
            if      (lo > up * 2.0) score += 0.3;
            else if (up > lo * 2.0) score += 0.3;
            break;
         }
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

   //------------------------------------------------------------------
   //  ContextScore — is the candle in the right market position?
   //------------------------------------------------------------------
   static double Context(const MqlRates &rates[], int shift,
                         int dir, ENUM_PATTERN_TYPE type)
   {
      double score      = 0.5;
      double recentHigh = rates[shift + 1].high;
      double recentLow  = rates[shift + 1].low;
      double curClose   = rates[shift].close;
      bool   isReversal = (type == PATTERN_PINBAR     ||
                           type == PATTERN_ENGULFING  ||
                           type == PATTERN_MORNING_STAR ||
                           type == PATTERN_THREE_INSIDE);

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

   //------------------------------------------------------------------
   //  MomentumScore — close position and follow-through strength
   //------------------------------------------------------------------
   static double Momentum(const MqlRates &rates[], int shift,
                          int dir, const StrategyConfig &cfg)
   {
      double score = 0.5;
      if (shift + 1 >= ArraySize(rates)) return score;
      double range = CandleUtils::Range(rates, shift);
      if (range <= 0) return score;

      double prevClose = rates[shift + 1].close;
      double currClose = rates[shift].close;

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

   //------------------------------------------------------------------
   //  ConfluenceScore — how many other valid votes agree with dir?   |
   //  excludeIdx prevents the vote from counting itself.             |
   //------------------------------------------------------------------
   static double Confluence(const PatternVote votes[], int dir, int excludeIdx)
   {
      int n = 0;
      for (int i = 0; i < 10; i++)
      {
         if (i == excludeIdx || !votes[i].valid || votes[i].dir != dir) continue;
         n++;
      }
      if      (n >= 2) return 0.85;
      else if (n == 1) return 0.65;
      return 0.50;
   }

   //------------------------------------------------------------------
   //  Normalise — map a raw accumulated score to [0..1]             |
   //  Formula: (raw * weight - 0.3) / 1.2, clamped to [0,1]        |
   //------------------------------------------------------------------
   static double Normalize(double rawScore, double patternWeight)
   {
      double n = (rawScore * patternWeight - 0.3) / 1.2;
      return MathMax(0.0, MathMin(1.0, n));
   }

   //------------------------------------------------------------------
   //  AssignGrade — derive enum grade from normalised score          |
   //------------------------------------------------------------------
   static void AssignGrade(PatternVote &v)
   {
      if      (v.normalizedScore >= 0.75) v.grade = GRADE_A;
      else if (v.normalizedScore >= 0.50) v.grade = GRADE_B;
      else                                v.grade = GRADE_C;
   }

   //------------------------------------------------------------------
   //  AddRejectionBonus — bonus from wick/body/ATR rejection quality |
   //------------------------------------------------------------------
   static void AddRejectionBonus(const MqlRates &rates[], int shift,
                                 double atrvalue, int dir,
                                 double &score, const StrategyConfig &cfg)
   {
      double range = CandleUtils::Range(rates, shift);
      if (range <= 0.0) return;
      double majorWick = (dir == 1) ? CandleUtils::LowerWick(rates, shift)
                                    : CandleUtils::UpperWick(rates, shift);
      if (majorWick / range                              >= cfg.wick_ratio_threshold) score += cfg.bonus_strong_wick;
      if (CandleUtils::Body(rates,shift) / range         <= cfg.body_ratio_threshold) score += cfg.bonus_strong_body;
      if (CandleUtils::ATRFactor(range, atrvalue)        >= cfg.atr_range_threshold)  score += cfg.bonus_strong_atr;
   }

   //------------------------------------------------------------------
   //  AddFollowThroughBonus — bonus when close confirms direction     |
   //------------------------------------------------------------------
   static void AddFollowThroughBonus(const MqlRates &rates[], int shift,
                                     int dir, double &score,
                                     const StrategyConfig &cfg)
   {
      double prev = CandleUtils::Close(rates, shift + 1);
      double cur  = CandleUtils::Close(rates, shift);
      if ((dir == 1 && cur > prev) || (dir == -1 && cur < prev))
         score += cfg.bonus_follow_through;
   }

   //------------------------------------------------------------------
   //  ResetVote — zero-initialise a PatternVote before an evaluator  |
   //------------------------------------------------------------------
   static void ResetVote(PatternVote &v, const StrategyConfig &cfg)
   {
      v.valid           = false;
      v.type            = PATTERN_NONE;
      v.dir             = 0;
      v.extreme         = 0.0;
      v.score           = 0.0;
      v.normalizedScore = 0.0;
      v.slMult          = cfg.default_sl_mult;
      v.label           = "";
      v.reasoning       = "";
      v.intrinsicScore  = 0.0;
      v.contextScore    = 0.0;
      v.momentumScore   = 0.0;
      v.confluenceScore = 0.0;
      v.grade           = GRADE_NONE;
   }
};

#endif // __SCORE_ENGINE_MQH__
