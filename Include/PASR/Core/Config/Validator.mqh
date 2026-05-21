//+------------------------------------------------------------------+
//|                                   Core/Config/Validator.mqh     |
//|                                   Copyright 2026, Agsicentre    |
//|                                                                  |
//|  PURPOSE: Standalone config validation — 25 business rules.     |
//|    - Zero dependencies (no EventBus, no IManager)               |
//|    - Returns human-readable error list                           |
//|    - Called by CConfigManager before every ConfigReload dispatch |
//|    - Can also be used in SmokeTest and OnInit guard             |
//|                                                                  |
//|  USAGE:                                                          |
//|    StrategyConfig cfg;                                           |
//|    // ... populate cfg ...                                       |
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
   //--- Main entry point. Returns true if ALL rules pass.
   //--- On failure, errors[] is populated with all failing rules.
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

         if(StringLen(cfg.AI.ModelFileName) == 0)
            AddError(errors, "[Config.AI] ModelFileName must not be empty when PersistWeights=true");
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

      //=== SECTION 6: Cross-field consistency ==========================

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

      return ArraySize(errors) == 0;
     }

   //--- Convenience: print all errors to Experts log
   static void PrintErrors(const string &errors[])
     {
      int n = ArraySize(errors);
      if(n == 0)
        {
         Print("[CConfigValidator] Config OK — all rules passed");
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
