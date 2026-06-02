//+------------------------------------------------------------------+
//| Orchestration/Stages/DataSyncStage.mqh - v0.20                  |
//| Runtime DataSync pipeline stage                                  |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_DATA_SYNC_STAGE_MQH__
#define __PASR_ORCHESTRATION_DATA_SYNC_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Infra/DataManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>

class CDataSyncStage : public IPipelineStage
  {
private:
   CDataManager *m_data;
   bool          m_enabled;
   bool          m_debug;
   bool          m_profiling;
   CPerfTimer    m_timer;

   void FillPriceContext(PipelineContext &ctx)
     {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
        {
         ctx.bid = tick.bid;
         ctx.ask = tick.ask;
        }
      else
        {
         ctx.bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         ctx.ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        }
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      ctx.spread_pts = (point > 0.0 && ctx.ask > ctx.bid) ? (ctx.ask - ctx.bid) / point : 0.0;
      ctx.atr_points = (m_data != NULL) ? m_data.GetATRPoints() : 0.0;
      ctx.atr = ctx.atr_points;
      ctx.bar_time = iTime(_Symbol, _Period, 0);
      ctx.market_open = (ctx.bid > 0.0 && ctx.ask > 0.0);
      ctx.session = PASRDetectSession();
      ctx.account.Capture();
     }

public:
   CDataSyncStage() : m_data(NULL), m_enabled(true), m_debug(false), m_profiling(true) {}

   void Bind(CDataManager *data)
     {
      m_data = data;
     }

   void SetEnabled(const bool enabled)
     {
     m_enabled = enabled;
     }

   void SetDebugMode(const bool enabled)
     {
      m_debug = enabled;
     }

   void EnableProfiling(const bool enabled)
     {
      m_profiling = enabled;
     }

   virtual string Name() const override { return "DataSyncStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_data == NULL)
        {
         if(m_debug) Print("[Pipeline] DataSync SKIP: manager is NULL");
         return STAGE_SKIP;
        }
      m_timer.Start();
      m_data.OnTick();
      FillPriceContext(ctx);
      if(m_profiling) m_timer.Log("Stage1_DataSync");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_DATA_SYNC_STAGE_MQH__
