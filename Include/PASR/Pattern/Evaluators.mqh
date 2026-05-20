//+------------------------------------------------------------------+
//|  Pattern/Evaluators.mqh                                          |
//|  PASR Framework — Pattern Evaluator Layer                        |
//|  10 Enhanced evaluators + legacy wrappers.                       |
//|  Each evaluator is a pure static method; all share the same      |
//|  signature template so a dispatch table can be added later.      |
//|  Depends: PatternTypes, CandleUtils, ScoreEngine, Config.Types   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property strict

#ifndef __EVALUATORS_MQH__
#define __EVALUATORS_MQH__

#include "PatternTypes.mqh"
#include "CandleUtils.mqh"
#include "ScoreEngine.mqh"

class Evaluators
{
public:
   //==================================================================
   //  PINBAR
   //==================================================================
   static void Pinbar(const MqlRates &rates[], int shift,
                      double atrvalue, PatternVote &vote,
                      const StrategyConfig &cfg, double w)
   {
      double range   = CandleUtils::Range(rates, shift);
      if (range <= 0.0) return;
      double bodyMid = (CandleUtils::Open(rates,shift) + CandleUtils::Close(rates,shift)) / 2.0;
      double upper   = CandleUtils::UpperWick(rates, shift);
      double lower   = CandleUtils::LowerWick(rates, shift);
      int    dir     = 0;
      double extreme = 0.0;

      if (CandleUtils::Close(rates,shift) > bodyMid &&
          lower > (upper > 0 ? upper * cfg.pinbar_wick_ratio : _Point))
      { dir =  1; extreme = CandleUtils::Low(rates,shift); }
      else if (CandleUtils::Close(rates,shift) < bodyMid &&
               upper > (lower > 0 ? lower * cfg.pinbar_wick_ratio : _Point))
      { dir = -1; extreme = CandleUtils::High(rates,shift); }
      else return;

      vote.valid          = true;
      vote.type           = PATTERN_PINBAR;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.pinbar_sl_mult;
      vote.label          = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_PINBAR, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_PINBAR);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);

      double raw = cfg.base_score;
      ScoreEngine::AddRejectionBonus(rates, shift, atrvalue, dir, raw, cfg);
      ScoreEngine::AddFollowThroughBonus(rates, shift, dir, raw, cfg);
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
      vote.reasoning = StringFormat("%s | Wick ratio: %.2f", vote.label,
                                    (dir == 1 ? lower : upper) / MathMax(range, _Point));
   }

   //==================================================================
   //  ENGULFING
   //==================================================================
   static void Engulfing(const MqlRates &rates[], int shift,
                         double atrvalue, PatternVote &vote,
                         const StrategyConfig &cfg, double w)
   {
      double o1 = CandleUtils::Open(rates,shift),   c1 = CandleUtils::Close(rates,shift);
      double o2 = CandleUtils::Open(rates,shift+1), c2 = CandleUtils::Close(rates,shift+1);
      int dir = 0; double extreme = 0.0;

      if      (c2 < o2 && c1 > o1 && c1 > o2 && o1 < c2)
      { dir =  1; extreme = MathMin(CandleUtils::Low(rates,shift), CandleUtils::Low(rates,shift+1)); }
      else if (c2 > o2 && c1 < o1 && c1 < o2 && o1 > c2)
      { dir = -1; extreme = MathMax(CandleUtils::High(rates,shift),CandleUtils::High(rates,shift+1)); }
      else return;

      double body1 = CandleUtils::Body(rates, shift);
      double body2 = CandleUtils::Body(rates, shift+1);

      vote.valid          = true;
      vote.type           = PATTERN_ENGULFING;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.default_sl_mult;
      vote.label          = (dir == 1) ? "Engulf Bull" : "Engulf Bear";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_ENGULFING, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_ENGULFING);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);

      double raw = cfg.base_score;
      if (body2 > 0.0 && body1 >= body2 * cfg.engulfing_body_mult) raw += cfg.bonus_strong_body;
      if (CandleUtils::ATRFactor(CandleUtils::Range(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      ScoreEngine::AddFollowThroughBonus(rates, shift, dir, raw, cfg);
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
      vote.reasoning = StringFormat("%s | Body ratio: %.2f", vote.label, body1 / MathMax(body2, _Point));
   }

   //==================================================================
   //  TWEEZER BOTTOM / TOP
   //==================================================================
   static void Tweezer(const MqlRates &rates[], int shift,
                       double atrvalue, PatternVote &vote,
                       const StrategyConfig &cfg, double w)
   {
      double tol = MathMax(atrvalue * cfg.sensitivity_atr * _Point, 3 * _Point);
      int dir = 0; double extreme = 0.0;

      if (MathAbs(CandleUtils::Low(rates,shift) - CandleUtils::Low(rates,shift+1)) <= tol
          && CandleUtils::IsBullish(rates,shift))
      { dir =  1; extreme = MathMin(CandleUtils::Low(rates,shift), CandleUtils::Low(rates,shift+1)); }
      else if (MathAbs(CandleUtils::High(rates,shift) - CandleUtils::High(rates,shift+1)) <= tol
               && CandleUtils::IsBearish(rates,shift))
      { dir = -1; extreme = MathMax(CandleUtils::High(rates,shift),CandleUtils::High(rates,shift+1)); }
      else return;

      vote.valid          = true;
      vote.type           = PATTERN_BOTTOM;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.default_sl_mult;
      vote.label          = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_BOTTOM, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_BOTTOM);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);

      double raw = cfg.base_score;
      double range = CandleUtils::Range(rates, shift);
      if (CandleUtils::ATRFactor(range, atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      if (CandleUtils::Body(rates,shift) / MathMax(range, _Point) >= cfg.body_ratio_threshold) raw += cfg.bonus_strong_body;
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
   }

   //==================================================================
   //  FAKEY (False Breakout)
   //==================================================================
   static void Fakey(const MqlRates &rates[], int shift,
                     double atrvalue, PatternVote &vote,
                     const StrategyConfig &cfg, double w)
   {
      if (shift + 2 >= ArraySize(rates)) return;
      double h1 = CandleUtils::High(rates,shift+1), l1 = CandleUtils::Low(rates,shift+1);
      double h2 = CandleUtils::High(rates,shift+2), l2 = CandleUtils::Low(rates,shift+2);
      if (!(h1 < h2 && l1 > l2)) return;   // shift+1 must be inside shift+2

      double h0 = CandleUtils::High(rates,shift), l0 = CandleUtils::Low(rates,shift);
      double o0 = CandleUtils::Open(rates,shift), c0 = CandleUtils::Close(rates,shift);
      int dir = 0; double extreme = 0.0;

      if      (l0 < l1 && c0 > l1 && c0 > o0) { dir =  1; extreme = l0; }
      else if (h0 > h1 && c0 < h1 && c0 < o0) { dir = -1; extreme = h0; }
      else return;

      vote.valid          = true;
      vote.type           = PATTERN_FAKEY;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.default_sl_mult;
      vote.label          = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_FAKEY, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_FAKEY);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);

      double raw   = cfg.base_score;
      double range = CandleUtils::Range(rates, shift);
      if (CandleUtils::ATRFactor(range, atrvalue) >= cfg.atr_range_threshold)  raw += cfg.bonus_strong_atr;
      if (CandleUtils::Body(rates,shift) / MathMax(range,_Point) >= cfg.body_ratio_threshold) raw += cfg.bonus_strong_body;
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
      vote.reasoning = StringFormat("%s | False break: %.1f pts", vote.label,
                                    (dir == 1 ? l1 - l0 : h0 - h1) / _Point);
   }

   //==================================================================
   //  INSIDE BAR
   //==================================================================
   static void InsideBar(const MqlRates &rates[], int shift,
                         double atrvalue, PatternVote &vote,
                         const StrategyConfig &cfg, double w)
   {
      if (!CandleUtils::IsInsideBar(rates, shift)) return;
      double motherMid  = (CandleUtils::High(rates,shift+1) + CandleUtils::Low(rates,shift+1)) / 2.0;
      double childClose = CandleUtils::Close(rates, shift);
      int dir = 0; double extreme = 0.0;

      if      (childClose > motherMid) { dir =  1; extreme = CandleUtils::Low(rates,shift); }
      else if (childClose < motherMid) { dir = -1; extreme = CandleUtils::High(rates,shift); }
      else return;

      double motherRange = CandleUtils::Range(rates, shift+1);
      double childRange  = CandleUtils::Range(rates, shift);

      vote.valid          = true;
      vote.type           = PATTERN_INSIDE_BAR_BREAKOUT;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.inside_bar_sl_mult;
      vote.label          = (dir == 1) ? "Inside Bull" : "Inside Bear";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_INSIDE_BAR_BREAKOUT, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_INSIDE_BAR_BREAKOUT);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);

      double raw = cfg.base_score;
      if (motherRange > 0.0 && childRange / motherRange <= cfg.inside_bar_range_max) raw += cfg.bonus_strong_body;
      if (CandleUtils::ATRFactor(motherRange, atrvalue) >= cfg.atr_range_threshold)   raw += cfg.bonus_strong_atr;
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
   }

   //==================================================================
   //  MORNING STAR / EVENING STAR
   //==================================================================
   static void MorningStar(const MqlRates &rates[], int shift,
                           double atrvalue, PatternVote &vote,
                           const StrategyConfig &cfg, double w)
   {
      if (shift + 2 >= ArraySize(rates)) return;
      double o0=CandleUtils::Open(rates,shift),  c0=CandleUtils::Close(rates,shift);
      double o1=CandleUtils::Open(rates,shift+1),c1=CandleUtils::Close(rates,shift+1);
      double o2=CandleUtils::Open(rates,shift+2),c2=CandleUtils::Close(rates,shift+2);
      double body0 = CandleUtils::Body(rates,shift);
      double body1 = CandleUtils::Body(rates,shift+1);
      double body2 = CandleUtils::Body(rates,shift+2);
      double range1 = CandleUtils::Range(rates,shift+1);
      double gap    = cfg.sensitivity_atr * atrvalue * _Point;

      bool isSmallMiddle = (range1 > 0)
                         && (body1 < body0 * cfg.star_middle_body_mult)
                         && (body1 < body2 * cfg.star_middle_body_mult);
      if (!isSmallMiddle) return;

      int dir = 0; double extreme = 0.0;
      double raw = cfg.base_score;

      // Morning Star (bull)
      bool mGap1  = (c2 < o2) && (MathMax(o1,c1) < c2 - gap);
      bool mGap2  = (c0 > o0) && (MathMin(o0,c0) > MathMax(o1,c1) + gap);
      bool mClose = c0 > (o2 + c2) / 2.0;
      if (mGap1 && mGap2 && mClose)
      { dir = 1; extreme = MathMin(CandleUtils::Low(rates,shift+2), CandleUtils::Low(rates,shift+1)); raw += cfg.bonus_gap_confirm; }

      // Evening Star (bear)
      bool eGap1  = (c2 > o2) && (MathMin(o1,c1) > c2 + gap);
      bool eGap2  = (c0 < o0) && (MathMax(o0,c0) < MathMin(o1,c1) - gap);
      bool eClose = c0 < (o2 + c2) / 2.0;
      if (eGap1 && eGap2 && eClose)
      { dir = -1; extreme = MathMax(CandleUtils::High(rates,shift+2), CandleUtils::High(rates,shift+1)); raw += cfg.bonus_gap_confirm; }

      if (dir == 0) return;  // PM-BUG-1 guard preserved

      if (CandleUtils::ATRFactor(CandleUtils::Range(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      double closePos = (dir == 1)
         ? (c0 - CandleUtils::Low(rates,shift))  / MathMax(CandleUtils::Range(rates,shift), _Point)
         : (CandleUtils::High(rates,shift) - c0) / MathMax(CandleUtils::Range(rates,shift), _Point);
      if (closePos >= cfg.star_close_min) raw += cfg.bonus_strong_body;

      vote.valid          = true;
      vote.type           = PATTERN_MORNING_STAR;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.default_sl_mult;
      vote.label          = (dir == 1) ? "Morning Star" : "Evening Star";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_MORNING_STAR, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_MORNING_STAR);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
   }

   //==================================================================
   //  THREE INSIDE UP / DOWN
   //==================================================================
   static void ThreeInside(const MqlRates &rates[], int shift,
                           double atrvalue, PatternVote &vote,
                           const StrategyConfig &cfg, double w)
   {
      if (shift + 2 >= ArraySize(rates)) return;
      double h2 = CandleUtils::High(rates,shift+2), l2 = CandleUtils::Low(rates,shift+2);
      double c0 = CandleUtils::Close(rates,shift);
      double c1 = CandleUtils::Close(rates,shift+1), o1 = CandleUtils::Open(rates,shift+1);
      double body0 = CandleUtils::Body(rates,shift);
      double body2 = CandleUtils::Body(rates,shift+2);
      int dir = 0; double extreme = 0.0; double raw = cfg.base_score;

      bool upOk = CandleUtils::IsBearish(rates,shift+2) && body0 > 0
               && CandleUtils::IsInsideBar(rates,shift+1) && c1 > o1 && c0 > h2;
      if (upOk)  { dir =  1; extreme = MathMin(CandleUtils::Low(rates,shift+1), l2); raw += cfg.bonus_breakout_confirm; }

      bool dnOk = CandleUtils::IsBullish(rates,shift+2) && body0 > 0
               && CandleUtils::IsInsideBar(rates,shift+1) && c1 < o1 && c0 < l2;
      if (dnOk)  { dir = -1; extreme = MathMax(CandleUtils::High(rates,shift+1),CandleUtils::High(rates,shift+2)); raw += cfg.bonus_breakout_confirm; }

      if (dir == 0) return;
      if (CandleUtils::ATRFactor(CandleUtils::Range(rates,shift), atrvalue) >= cfg.atr_range_threshold) raw += cfg.bonus_strong_atr;
      if (body2 > 0 && body0 / body2 >= cfg.three_inside_body_min) raw += cfg.bonus_strong_body;

      vote.valid          = true;
      vote.type           = PATTERN_THREE_INSIDE;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.default_sl_mult;
      vote.label          = (dir == 1) ? "Three Inside Up" : "Three Inside Down";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_THREE_INSIDE, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_THREE_INSIDE);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
   }

   //==================================================================
   //  RAILROAD TRACKS
   //==================================================================
   static void RailroadTracks(const MqlRates &rates[], int shift,
                               double atrvalue, PatternVote &vote,
                               const StrategyConfig &cfg, double w)
   {
      if (shift + 1 >= ArraySize(rates)) return;
      double body0 = CandleUtils::Body(rates, shift);
      double body1 = CandleUtils::Body(rates, shift+1);
      if (body0 <= _Point || body1 <= _Point) return;
      if (MathMax(body0,body1) / MathMin(body0,body1) > cfg.railroad_min_body_ratio) return;

      int dir = 0; double extreme = 0.0; double raw = cfg.base_score;
      if (CandleUtils::IsBearish(rates,shift+1) && CandleUtils::IsBullish(rates,shift))
      { dir =  1; extreme = MathMin(CandleUtils::Low(rates,shift+1),CandleUtils::Low(rates,shift)); raw += cfg.bonus_small; }
      else if (CandleUtils::IsBullish(rates,shift+1) && CandleUtils::IsBearish(rates,shift))
      { dir = -1; extreme = MathMax(CandleUtils::High(rates,shift+1),CandleUtils::High(rates,shift)); raw += cfg.bonus_small; }
      if (dir == 0) return;

      double avgBody  = (body0 + body1) / 2.0;
      double atrPrice = atrvalue * _Point;
      if (atrPrice > 0 && avgBody >= atrPrice * cfg.railroad_avg_body_min) raw += cfg.bonus_strong_atr;
      if (dir ==  1 && CandleUtils::LowerWick(rates,shift+1) > body1 * cfg.railroad_wick_mult) raw += cfg.bonus_strong_wick;
      if (dir == -1 && CandleUtils::UpperWick(rates,shift+1) > body1 * cfg.railroad_wick_mult) raw += cfg.bonus_strong_wick;

      vote.valid          = true;
      vote.type           = PATTERN_RAILROAD_TRACKS;
      vote.dir            = dir;
      vote.extreme        = extreme;
      vote.slMult         = cfg.default_sl_mult;
      vote.label          = (dir == 1) ? "Railroad Bull" : "Railroad Bear";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_RAILROAD_TRACKS, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_RAILROAD_TRACKS);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
      vote.reasoning = StringFormat("%s | Body ratio: %.2f", vote.label, MathMax(body0,body1)/MathMin(body0,body1));
   }

   //==================================================================
   //  DARK CLOUD COVER / PIERCING LINE
   //==================================================================
   static void DarkCloudPiercing(const MqlRates &rates[], int shift,
                                  double atrvalue, PatternVote &vote,
                                  const StrategyConfig &cfg, double w)
   {
      if (shift + 1 >= ArraySize(rates)) return;
      double o0=CandleUtils::Open(rates,shift),  c0=CandleUtils::Close(rates,shift);
      double o1=CandleUtils::Open(rates,shift+1),c1=CandleUtils::Close(rates,shift+1);
      double h1=CandleUtils::High(rates,shift+1),l1=CandleUtils::Low(rates,shift+1);
      double mid1 = (o1 + c1) / 2.0;
      int dir = 0; double raw = cfg.base_score;

      if (CandleUtils::IsBearish(rates,shift+1) && CandleUtils::IsBullish(rates,shift)
          && o0 < l1 && c0 > mid1 && c0 < o1)
      { dir = 1; vote.extreme = CandleUtils::Low(rates,shift); vote.label = "Piercing Line"; }
      else if (CandleUtils::IsBullish(rates,shift+1) && CandleUtils::IsBearish(rates,shift)
               && o0 > h1 && c0 < mid1 && c0 > o1)
      { dir = -1; vote.extreme = CandleUtils::High(rates,shift); vote.label = "Dark Cloud Cover"; }
      if (dir == 0) return;

      ScoreEngine::AddFollowThroughBonus(rates, shift, dir, raw, cfg);
      vote.valid          = true;
      vote.type           = PATTERN_DARK_CLOUD_PIERCING;
      vote.dir            = dir;
      vote.slMult         = cfg.default_sl_mult;
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_DARK_CLOUD_PIERCING, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_DARK_CLOUD_PIERCING);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
   }

   //==================================================================
   //  MARUBOZU
   //==================================================================
   static void Marubozu(const MqlRates &rates[], int shift,
                        double atrvalue, PatternVote &vote,
                        const StrategyConfig &cfg, double w)
   {
      double range = CandleUtils::Range(rates, shift);
      if (range <= 0) return;
      if (CandleUtils::Body(rates,shift) / range < cfg.marubozu_min_body_pct) return;
      double atrFactor = CandleUtils::ATRFactor(range, atrvalue);
      if (atrFactor < cfg.momentum_threshold_atr * cfg.marubozu_min_atr_mult) return;

      int dir    = CandleUtils::IsBullish(rates,shift) ? 1 : -1;
      double raw = cfg.base_score + cfg.bonus_small;
      if (atrFactor > cfg.marubozu_strong_atr_min) raw += cfg.bonus_strong_atr;

      vote.valid          = true;
      vote.type           = PATTERN_MARUBOZU;
      vote.dir            = dir;
      vote.extreme        = (dir == 1) ? CandleUtils::Low(rates,shift)
                                       : CandleUtils::High(rates,shift);
      vote.slMult         = cfg.default_sl_mult;
      vote.label          = (dir == 1) ? "Marubozu Bull" : "Marubozu Bear";
      vote.intrinsicScore = ScoreEngine::Intrinsic(rates, shift, atrvalue, PATTERN_MARUBOZU, cfg);
      vote.contextScore   = ScoreEngine::Context(rates, shift, dir, PATTERN_MARUBOZU);
      vote.momentumScore  = ScoreEngine::Momentum(rates, shift, dir, cfg);
      vote.score           = raw;
      vote.normalizedScore = ScoreEngine::Normalize(raw, w);
      ScoreEngine::AssignGrade(vote);
   }
};

#endif // __EVALUATORS_MQH__
