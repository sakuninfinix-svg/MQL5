//+------------------------------------------------------------------+
//|                                      ValidationStage.mqh         |
//|                                  Copyright 2024, PASR Team       |
//|                                     https://pasr-trading.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Team"
#property link      "https://pasr-trading.com"
#property version   "1.00"
//+------------------------------------------------------------------+
#include "../Core/IPatternStage.mqh"
#include "../../MarketRegimeDetector.mqh"
//+------------------------------------------------------------------+
/**
 * @class CValidationStage
 * @brief Stage ketiga dalam pipeline: Validasi pattern dengan konteks market
 * 
 * Tanggung jawab:
 * - Validasi pattern terhadap market regime
 * - Check confluence dengan support/resistance
 * - Filter berdasarkan lokasi price (trend, range)
 * - Multi-timeframe confirmation (opsional)
 */
class CValidationStage : public IPatternStage
{
private:
   CMarketRegimeDetector *m_regimeDetector;     // Market regime detector
   bool                   m_enableRegimeFilter; // Enable regime filtering
   bool                   m_enableSRFilter;     // Enable S/R filter
   double                 m_minConfidence;      // Minimum confidence threshold
   
public:
   CValidationStage(CMarketRegimeDetector *regimeDet = NULL);
   ~CValidationStage();
   
   // Implementasi interface
   virtual bool Init() override;
   virtual string Name() const override { return "ValidationStage"; }
   virtual EStageResult Execute(CPatternContext &ctx) override;
   virtual void Reset() override;
   
   // Configuration
   void EnableRegimeFilter(bool enable) { m_enableRegimeFilter = enable; }
   void EnableSRFilter(bool enable) { m_enableSRFilter = enable; }
   void SetMinConfidence(double minConf) { m_minConfidence = minConf; }
   
   // Getters
   bool IsRegimeFilterEnabled() const { return m_enableRegimeFilter; }
   bool IsSRFilterEnabled() const { return m_enableSRFilter; }
   double GetMinConfidence() const { return m_minConfidence; }
   
private:
   /**
    * Validasi pattern terhadap market regime
    */
   bool ValidateRegime(CPatternContext &ctx);
   
   /**
    * Validasi pattern dengan support/resistance
    */
   bool ValidateSupportResistance(CPatternContext &ctx);
   
   /**
    * Validasi lokasi price dalam trend
    */
   bool ValidatePriceLocation(CPatternContext &ctx);
   
   /**
    * Hitung validation score
    */
   double CalculateValidationScore(const CPatternContext &ctx);
};
//+------------------------------------------------------------------+
/**
 * Constructor
 */
CValidationStage::CValidationStage(CMarketRegimeDetector *regimeDet)
   : m_regimeDetector(regimeDet),
     m_enableRegimeFilter(true),
     m_enableSRFilter(true),
     m_minConfidence(0.6)
{
}
//+------------------------------------------------------------------+
/**
 * Destructor
 */
CValidationStage::~CValidationStage()
{
   // Note: m_regimeDetector tidak di-delete karena ownership ada di luar
}
//+------------------------------------------------------------------+
/**
 * Initialize stage
 */
bool CValidationStage::Init()
{
   // Validasi parameter
   if(m_minConfidence < 0.0 || m_minConfidence > 1.0)
   {
      PrintFormat("[%s] Invalid minimum confidence: %.2f", Name(), m_minConfidence);
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Execute validation stage
 */
EStageResult CValidationStage::Execute(CPatternContext &ctx)
{
   // Check detection flag
   if(!(ctx.Flags & CONTEXT_FLAG_DETECTED))
   {
      ctx.ErrorMessage = "Detection not completed";
      return STAGE_RESULT_ERROR;
   }
   
   // Skip jika pattern tidak terdeteksi
   if(ctx.DetectedPattern == PATTERN_NONE)
   {
      ctx.ErrorMessage = "No pattern to validate";
      return STAGE_RESULT_SKIP;
   }
   
   // Validasi minimum confidence
   if(ctx.Confidence < m_minConfidence)
   {
      ctx.ErrorMessage = StringFormat("Confidence too low: %.2f < %.2f", 
                                       ctx.Confidence, m_minConfidence);
      ctx.ValidationScore = 0.0;
      return STAGE_RESULT_SKIP;
   }
   
   // Validasi market regime
   if(m_enableRegimeFilter && !ValidateRegime(ctx))
   {
      ctx.ErrorMessage = "Failed regime validation";
      return STAGE_RESULT_SKIP;
   }
   
   // Validasi support/resistance
   if(m_enableSRFilter && !ValidateSupportResistance(ctx))
   {
      ctx.ErrorMessage = "Failed S/R validation";
      return STAGE_RESULT_SKIP;
   }
   
   // Validasi price location
   if(!ValidatePriceLocation(ctx))
   {
      ctx.ErrorMessage = "Failed price location validation";
      return STAGE_RESULT_SKIP;
   }
   
   // Hitung validation score
   ctx.ValidationScore = CalculateValidationScore(ctx);
   
   // Set flag validation complete
   ctx.Flags |= CONTEXT_FLAG_VALIDATED;
   
   // Skip jika validation score terlalu rendah
   if(ctx.ValidationScore < 0.5)
   {
      ctx.ErrorMessage = StringFormat("Validation score too low: %.2f", ctx.ValidationScore);
      return STAGE_RESULT_SKIP;
   }
   
   return STAGE_RESULT_SUCCESS;
}
//+------------------------------------------------------------------+
/**
 * Reset stage state
 */
void CValidationStage::Reset()
{
   // Nothing to reset for now
}
//+------------------------------------------------------------------+
/**
 * Validasi pattern terhadap market regime
 */
bool CValidationStage::ValidateRegime(CPatternContext &ctx)
{
   if(m_regimeDetector == NULL)
      return true; // Skip jika detector tidak ada
   
   // Get current regime
   ENUM_MARKET_REGIME regime = m_regimeDetector.GetCurrentRegime(ctx.Symbol, ctx.Timeframe);
   
   // Pattern-specific regime requirements
   switch(ctx.DetectedPattern)
   {
      case PATTERN_PINBAR:
         // Pinbar lebih valid di trending market atau reversal di extreme
         if(regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN)
            return true;
         
         // Di ranging market, pinbar hanya valid di boundary
         if(regime == REGIME_RANGING)
         {
            // Check apakah price di boundary range
            return (ctx.UpperShadowRatio > 0.6 || ctx.LowerShadowRatio > 0.6);
         }
         break;
         
      case PATTERN_ENGULFING:
         // Engulfing kuat di semua regime, tapi sangat kuat di reversal
         if(regime == REGIME_REVERSAL)
            return true;
         
         // Di trending, engulfing searah trend lebih valid
         if(regime == REGIME_TRENDING_UP && ctx.Direction == DIRECTION_BUY)
            return true;
         if(regime == REGIME_TRENDING_DOWN && ctx.Direction == DIRECTION_SELL)
            return true;
         break;
         
      case PATTERN_INSIDE_BAR:
      case PATTERN_INSIDE_BAR_BREAKOUT:
         // Inside bar breakout lebih valid di trending market
         if(regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN)
            return true;
         break;
         
      case PATTERN_FAKEY:
         // Fakey sangat kuat di ranging market atau key levels
         if(regime == REGIME_RANGING)
            return true;
         break;
         
      default:
         return true;
   }
   
   return false;
}
//+------------------------------------------------------------------+
/**
 * Validasi pattern dengan support/resistance
 */
bool CValidationStage::ValidateSupportResistance(CPatternContext &ctx)
{
   // TODO: Integrate dengan SRManager
   // Untuk sekarang, implementasi sederhana berdasarkan shadow ratio
   
   // Pattern dengan shadow panjang di area S/R lebih valid
   if(ctx.DetectedPattern == PATTERN_PINBAR || ctx.DetectedPattern == PATTERN_FAKEY)
   {
      // Bullish pattern di support (lower shadow panjang)
      if(ctx.Direction == DIRECTION_BUY && ctx.LowerShadowRatio > 0.6)
         return true;
      
      // Bearish pattern di resistance (upper shadow panjang)
      if(ctx.Direction == DIRECTION_SELL && ctx.UpperShadowRatio > 0.6)
         return true;
   }
   
   // Engulfing di area S/R lebih valid
   if(ctx.DetectedPattern == PATTERN_ENGULFING)
   {
      // Butuh konfirmasi volume atau proximity ke S/R
      // Untuk sekarang, accept semua engulfing dengan confidence tinggi
      if(ctx.Confidence > 0.7)
         return true;
   }
   
   return true; // Default accept
}
//+------------------------------------------------------------------+
/**
 * Validasi lokasi price dalam trend
 */
bool CValidationStage::ValidatePriceLocation(CPatternContext &ctx)
{
   // Simple trend detection menggunakan EMA
   int emaFast = 20;
   int emaSlow = 50;
   
   double emaFastVal = iMA(ctx.Symbol, ctx.Timeframe, emaFast, 0, MODE_EMA, PRICE_CLOSE, ctx.BarIndex);
   double emaSlowVal = iMA(ctx.Symbol, ctx.Timeframe, emaSlow, 0, MODE_EMA, PRICE_CLOSE, ctx.BarIndex);
   
   if(emaFastVal == 0.0 || emaSlowVal == 0.0)
      return true; // Skip jika data tidak tersedia
   
   bool uptrend = (emaFastVal > emaSlowVal);
   bool downtrend = (emaFastVal < emaSlowVal);
   
   // Pattern searah trend lebih valid
   if(ctx.Direction == DIRECTION_BUY && uptrend)
      return true;
   
   if(ctx.Direction == DIRECTION_SELL && downtrend)
      return true;
   
   // Counter-trend pattern butuh confidence lebih tinggi
   if(ctx.Direction == DIRECTION_BUY && downtrend)
      return (ctx.Confidence > 0.8);
   
   if(ctx.Direction == DIRECTION_SELL && uptrend)
      return (ctx.Confidence > 0.8);
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Hitung validation score
 */
double CValidationStage::CalculateValidationScore(const CPatternContext &ctx)
{
   double score = 0.0;
   double weight = 0.0;
   
   // Base score dari confidence (40% weight)
   score += ctx.Confidence * 0.4;
   weight += 0.4;
   
   // Regime alignment (30% weight)
   if(m_regimeDetector != NULL)
   {
      ENUM_MARKET_REGIME regime = m_regimeDetector.GetCurrentRegime(ctx.Symbol, ctx.Timeframe);
      bool regimeAligned = false;
      
      // Check alignment
      if(ctx.Direction == DIRECTION_BUY && (regime == REGIME_TRENDING_UP || regime == REGIME_REVERSAL))
         regimeAligned = true;
      if(ctx.Direction == DIRECTION_SELL && (regime == REGIME_TRENDING_DOWN || regime == REGIME_REVERSAL))
         regimeAligned = true;
      
      score += (regimeAligned ? 1.0 : 0.3) * 0.3;
      weight += 0.3;
   }
   
   // Shadow quality (20% weight)
   double shadowQuality = MathMax(ctx.UpperShadowRatio, ctx.LowerShadowRatio);
   score += shadowQuality * 0.2;
   weight += 0.2;
   
   // Body ratio (10% weight)
   // Body yang terlalu kecil menandakan indecision
   double bodyScore = (ctx.BodyRatio > 0.3 && ctx.BodyRatio < 0.9) ? 1.0 : 0.5;
   score += bodyScore * 0.1;
   weight += 0.1;
   
   // Normalize score
   return (weight > 0) ? score / weight : 0.0;
}
//+------------------------------------------------------------------+
