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

   double NormalizeVolume(const string symbol, const double volume) const
     {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(minLot <= 0.0) minLot = 0.01;
      if(maxLot <= 0.0) maxLot = 100.0;
      if(step <= 0.0) step = 0.01;
      double clipped = MathMax(minLot, MathMin(maxLot, volume));
      double stepped = MathFloor(clipped / step) * step;
      return NormalizeDouble(MathMax(minLot, MathMin(maxLot, stepped)), 2);
     }

   bool ShouldPartialClose(const SPositionSnapshot &pos, const ENUM_ORDER_TYPE orderType, const double curPrice, const StrategyConfig &cfg, double &partialVolume) const
     {
      partialVolume = 0.0;
      if(cfg.Risk.PartialClosePct <= 0.0 || cfg.Risk.PartialClosePct >= 1.0) return false;
      if(pos.tp <= 0.0 || pos.open_price <= 0.0 || pos.volume <= 0.0) return false;

      double target = (orderType == ORDER_TYPE_BUY)
         ? pos.open_price + (pos.tp - pos.open_price) * 0.5
         : pos.open_price - (pos.open_price - pos.tp) * 0.5;
      bool reached = (orderType == ORDER_TYPE_BUY) ? (curPrice >= target) : (curPrice <= target);
      if(!reached) return false;

      double minLot = SymbolInfoDouble(pos.symbol, SYMBOL_VOLUME_MIN);
      if(minLot <= 0.0) minLot = 0.01;
      partialVolume = NormalizeVolume(pos.symbol, pos.volume * cfg.Risk.PartialClosePct);
      double remaining = NormalizeVolume(pos.symbol, pos.volume - partialVolume);
      return partialVolume >= minLot && remaining >= minLot && partialVolume < pos.volume;
     }

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
         if(m_exit.HasRetryableExit(ticket))
           {
            ENUM_EXIT_REQUEST_ACTION retryAction = EXIT_ACTION_NONE;
            double retryVolume = 0.0;
            int retryReason = 0;
            string retryText = "";
            if(m_exit.PrepareExitRetry(ticket, retryAction, retryVolume, retryReason, retryText))
              {
               bool retrySent = false;
               if(retryAction == EXIT_ACTION_PARTIAL)
                  retrySent = trade.PositionClosePartial(ticket, retryVolume);
               else
                  retrySent = trade.PositionClose(ticket);
               int retryRetcode = (int)trade.ResultRetcode();
               string retryComment = trade.ResultComment();
               if(retrySent)
                  m_exit.MarkCloseSent(ticket, retryRetcode, retryComment);
               else
                  m_exit.MarkCloseRejected(ticket, retryRetcode, retryComment);
               if(m_debug)
                  PrintFormat("[PosMgmt] Exit retry ticket=%I64u action=%d vol=%.2f sent=%s ret=%d",
                              ticket, (int)retryAction, retryVolume, retrySent ? "true" : "false", retryRetcode);
              }
            continue;
           }
         if(m_exit.HasPendingClose(ticket))
            continue;

         string sym = pos.symbol;
         ENUM_POSITION_TYPE posType = pos.type;
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double entryPrice = pos.open_price;
         datetime entryTime = pos.open_time;
         double curPrice = (orderType == ORDER_TYPE_BUY)
                           ? SymbolInfoDouble(sym, SYMBOL_BID)
                           : SymbolInfoDouble(sym, SYMBOL_ASK);

         double partialVolume = 0.0;
         if(!m_exit.HasConfirmedPartial(ticket) && ShouldPartialClose(pos, orderType, curPrice, cfg, partialVolume))
           {
            ulong requestId = m_exit.RequestPartialClose(ticket, EXIT_PROFIT_FADE, partialVolume, "Partial close at half target");
            bool partialClosed = trade.PositionClosePartial(ticket, partialVolume);
            int partialRetcode = (int)trade.ResultRetcode();
            string partialComment = trade.ResultComment();
            if(partialClosed)
               m_exit.MarkCloseSent(ticket, partialRetcode, partialComment);
            else
               m_exit.MarkCloseRejected(ticket, partialRetcode, partialComment);
            if(m_debug)
               PrintFormat("[PosMgmt] Partial req=%I64u ticket=%I64u vol=%.2f sent=%s ret=%d",
                           requestId, ticket, partialVolume, partialClosed ? "true" : "false", partialRetcode);
            continue;
           }

         ExitSignal sig = m_exit.CheckExit(sym, orderType, entryPrice, curPrice, entryTime);
         if(sig.reason == EXIT_NONE) continue;

         ulong requestId = m_exit.RequestClose(ticket, sig.reason, sig.description);
         bool closed = trade.PositionClose(ticket);
         int retcode = (int)trade.ResultRetcode();
         string comment = trade.ResultComment();
         if(closed)
            m_exit.MarkCloseSent(ticket, retcode, comment);
         else
            m_exit.MarkCloseRejected(ticket, retcode, comment);
         if(m_debug)
            PrintFormat("[PosMgmt] Exit req=%I64u ticket=%I64u reason=%d closed=%s ret=%d desc=%s",
                        requestId, ticket, (int)sig.reason, closed ? "true" : "false", retcode, sig.description);
        }

      if(m_profiling) m_timer.Log("Stage11_PosMgmt");
      return STAGE_OK;
     }
  };

#endif // __PASR_ORCHESTRATION_POSITION_STAGE_MQH__
