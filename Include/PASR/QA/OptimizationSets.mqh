//+------------------------------------------------------------------+
//| PASR Optimization Parameter Sets                                 |
//| Pre-defined parameter ranges for Strategy Tester optimization    |
//| Quant Developer — Senior MQL Architecture                        |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_OPTIMIZATION_SETS_MQH__
#define __PASR_OPTIMIZATION_SETS_MQH__

// ====================================================================
// Parameter optimization definition
// ====================================================================
struct SOptParam
  {
   string name;
   double start;
   double end;
   double step;
   bool   enabled;
   string description;
  };

// ====================================================================
// Optimization Set A: Conservative — Minimal parameters, fast run
// Best for: Initial validation, checking if strategy has any edge
// ====================================================================
void GetOptSetConservative(SOptParam &params[], int &count)
  {
   count = 5;
   ArrayResize(params, count);

   params[0].name = "RiskPercent";         params[0].start = 0.5;  params[0].end = 1.5;  params[0].step = 0.25; params[0].enabled = true;  params[0].description = "Risk per trade (%)";
   params[1].name = "SLMultiplier";         params[1].start = 1.5;  params[1].end = 2.5;  params[1].step = 0.25; params[1].enabled = true;  params[1].description = "Stop loss ATR multiplier";
   params[2].name = "TPMultiplier";         params[2].start = 2.0;  params[2].end = 3.5;  params[2].step = 0.25; params[2].enabled = true;  params[2].description = "Take profit ATR multiplier";
   params[3].name = "ADXThreshold";         params[3].start = 20.0; params[3].end = 30.0; params[3].step = 2.5;  params[3].enabled = true;  params[3].description = "ADX trend filter threshold";
   params[4].name = "MinConfluence";        params[4].start = 1.0;  params[4].end = 2.0;  params[4].step = 1.0;  params[4].enabled = true;  params[4].description = "Minimum signal agreement";
  }

// ====================================================================
// Optimization Set B: Moderate — Full parameter sweep
// Best for: Deep optimization after initial validation passes
// ====================================================================
void GetOptSetModerate(SOptParam &params[], int &count)
  {
   count = 10;
   ArrayResize(params, count);

   params[0].name = "RiskPercent";          params[0].start = 0.5;  params[0].end = 2.0;  params[0].step = 0.25; params[0].enabled = true;  params[0].description = "Risk per trade (%)";
   params[1].name = "SLMultiplier";          params[1].start = 1.0;  params[1].end = 3.0;  params[1].step = 0.25; params[1].enabled = true;  params[1].description = "Stop loss ATR multiplier";
   params[2].name = "TPMultiplier";          params[2].start = 1.5;  params[2].end = 4.0;  params[2].step = 0.25; params[2].enabled = true;  params[2].description = "Take profit ATR multiplier";
   params[3].name = "ADXThreshold";          params[3].start = 15.0; params[3].end = 35.0; params[3].step = 2.5;  params[3].enabled = true;  params[3].description = "ADX trend filter threshold";
   params[4].name = "MinConfluence";         params[4].start = 1.0;  params[4].end = 3.0;  params[4].step = 1.0;  params[4].enabled = true;  params[4].description = "Minimum signal agreement";
   params[5].name = "SignalMinScore";        params[5].start = 0.30; params[5].end = 0.55; params[5].step = 0.05; params[5].enabled = true;  params[5].description = "Minimum signal score";
   params[6].name = "MinRRRatio";            params[6].start = 1.2;  params[6].end = 2.5;  params[6].step = 0.15; params[6].enabled = true;  params[6].description = "Minimum risk/reward ratio";
   params[7].name = "MinPatternScore";       params[7].start = 35.0; params[7].end = 60.0; params[7].step = 5.0;  params[7].enabled = true;  params[7].description = "Minimum pattern score";
   params[8].name = "MaxDailyLossPct";       params[8].start = 2.0;  params[8].end = 5.0;  params[8].step = 0.5;  params[8].enabled = true;  params[8].description = "Max daily loss (%)";
   params[9].name = "MaxDrawdownPct";        params[9].start = 8.0;  params[9].end = 20.0; params[9].step = 2.0;  params[9].enabled = true;  params[9].description = "Max drawdown (%)";
  }

// ====================================================================
// Optimization Set C: AI-Focused — AI confidence and regime tuning
// Best for: AI Driven and Pattern Heavy profiles
// ====================================================================
void GetOptSetAI(SOptParam &params[], int &count)
  {
   count = 8;
   ArrayResize(params, count);

   params[0].name = "AIMinConfidence";       params[0].start = 0.50; params[0].end = 0.80; params[0].step = 0.05; params[0].enabled = true;  params[0].description = "AI minimum confidence";
   params[1].name = "AIMinExpectedR";        params[1].start = 0.3;  params[1].end = 1.2;  params[1].step = 0.1;  params[1].enabled = true;  params[1].description = "AI minimum expected return";
   params[2].name = "AIMaxFailureProbability"; params[2].start = 0.35; params[2].end = 0.65; params[2].step = 0.05; params[2].enabled = true;  params[2].description = "AI maximum failure probability";
   params[3].name = "TrendEntryThreshold";   params[3].start = 0.50; params[3].end = 0.75; params[3].step = 0.05; params[3].enabled = true;  params[3].description = "Trend regime entry threshold";
   params[4].name = "RangeEntryThreshold";   params[4].start = 0.55; params[4].end = 0.80; params[4].step = 0.05; params[4].enabled = true;  params[4].description = "Range regime entry threshold";
   params[5].name = "VolatileEntryThreshold"; params[5].start = 0.70; params[5].end = 0.95; params[5].step = 0.05; params[5].enabled = true;  params[5].description = "Volatile regime entry threshold";
   params[6].name = "RiskPercent";           params[6].start = 0.5;  params[6].end = 2.0;  params[6].step = 0.25; params[6].enabled = true;  params[6].description = "Risk per trade (%)";
   params[7].name = "TPMultiplier";          params[7].start = 1.5;  params[7].end = 4.0;  params[7].step = 0.25; params[7].enabled = true;  params[7].description = "Take profit ATR multiplier";
  }

// ====================================================================
// Print optimization parameter summary
// ====================================================================
void PrintOptSetSummary(const string setName, SOptParam &params[], int count)
  {
   Print("====================================================================");
   Print("  Optimization Set: ", setName);
   Print("  Parameters: ", count);
   Print("  Total combinations: ", ComputeTotalCombinations(params, count));
   Print("====================================================================");
   Print(StringFormat("%-25s | %-8s | %-8s | %-8s | %s",
      "Parameter", "Start", "End", "Step", "Values"));
   Print("--------------------------------------------------------------------");

   for(int i = 0; i < count; i++)
     {
      if(!params[i].enabled) continue;
      int values = (int)((params[i].end - params[i].start) / params[i].step) + 1;
      Print(StringFormat("%-25s | %-8.2f | %-8.2f | %-8.2f | %d",
         params[i].name,
         params[i].start,
         params[i].end,
         params[i].step,
         values));
     }
   Print("====================================================================");
  }

int ComputeTotalCombinations(SOptParam &params[], int count)
  {
   int total = 1;
   for(int i = 0; i < count; i++)
     {
      if(!params[i].enabled) continue;
      int values = (int)((params[i].end - params[i].start) / params[i].step) + 1;
      total *= values;
     }
   return total;
  }

#endif // __PASR_OPTIMIZATION_SETS_MQH__
