//+------------------------------------------------------------------+
//|                                                      AITypes.mqh |
//|                        Shared structs & enums for AI subsystem   |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property version   "3.01"
#property strict

#ifndef __AI_TYPES_MQH__
#define __AI_TYPES_MQH__

// v4.01: expanded from 18 → 26 features (Priority-1 feature engineering)
#define AI_FEATURE_DIM   26
// NN input layer expanded to match — 12 inputs for first hidden layer
// (8 core + 4 structural/temporal new dims fed to linear branch)
#define NN_INPUTS        12
#define NN_H1             8
#define NN_H2             4
#define REPLAY_CAPACITY  500
#define MINIBATCH_SIZE    16
#define L2_LAMBDA        0.0001

//--- Expert type enum
enum ExpertType
{
   EXPERT_NONE           = 0,
   EXPERT_TREND          = 1,
   EXPERT_MEAN_REVERSION = 2,
   EXPERT_MOMENTUM       = 3
};

//--- Evaluation context (feature vector, built once per signal)
struct EvalContext
{
   double atrNorm;
   double spreadNorm;
   double slNorm;
   double regimeScore;
   double volatilityScore;
   double timeOfDayNorm;
   double mtConfluenceNorm;
   double volumeNorm;
   double momentumNorm;
   double zoneNorm;
   double lossStreakNorm;
   double noiseNorm;
   double rsiNorm;
   double candleBodyRatio;
   double emaDistNorm;
   double sessionNorm;

   // V3.02: Advanced statistical features (computed inline by AIFeatureBuilder)
   double zScore;            // Price Z-score (standardized position)
   double skewness;          // Return distribution asymmetry
   double kurtosis;          // Tail risk measure
   double volatilityRegime;  // Normalized volatility regime (0-1)

   // v4.01: Priority-1 new features
   double srProxBull;        // F19: (price-support)/ATR
   double srProxBear;        // F20: (resistance-price)/ATR
   double upperWickRatio;    // F21: upper wick rejection
   double lowerWickRatio;    // F22: lower wick support
   double hourSin;           // F23: cyclical hour sin
   double hourCos;           // F24: cyclical hour cos
   double htfTrendH4;        // F25: H4 EMA trend alignment
   double atrPercentile;     // F26: ATR rank vs 60-bar history

   void Reset() { ZeroMemory(this); }
};

//--- Bar data cache — one closed bar per timeframe
struct CachedBarData
{
   datetime timestamp;
   double   open;
   double   high;
   double   low;
   double   close;
   long     volume;
   bool     valid;

   void Reset() { ZeroMemory(this); valid = false; }
};

//--- Multi-bar cache used by AIFeatureBuilder
//    v4.01: added bars60[] (ATR percentile) + barsH4_20[] (HTF trend H4)
struct BarCache
{
   MqlRates bars14[];      // Last 14 bars — momentum, RSI, ADX
   MqlRates bars15[];      // Last 15 bars — RSI (needs 14 diffs)
   MqlRates bars20[];      // Last 20 bars — EMA, volatility
   MqlRates bars50[];      // Last 50 bars — volume profile
   MqlRates bars60[];      // Last 60 bars — ATR percentile rank  [v4.01]
   MqlRates barsH4_20[];   // Last 20 H4 bars — HTF EMA trend     [v4.01]
   MqlRates bar1[];        // Last 1 closed bar — candle body
   CachedBarData current;   // Current TF last closed
   CachedBarData higher;    // Next-higher TF last closed
   datetime lastUpdate;
   bool     initialized;

   void Init()
   {
      ArrayResize(bars14,    14);
      ArrayResize(bars15,    15);
      ArrayResize(bars20,    20);
      ArrayResize(bars50,    50);
      ArrayResize(bars60,    60);   // v4.01
      ArrayResize(barsH4_20, 20);   // v4.01
      ArrayResize(bar1,       1);
      ArrayInitialize(bars14,    0.0);
      ArrayInitialize(bars15,    0.0);
      ArrayInitialize(bars20,    0.0);
      ArrayInitialize(bars50,    0.0);
      ArrayInitialize(bars60,    0.0);
      ArrayInitialize(barsH4_20, 0.0);
      ArrayInitialize(bar1,      0.0);
      current.Reset();
      higher.Reset();
      lastUpdate   = 0;
      initialized  = true;
   }
};

//--- Replay buffer sample — v4.01: sized to AI_FEATURE_DIM
struct ReplaySample
{
   double features[AI_FEATURE_DIM];
   double label;
};

//--- Full neural-network + linear model state
//    v4.01: NN_INPUTS 8→12, NN_H1 6→8
struct AIModelState
{
   double bias;
   double atrWeight;
   double spreadWeight;
   double slWeight;
   double momentumWeight;
   double lossStreakWeight;
   double volNoiseWeight;
   double regimeScoreWeight;
   double timeOfDayWeight;
   double mtConfluenceWeight;
   double volumeWeight;
   // v4.01: 4 new linear weights
   double srProxWeight;
   double wickRatioWeight;
   double htfTrendWeight;
   double atrPercentileWeight;
   // ensemble
   double trendExpertWeight;
   double meanRevExpertWeight;
   double momentumExpertWeight;
   double recentWinRate;
   double longTermWinRate;
   int    driftDetectionWindow;
   // NN layers (expanded)
   double h1w[NN_INPUTS][NN_H1];
   double h1b[NN_H1];
   double h2w[NN_H1][NN_H2];
   double h2b[NN_H2];
   double ow[NN_H2];
   double ob;
   double plattA;
   double plattB;
   int    plattSamples;
   double nnLearningRate;
   int    nnTrainingSamples;
   int    replayTrainCount;
   bool   initialized;
   datetime lastUpdateTime;
   int    validationCounter;

   void InitWeights()
   {
      bias                 = 0.55;
      atrWeight            = 0.18;
      spreadWeight         = 0.14;
      slWeight             = 0.16;
      momentumWeight       = 0.08;
      lossStreakWeight     = 0.06;
      volNoiseWeight       = 0.12;
      regimeScoreWeight    = 0.15;
      timeOfDayWeight      = 0.10;
      mtConfluenceWeight   = 0.20;
      volumeWeight         = 0.12;
      // v4.01 new weights
      srProxWeight         = 0.18;  // SR proximity is high-value for PA
      wickRatioWeight      = 0.10;
      htfTrendWeight       = 0.16;  // HTF alignment strongly predictive
      atrPercentileWeight  = 0.08;
      // ensemble
      trendExpertWeight    = 0.35;
      meanRevExpertWeight  = 0.30;
      momentumExpertWeight = 0.35;
      recentWinRate        = -1.0;
      longTermWinRate      = -1.0;
      driftDetectionWindow = 50;

      double s1 = MathSqrt(2.0 / (NN_INPUTS + NN_H1));
      double s2 = MathSqrt(2.0 / (NN_H1   + NN_H2));
      double s3 = MathSqrt(2.0 / (NN_H2   + 1));
      for(int i = 0; i < NN_INPUTS; i++)
         for(int j = 0; j < NN_H1; j++)
            h1w[i][j] = s1 * (0.2 - (double)(i + j) * 0.007);
      for(int j = 0; j < NN_H1; j++) h1b[j] = 0.01;
      for(int i = 0; i < NN_H1; i++)
         for(int j = 0; j < NN_H2; j++)
            h2w[i][j] = s2 * (0.2 - (double)(i + j) * 0.01);
      for(int j = 0; j < NN_H2; j++) h2b[j] = 0.01;
      for(int j = 0; j < NN_H2; j++) ow[j]  = s3 * 0.5;
      ob = 0.0;

      plattA            = 1.0;
      plattB            = 0.0;
      plattSamples      = 0;
      nnLearningRate    = 0.01;
      nnTrainingSamples = 0;
      replayTrainCount  = 0;
      initialized       = true;
      lastUpdateTime    = 0;
      validationCounter = 0;
   }
};

//--- Per-signal sample for dataset logging + labeling
struct AISignalSample
{
   string         sampleId;
   ulong          ticket;
   datetime       timestamp;
   bool           accepted;
   bool           labeled;
   double         atrPoints;
   double         volatility;
   double         mtConfluence;
   double         volumeRatio;
   double         zoneStrength;
   double         slMultiplier;
   int            patternType;
   double         support;
   double         resistance;
   SignalDecision signal;
   double         features[AI_FEATURE_DIM];   // v4.01: sized to 26
};

#endif // __AI_TYPES_MQH__
