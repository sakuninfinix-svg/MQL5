//+------------------------------------------------------------------+
//|                                          IPatternStrategy.mqh    |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Interface for pattern detection strategies"

#include "PatternTypes.mqh"
#include "../Context/PatternContext.mqh"
#include "../Config/PatternConfig.mqh"

//+------------------------------------------------------------------+
//| Pattern Detection Result                                         |
//+------------------------------------------------------------------+
struct SPatternResult
{
   ENUM_PATTERN_TYPE   type;               // Pattern type detected
   int                 direction;          // 1=Bullish, -1=Bearish, 0=None
   double              score;              // Raw score (0-100)
   double              contextScore;       // Context-adjusted score
   double              finalScore;         // Final weighted score
   int                 barIndex;           // Bar index where detected
   datetime            time;               // Bar time
   double              entryPrice;         // Suggested entry
   double              stopLoss;           // Suggested stop loss
   double              takeProfit;         // Suggested take profit
   string              notes;              // Additional notes
   
   void Init()
   {
      type          = PATTERN_NONE;
      direction     = 0;
      score         = 0.0;
      contextScore  = 0.0;
      finalScore    = 0.0;
      barIndex      = 0;
      time          = 0;
      entryPrice    = 0.0;
      stopLoss      = 0.0;
      takeProfit    = 0.0;
      notes         = "";
   }
   
   bool IsValid() const
   {
      return (type != PATTERN_NONE && direction != 0 && finalScore > 0);
   }
   
   string ToString() const
   {
      if(!IsValid())
         return "No valid pattern";
      
      return StringFormat("%s %s [Score: %.1f, Final: %.1f] @ %d",
                         EnumToString(type),
                         direction > 0 ? "BULL" : "BEAR",
                         score,
                         finalScore,
                         barIndex);
   }
};

//+------------------------------------------------------------------+
//| Abstract Pattern Strategy Interface                              |
//+------------------------------------------------------------------+
class IPatternStrategy
{
protected:
   string            m_name;               // Strategy name
   ENUM_PATTERN_TYPE m_patternType;        // Pattern type this strategy detects
   
public:
   virtual ~IPatternStrategy() {}
   
   // Initialize strategy
   virtual void Init() = 0;
   
   // Get strategy name
   string GetName() const { return m_name; }
   
   // Get pattern type
   ENUM_PATTERN_TYPE GetPatternType() const { return m_patternType; }
   
   // Main detection method
   virtual SPatternResult Detect(int shift, 
                                 const CPatternContext &context,
                                 const SPatternParams &params) = 0;
   
   // Calculate raw pattern score (without context)
   virtual double CalculateRawScore(int shift, 
                                   const CPatternContext &context) = 0;
   
   // Apply context adjustments to score
   virtual double ApplyContextAdjustment(double rawScore, 
                                        const CPatternContext &context) = 0;
   
   // Validate pattern meets minimum criteria
   virtual bool ValidatePattern(const SPatternResult &result,
                               const SPatternParams &params) = 0;
   
   // Get suggested risk management levels
   virtual void GetRiskLevels(int shift, 
                             int direction,
                             double &entry,
                             double &stopLoss,
                             double &takeProfit) = 0;
   
   // Return detailed evaluation notes
   virtual string GetEvaluationNotes() const = 0;
};

//+------------------------------------------------------------------+
//| Base Strategy Implementation (Template Method Pattern)           |
//+------------------------------------------------------------------+
class CBasePatternStrategy : public IPatternStrategy
{
protected:
   string            m_notes;              // Evaluation notes
   CPatternContext   m_currentContext;     // Current context cache
   
   // Template methods for subclasses to override
   virtual bool CheckPatternShape(int shift) = 0;
   virtual bool CheckPatternLocation(int shift, const CPatternContext &context) = 0;
   virtual bool CheckPatternSize(int shift, const SPatternParams &params) = 0;
   virtual double EvaluatePatternStrength(int shift) = 0;
   
public:
   virtual void Init() override
   {
      m_notes = "";
   }
   
   virtual SPatternResult Detect(int shift, 
                                 const CPatternContext &context,
                                 const SPatternParams &params) override
   {
      SPatternResult result;
      result.Init();
      result.type = m_patternType;
      result.barIndex = shift;
      
      m_currentContext = context;
      m_notes = "";
      
      // Step 1: Check basic pattern shape
      if(!CheckPatternShape(shift))
      {
         m_notes += "Shape mismatch; ";
         return result;
      }
      
      // Step 2: Check location context
      if(!CheckPatternLocation(shift, context))
      {
         m_notes += "Location not favorable; ";
         return result;
      }
      
      // Step 3: Check size requirements
      if(!CheckPatternSize(shift, params))
      {
         m_notes += "Size out of range; ";
         return result;
      }
      
      // Step 4: Calculate raw score
      double rawScore = EvaluatePatternStrength(shift);
      result.score = MathMax(0.0, MathMin(rawScore, 100.0));
      
      // Step 5: Apply context adjustment
      result.contextScore = ApplyContextAdjustment(result.score, context);
      result.finalScore = result.contextScore;
      
      // Step 6: Determine direction (to be implemented by subclass)
      result.direction = DetermineDirection(shift);
      
      // Step 7: Validate against parameters
      if(!ValidatePattern(result, params))
      {
         m_notes += "Failed validation; ";
         result.Init();
         return result;
      }
      
      // Step 8: Set risk levels
      GetRiskLevels(shift, result.direction, 
                   result.entryPrice, 
                   result.stopLoss, 
                   result.takeProfit);
      
      result.time = iTime(_Symbol, _Period, shift);
      result.notes = m_notes;
      
      return result;
   }
   
   virtual double ApplyContextAdjustment(double rawScore, 
                                        const CPatternContext &context) override
   {
      double adjusted = rawScore;
      
      // Location confluence bonus (up to +20%)
      double locScore = context.GetLocationContext().GetConfluenceScore();
      adjusted += locScore * 0.20;
      
      // MTF alignment bonus (up to +15%)
      double mtfBonus = context.GetMTFContext().GetAlignmentBonus();
      adjusted += mtfBonus * 0.15;
      
      // Volume confirmation bonus (up to +10%)
      double volScore = context.GetVolumeContext().GetVolumeScore();
      if(volScore > 60.0)
         adjusted += (volScore - 60.0) * 0.10;
      
      // Regime penalty/bonus
      ENUM_MARKET_REGIME regime = context.GetMarketContext().regime;
      if(regime == REGIME_VOLATILE)
         adjusted *= 0.9;  // Penalty in volatile markets
      else if(regime == REGIME_TRENDING_STRONG)
         adjusted *= 1.1;  // Bonus in strong trends
      
      return MathMax(0.0, MathMin(adjusted, 100.0));
   }
   
   virtual bool ValidatePattern(const SPatternResult &result,
                               const SPatternParams &params) override
   {
      if(!result.IsValid())
         return false;
      
      if(result.finalScore < params.minTotalScore)
         return false;
      
      return true;
   }
   
   virtual void GetRiskLevels(int shift, 
                             int direction,
                             double &entry,
                             double &stopLoss,
                             double &takeProfit) override
   {
      double high = iHigh(_Symbol, _Period, shift);
      double low = iLow(_Symbol, _Period, shift);
      double close = iClose(_Symbol, _Period, shift);
      double point = _Point;
      
      if(direction > 0)  // Bullish
      {
         entry = close;
         stopLoss = low - 2 * point;
         takeProfit = close + 2 * (close - stopLoss);  // 1:2 RR
      }
      else if(direction < 0)  // Bearish
      {
         entry = close;
         stopLoss = high + 2 * point;
         takeProfit = close - 2 * (stopLoss - close);  // 1:2 RR
      }
   }
   
   virtual string GetEvaluationNotes() const override
   {
      return m_notes;
   }
   
protected:
   // Helper method for direction determination
   virtual int DetermineDirection(int shift)
   {
      // Default implementation - should be overridden
      return 0;
   }
};
