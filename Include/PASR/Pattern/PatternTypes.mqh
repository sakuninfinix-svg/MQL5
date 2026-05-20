//+------------------------------------------------------------------+
//|  Pattern/PatternTypes.mqh                                        |
//|  PASR Framework — Data Contracts Layer                           |
//|  All enums, structs, and weight configuration for pattern system  |
//|  No logic. No dependencies beyond Config/Types.                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property strict

#ifndef __PATTERN_TYPES_MQH__
#define __PATTERN_TYPES_MQH__

#include "../2.Config.Types.mqh"

//+------------------------------------------------------------------+
//| Pattern Quality Grade                                            |
//+------------------------------------------------------------------+
enum ENUM_PATTERN_GRADE
{
   GRADE_C,
   GRADE_B,
   GRADE_A,
   GRADE_NONE
};

//+------------------------------------------------------------------+
//| Public result returned to callers                                |
//+------------------------------------------------------------------+
struct PatternResult
{
   bool                valid;
   ENUM_PATTERN_TYPE   type;
   int                 dir;              // +1 = bull, -1 = bear
   double              extreme;          // SL anchor price
   double              score;            // final normalised 0..1
   ENUM_PATTERN_GRADE  grade;
   double              slMult;
   string              label;
   string              reasoning;
   double              confidence;
   double              intrinsicScore;
   double              contextScore;
   double              momentumScore;
   double              confluenceScore;
   datetime            timestamp;

   // Convenience predicate — avoids magic-number comparisons in callers
   bool IsActionable(double minScore = 0.5) const
   {
      return valid && score >= minScore && grade != GRADE_C;
   }
};

//+------------------------------------------------------------------+
//| Fakeout detection result                                         |
//+------------------------------------------------------------------+
struct FakeoutResult
{
   bool    detected;
   int     level;
   double  penetrationPts;
   double  confidence;
   string  reason;
};

//+------------------------------------------------------------------+
//| Per-pattern weighting configuration                              |
//| Instantiate with defaults; caller may override individual fields  |
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
      pinbarWeight      = 0.85;
      engulfingWeight   = 0.90;
      tweezerWeight     = 0.75;
      fakeyWeight       = 0.80;
      insideBarWeight   = 0.70;
      morningStarWeight = 0.88;
      threeInsideWeight = 0.85;
      railroadWeight    = 0.78;
      darkCloudWeight   = 0.72;
      marubozuWeight    = 0.82;
   }
};

//+------------------------------------------------------------------+
//| Internal vote — private to pattern subsystem, exposed here so    |
//| ScoreEngine and Evaluators share the same struct definition.     |
//+------------------------------------------------------------------+
struct PatternVote
{
   bool                valid;
   ENUM_PATTERN_TYPE   type;
   int                 dir;
   double              extreme;
   double              score;
   double              normalizedScore;
   double              slMult;
   string              label;
   string              reasoning;
   double              intrinsicScore;
   double              contextScore;
   double              momentumScore;
   double              confluenceScore;
   ENUM_PATTERN_GRADE  grade;
};

#endif // __PATTERN_TYPES_MQH__
