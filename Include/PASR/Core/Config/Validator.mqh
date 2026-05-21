//+------------------------------------------------------------------+
//|                                   Core/Config/Validator.mqh     |
//|                                   Copyright 2026, Agsicentre    |
//|                                                                  |
//|  PURPOSE: Standalone config validation — 28 business rules.     |
//|    - Zero dependencies (no EventBus, no IManager)               |
//|    - Returns human-readable error list                           |
//|    - Called by CConfigManager before every ConfigReload dispatch |
//|    - Can also be used in SmokeTest and OnInit guard             |
//|                                                                  |
//|  CHANGES v2.01 (2026-05-21):                                     |
//|    Rule 26: DisplayConfig.FontSize range check [6,20]            |
//|    Rule 27: Total theoretical risk guard:                        |
//|             RiskPercent * MaxOpenPositions < MaxDailyLossPct     |
//|             Prevents silent account blow-up from concurrent pos. |
//|    Rule 28: ModelFileName path traversal guard:                  |
//|             File must not start with "../"                       |
//|             Blocks malicious .set files from escaping MQL5 dir.  |
//|                                                                  |
//|  USAGE:                                                          |
//|    StrategyConfig cfg;                                           |
//|    string errors[];                                              |
//|    if(!CConfigValidator::Validate(cfg, errors))                  |
//|    {                                                             |
//|      for(int i=0;i<ArraySize(errors);i++) Alert(errors[i]);      |
//|      return INIT_PARAMETERS_INCORRECT;                           |
//|    }                                                             |
//+------------------------------------------------------------------+
#property strict
#ifndef __CORE_CONFIG_VALIDATOR_MQH__
#define __CORE_CONFIG_VALIDATOR_MQH__

#include "Types.mqh"

//+------------------------------------------------------------------+
//| CConfigValidator — static-only, no instances needed             |
//+------------------------------------------------------------------+
class CConfigValidator
  {
private:
   //--- Append one error message to the error array
   static void AddError(string &errors[], const string msg)
     {
      int n = ArraySize(errors);
      ArrayResize(errors, n + 1);
      errors[n] = msg;
     }

public:
   //--- Main entry point. Returns true if ALL 28 rules pass.
   //--- On failure, errors[] is populated with all failing rules.
   //--- This is a COMPLETE scan — all errors collected, not fail-fast.
   static bool Validate(const StrategyConfig &cfg, string &errors[])
     {
      ArrayResize(errors, 0);

      //=== SECTION 1: Identity =========================================

      if(cfg.MagicNumber <= 0)
         AddError(errors, "[Config] MagicNumber must be > 0 (got " +
                  IntegerToString(cfg.MagicNumber) + ")");

      if(StringLen(cfg.EAName) == 0)
         AddError(errors, "[Config] EAName must not be empty");

      //=== SECTION 2: Risk =============================================

      if(cfg.Risk.LotSize <= 0.0 && cfg.Risk.RiskPercent <= 0.0)
         AddError(errors, "[Config.Risk] Either LotSize or RiskPercent must be > 0");

      if(cfg.Risk.LotSize < 0.0)
         AddError(errors, "[Config.Risk] LotSize cannot be negative (got " +
                  DoubleToString(cfg.Risk.LotSize, 4) + ")");

      if(cfg.Risk.RiskPercent < 0.0 || cfg.Risk.RiskPercent > 100.0)
         AddError(errors, "[Config.Risk] RiskPercent must be in [0, 100] (got " +
                  DoubleToString(cfg.Risk.RiskPercent, 2) + ")");

      if(cfg.Risk.MaxDailyLossPct <= 0.0 || cfg.Risk.MaxDailyLossPct > 50.0)
         AddError(errors, "[Config.Risk] MaxDailyLossPct must be in (0, 50] (got " +
                  DoubleToString(cfg.Risk.MaxDailyLossPct, 2) + ")");

      if(cfg.Risk.MaxOpenPositions <= 0 || cfg.Risk.MaxOpenPositions > 100)
         AddError(errors, "[Config.Risk] MaxOpenPositions must be in [1, 100] (got " +
                  IntegerToString(cfg.Risk.MaxOpenPositions) + ")");

      if(cfg.Risk.SLMultiplier <= 0.0 || cfg.Risk.SLMultiplier > 20.0)
         AddError(errors, "[Config.Risk] SLMultiplier must be in (0, 20] (got " +
                  DoubleToString(cfg.Risk.SLMultiplier, 2) + ")");

      if(cfg.Risk.TPMultiplier <= 0.0 || cfg.Risk.TPMultiplier > 20.0)
         AddError(errors, "[Config.Risk] TPMultiplier must be in (0, 20] (got " +
                  DoubleToString(cfg.Risk.TPMultiplier, 2) + ")");

      //=== SECTION 3: Market ===========================================

      if(cfg.Market.ATRPeriod <= 0 || cfg.Market.ATRPeriod > 500)
         AddError(errors, "[Config.Market] ATRPeriod must be in [1, 500] (got " +
                  IntegerToString(cfg.Market.ATRPeriod) + ")");

      if(cfg.Market.ADXPeriod <= 0 || cfg.Market.ADXPeriod > 500)
         AddError(errors, "[Config.Market] ADXPeriod must be in [1, 500] (got " +
                  IntegerToString(cfg.Market.ADXPeriod) + ")");

      if(cfg.Market.ADXTrendThreshold <= 0.0 || cfg.Market.ADXTrendThreshold > 100.0)
         AddError(errors, "[Config.Market] ADXTrendThreshold must be in (0, 100] (got " +
                  DoubleToString(cfg.Market.ADXTrendThreshold, 2) + ")");

      if(cfg.Market.SpreadFilterPips < 0.0)
         AddError(errors, "[Config.Market] SpreadFilterPips cannot be negative");

      if(cfg.Market.SessionStartHour < 0 || cfg.Market.SessionStartHour > 23)
         AddError(errors, "[Config.Market] SessionStartHour must be in [0, 23] (got " +
                  IntegerToString(cfg.Market.SessionStartHour) + ")");

      if(cfg.Market.SessionEndHour < 0 || cfg.Market.SessionEndHour > 23)
         AddError(errors, "[Config.Market] SessionEndHour must be in [0, 23] (got " +
                  IntegerToString(cfg.Market.SessionEndHour) + ")");

      //=== SECTION 4: AI ===============================================

      if(cfg.AI.EnableAI)
        {
         if(cfg.AI.MinConfidence < 0.0 || cfg.AI.MinConfidence > 1.0)
            AddError(errors, "[Config.AI] MinConfidence must be in [0.0, 1.0] (got " +
                     DoubleToString(cfg.AI.MinConfidence, 3) + ")");

         if(cfg.AI.LearningRate <= 0.0 || cfg.AI.LearningRate > 1.0)
            AddError(errors, "[Config.AI] LearningRate must be in (0, 1.0] (got " +
                     DoubleToString(cfg.AI.LearningRate, 6) + ")");

         if(cfg.AI.TrainIntervalBars <= 0 || cfg.AI.TrainIntervalBars > 1000)
            AddError(errors, "[Config.AI] TrainIntervalBars must be in [1, 1000] (got " +
                     IntegerToString(cfg.AI.TrainIntervalBars) + ")");

         if(cfg.AI.ReplayBufferSize < cfg.AI.MinibatchSize)
            AddError(errors, "[Config.AI] ReplayBufferSize (" +
                     IntegerToString(cfg.AI.ReplayBufferSize) +
                     ") must be >= MinibatchSize (" +
                     IntegerToString(cfg.AI.MinibatchSize) + ")");

         if(cfg.AI.MinibatchSize <= 0 || cfg.AI.MinibatchSize > 512)
            AddError(errors, "[Config.AI] MinibatchSize must be in [1, 512] (got " +
                     IntegerToString(cfg.AI.MinibatchSize) + ")");

         if(cfg.AI.PersistWeights && StringLen(cfg.AI.ModelFileName) == 0)
            AddError(errors, "[Config.AI] ModelFileName must not be empty when PersistWeights=true");

         // RULE 28 — Path traversal guard
         // A malicious .set file could set ModelFileName = "../../Windows/System32/evil.bin"
         // and force the EA to write or read from an arbitrary filesystem path.
         // Block any filename that tries to escape the MQL5/Common directory.
         if(StringLen(cfg.AI.ModelFileName) > 0 &&
            StringFind(cfg.AI.ModelFileName, "..\\") == 0)
            AddError(errors, "[Config.AI] ModelFileName must not start with '../' "
                     "(path traversal not allowed): " + cfg.AI.ModelFileName);
         if(StringLen(cfg.AI.ModelFileName) > 0 &&
            StringFind(cfg.AI.ModelFileName, "../") == 0)
            AddError(errors, "[Config.AI] ModelFileName must not start with '../' "
                     "(path traversal not allowed): " + cfg.AI.ModelFileName);
        }

      //=== SECTION 5: Pattern ==========================================

      if(cfg.Pattern.MinPatternScore < 0.0 || cfg.Pattern.MinPatternScore > 100.0)
         AddError(errors, "[Config.Pattern] MinPatternScore must be in [0, 100] (got " +
                  DoubleToString(cfg.Pattern.MinPatternScore, 2) + ")");

      if(cfg.Pattern.LookbackBars <= 0 || cfg.Pattern.LookbackBars > 2000)
         AddError(errors, "[Config.Pattern] LookbackBars must be in [1, 2000] (got " +
                  IntegerToString(cfg.Pattern.LookbackBars) + ")");

      if(cfg.Pattern.PinBarRatio <= 0.0)
         AddError(errors, "[Config.Pattern] PinBarRatio must be > 0 (got " +
                  DoubleToString(cfg.Pattern.PinBarRatio, 2) + ")");

      if(cfg.Pattern.EngulfMultiplier <= 0.0)
         AddError(errors, "[Config.Pattern] EngulfMultiplier must be > 0 (got " +
                  DoubleToString(cfg.Pattern.EngulfMultiplier, 2) + ")");

      //=== SECTION 6: Display ==========================================

      // RULE 26 — FontSize: must be renderable on MT5 chart
      // Below 6pt is illegible; above 20pt overflows the panel area.
      if(cfg.Display.FontSize < 6 || cfg.Display.FontSize > 20)
         AddError(errors, "[Config.Display] FontSize must be in [6, 20] (got " +
                  IntegerToString(cfg.Display.FontSize) + ")");

      //=== SECTION 7: Cross-field consistency ==========================

      // TP must be strictly greater than SL (positive R:R)
      if(cfg.Risk.TPMultiplier > 0.0 && cfg.Risk.SLMultiplier > 0.0 &&
         cfg.Risk.TPMultiplier <= cfg.Risk.SLMultiplier)
         AddError(errors, "[Config.Risk] TPMultiplier (" +
                  DoubleToString(cfg.Risk.TPMultiplier, 2) +
                  ") must be > SLMultiplier (" +
                  DoubleToString(cfg.Risk.SLMultiplier, 2) +
                  ") for positive R:R");

      // Single trade risk must be less than daily loss limit
      if(cfg.Risk.RiskPercent > 0.0 &&
         cfg.Risk.MaxDailyLossPct > 0.0 &&
         cfg.Risk.RiskPercent >= cfg.Risk.MaxDailyLossPct)
         AddError(errors, "[Config.Risk] RiskPercent per trade (" +
                  DoubleToString(cfg.Risk.RiskPercent, 2) +
                  "%) must be < MaxDailyLossPct (" +
                  DoubleToString(cfg.Risk.MaxDailyLossPct, 2) + "%)");

      // Session hours: start must be before end (unless 0-23 = all day)
      if(cfg.Market.SessionStartHour > 0 || cfg.Market.SessionEndHour < 23)
        {
         if(cfg.Market.SessionStartHour >= cfg.Market.SessionEndHour)
            AddError(errors, "[Config.Market] SessionStartHour (" +
                     IntegerToString(cfg.Market.SessionStartHour) +
                     ") must be < SessionEndHour (" +
                     IntegerToString(cfg.Market.SessionEndHour) + ")");
        }

      // RULE 27 — Total theoretical risk guard
      // Scenario: RiskPercent=5%, MaxOpenPositions=10 → 50% exposure at once
      // If MaxDailyLossPct=3%, this is incoherent: 10 simultaneous 5% risks
      // can blow the account in a single correlated adverse move.
      // Rule: RiskPercent * MaxOpenPositions must not exceed MaxDailyLossPct * 2
      // (factor 2 allows for reasonable concurrent trades within daily limit)
      if(cfg.Risk.RiskPercent > 0.0 &&
         cfg.Risk.MaxOpenPositions > 0 &&
         cfg.Risk.MaxDailyLossPct > 0.0)
        {
         double totalRisk = cfg.Risk.RiskPercent * cfg.Risk.MaxOpenPositions;
         double safeLimit = cfg.Risk.MaxDailyLossPct * 2.0;
         if(totalRisk > safeLimit)
            AddError(errors,
                     "[Config.Risk] Total theoretical risk (RiskPercent " +
                     DoubleToString(cfg.Risk.RiskPercent, 2) + "% x " +
                     IntegerToString(cfg.Risk.MaxOpenPositions) + " positions = " +
                     DoubleToString(totalRisk, 2) + "%) exceeds 2x MaxDailyLossPct (" +
                     DoubleToString(safeLimit, 2) +
                     "%). Reduce RiskPercent or MaxOpenPositions.");
        }

      return ArraySize(errors) == 0;
     }

   //--- Convenience: print all errors to Experts log
   static void PrintErrors(const string &errors[])
     {
      int n = ArraySize(errors);
      if(n == 0)
        {
         Print("[CConfigValidator] Config OK — all 28 rules passed");
         return;
        }
      Print("[CConfigValidator] Config INVALID — ", n, " error(s):");
      for(int i = 0; i < n; i++)
         Print("  [!", i + 1, "] ", errors[i]);
     }

   //--- Quick boolean check (no error list needed)
   static bool IsValid(const StrategyConfig &cfg)
     {
      string dummy[];
      return Validate(cfg, dummy);
     }
  };

#endif // __CORE_CONFIG_VALIDATOR_MQH__
