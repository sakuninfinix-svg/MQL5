//+------------------------------------------------------------------+
//|                                      ScoringStage.mqh            |
//|                                  Copyright 2024, PASR Team       |
//|                                     https://pasr-trading.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Team"
#property link      "https://pasr-trading.com"
#property version   "1.00"
//+------------------------------------------------------------------+
#include "../Core/IPatternStage.mqh"
#include "../ScoreEngine.mqh"
//+------------------------------------------------------------------+
/**
 * @class CScoringStage
 * @brief Stage keempat dalam pipeline: Final scoring dan grading
 * 
 * Tanggung jawab:
 * - Aggregate semua scores (raw, validation)
 * - Apply weighting dan adjustments
 * - Generate final grade (A+-F)
 * - Set actionable signals
 */
class CScoringStage : public IPatternStage
{
private:
   CScoreEngine         m_scoreEngine;         // Score engine
   double               m_rawWeight;           // Weight untuk raw score
   double               m_validationWeight;    // Weight untuk validation score
   double               m_contextWeight;       // Weight untuk context score
   bool                 m_enableGrading;       // Enable letter grading
   
public:
   CScoringStage();
   ~CScoringStage();
   
   // Implementasi interface
   virtual bool Init() override;
   virtual string Name() const override { return "ScoringStage"; }
   virtual EStageResult Execute(CPatternContext &ctx) override;
   virtual void Reset() override;
   
   // Configuration
   void SetWeights(double rawW, double valW, double ctxW);
   void EnableGrading(bool enable) { m_enableGrading = enable; }
   
   // Getters
   double GetRawWeight() const { return m_rawWeight; }
   double GetValidationWeight() const { return m_validationWeight; }
   double GetContextWeight() const { return m_contextWeight; }
   bool IsGradingEnabled() const { return m_enableGrading; }
   
private:
   /**
    * Hitung weighted final score
    */
   double CalculateFinalScore(const CPatternContext &ctx);
   
   /**
    * Apply context adjustments
    */
   double ApplyContextAdjustments(double baseScore, CPatternContext &ctx);
   
   /**
    * Generate letter grade dari score
    */
   ENUM_SCORE_GRADE GenerateGrade(double finalScore);
};
//+------------------------------------------------------------------+
/**
 * Constructor
 */
CScoringStage::CScoringStage()
   : m_rawWeight(0.3),
     m_validationWeight(0.5),
     m_contextWeight(0.2),
     m_enableGrading(true)
{
}
//+------------------------------------------------------------------+
/**
 * Destructor
 */
CScoringStage::~CScoringStage()
{
   Reset();
}
//+------------------------------------------------------------------+
/**
 * Initialize stage
 */
bool CScoringStage::Init()
{
   // Validasi weights
   double totalWeight = m_rawWeight + m_validationWeight + m_contextWeight;
   
   if(totalWeight <= 0.0 || totalWeight > 1.0)
   {
      PrintFormat("[%s] Invalid weight configuration: %.2f + %.2f + %.2f = %.2f",
                  Name(), m_rawWeight, m_validationWeight, m_contextWeight, totalWeight);
      return false;
   }
   
   // Normalize weights jika tidak sama dengan 1.0
   if(MathAbs(totalWeight - 1.0) > 0.001)
   {
      m_rawWeight /= totalWeight;
      m_validationWeight /= totalWeight;
      m_contextWeight /= totalWeight;
      
      PrintFormat("[%s] Weights normalized to sum to 1.0", Name());
   }
   
   // Init score engine
   if(!m_scoreEngine.Init())
   {
      PrintFormat("[%s] Failed to init score engine", Name());
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Execute scoring stage
 */
EStageResult CScoringStage::Execute(CPatternContext &ctx)
{
   // Check validation flag
   if(!(ctx.Flags & CONTEXT_FLAG_VALIDATED))
   {
      ctx.ErrorMessage = "Validation not completed";
      return STAGE_RESULT_ERROR;
   }
   
   // Skip jika pattern tidak valid
   if(ctx.DetectedPattern == PATTERN_NONE)
   {
      ctx.ErrorMessage = "No pattern to score";
      return STAGE_RESULT_SKIP;
   }
   
   // Hitung final score
   double finalScore = CalculateFinalScore(ctx);
   
   // Apply context adjustments
   finalScore = ApplyContextAdjustments(finalScore, ctx);
   
   // Clamp score ke range [0, 1]
   finalScore = MathMax(0.0, MathMin(1.0, finalScore));
   
   // Set final score ke context
   ctx.FinalScore = finalScore;
   
   // Generate grade jika enabled
   if(m_enableGrading)
   {
      ctx.Grade = GenerateGrade(finalScore);
   }
   else
   {
      ctx.Grade = GRADE_NONE;
   }
   
   // Determine action berdasarkan score
   if(finalScore >= 0.85)
   {
      ctx.Action = ACTION_STRONG_ENTRY;
   }
   else if(finalScore >= 0.70)
   {
      ctx.Action = ACTION_ENTRY;
   }
   else if(finalScore >= 0.50)
   {
      ctx.Action = ACTION_WATCH;
   }
   else
   {
      ctx.Action = ACTION_IGNORE;
      ctx.ErrorMessage = StringFormat("Score too low for action: %.2f", finalScore);
      return STAGE_RESULT_SKIP;
   }
   
   // Set flag scoring complete
   ctx.Flags |= CONTEXT_FLAG_SCORED;
   
   return STAGE_RESULT_SUCCESS;
}
//+------------------------------------------------------------------+
/**
 * Reset stage state
 */
void CScoringStage::Reset()
{
   m_scoreEngine.Reset();
}
//+------------------------------------------------------------------+
/**
 * Set weights untuk scoring
 */
void CScoringStage::SetWeights(double rawW, double valW, double ctxW)
{
   if(rawW < 0.0 || valW < 0.0 || ctxW < 0.0)
   {
      PrintFormat("[%s] Weights cannot be negative", Name());
      return;
   }
   
   m_rawWeight = rawW;
   m_validationWeight = valW;
   m_contextWeight = ctxW;
}
//+------------------------------------------------------------------+
/**
 * Hitung weighted final score
 */
double CScoringStage::CalculateFinalScore(const CPatternContext &ctx)
{
   double score = 0.0;
   
   // Raw score dari detection (confidence)
   score += ctx.RawScore * m_rawWeight;
   
   // Validation score
   score += ctx.ValidationScore * m_validationWeight;
   
   // Context score (dari market context, regime alignment, dll)
   double contextScore = 0.0;
   
   // Regime alignment bonus
   if(ctx.MarketRegime != REGIME_UNKNOWN)
   {
      bool aligned = false;
      
      if(ctx.Direction == DIRECTION_BUY && 
         (ctx.MarketRegime == REGIME_TRENDING_UP || ctx.MarketRegime == REGIME_REVERSAL))
         aligned = true;
      
      if(ctx.Direction == DIRECTION_SELL && 
         (ctx.MarketRegime == REGIME_TRENDING_DOWN || ctx.MarketRegime == REGIME_REVERSAL))
         aligned = true;
      
      contextScore += (aligned ? 1.0 : 0.3) * 0.5;
   }
   
   // Volume confirmation (jika tersedia)
   if(ctx.Volume > 0 && ctx.AvgVolume > 0)
   {
      double volumeRatio = ctx.Volume / ctx.AvgVolume;
      if(volumeRatio > 1.5)
         contextScore += 1.0 * 0.3;
      else if(volumeRatio > 1.0)
         contextScore += 0.7 * 0.3;
      else
         contextScore += 0.3 * 0.3;
   }
   else
   {
      contextScore += 0.5 * 0.3; // Neutral jika volume tidak tersedia
   }
   
   // Time of day adjustment (opsional)
   // Bisa ditambahkan logic untuk session trading
   
   score += contextScore * m_contextWeight;
   
   return score;
}
//+------------------------------------------------------------------+
/**
 * Apply context adjustments
 */
double CScoringStage::ApplyContextAdjustments(double baseScore, CPatternContext &ctx)
{
   double adjustedScore = baseScore;
   
   // Pattern-specific adjustments
   switch(ctx.DetectedPattern)
   {
      case PATTERN_PINBAR:
         // Pinbar dengan shadow sangat panjang dapat bonus
         if(MathMax(ctx.UpperShadowRatio, ctx.LowerShadowRatio) > 0.7)
            adjustedScore += 0.05;
         break;
         
      case PATTERN_ENGULFING:
         // Engulfing yang mencakup multiple candles dapat bonus
         // TODO: Check previous candles
         adjustedScore += 0.03;
         break;
         
      case PATTERN_FAKEY:
         // Fakey di key levels dapat bonus besar
         if(ctx.Confidence > 0.8)
            adjustedScore += 0.07;
         break;
         
      default:
         break;
   }
   
   // Multi-timeframe alignment bonus (future enhancement)
   // if(MTFAligned(ctx)) adjustedScore += 0.05;
   
   // Recent news filter (future enhancement)
   // if(NearNewsEvent(ctx.Time)) adjustedScore -= 0.1;
   
   return adjustedScore;
}
//+------------------------------------------------------------------+
/**
 * Generate letter grade dari score
 */
ENUM_SCORE_GRADE CScoringStage::GenerateGrade(double finalScore)
{
   if(finalScore >= 0.95) return GRADE_A_PLUS;
   if(finalScore >= 0.90) return GRADE_A;
   if(finalScore >= 0.85) return GRADE_A_MINUS;
   if(finalScore >= 0.80) return GRADE_B_PLUS;
   if(finalScore >= 0.75) return GRADE_B;
   if(finalScore >= 0.70) return GRADE_B_MINUS;
   if(finalScore >= 0.65) return GRADE_C_PLUS;
   if(finalScore >= 0.60) return GRADE_C;
   if(finalScore >= 0.55) return GRADE_C_MINUS;
   if(finalScore >= 0.50) return GRADE_D;
   
   return GRADE_F;
}
//+------------------------------------------------------------------+
