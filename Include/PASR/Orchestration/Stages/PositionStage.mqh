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
#include <PASR/Trade/PositionManager.mqh>
#include <PASR/Orchestration/PipelineStage.mqh>
#include <Trade/Trade.mqh>

class CPositionStage : public IPipelineStage
  {
private:
   CExitEngine  *m_exit;
   CDataManager *m_data;
   CPositionManager *m_positions;
   bool          m_enabled;
   bool          m_debug;
   bool          m_profiling;
   CPerfTimer    m_timer;

public:
   CPositionStage()
      : m_exit(NULL), m_data(NULL), m_positions(NULL), m_enabled(true), m_debug(false), m_profiling(true)
     {}

   void Bind(CExitEngine *exit_engine, CDataManager *data, CPositionManager *positions = NULL)
     {
      m_exit = exit_engine;
      m_data = data;
      m_positions = positions;
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

      if(m_positions != NULL)
         m_positions.ScanPositions(ctx);
      else
         ctx.positions.Scan(_Symbol, cfgMagic);

      ctx.positions_count = ctx.positions.Count();
      ctx.position_ticket = ctx.positions.FirstTicket();
      ctx.has_position = ctx.positions.HasPosition();

      for(int i = 0; i < ctx.positions.Count(); i++)
        {
         SPositionSnapshot pos;
         if(!ctx.positions.GetAt(i, pos)) continue;
         ulong ticket = pos.ticket;
         string sym = pos.symbol;
         ENUM_POSITION_TYPE posType = pos.type;
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double entryPrice = pos.open_price;
         datetime entryTime = pos.open_time;
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
