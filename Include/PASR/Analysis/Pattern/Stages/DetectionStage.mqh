//+------------------------------------------------------------------+
//|                                      DetectionStage.mqh          |
//|                                  Copyright 2024, PASR Team       |
//|                                     https://pasr-trading.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Team"
#property link      "https://pasr-trading.com"
#property version   "1.00"
//+------------------------------------------------------------------+
#include "../Core/IPatternStage.mqh"
#include "../Strategies/IPatternStrategy.mqh"
#include <Arrays/ArrayObj.mqh>
//+------------------------------------------------------------------+
/**
 * @class CDetectionStage
 * @brief Stage kedua dalam pipeline: Deteksi pattern menggunakan strategies
 * 
 * Tanggung jawab:
 * - Menjalankan semua registered strategies
 * - Agregasi hasil deteksi
 * - Set pattern type dan direction
 * - Early exit jika pattern terdeteksi
 */
class CDetectionStage : public IPatternStage
{
private:
   CArrayObj            m_strategies;         // List strategies
   ENUM_PATTERN_TYPE    m_detectedPattern;    // Pattern yang terdeteksi
   ENUM_ORDER_TYPE      m_detectedDirection;  // Direction pattern
   double               m_confidence;         // Confidence level
   
public:
   CDetectionStage();
   ~CDetectionStage();
   
   // Implementasi interface
   virtual bool Init() override;
   virtual string Name() const override { return "DetectionStage"; }
   virtual EStageResult Execute(CPatternContext &ctx) override;
   virtual void Reset() override;
   
   // Strategy management
   bool AddStrategy(IPatternStrategy *strategy);
   bool RemoveStrategy(const string &name);
   int GetStrategyCount() const { return m_strategies.Total(); }
   
   // Getters
   ENUM_PATTERN_TYPE GetDetectedPattern() const { return m_detectedPattern; }
   ENUM_ORDER_TYPE GetDetectedDirection() const { return m_detectedDirection; }
   double GetConfidence() const { return m_confidence; }
   
private:
   /**
    * Jalankan semua strategies
    */
   bool RunStrategies(CPatternContext &ctx);
   
   /**
    * Aggregate hasil dari multiple strategies
    */
   void AggregateResults(CPatternContext &ctx);
};
//+------------------------------------------------------------------+
/**
 * Constructor
 */
CDetectionStage::CDetectionStage()
   : m_detectedPattern(PATTERN_NONE),
     m_detectedDirection(WRONG_VALUE),
     m_confidence(0.0)
{
}
//+------------------------------------------------------------------+
/**
 * Destructor
 */
CDetectionStage::~CDetectionStage()
{
   Reset();
   m_strategies.Clear();
}
//+------------------------------------------------------------------+
/**
 * Initialize stage
 */
bool CDetectionStage::Init()
{
   // Validate strategies
   if(m_strategies.Total() == 0)
   {
      PrintFormat("[%s] Warning: No strategies registered", Name());
      return true; // Tetap return true, hanya warning
   }
   
   // Init semua strategies
   for(int i = 0; i < m_strategies.Total(); i++)
   {
      IPatternStrategy *strategy = m_strategies.At(i);
      if(strategy != NULL && !strategy.Init())
      {
         PrintFormat("[%s] Failed to init strategy: %s", Name(), strategy.Name());
         return false;
      }
   }
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Execute detection stage
 */
EStageResult CDetectionStage::Execute(CPatternContext &ctx)
{
   // Reset state
   m_detectedPattern = PATTERN_NONE;
   m_detectedDirection = WRONG_VALUE;
   m_confidence = 0.0;
   
   // Check preprocessing flag
   if(!(ctx.Flags & CONTEXT_FLAG_PREPROCESSED))
   {
      ctx.ErrorMessage = "Preprocessing not completed";
      return STAGE_RESULT_ERROR;
   }
   
   // Jalankan strategies
   if(!RunStrategies(ctx))
   {
      ctx.ErrorMessage = "Strategy execution failed";
      return STAGE_RESULT_ERROR;
   }
   
   // Aggregate results
   AggregateResults(ctx);
   
   // Set hasil ke context
   ctx.DetectedPattern = m_detectedPattern;
   ctx.Direction = m_detectedDirection;
   ctx.Confidence = m_confidence;
   
   // Set flag detection complete
   ctx.Flags |= CONTEXT_FLAG_DETECTED;
   
   // Return skip jika tidak ada pattern terdeteksi
   if(m_detectedPattern == PATTERN_NONE)
   {
      ctx.ErrorMessage = "No pattern detected";
      return STAGE_RESULT_SKIP;
   }
   
   return STAGE_RESULT_SUCCESS;
}
//+------------------------------------------------------------------+
/**
 * Reset stage state
 */
void CDetectionStage::Reset()
{
   // Reset semua strategies
   for(int i = 0; i < m_strategies.Total(); i++)
   {
      IPatternStrategy *strategy = m_strategies.At(i);
      if(strategy != NULL)
         strategy.Reset();
   }
   
   m_detectedPattern = PATTERN_NONE;
   m_detectedDirection = WRONG_VALUE;
   m_confidence = 0.0;
}
//+------------------------------------------------------------------+
/**
 * Tambah strategy ke list
 */
bool CDetectionStage::AddStrategy(IPatternStrategy *strategy)
{
   if(strategy == NULL)
      return false;
   
   // Check duplicate
   for(int i = 0; i < m_strategies.Total(); i++)
   {
      IPatternStrategy *existing = m_strategies.At(i);
      if(existing != NULL && existing->Name() == strategy->Name())
      {
         PrintFormat("[%s] Strategy already exists: %s", Name(), strategy->Name());
         return false;
      }
   }
   
   // Add to list
   if(!m_strategies.Add(strategy))
   {
      PrintFormat("[%s] Failed to add strategy: %s", Name(), strategy->Name());
      return false;
   }
   
   // Init strategy jika stage sudah initialized
   if(!strategy.Init())
   {
      PrintFormat("[%s] Failed to init strategy on add: %s", Name(), strategy->Name());
      m_strategies.Delete(m_strategies.Total() - 1);
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+
/**
 * Hapus strategy dari list
 */
bool CDetectionStage::RemoveStrategy(const string &name)
{
   for(int i = 0; i < m_strategies.Total(); i++)
   {
      IPatternStrategy *strategy = m_strategies.At(i);
      if(strategy != NULL && strategy->Name() == name)
      {
         delete m_strategies.Delete(i);
         return true;
      }
   }
   
   return false;
}
//+------------------------------------------------------------------+
/**
 * Jalankan semua strategies
 */
bool CDetectionStage::RunStrategies(CPatternContext &ctx)
{
   bool anySuccess = false;
   
   for(int i = 0; i < m_strategies.Total(); i++)
   {
      IPatternStrategy *strategy = m_strategies.At(i);
      if(strategy == NULL)
         continue;
      
      // Execute strategy
      EStrategyResult result = strategy.Execute(ctx);
      
      if(result == STRATEGY_RESULT_ERROR)
      {
         PrintFormat("[%s] Strategy error: %s - %s", 
                     Name(), strategy->Name(), strategy.GetLastError());
         continue;
      }
      
      if(result == STRATEGY_RESULT_SUCCESS)
      {
         anySuccess = true;
         
         // Update detected pattern jika confidence lebih tinggi
         if(strategy.GetConfidence() > m_confidence)
         {
            m_detectedPattern = strategy.GetPatternType();
            m_detectedDirection = strategy.GetDirection();
            m_confidence = strategy.GetConfidence();
         }
      }
   }
   
   return anySuccess;
}
//+------------------------------------------------------------------+
/**
 * Aggregate hasil dari multiple strategies
 */
void CDetectionStage::AggregateResults(CPatternContext &ctx)
{
   // Jika hanya satu pattern terdeteksi, langsung set
   if(m_detectedPattern != PATTERN_NONE)
   {
      ctx.RawScore = m_confidence;
      return;
   }
   
   // Jika multiple patterns terdeteksi dengan confidence sama
   // Bisa ditambahkan logic voting/weighting di sini
   // Untuk sekarang, ambil yang pertama terdeteksi
   
   ctx.RawScore = 0.0;
}
//+------------------------------------------------------------------+
