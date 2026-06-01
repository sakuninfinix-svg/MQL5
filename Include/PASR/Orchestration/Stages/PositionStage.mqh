//+------------------------------------------------------------------+
//| Orchestration/Stages/PositionStage.mqh - v0.10                  |
//| Runtime PositionMgmt pipeline stage                              |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_ORCHESTRATION_POSITION_STAGE_MQH__
#define __PASR_ORCHESTRATION_POSITION_STAGE_MQH__

#include <PASR/Core/PipelineTypes.mqh>
#include <PASR/Core/Config/Types.mqh>
#include <PASR/Core/Globals.mqh>
#include <PASR/Infra/DataManager.mqh>
#include <PASR/Trade/ExitEngine.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>
#include <Trade/Trade.mqh>

class CPositionStage : public IPipelineStage
  {
private:
   CExitEngine  *m_exit;
   CDataManager *m_data;
   bool          m_enabled;
   bool          m_debug;
   bool          m_profiling;
   CPerfTimer    m_timer;

public:
   CPositionStage()
      : m_exit(NULL), m_data(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CExitEngine *exit_engine, CDataManager *data)
     {
      m_exit = exit_engine;
      m_data = data;
     }

   void SetEnabled(const bool enabled) { m_enabled = enabled; }
   void SetDebugMode(const bool enabled) { m_debug = enabled; }
   void EnableProfiling(const bool enabled) { m_profiling = enabled; }

   virtual string Name() const override { return "PositionStage"; }
   virtual bool IsEnabled() const override { return m_enabled; }

   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled)
         return STAGE_SKIP;
      if(m_exit == NULL)
        {
         if(m_debug) Print("[Pipeline] PosMgmt SKIP: manager is NULL");
         return STAGE_SKIP;
        }
      m_timer.Start();

      CTrade trade;
      StrategyConfig cfg;
      if(m_data != NULL)
         m_data.GetConfigCache(cfg);
      else
         cfg.MagicNumber = 0;
      long cfgMagic = cfg.MagicNumber;
      if(cfgMagic > 0) trade.SetExpertMagicNumber(cfgMagic);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         long magic = PositionGetInteger(POSITION_MAGIC);
         if(cfgMagic > 0 && magic != cfgMagic) continue;

         string sym = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
         double curPrice = (orderType == ORDER_TYPE_BUY)
                           ? SymbolInfoDouble(sym, SYMBOL_BID)
                           : SymbolInfoDouble(sym, SYMBOL_ASK);

         ExitSignal sig = m_exit.CheckExit(sym, orderType, entryPrice, curPrice, entryTime);
         if(sig.reason == EXIT_NONE) continue;

         bool closed = trade.PositionClose(ticket);
         if(m_debug)
            PrintFormat("[PosMgmt] Exit %I64u reason=%d closed=%s desc=%s",
                        ticket, (int)sig.reason, closed ? "true" : "false", sig.description);
        }

      if(m_profiling) m_timer.Log("Stage11_PosMgmt");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_POSITION_STAGE_MQH__
