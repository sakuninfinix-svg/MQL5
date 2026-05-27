//+------------------------------------------------------------------+
//| Analysis/Pattern/Stages/ValidationStage.mqh — v1.01              |
//| Canonical compile-safe validation stage                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_PATTERN_VALIDATION_STAGE_MQH__
#define __ANALYSIS_PATTERN_VALIDATION_STAGE_MQH__

#include "../Core/IPatternStage.mqh"
#include "../Context/PatternContext.mqh"
#include "../../MarketRegimeDetector.mqh"

class CValidationStage : public IPatternStage
  {
private:
   CMarketRegimeDetector *m_regimeDetector;
   bool                   m_enableRegimeFilter;
   bool                   m_enableSRFilter;
   double                 m_minConfidence;

public:
   CValidationStage(CMarketRegimeDetector *regimeDet = NULL)
      : IPatternStage(),
        m_regimeDetector(regimeDet),
        m_enableRegimeFilter(true),
        m_enableSRFilter(true),
        m_minConfidence(0.6)
     {
      SetName("ValidationStage");
     }

   virtual ~CValidationStage() {}

   virtual bool Init() override
     {
      if(m_minConfidence < 0.0 || m_minConfidence > 1.0)
        {
         PrintFormat("[%s] Invalid minimum confidence: %.2f", GetName(), m_minConfidence);
         return false;
        }
      return true;
     }

   virtual ENUM_STAGE_STATUS Process(CPatternContext &ctx) override
     {
      if(!m_enabled) return STAGE_SKIP;

      // The canonical CPatternContext is currently an enrichment container, not
      // the older detection-result DTO that exposed Symbol/Timeframe/Direction.
      // Keep this stage compile-safe and treat context score as the validation
      // signal until the pattern pipeline DTOs are unified.
      double contextScore = ctx.GetTotalContextScore();
      if(contextScore <= 0.0) return STAGE_SKIP;

      double normalized = contextScore / 100.0;
      if(normalized < m_minConfidence) return STAGE_SKIP;

      return STAGE_OK;
     }

   virtual void Shutdown() override {}

   void EnableRegimeFilter(bool enable) { m_enableRegimeFilter = enable; }
   void EnableSRFilter(bool enable)     { m_enableSRFilter = enable; }
   void SetMinConfidence(double minConf)
     {
      m_minConfidence = MathMax(0.0, MathMin(1.0, minConf));
     }

   bool   IsRegimeFilterEnabled() const { return m_enableRegimeFilter; }
   bool   IsSRFilterEnabled()     const { return m_enableSRFilter; }
   double GetMinConfidence()      const { return m_minConfidence; }
  };

#endif // __ANALYSIS_PATTERN_VALIDATION_STAGE_MQH__
