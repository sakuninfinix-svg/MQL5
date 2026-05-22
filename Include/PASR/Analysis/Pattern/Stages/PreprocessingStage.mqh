//+------------------------------------------------------------------+
//|                                      PreprocessingStage.mqh      |
//|                                  Copyright 2024, PASR Team       |
//|                                     https://pasr-trading.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Team"
#property link      "https://pasr-trading.com"
#property version   "1.00"
//+------------------------------------------------------------------+
#include "../Core/IPatternStage.mqh"
#include "../CandleUtils.mqh"
//+------------------------------------------------------------------+
/**
 * @class CPreprocessingStage
 * @brief Stage pertama dalam pipeline: Validasi data dan normalisasi
 * 
 * Tanggung jawab:
 * - Validasi kelengkapan data candle
 * - Normalisasi nilai (ATR, range, dll)
 * - Filter noise berdasarkan volatilitas
 * - Persiapan context untuk stage berikutnya
 */
class CPreprocessingStage : public IPatternStage
{
private:
   double             m_atrBuffer[];         // Buffer ATR untuk normalisasi
   int                m_atrPeriod;           // Periode ATR
   double             m_minVolatilityRatio;  // Minimum rasio volatilitas
   double             m_maxVolatilityRatio;  // Maximum rasio volatilitas
   
public:
   /**
    * Constructor
    * @param atrPeriod Periode ATR untuk normalisasi
    * @param minVolRatio Minimum volatility ratio filter
    * @param maxVolRatio Maximum volatility ratio filter
    */
   CPreprocessingStage(int atrPeriod = 14, 
                       double minVolRatio = 0.5, 
                       double maxVolRatio = 3.0);
   
   ~CPreprocessingStage();
   
   // Implementasi interface
   virtual bool Init() override;
   virtual string Name() const override { return "PreprocessingStage"; }
   virtual EStageResult Execute(CPatternContext &ctx) override;
   virtual void Reset() override;
   
   // Getters/Setters
   void SetATRPeriod(int period) { m_atrPeriod = period; }
   int GetATRPeriod() const { return m_atrPeriod; }
   
   void SetVolatilityFilter(double minRatio, double maxRatio)
   {
      m_minVolatilityRatio = minRatio;
      m_maxVolatilityRatio = maxRatio;
   }
   
private:
   /**
    * Validasi data candle lengkap
    */
   bool ValidateCandleData(CPatternContext &ctx);
   
   /**
    * Hitung dan set ATR untuk normalisasi
    */
   bool CalculateATR(CPatternContext &ctx, int barIndex);
   
   /**
    * Normalisasi candle metrics
    */
   void NormalizeMetrics(CPatternContext &ctx, int barIndex);
   
   /**
    * Filter candle berdasarkan volatilitas
    */
   bool PassVolatilityFilter(const CPatternContext &ctx) const;
};
//+------------------------------------------------------------------+
/**
 * Constructor
 */
CPreprocessingStage::CPreprocessingStage(int atrPeriod, 
                                         double minVolRatio, 
                                         double maxVolRatio)
   : m_atrPeriod(atrPeriod),
     m_minVolatilityRatio(minVolRatio),
     m_maxVolatilityRatio(maxVolRatio)
{
   ArraySetAsSeries(m_atrBuffer, true);
}
//+------------------------------------------------------------------+
/**
 * Destructor
 */
CPreprocessingStage::~CPreprocessingStage()
{
   Reset();
}
//+------------------------------------------------------------------+
/**
 * Initialize stage
 */
bool CPreprocessingStage::Init()
{
   // Reset buffer
   ArrayFree(m_atrBuffer);
   
   // Validasi parameter
   if(m_atrPeriod < 1 || m_atrPeriod > 100)
   {
      PrintFormat("[%s] Invalid ATR period: %d", Name(), m_atrPeriod);
      return false;
   }
   
   if(m_minVolatilityRatio <= 0 || m_maxVolatilityRatio <= m_minVolatilityRatio)
   {
      PrintFormat("[%s] Invalid volatility ratio range: %.2f - %.2f", 
                  Name(), m_minVolatilityRatio, m_maxVolatilityRatio);
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Execute preprocessing stage
 */
EStageResult CPreprocessingStage::Execute(CPatternContext &ctx)
{
   // Validasi input
   if(ctx.BarIndex < 0 || ctx.BarIndex >= Bars(ctx.Symbol, ctx.Timeframe))
   {
      ctx.ErrorMessage = StringFormat("Invalid bar index: %d", ctx.BarIndex);
      return STAGE_RESULT_ERROR;
   }
   
   // Validasi data candle
   if(!ValidateCandleData(ctx))
   {
      ctx.ErrorMessage = "Incomplete candle data";
      return STAGE_RESULT_SKIP;
   }
   
   // Hitung ATR untuk normalisasi
   if(!CalculateATR(ctx, ctx.BarIndex))
   {
      ctx.ErrorMessage = "Failed to calculate ATR";
      return STAGE_RESULT_SKIP;
   }
   
   // Normalisasi metrics
   NormalizeMetrics(ctx, ctx.BarIndex);
   
   // Filter volatilitas
   if(!PassVolatilityFilter(ctx))
   {
      ctx.ErrorMessage = "Candle failed volatility filter";
      ctx.NormalizedScore = 0.0;
      return STAGE_RESULT_SKIP;
   }
   
   // Set flag preprocessing complete
   ctx.Flags |= CONTEXT_FLAG_PREPROCESSED;
   
   return STAGE_RESULT_SUCCESS;
}
//+------------------------------------------------------------------+
/**
 * Reset stage state
 */
void CPreprocessingStage::Reset()
{
   ArrayFree(m_atrBuffer);
}
//+------------------------------------------------------------------+
/**
 * Validasi data candle lengkap
 */
bool CPreprocessingStage::ValidateCandleData(CPatternContext &ctx)
{
   // Check jika ada data gap
   if(ctx.Open == 0.0 || ctx.High == 0.0 || ctx.Low == 0.0 || ctx.Close == 0.0)
      return false;
   
   // Validasi konsistensi OHLC
   if(ctx.High < ctx.Low)
      return false;
   
   if(ctx.High < ctx.Open || ctx.High < ctx.Close)
      return false;
   
   if(ctx.Low > ctx.Open || ctx.Low > ctx.Close)
      return false;
   
   // Validasi volume (jika tersedia)
   if(ctx.Volume < 0)
      return false;
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Hitung dan set ATR untuk normalisasi
 */
bool CPreprocessingStage::CalculateATR(CPatternContext &ctx, int barIndex)
{
   // Resize buffer jika perlu
   if(ArraySize(m_atrBuffer) < m_atrPeriod + 1)
      ArrayResize(m_atrBuffer, m_atrPeriod + 100);
   
   // Hitung True Range untuk periode yang dibutuhkan
   double trSum = 0.0;
   int validBars = 0;
   
   for(int i = 0; i < m_atrPeriod && (barIndex + i) < Bars(ctx.Symbol, ctx.Timeframe); i++)
   {
      int currentBar = barIndex + i;
      
      double high = iHigh(ctx.Symbol, ctx.Timeframe, currentBar);
      double low = iLow(ctx.Symbol, ctx.Timeframe, currentBar);
      double prevClose = iClose(ctx.Symbol, ctx.Timeframe, currentBar + 1);
      
      if(high == 0.0 || low == 0.0 || prevClose == 0.0)
         continue;
      
      double tr = MathMax(high - low, 
                          MathMax(MathAbs(high - prevClose), 
                                  MathAbs(low - prevClose)));
      
      trSum += tr;
      validBars++;
   }
   
   if(validBars < m_atrPeriod / 2)
      return false;
   
   double atr = trSum / validBars;
   
   if(atr <= 0.0)
      return false;
   
   ctx.ATR = atr;
   ctx.ATRPips = atr / Point();
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Normalisasi candle metrics
 */
void CPreprocessingStage::NormalizeMetrics(CPatternContext &ctx, int barIndex)
{
   // Candle range
   double candleRange = ctx.High - ctx.Low;
   ctx.NormalizedRange = (ctx.ATR > 0) ? candleRange / ctx.ATR : 0.0;
   
   // Body size
   double bodySize = MathAbs(ctx.Close - ctx.Open);
   ctx.NormalizedBody = (ctx.ATR > 0) ? bodySize / ctx.ATR : 0.0;
   
   // Upper shadow
   double upperShadow = ctx.High - MathMax(ctx.Open, ctx.Close);
   ctx.NormalizedUpperShadow = (ctx.ATR > 0) ? upperShadow / ctx.ATR : 0.0;
   
   // Lower shadow
   double lowerShadow = MathMin(ctx.Open, ctx.Close) - ctx.Low;
   ctx.NormalizedLowerShadow = (ctx.ATR > 0) ? lowerShadow / ctx.ATR : 0.0;
   
   // Body ratio (body/range)
   ctx.BodyRatio = (candleRange > 0) ? bodySize / candleRange : 0.0;
   
   // Upper shadow ratio
   ctx.UpperShadowRatio = (candleRange > 0) ? upperShadow / candleRange : 0.0;
   
   // Lower shadow ratio
   ctx.LowerShadowRatio = (candleRange > 0) ? lowerShadow / candleRange : 0.0;
   
   // Direction
   ctx.Direction = (ctx.Close > ctx.Open) ? DIRECTION_BUY : 
                   (ctx.Close < ctx.Open) ? DIRECTION_SELL : DIRECTION_NEUTRAL;
}
//+------------------------------------------------------------------+
/**
 * Filter candle berdasarkan volatilitas
 */
bool CPreprocessingStage::PassVolatilityFilter(const CPatternContext &ctx) const
{
   if(ctx.ATR <= 0.0 || ctx.NormalizedRange <= 0.0)
      return false;
   
   // Filter candle dengan volatilitas terlalu rendah (noise)
   if(ctx.NormalizedRange < m_minVolatilityRatio)
      return false;
   
   // Filter candle dengan volatilitas terlalu tinggi (anomali)
   if(ctx.NormalizedRange > m_maxVolatilityRatio)
      return false;
   
   return true;
}
//+------------------------------------------------------------------+
