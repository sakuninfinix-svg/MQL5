//+------------------------------------------------------------------+
//| PASR Strategy Test Suite                                         |
//| Comprehensive trading logic validation & optimization framework  |
//| Quant Developer — Senior MQL Architecture                        |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_STRATEGY_TEST_SUITE_MQH__
#define __PASR_STRATEGY_TEST_SUITE_MQH__

#include <PASR/Core/PipelineTypes.mqh>

// ====================================================================
// STRATEGY TEST MATRIX
// Defines all strategy configurations to be tested
// ====================================================================

enum ENUM_STRATEGY_PROFILE
  {
   STRATEGY_CONSERATIVE,    // Low risk, high confidence, trend-following
   STRATEGY_MODERATE,       // Balanced risk/reward, mixed regimes
   STRATEGY_AGGRESSIVE,     // Higher risk, more trades, scalping allowed
   STRATEGY_TREND_ONLY,     // Trend-only entries, regime-filtered
   STRATEGY_RANGE_ONLY,     // Range-bound mean reversion
   STRATEGY_AI_DRIVEN,      // AI-gated entries, minimum rules
   STRATEGY_PATTERN_HEAVY,  // Pattern-driven with AI confirmation
   STRATEGY_BREAKOUT        // Volatility breakout, squeeze expansion
  };

// ====================================================================
// Strategy parameter set for testing
// ====================================================================
struct SStrategyTestConfig
  {
   string name;
   ENUM_STRATEGY_PROFILE profile;

   // Risk parameters
   double lotSize;
   double riskPercent;
   double slMultiplier;
   double tpMultiplier;
   double maxDailyLossPct;
   double maxDrawdownPct;
   int    maxOpenPositions;
   int    maxConsecLoss;
   bool   useBreakEven;
   bool   useTrailingStop;

   // Market filters
   double adxTrendThreshold;
   double spreadFilterPips;
   int    sessionStartMin;    // Minutes from midnight (weekday start)
   int    sessionEndMin;      // Minutes from midnight (weekday end)

   // Signal parameters
   bool   useMTF;
   int    minConfluence;
   double signalMinScore;
   double minRRRatio;

   // Pattern parameters
   bool   enablePatterns;
   double minPatternScore;
   double minPatternDominanceGap;

   // AI parameters
   bool   enableAI;
   double aiMinConfidence;
   double aiMinExpectedR;
   double aiMaxFailureProbability;

   // Regime-specific adjustments
   double trendEntryThreshold;
   double trendRiskMultiplier;
   double rangeEntryThreshold;
   double rangeRiskMultiplier;
   double volatileEntryThreshold;
   double volatileRiskMultiplier;

   // Expected characteristics
   int    expectedMinTrades;     // Minimum trades per test period
   double expectedWinRate;       // Target win rate
   double expectedProfitFactor;  // Target profit factor
   double maxAcceptableDD;       // Maximum acceptable drawdown %
  };

// ====================================================================
// Pre-defined strategy configurations for testing
// ====================================================================
SStrategyTestConfig GetStrategyConfig(ENUM_STRATEGY_PROFILE profile)
  {
   SStrategyTestConfig cfg;
   ZeroMemory(cfg);

   switch(profile)
     {
      case STRATEGY_CONSERATIVE:
         cfg.name = "Conservative";
         cfg.profile = STRATEGY_CONSERATIVE;
         cfg.lotSize = 0.01;
         cfg.riskPercent = 0.5;
         cfg.slMultiplier = 2.0;
         cfg.tpMultiplier = 3.0;
         cfg.maxDailyLossPct = 2.0;
         cfg.maxDrawdownPct = 5.0;
         cfg.maxOpenPositions = 1;
         cfg.maxConsecLoss = 3;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = true;
         cfg.adxTrendThreshold = 30.0;
         cfg.spreadFilterPips = 2.0;
         cfg.sessionStartMin = 120;
         cfg.sessionEndMin = 1320;
         cfg.useMTF = true;
         cfg.minConfluence = 2;
         cfg.signalMinScore = 0.55;
         cfg.minRRRatio = 2.0;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 55.0;
         cfg.minPatternDominanceGap = 0.10;
         cfg.enableAI = true;
         cfg.aiMinConfidence = 0.70;
         cfg.aiMinExpectedR = 1.0;
         cfg.aiMaxFailureProbability = 0.35;
         cfg.trendEntryThreshold = 0.65;
         cfg.trendRiskMultiplier = 1.0;
         cfg.rangeEntryThreshold = 0.75;
         cfg.rangeRiskMultiplier = 0.5;
         cfg.volatileEntryThreshold = 0.90;
         cfg.volatileRiskMultiplier = 0.3;
         cfg.expectedMinTrades = 50;
         cfg.expectedWinRate = 0.55;
         cfg.expectedProfitFactor = 1.5;
         cfg.maxAcceptableDD = 8.0;
         break;

      case STRATEGY_MODERATE:
         cfg.name = "Moderate";
         cfg.profile = STRATEGY_MODERATE;
         cfg.lotSize = 0.01;
         cfg.riskPercent = 1.0;
         cfg.slMultiplier = 1.5;
         cfg.tpMultiplier = 2.5;
         cfg.maxDailyLossPct = 3.0;
         cfg.maxDrawdownPct = 10.0;
         cfg.maxOpenPositions = 3;
         cfg.maxConsecLoss = 5;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = false;
         cfg.adxTrendThreshold = 25.0;
         cfg.spreadFilterPips = 3.0;
         cfg.sessionStartMin = 0;
         cfg.sessionEndMin = 1380;
         cfg.useMTF = true;
         cfg.minConfluence = 1;
         cfg.signalMinScore = 0.40;
         cfg.minRRRatio = 1.5;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 45.0;
         cfg.minPatternDominanceGap = 0.05;
         cfg.enableAI = false;
         cfg.aiMinConfidence = 0.60;
         cfg.aiMinExpectedR = 0.5;
         cfg.aiMaxFailureProbability = 0.55;
         cfg.trendEntryThreshold = 0.60;
         cfg.trendRiskMultiplier = 1.2;
         cfg.rangeEntryThreshold = 0.65;
         cfg.rangeRiskMultiplier = 1.1;
         cfg.volatileEntryThreshold = 0.85;
         cfg.volatileRiskMultiplier = 0.9;
         cfg.expectedMinTrades = 100;
         cfg.expectedWinRate = 0.50;
         cfg.expectedProfitFactor = 1.3;
         cfg.maxAcceptableDD = 15.0;
         break;

      case STRATEGY_AGGRESSIVE:
         cfg.name = "Aggressive";
         cfg.profile = STRATEGY_AGGRESSIVE;
         cfg.lotSize = 0.02;
         cfg.riskPercent = 2.0;
         cfg.slMultiplier = 1.2;
         cfg.tpMultiplier = 2.0;
         cfg.maxDailyLossPct = 5.0;
         cfg.maxDrawdownPct = 15.0;
         cfg.maxOpenPositions = 5;
         cfg.maxConsecLoss = 7;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = true;
         cfg.adxTrendThreshold = 20.0;
         cfg.spreadFilterPips = 4.0;
         cfg.sessionStartMin = 0;
         cfg.sessionEndMin = 1380;
         cfg.useMTF = false;
         cfg.minConfluence = 1;
         cfg.signalMinScore = 0.35;
         cfg.minRRRatio = 1.2;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 40.0;
         cfg.minPatternDominanceGap = 0.03;
         cfg.enableAI = true;
         cfg.aiMinConfidence = 0.55;
         cfg.aiMinExpectedR = 0.3;
         cfg.aiMaxFailureProbability = 0.60;
         cfg.trendEntryThreshold = 0.55;
         cfg.trendRiskMultiplier = 1.5;
         cfg.rangeEntryThreshold = 0.60;
         cfg.rangeRiskMultiplier = 1.3;
         cfg.volatileEntryThreshold = 0.80;
         cfg.volatileRiskMultiplier = 1.0;
         cfg.expectedMinTrades = 200;
         cfg.expectedWinRate = 0.45;
         cfg.expectedProfitFactor = 1.2;
         cfg.maxAcceptableDD = 25.0;
         break;

      case STRATEGY_TREND_ONLY:
         cfg.name = "Trend Only";
         cfg.profile = STRATEGY_TREND_ONLY;
         cfg.lotSize = 0.01;
         cfg.riskPercent = 1.0;
         cfg.slMultiplier = 1.8;
         cfg.tpMultiplier = 3.5;
         cfg.maxDailyLossPct = 3.0;
         cfg.maxDrawdownPct = 10.0;
         cfg.maxOpenPositions = 2;
         cfg.maxConsecLoss = 4;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = true;
         cfg.adxTrendThreshold = 28.0;
         cfg.spreadFilterPips = 2.5;
         cfg.sessionStartMin = 60;
         cfg.sessionEndMin = 1260;
         cfg.useMTF = true;
         cfg.minConfluence = 2;
         cfg.signalMinScore = 0.50;
         cfg.minRRRatio = 2.0;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 50.0;
         cfg.minPatternDominanceGap = 0.08;
         cfg.enableAI = true;
         cfg.aiMinConfidence = 0.65;
         cfg.aiMinExpectedR = 0.8;
         cfg.aiMaxFailureProbability = 0.40;
         cfg.trendEntryThreshold = 0.60;
         cfg.trendRiskMultiplier = 1.3;
         cfg.rangeEntryThreshold = 0.95;  // Effectively disable range
         cfg.rangeRiskMultiplier = 0.1;
         cfg.volatileEntryThreshold = 0.90;
         cfg.volatileRiskMultiplier = 0.5;
         cfg.expectedMinTrades = 60;
         cfg.expectedWinRate = 0.52;
         cfg.expectedProfitFactor = 1.6;
         cfg.maxAcceptableDD = 12.0;
         break;

      case STRATEGY_RANGE_ONLY:
         cfg.name = "Range Only";
         cfg.profile = STRATEGY_RANGE_ONLY;
         cfg.lotSize = 0.01;
         cfg.riskPercent = 0.8;
         cfg.slMultiplier = 1.3;
         cfg.tpMultiplier = 1.8;
         cfg.maxDailyLossPct = 2.5;
         cfg.maxDrawdownPct = 8.0;
         cfg.maxOpenPositions = 2;
         cfg.maxConsecLoss = 4;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = false;
         cfg.adxTrendThreshold = 22.0;
         cfg.spreadFilterPips = 2.0;
         cfg.sessionStartMin = 120;
         cfg.sessionEndMin = 1200;
         cfg.useMTF = true;
         cfg.minConfluence = 2;
         cfg.signalMinScore = 0.45;
         cfg.minRRRatio = 1.3;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 50.0;
         cfg.minPatternDominanceGap = 0.07;
         cfg.enableAI = true;
         cfg.aiMinConfidence = 0.65;
         cfg.aiMinExpectedR = 0.5;
         cfg.aiMaxFailureProbability = 0.45;
         cfg.trendEntryThreshold = 0.95;  // Effectively disable trend
         cfg.trendRiskMultiplier = 0.1;
         cfg.rangeEntryThreshold = 0.60;
         cfg.rangeRiskMultiplier = 1.2;
         cfg.volatileEntryThreshold = 0.95;
         cfg.volatileRiskMultiplier = 0.2;
         cfg.expectedMinTrades = 120;
         cfg.expectedWinRate = 0.58;
         cfg.expectedProfitFactor = 1.4;
         cfg.maxAcceptableDD = 10.0;
         break;

      case STRATEGY_AI_DRIVEN:
         cfg.name = "AI Driven";
         cfg.profile = STRATEGY_AI_DRIVEN;
         cfg.lotSize = 0.01;
         cfg.riskPercent = 1.0;
         cfg.slMultiplier = 1.5;
         cfg.tpMultiplier = 2.5;
         cfg.maxDailyLossPct = 3.0;
         cfg.maxDrawdownPct = 10.0;
         cfg.maxOpenPositions = 3;
         cfg.maxConsecLoss = 5;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = true;
         cfg.adxTrendThreshold = 20.0;
         cfg.spreadFilterPips = 3.0;
         cfg.sessionStartMin = 0;
         cfg.sessionEndMin = 1380;
         cfg.useMTF = true;
         cfg.minConfluence = 1;
         cfg.signalMinScore = 0.30;  // Low rule threshold, let AI gate
         cfg.minRRRatio = 1.2;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 35.0;
         cfg.minPatternDominanceGap = 0.03;
         cfg.enableAI = true;
         cfg.aiMinConfidence = 0.65;
         cfg.aiMinExpectedR = 0.6;
         cfg.aiMaxFailureProbability = 0.50;
         cfg.trendEntryThreshold = 0.55;
         cfg.trendRiskMultiplier = 1.3;
         cfg.rangeEntryThreshold = 0.60;
         cfg.rangeRiskMultiplier = 1.2;
         cfg.volatileEntryThreshold = 0.75;
         cfg.volatileRiskMultiplier = 0.8;
         cfg.expectedMinTrades = 150;
         cfg.expectedWinRate = 0.52;
         cfg.expectedProfitFactor = 1.4;
         cfg.maxAcceptableDD = 15.0;
         break;

      case STRATEGY_PATTERN_HEAVY:
         cfg.name = "Pattern Heavy";
         cfg.profile = STRATEGY_PATTERN_HEAVY;
         cfg.lotSize = 0.01;
         cfg.riskPercent = 1.0;
         cfg.slMultiplier = 1.5;
         cfg.tpMultiplier = 2.5;
         cfg.maxDailyLossPct = 3.0;
         cfg.maxDrawdownPct = 10.0;
         cfg.maxOpenPositions = 3;
         cfg.maxConsecLoss = 5;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = false;
         cfg.adxTrendThreshold = 25.0;
         cfg.spreadFilterPips = 3.0;
         cfg.sessionStartMin = 0;
         cfg.sessionEndMin = 1380;
         cfg.useMTF = true;
         cfg.minConfluence = 1;
         cfg.signalMinScore = 0.35;
         cfg.minRRRatio = 1.5;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 55.0;  // High pattern threshold
         cfg.minPatternDominanceGap = 0.12;
         cfg.enableAI = true;
         cfg.aiMinConfidence = 0.60;
         cfg.aiMinExpectedR = 0.5;
         cfg.aiMaxFailureProbability = 0.50;
         cfg.trendEntryThreshold = 0.60;
         cfg.trendRiskMultiplier = 1.2;
         cfg.rangeEntryThreshold = 0.65;
         cfg.rangeRiskMultiplier = 1.1;
         cfg.volatileEntryThreshold = 0.85;
         cfg.volatileRiskMultiplier = 0.9;
         cfg.expectedMinTrades = 80;
         cfg.expectedWinRate = 0.55;
         cfg.expectedProfitFactor = 1.5;
         cfg.maxAcceptableDD = 12.0;
         break;

      case STRATEGY_BREAKOUT:
         cfg.name = "Breakout";
         cfg.profile = STRATEGY_BREAKOUT;
         cfg.lotSize = 0.01;
         cfg.riskPercent = 1.5;
         cfg.slMultiplier = 1.2;
         cfg.tpMultiplier = 3.0;
         cfg.maxDailyLossPct = 4.0;
         cfg.maxDrawdownPct = 12.0;
         cfg.maxOpenPositions = 2;
         cfg.maxConsecLoss = 5;
         cfg.useBreakEven = true;
         cfg.useTrailingStop = true;
         cfg.adxTrendThreshold = 22.0;
         cfg.spreadFilterPips = 3.0;
         cfg.sessionStartMin = 0;
         cfg.sessionEndMin = 1380;
         cfg.useMTF = true;
         cfg.minConfluence = 1;
         cfg.signalMinScore = 0.35;
         cfg.minRRRatio = 2.0;
         cfg.enablePatterns = true;
         cfg.minPatternScore = 40.0;
         cfg.minPatternDominanceGap = 0.05;
         cfg.enableAI = true;
         cfg.aiMinConfidence = 0.60;
         cfg.aiMinExpectedR = 0.8;
         cfg.aiMaxFailureProbability = 0.45;
         cfg.trendEntryThreshold = 0.55;
         cfg.trendRiskMultiplier = 1.4;
         cfg.rangeEntryThreshold = 0.70;
         cfg.rangeRiskMultiplier = 0.8;
         cfg.volatileEntryThreshold = 0.75;  // Enter on volatility expansion
         cfg.volatileRiskMultiplier = 1.2;
         cfg.expectedMinTrades = 70;
         cfg.expectedWinRate = 0.45;
         cfg.expectedProfitFactor = 1.8;
         cfg.maxAcceptableDD = 18.0;
         break;
     }

   return cfg;
  }

// ====================================================================
// TEST EVALUATION METRICS
// ====================================================================
struct SStrategyTestResult
  {
   string configName;
   int    totalTrades;
   double profitFactor;
   double recoveryFactor;
   double expectedPayoff;
   double winRate;
   double profit;
   double maxDD;
   double maxDDPct;
   double sharpeRatio;
   double sortinoRatio;
   double customFitness;
   bool   passed;
   string failReason;
  };

// ====================================================================
// Fitness function for Strategy Tester optimization
// Combines multiple metrics into a single score
// ====================================================================
double ComputeStrategyFitness()
  {
   double profit           = TesterStatistics(STAT_PROFIT);
   double profitFactor     = TesterStatistics(STAT_PROFIT_FACTOR);
   double recoveryFactor   = TesterStatistics(STAT_RECOVERY_FACTOR);
   double expectedPayoff   = TesterStatistics(STAT_EXPECTED_PAYOFF);
   int    trades           = (int)TesterStatistics(STAT_TRADES);
   double equityDrawdownPct= TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   double sharpeRatio      = TesterStatistics(STAT_SHARPE_RATIO);
   double winRate          = TesterStatistics(STAT_PROFIT_TRADES) / MathMax(1.0, TesterStatistics(STAT_TRADES));

   // Minimum trade count filter
   if(trades < 30)
      return -10000.0;

   // Must be profitable
   if(profit <= 0)
      return -1000.0 - MathAbs(profit);

   // Cap extreme values to prevent overflow
   profit = MathMin(1000000.0, profit);
   profitFactor = MathMin(100.0, MathMax(0.0, profitFactor));
   recoveryFactor = MathMin(100.0, MathMax(0.0, recoveryFactor));
   expectedPayoff = MathMin(1000.0, MathMax(0.0, expectedPayoff));
   equityDrawdownPct = MathMin(100.0, MathMax(0.0, equityDrawdownPct));
   sharpeRatio = MathMax(-5.0, MathMin(5.0, sharpeRatio));

   // Composite fitness score
   double score = 0.0;

   // Profit component (log scale to prevent dominance)
   score += MathLog(1.0 + profit);

   // Profit factor (quality of trades)
   score += 2.5 * MathLog(1.0 + profitFactor);

   // Recovery factor (drawdown resilience)
   score += 2.0 * MathLog(1.0 + recoveryFactor);

   // Expected payoff (consistency)
   score += MathLog(1.0 + expectedPayoff);

   // Sharpe ratio (risk-adjusted returns)
   score += 0.5 * sharpeRatio;

   // Trade count bonus (statistical significance)
   score += MathMin(3.0, (double)trades / 50.0);

   // Win rate bonus
   score += 2.0 * winRate;

   // Drawdown penalty
   score -= 0.20 * equityDrawdownPct;

   return score;
  }

// ====================================================================
// Strategy validation: check if results meet minimum criteria
// ====================================================================
bool ValidateStrategyResult(SStrategyTestResult &result, SStrategyTestConfig &config)
  {
   result.passed = true;
   result.failReason = "";

   if(result.totalTrades < config.expectedMinTrades)
     {
      result.passed = false;
      result.failReason = StringFormat("Insufficient trades: %d < %d",
         result.totalTrades, config.expectedMinTrades);
      return false;
     }

   if(result.winRate < config.expectedWinRate)
     {
      result.passed = false;
      result.failReason = StringFormat("Win rate too low: %.1f%% < %.1f%%",
         result.winRate * 100, config.expectedWinRate * 100);
      return false;
     }

   if(result.profitFactor < config.expectedProfitFactor)
     {
      result.passed = false;
      result.failReason = StringFormat("Profit factor too low: %.2f < %.2f",
         result.profitFactor, config.expectedProfitFactor);
      return false;
     }

   if(result.maxDDPct > config.maxAcceptableDD)
     {
      result.passed = false;
      result.failReason = StringFormat("Drawdown too high: %.1f%% > %.1f%%",
         result.maxDDPct, config.maxAcceptableDD);
      return false;
     }

   if(result.profit <= 0)
     {
      result.passed = false;
      result.failReason = "Strategy is not profitable";
      return false;
     }

   return true;
  }

// ====================================================================
// Build test result from Strategy Tester statistics
// ====================================================================
void BuildTestResult(SStrategyTestResult &result, const string configName)
  {
   result.configName = configName;
   result.totalTrades = (int)TesterStatistics(STAT_TRADES);
   result.profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   result.recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
   result.expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   result.winRate = TesterStatistics(STAT_PROFIT_TRADES) / MathMax(1.0, TesterStatistics(STAT_TRADES));
   result.profit = TesterStatistics(STAT_PROFIT);
   result.maxDD = TesterStatistics(STAT_BALANCE_DD);
   result.maxDDPct = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   result.sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);
   result.sortinoRatio = 0.0; // STAT_SORTINO_RATIO not available in this MQL5 build
   result.customFitness = ComputeStrategyFitness();
  }

// ====================================================================
// Print comparison table for multiple strategy results
// ====================================================================
void PrintStrategyComparison(SStrategyTestResult &results[], int count)
  {
   Print("====================================================================");
   Print("                    STRATEGY COMPARISON REPORT                      ");
   Print("====================================================================");
   Print(StringFormat("%-15s | %5s | %5s | %6s | %6s | %5s | %6s | %s",
      "Strategy", "Trades", "Win%", "PF", "RF", "DD%", "Sharpe", "Fitness"));
   Print("--------------------------------------------------------------------");

   // Sort by fitness (simple bubble sort for small arrays)
   for(int i = 0; i < count - 1; i++)
     {
      for(int j = i + 1; j < count; j++)
        {
         if(results[j].customFitness > results[i].customFitness)
           {
            SStrategyTestResult tmp = results[i];
            results[i] = results[j];
            results[j] = tmp;
           }
        }
     }

   for(int i = 0; i < count; i++)
     {
      string marker = results[i].passed ? "  " : "!!";
      Print(StringFormat("%s%-15s | %5d | %5.1f | %6.2f | %6.2f | %5.1f | %6.2f | %.2f",
         marker,
         results[i].configName,
         results[i].totalTrades,
         results[i].winRate * 100,
         results[i].profitFactor,
         results[i].recoveryFactor,
         results[i].maxDDPct,
         results[i].sharpeRatio,
         results[i].customFitness));

      if(!results[i].passed)
         Print("  FAIL: " + results[i].failReason);
     }

   Print("====================================================================");
   if(count > 0 && results[0].passed)
      Print("BEST: " + results[0].configName + " (Fitness: " +
            DoubleToString(results[0].customFitness, 2) + ")");
   else
      Print("NO PASSING STRATEGIES");
   Print("====================================================================");
  }

#endif // __PASR_STRATEGY_TEST_SUITE_MQH__
