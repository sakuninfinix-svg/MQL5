//+------------------------------------------------------------------+
//| PASR Walk-Forward Testing Framework                              |
//| Rolling window optimization + out-of-sample validation           |
//| Quant Developer — Senior MQL Architecture                        |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_WALK_FORWARD_MQH__
#define __PASR_WALK_FORWARD_MQH__

#include "StrategyTestSuite.mqh"

// ====================================================================
// Walk-Forward Test Configuration
// ====================================================================
struct SWFConfig
  {
   // Window settings
   int    trainMonths;      // In-sample optimization window (months)
   int    testMonths;       // Out-of-sample validation window (months)
   int    stepMonths;       // How far to roll forward each iteration
   int    minTradesTrain;   // Minimum trades required in training window
   int    minTradesTest;    // Minimum trades required in test window

   // Overfitting detection
   double maxPerfDegradation;   // Maximum allowed PF drop from train→test (ratio)
   double maxDDIncrease;        // Maximum allowed DD increase from train→test (%)

   // Stability metrics
   int    minRollingWindows;  // Minimum number of rolling windows for statistical significance
   double consistencyThreshold; // % of windows that must be profitable
  };

// ====================================================================
// Walk-Forward Result for a single window
// ====================================================================
struct SWFWindowResult
  {
   datetime trainStart;
   datetime trainEnd;
   datetime testStart;
   datetime testEnd;

   // Training (in-sample) metrics
   double trainProfit;
   double trainPF;
   double trainDD;
   int    trainTrades;
   double trainFitness;

   // Test (out-of-sample) metrics
   double testProfit;
   double testPF;
   double testDD;
   int    testTrades;
   double testFitness;

   // Quality indicators
   bool   trainPassed;
   bool   testPassed;
   bool   overfitting;          // true if test performance degrades too much
   string degradationReason;

   // Computed metrics
   double pfDegradation;        // testPF / trainPF (should be > 0.5)
   double ddIncrease;           // testDD - trainDD
  };

// ====================================================================
// Aggregate Walk-Forward Summary
// ====================================================================
struct SWFSummary
  {
   string profileName;
   int    totalWindows;
   int    profitableWindows;
   int    passingWindows;
   int    overfitWindows;

   double avgTrainPF;
   double avgTestPF;
   double avgTrainDD;
   double avgTestDD;
   double avgTrainFitness;
   double avgTestFitness;

   double overallDegradation;    // avgTestPF / avgTrainPF
   double consistencyScore;      // % profitable windows
   double stabilityScore;        // % passing windows
   bool   robust;                // true if meets all robustness criteria
   string assessment;
  };

// ====================================================================
// Default walk-forward configuration
// ====================================================================
SWFConfig GetDefaultWFConfig()
  {
   SWFConfig cfg;
   cfg.trainMonths = 6;
   cfg.testMonths = 3;
   cfg.stepMonths = 1;
   cfg.minTradesTrain = 30;
   cfg.minTradesTest = 15;
   cfg.maxPerfDegradation = 0.50;   // Test PF can be at most 50% lower than train PF
   cfg.maxDDIncrease = 10.0;        // Test DD can be at most 10% higher than train DD
   cfg.minRollingWindows = 4;
   cfg.consistencyThreshold = 0.60; // At least 60% of windows must be profitable
   return cfg;
  }

// ====================================================================
// Evaluate a single walk-forward window
// ====================================================================
void EvaluateWFWindow(SWFWindowResult &wr, const SWFConfig &cfg)
  {
   wr.pfDegradation = (wr.trainPF > 0) ? (wr.testPF / wr.trainPF) : 0.0;
   wr.ddIncrease = wr.testDD - wr.trainDD;

   // Training window passes if profitable with minimum trades
   wr.trainPassed = (wr.trainProfit > 0 && wr.trainTrades >= cfg.minTradesTrain &&
                     wr.trainPF > 1.0 && wr.trainDD < 25.0);

   // Test window passes if profitable with minimum trades
   wr.testPassed = (wr.testProfit > 0 && wr.testTrades >= cfg.minTradesTest &&
                    wr.testPF > 1.0);

   // Overfitting detection
   wr.overfitting = false;
   wr.degradationReason = "";

   if(wr.trainPassed && !wr.testPassed)
     {
      wr.overfitting = true;
      wr.degradationReason = "In-sample passed but out-of-sample failed";
     }
   else if(wr.pfDegradation < cfg.maxPerfDegradation)
     {
      wr.overfitting = true;
      wr.degradationReason = StringFormat("PF degradation: %.2f (min: %.2f)",
         wr.pfDegradation, cfg.maxPerfDegradation);
     }
   else if(wr.ddIncrease > cfg.maxDDIncrease)
     {
      wr.overfitting = true;
      wr.degradationReason = StringFormat("DD increase: %.1f%% (max: %.1f%%)",
         wr.ddIncrease, cfg.maxDDIncrease);
     }
  }

// ====================================================================
// Compute aggregate summary from multiple windows
// ====================================================================
void ComputeWFSummary(SWFSummary &summary, SWFWindowResult &results[], int count)
  {
   summary.totalWindows = count;
   summary.profitableWindows = 0;
   summary.passingWindows = 0;
   summary.overfitWindows = 0;

   double totalTrainPF = 0, totalTestPF = 0;
   double totalTrainDD = 0, totalTestDD = 0;
   double totalTrainFitness = 0, totalTestFitness = 0;

   for(int i = 0; i < count; i++)
     {
      if(results[i].testProfit > 0)
         summary.profitableWindows++;
      if(results[i].testPassed)
         summary.passingWindows++;
      if(results[i].overfitting)
         summary.overfitWindows++;

      totalTrainPF += results[i].trainPF;
      totalTestPF += results[i].testPF;
      totalTrainDD += results[i].trainDD;
      totalTestDD += results[i].testDD;
      totalTrainFitness += results[i].trainFitness;
      totalTestFitness += results[i].testFitness;
     }

   if(count > 0)
     {
      summary.avgTrainPF = totalTrainPF / count;
      summary.avgTestPF = totalTestPF / count;
      summary.avgTrainDD = totalTrainDD / count;
      summary.avgTestDD = totalTestDD / count;
      summary.avgTrainFitness = totalTrainFitness / count;
      summary.avgTestFitness = totalTestFitness / count;

      summary.overallDegradation = (summary.avgTrainPF > 0) ?
         (summary.avgTestPF / summary.avgTrainPF) : 0.0;
      summary.consistencyScore = (double)summary.profitableWindows / count;
      summary.stabilityScore = (double)summary.passingWindows / count;

      // Robustness criteria
      summary.robust = (summary.totalWindows >= 4 &&
                       summary.consistencyScore >= 0.60 &&
                       summary.stabilityScore >= 0.50 &&
                       summary.overallDegradation >= 0.50 &&
                       summary.avgTestPF > 1.0);

      if(summary.robust)
         summary.assessment = "ROBUST — Strategy passes walk-forward validation";
      else if(summary.overfitWindows > count / 2)
         summary.assessment = "OVERFITTED — Strategy performs well in-sample but fails out-of-sample";
      else if(summary.consistencyScore < 0.40)
         summary.assessment = "INCONSISTENT — Strategy profitability is unreliable";
      else if(summary.stabilityScore < 0.30)
         summary.assessment = "UNSTABLE — Strategy fails validation criteria in most windows";
      else
         summary.assessment = "MARGINAL — Strategy shows mixed results; needs more data";
     }
  }

// ====================================================================
// Print walk-forward report
// ====================================================================
void PrintWFReport(SWFSummary &summary, SWFWindowResult &results[], int count)
  {
   Print("====================================================================");
   Print("               WALK-FORWARD ANALYSIS REPORT                         ");
   Print("====================================================================");
   Print("Strategy: ", summary.profileName);
   Print("Windows: ", summary.totalWindows,
         " | Profitable: ", summary.profitableWindows,
         " | Passing: ", summary.passingWindows,
         " | Overfit: ", summary.overfitWindows);
   Print("");
   Print(StringFormat("%-6s | %-8s | %-8s | %-6s | %-6s | %-8s | %-6s | %s",
      "Window", "TrainPF", "TestPF", "TrainDD", "TestDD", "Degrade", "Trades", "Status"));
   Print("--------------------------------------------------------------------");

   for(int i = 0; i < count; i++)
     {
      string status;
      if(results[i].overfitting)
         status = "OVERFIT";
      else if(results[i].testPassed)
         status = "PASS";
      else if(results[i].testProfit > 0)
         status = "PROFIT";
      else
         status = "FAIL";

      Print(StringFormat("%-6d | %-8.2f | %-8.2f | %-5.1f%% | %-5.1f%% | %-7.2f | %-6d | %s",
         i + 1,
         results[i].trainPF,
         results[i].testPF,
         results[i].trainDD,
         results[i].testDD,
         results[i].pfDegradation,
         results[i].testTrades,
         status));

      if(results[i].overfitting && results[i].degradationReason != "")
         Print("  Reason: " + results[i].degradationReason);
     }

   Print("--------------------------------------------------------------------");
   Print("AVERAGE  | Train PF: ", DoubleToString(summary.avgTrainPF, 2),
         " | Test PF: ", DoubleToString(summary.avgTestPF, 2),
         " | Degradation: ", DoubleToString(summary.overallDegradation, 2));
   Print("         | Train DD: ", DoubleToString(summary.avgTrainDD, 1), "%",
         " | Test DD: ", DoubleToString(summary.avgTestDD, 1), "%");
   Print("         | Consistency: ", DoubleToString(summary.consistencyScore * 100, 0), "%",
         " | Stability: ", DoubleToString(summary.stabilityScore * 100, 0), "%");
   Print("====================================================================");
   Print("ASSESSMENT: ", summary.assessment);
   Print("====================================================================");
  }

// ====================================================================
// Usage guide (printed to Experts log)
// ====================================================================
void PrintWalkForwardUsageGuide()
  {
   Print("====================================================================");
   Print("         WALK-FORWARD TESTING — HOW TO USE                          ");
   Print("====================================================================");
   Print("");
   Print("Step 1: Prepare your data");
   Print("  - Ensure you have at least 2 years of tick data");
   Print("  - Use 'Every tick based on real ticks' mode");
   Print("");
   Print("Step 2: Define windows");
   Print("  - Default: 6 months train → 3 months test, roll forward 1 month");
   Print("  - For 2 years of data: you get ~10 rolling windows");
   Print("");
   Print("Step 3: For each window:");
   Print("  a) Run optimization on the training window");
   Print("  b) Record best parameters and train metrics");
   Print("  c) Run backtest with those parameters on the test window");
   Print("  d) Record test metrics");
   Print("  e) Compare: is test PF >= 50% of train PF?");
   Print("  f) Compare: is test DD <= train DD + 10%?");
   Print("");
   Print("Step 4: Evaluate aggregate results");
   Print("  - Consistency Score: % of windows that were profitable");
   Print("  - Stability Score: % of windows that passed all criteria");
   Print("  - Overall Degradation: avg(test PF) / avg(train PF)");
   Print("");
   Print("Step 5: Decision");
   Print("  - ROBUST: Deploy to demo/live");
   Print("  - OVERFITTED: Simplify strategy, reduce parameters");
   Print("  - INCONSISTENT: Strategy needs regime adaptation");
   Print("  - MARGINAL: Collect more data, re-test");
   Print("====================================================================");
  }

#endif // __PASR_WALK_FORWARD_MQH__
