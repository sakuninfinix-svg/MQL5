//+------------------------------------------------------------------+
//| Orchestration/Stages/RegimeStage.mqh - v0.10                    |
//| Runtime RegimeDet pipeline stage                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_REGIME_STAGE_MQH__
#define __PASR_ORCHESTRATION_REGIME_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Signal/RegimeFilter.mqh>
#include <PASR/Analysis/MarketRegimeDetector.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CRegimeStage : public IPipelineStage
  {
private:
   CRegimeFilter         *m_regime;
   CMarketRegimeDetector *m_regime_det;
   bool                   m_enabled;
   bool                   m_debug;
   bool                   m_profiling;
   CPerfTimer             m_timer;

public:
   CRegimeStage()
      : m_regime(NULL), m_regime_det(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CRegimeFilter *regime, CMarketRegimeDetector *regime_det)
     {
      m_regime = regime;
      m_regime_det = regime_det;
     }

   void SetEnabled(const bool enabled) { m_enabled = enabled; }
   void SetDebugMode(const bool enabled) { m_debug = enabled; }
   void EnableProfiling(const bool enabled) { m_profiling = enabled; }

   virtual string Name() const override { return "RegimeStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;

      if(m_regime != NULL)
        {
         m_timer.Start();
         if(ctx.new_bar) m_regime.OnNewBar();
         ctx.regime = m_regime.GetRegime();
         ctx.regime_confidence = m_regime.IsReady() ? 1.0 : 0.0;
         if(m_profiling) m_timer.Log("Stage5_RegimeDet");
         return STAGE_OK;
        }

      if(m_regime_det == NULL)
        {
         if(m_debug) Print("[Pipeline] RegimeDet SKIP: manager is NULL");
         return STAGE_SKIP;
        }

      m_timer.Start();
      ctx.regime = m_regime_det.GetCurrentRegime();
      SDynamicParams params = m_regime_det.GetParams();
      ctx.regime_confidence = MathMin(1.0, MathMax(0.0, params.trend_strength / 100.0));
      if(m_profiling) m_timer.Log("Stage5_RegimeDet");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_REGIME_STAGE_MQH__
