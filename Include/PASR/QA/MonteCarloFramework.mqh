//+------------------------------------------------------------------+
//| PASR Monte Carlo Robustness Testing Framework                    |
//| Trade sequence randomization + statistical robustness validation  |
//| Quant Developer — Senior MQL Architecture                        |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_MONTE_CARLO_MQH__
#define __PASR_MONTE_CARLO_MQH__

#include "StrategyTestSuite.mqh"

// ====================================================================
// Monte Carlo Simulation Configuration
// ====================================================================
enum ENUM_MC_METHOD
  {
   MC_TRADE_RANDOMIZE,     // Shuffle trade order (preserves trade stats)
   MC_TRADE_SHUFFLE_BLOCKS, // Shuffle in blocks (preserves some autocorrelation)
   MC_TRADE_RESAMPLE,      // Bootstrap resampling (with replacement)
   MC_TRADE_MUTATE,        // Mutate individual trade PnL by small random amount
   MC_SPREAD_MUTATE,       // Randomly widen spreads on subset of trades
   MC_SLIPPAGE_INJECT      // Inject random slippage on entries/exits
  };

struct SMCConfig
  {
   int              numSimulations;      // Number of Monte Carlo runs (500-5000)
   ENUM_MC_METHOD   method;              // Randomization method
   double           mutatePct;           // For MUTATE: max % PnL change per trade (e.g., 0.10 = 10%)
   double           slippagePips;        // For SLIPPAGE_INJECT: max slippage in pips
   double           spreadWidenPips;     // For SPREAD_MUTATE: extra spread on mutated trades
   double           blockCount;          // For SHUFFLE_BLOCKS: number of blocks
   double           sampleRate;          // For RESAMPLE: sample rate (1.0 = same size)
   int              confidenceLevel;     // Confidence level for VaR (90, 95, 99)
  };

// ====================================================================
// Individual trade record for Monte Carlo
// ====================================================================
struct SMCTrade
  {
   datetime openTime;
   datetime closeTime;
   ENUM_SIGNAL_DIR direction;
   double openPrice;
   double closePrice;
   double lot;
   double profit;        // Net PnL (including commission/swap)
   double profitPips;    // PnL in pips
   double commission;
   double swap;
   int    barsHeld;
   bool   hitSL;
   bool   hitTP;
  };

// ====================================================================
// Monte Carlo Simulation Result
// ====================================================================
struct SMCSimResult
  {
   int    simId;
   double totalProfit;
   double profitFactor;
   double winRate;
   double maxDD;
   double maxDDPct;
   double sharpeRatio;
   double recoveryFactor;
   int    totalTrades;
   int    winTrades;
   int    lossTrades;
  };

// ====================================================================
// Monte Carlo Aggregate Summary
// ====================================================================
struct SMCSummary
  {
   string profileName;
   int    totalSims;
   int    profitableSims;
   double profitPct;           // % simulations that were profitable

   // Statistics
   double avgProfit;           // Average profit across all sims
   double medianProfit;        // Median profit
   double p5Profit;            // 5th percentile profit (worst case)
   double p95Profit;           // 95th percentile profit
   double minProfit;           // Absolute minimum
   double maxProfit;           // Absolute maximum

   double avgPF;               // Average profit factor
   double medianPF;            // Median profit factor
   double p5PF;                // 5th percentile PF

   double avgDD;               // Average max drawdown
   double medianDD;            // Median max drawdown
   double p95DD;               // 95th percentile DD (worst case DD)

   double var90;               // Value at Risk 90%
   double var95;               // Value at Risk 95%
   double var99;               // Value at Risk 99%

   double cvar95;              // Conditional VaR (expected loss beyond VaR)

   // Robustness assessment
   bool   robust;              // true if meets all robustness criteria
   string assessment;
  };

// ====================================================================
// Default Monte Carlo configuration
// ====================================================================
SMCConfig GetDefaultMCConfig()
  {
   SMCConfig cfg;
   cfg.numSimulations = 1000;
   cfg.method = MC_TRADE_RANDOMIZE;
   cfg.mutatePct = 0.10;
   cfg.slippagePips = 1.0;
   cfg.spreadWidenPips = 0.5;
   cfg.blockCount = 10;
   cfg.sampleRate = 1.0;
   cfg.confidenceLevel = 95;
   return cfg;
  }

// ====================================================================
// Helper: Sort array for percentile calculation
// ====================================================================
void SortDouble(double &arr[], int count)
  {
   for(int i = 0; i < count - 1; i++)
     {
      for(int j = i + 1; j < count; j++)
        {
         if(arr[j] < arr[i])
           {
            double tmp = arr[i];
            arr[i] = arr[j];
            arr[j] = tmp;
           }
        }
     }
  }

// ====================================================================
// Helper: Get percentile from sorted array
// ====================================================================
double GetPercentile(double &sorted[], int count, double pct)
  {
   if(count == 0) return 0.0;
   int idx = (int)MathFloor(pct * (count - 1));
   idx = MathMax(0, MathMin(count - 1, idx));
   return sorted[idx];
  }

// ====================================================================
// Randomize trades (Fisher-Yates shuffle)
// ====================================================================
void ShuffleTrades(SMCTrade &trades[], int count)
  {
   for(int i = count - 1; i > 0; i--)
     {
      int j = (int)(MathRand() / 32767.0 * i);
      SMCTrade tmp = trades[i];
      trades[i] = trades[j];
      trades[j] = tmp;
     }
  }

// ====================================================================
// Shuffle in blocks (preserves some autocorrelation)
// ====================================================================
void ShuffleBlocks(SMCTrade &trades[], int count, int numBlocks)
  {
   int blockSize = MathMax(1, count / numBlocks);
   for(int b = 0; b < numBlocks; b++)
     {
      int start = b * blockSize;
      int end = MathMin(start + blockSize, count);
      if(end - start > 1)
        {
         // Shuffle within block
         for(int i = end - 1; i > start; i--)
           {
            int range = i - start + 1;
            int j = start + (int)(MathRand() / 32767.0 * range);
            SMCTrade tmp = trades[i];
            trades[i] = trades[j];
            trades[j] = tmp;
           }
        }
     }
  }

// ====================================================================
// Mutate individual trade PnL by random percentage
// ====================================================================
void MutateTrades(SMCTrade &trades[], int count, double maxPct)
  {
   for(int i = 0; i < count; i++)
     {
      double mutation = (MathRand() / 32767.0 * 2.0 - 1.0) * maxPct;
      trades[i].profit *= (1.0 + mutation);
      trades[i].profitPips *= (1.0 + mutation);
     }
  }

// ====================================================================
// Inject slippage on entries/exits
// ====================================================================
void InjectSlippage(SMCTrade &trades[], int count, double maxSlippagePips)
  {
   for(int i = 0; i < count; i++)
     {
      double slip = (MathRand() / 32767.0 * 2.0 - 1.0) * maxSlippagePips;
      double slipValue = slip * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10; // convert pips
      if(trades[i].direction == SIGNAL_BUY)
         trades[i].profit -= slipValue * trades[i].lot * 100000;
      else
         trades[i].profit -= slipValue * trades[i].lot * 100000;
     }
  }

// ====================================================================
// Run a single Monte Carlo simulation
// ====================================================================
void RunMCSimulation(SMCSimResult &result, SMCTrade &originalTrades[], int tradeCount,
                     const SMCConfig &cfg, int simId)
  {
   // Create working copy
   SMCTrade trades[];
   ArrayCopy(trades, originalTrades);

   // Apply randomization method
   switch(cfg.method)
     {
      case MC_TRADE_RANDOMIZE:
         ShuffleTrades(trades, tradeCount);
         break;
      case MC_TRADE_SHUFFLE_BLOCKS:
         ShuffleBlocks(trades, tradeCount, (int)cfg.blockCount);
         break;
      case MC_TRADE_RESAMPLE:
         // Bootstrap: sample with replacement
         {
            int newCount = (int)(tradeCount * cfg.sampleRate);
            for(int i = 0; i < newCount; i++)
              {
               int src = (int)(MathRand() / 32767.0 * tradeCount);
               trades[i] = originalTrades[src % tradeCount];
              }
            tradeCount = newCount;
         }
         break;
      case MC_TRADE_MUTATE:
         ShuffleTrades(trades, tradeCount);
         MutateTrades(trades, tradeCount, cfg.mutatePct);
         break;
      case MC_SPREAD_MUTATE:
         MutateTrades(trades, tradeCount, cfg.spreadWidenPips * 0.01);
         break;
      case MC_SLIPPAGE_INJECT:
         ShuffleTrades(trades, tradeCount);
         InjectSlippage(trades, tradeCount, cfg.slippagePips);
         break;
     }

   // Calculate simulation metrics
   result.simId = simId;
   result.totalProfit = 0.0;
   result.winTrades = 0;
   result.lossTrades = 0;
   result.totalTrades = tradeCount;

   double grossProfit = 0.0, grossLoss = 0.0;
   double peakEquity = 0.0, currentEquity = 0.0;
   result.maxDD = 0.0;

   for(int i = 0; i < tradeCount; i++)
     {
      double pnl = trades[i].profit;
      result.totalProfit += pnl;
      currentEquity += pnl;

      if(pnl > 0)
        {
         result.winTrades++;
         grossProfit += pnl;
        }
      else
        {
         result.lossTrades++;
         grossLoss += MathAbs(pnl);
        }

      if(currentEquity > peakEquity)
         peakEquity = currentEquity;
      double dd = peakEquity - currentEquity;
      if(dd > result.maxDD)
         result.maxDD = dd;
     }

   result.winRate = (tradeCount > 0) ? (double)result.winTrades / tradeCount : 0.0;
   result.profitFactor = (grossLoss > 0) ? grossProfit / grossLoss : (grossProfit > 0 ? 999.0 : 0.0);
   result.maxDDPct = (peakEquity > 0) ? (result.maxDD / peakEquity) * 100.0 : 0.0;
   result.recoveryFactor = (result.maxDD > 0) ? result.totalProfit / result.maxDD : 0.0;
  }

// ====================================================================
// Run full Monte Carlo analysis
// ====================================================================
void RunMonteCarlo(SMCSummary &summary, SMCTrade &trades[], int tradeCount,
                   const SMCConfig &cfg, const string profileName)
  {
   summary.profileName = profileName;
   summary.totalSims = cfg.numSimulations;
   summary.profitableSims = 0;

   SMCSimResult results[];
   ArrayResize(results, cfg.numSimulations);

   double profits[], pfs[], dds[];
   ArrayResize(profits, cfg.numSimulations);
   ArrayResize(pfs, cfg.numSimulations);
   ArrayResize(dds, cfg.numSimulations);

   for(int i = 0; i < cfg.numSimulations; i++)
     {
      RunMCSimulation(results[i], trades, tradeCount, cfg, i);
      profits[i] = results[i].totalProfit;
      pfs[i] = results[i].profitFactor;
      dds[i] = results[i].maxDDPct;

      if(results[i].totalProfit > 0)
         summary.profitableSims++;
     }

   // Sort for percentile calculations
   SortDouble(profits, cfg.numSimulations);
   SortDouble(pfs, cfg.numSimulations);
   SortDouble(dds, cfg.numSimulations);

   // Compute statistics
   summary.profitPct = (double)summary.profitableSims / cfg.numSimulations * 100.0;

   double totalProfit = 0, totalPF = 0, totalDD = 0;
   for(int i = 0; i < cfg.numSimulations; i++)
     {
      totalProfit += results[i].totalProfit;
      totalPF += results[i].profitFactor;
      totalDD += results[i].maxDDPct;
     }

   summary.avgProfit = totalProfit / cfg.numSimulations;
   summary.medianProfit = GetPercentile(profits, cfg.numSimulations, 0.50);
   summary.p5Profit = GetPercentile(profits, cfg.numSimulations, 0.05);
   summary.p95Profit = GetPercentile(profits, cfg.numSimulations, 0.95);
   summary.minProfit = profits[0];
   summary.maxProfit = profits[cfg.numSimulations - 1];

   summary.avgPF = totalPF / cfg.numSimulations;
   summary.medianPF = GetPercentile(pfs, cfg.numSimulations, 0.50);
   summary.p5PF = GetPercentile(pfs, cfg.numSimulations, 0.05);

   summary.avgDD = totalDD / cfg.numSimulations;
   summary.medianDD = GetPercentile(dds, cfg.numSimulations, 0.50);
   summary.p95DD = GetPercentile(dds, cfg.numSimulations, 0.95);

   // Value at Risk
   summary.var90 = GetPercentile(profits, cfg.numSimulations, 0.10);
   summary.var95 = GetPercentile(profits, cfg.numSimulations, 0.05);
   summary.var99 = GetPercentile(profits, cfg.numSimulations, 0.01);

   // Conditional VaR (average of losses beyond VaR)
   {
      int cvarStart = (int)(0.05 * cfg.numSimulations);
      double cvarSum = 0;
      for(int i = 0; i < cvarStart; i++) cvarSum += profits[i];
      summary.cvar95 = (cvarStart > 0) ? cvarSum / cvarStart : 0.0;
   }

   // Robustness assessment
   summary.robust = (summary.profitPct >= 80.0 &&        // 80%+ sims profitable
                    summary.medianPF >= 1.2 &&            // Median PF > 1.2
                    summary.p5PF >= 1.0 &&                // 5th percentile PF > 1.0
                    summary.p95DD <= 25.0 &&              // 95th percentile DD < 25%
                    summary.var95 > -summary.avgProfit * 0.5); // VaR not catastrophic

   if(summary.robust)
      summary.assessment = "ROBUST — Strategy survives randomization stress test";
   else if(summary.profitPct < 50.0)
      summary.assessment = "FRAGILE — Less than half of randomized sequences are profitable";
   else if(summary.p5PF < 1.0)
      summary.assessment = "MARGINAL — Worst-case scenarios produce losing results";
   else if(summary.p95DD > 30.0)
      summary.assessment = "HIGH RISK — Extreme drawdown scenarios are too large";
   else
      summary.assessment = "MODERATE — Some vulnerability to trade sequence randomization";
  }

// ====================================================================
// Print Monte Carlo report
// ====================================================================
void PrintMCReport(const SMCSummary &summary)
  {
   Print("====================================================================");
   Print("               MONTE CARLO ROBUSTNESS REPORT                        ");
   Print("====================================================================");
   Print("Strategy: ", summary.profileName);
   Print("Simulations: ", summary.totalSims);
   Print("");
   Print("PROFITABILITY:");
   Print("  Profitable Sims: ", DoubleToString(summary.profitPct, 1), "%");
   Print("  Avg Profit: $", DoubleToString(summary.avgProfit, 2));
   Print("  Median Profit: $", DoubleToString(summary.medianProfit, 2));
   Print("  5th Percentile: $", DoubleToString(summary.p5Profit, 2));
   Print("  95th Percentile: $", DoubleToString(summary.p95Profit, 2));
   Print("  Min: $", DoubleToString(summary.minProfit, 2), " | Max: $", DoubleToString(summary.maxProfit, 2));
   Print("");
   Print("PROFIT FACTOR:");
   Print("  Avg PF: ", DoubleToString(summary.avgPF, 2));
   Print("  Median PF: ", DoubleToString(summary.medianPF, 2));
   Print("  5th Percentile PF: ", DoubleToString(summary.p5PF, 2));
   Print("");
   Print("DRAWDOWN:");
   Print("  Avg Max DD: ", DoubleToString(summary.avgDD, 1), "%");
   Print("  Median Max DD: ", DoubleToString(summary.medianDD, 1), "%");
   Print("  95th Percentile DD: ", DoubleToString(summary.p95DD, 1), "%");
   Print("");
   Print("VALUE AT RISK:");
   Print("  VaR 90%: $", DoubleToString(summary.var90, 2));
   Print("  VaR 95%: $", DoubleToString(summary.var95, 2));
   Print("  VaR 99%: $", DoubleToString(summary.var99, 2));
   Print("  CVaR 95%: $", DoubleToString(summary.cvar95, 2));
   Print("");
   Print("====================================================================");
   Print("ASSESSMENT: ", summary.assessment);
   Print("====================================================================");
  }

// ====================================================================
// Convert tester history to Monte Carlo trades
// ====================================================================
void ConvertHistoryToMCTrades(SMCTrade &trades[], int &count)
  {
   // This function would read from HistoryDealsSelect
   // For now, it's a placeholder — actual implementation requires
   // iterating through deal history and building trade records
   count = 0;
  }

#endif // __PASR_MONTE_CARLO_MQH__
