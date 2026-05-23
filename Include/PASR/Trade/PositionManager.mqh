//+------------------------------------------------------------------+
//| Trade/PositionManager.mqh — v2.00 (Pipeline Integrated)         |
//| Open position scanner and cache manager for Stage_PositionMgmt  |
//|                                                                   |
//| CHANGELOG:                                                        |
//|   v2.00 (2026-05-23) Sprint 5:                                   |
//|     - Added ScanPositions(PipelineContext &ctx) method           |
//|     - Fills ctx.positions_count and ctx.position_ticket          |
//|     - Single MT5 PositionsTotal() call per pipeline cycle        |
//|     - Magic number filter: only counts positions with InpMagic   |
//|     - Replaces ad-hoc PositionGetTicket loop in pipeline         |
//|   v1.xx — Standalone position query helpers                     |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_POSITION_MANAGER_MQH__
#define __TRADE_POSITION_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "../Core/PASR.Types.mqh"

//+------------------------------------------------------------------+
//| CPositionManager — Pipeline-aware position scanner              |
//+------------------------------------------------------------------+
class CPositionManager : public IManager
  {
private:
   long              m_magic;          // EA magic number filter
   string            m_symbol;         // Symbol filter

   // Cache (filled by ScanPositions, valid for current pipeline cycle)
   int               m_cached_count;   // PositionsTotal() filtered result
   ulong             m_cached_ticket;  // First matching position ticket
   datetime          m_cache_time;     // Timestamp of last scan

public:
              CPositionManager()
     : m_magic(0), m_symbol(""),
       m_cached_count(0), m_cached_ticket(0), m_cache_time(0)
     {}

   //--- IManager interface -------------------------------------------
   virtual bool      Initialize(CEventBus *bus) override
     {
      m_bus = bus;
      DeclareEvents();
      return true;
     }

   virtual void      DeclareEvents() override
     {
      // Subscribe to position update events from EventBus
      if(CheckPointer(m_bus) != POINTER_INVALID)
         m_bus.Subscribe(GetPointer(this));
     }

   virtual void      OnEvent(const PASREvent &ev) override
     {
      // Invalidate cache on trade transaction
      if(ev.id == EVENT_ID_TRADE_CLOSED || ev.id == EVENT_ID_TRADE_OPENED)
         m_cached_count = -1; // Force rescan next ScanPositions call
     }

   virtual string    HandlerName() const override
     { return "CPositionManager"; }

   virtual void      Shutdown() override
     {
      if(CheckPointer(m_bus) != POINTER_INVALID)
         m_bus.Unsubscribe(GetPointer(this));
     }

   //--- Configuration ------------------------------------------------
   void              SetMagic(long magic)   { m_magic  = magic;  }
   void              SetSymbol(string sym)  { m_symbol = sym;    }

   //--- Core: single scan fills PipelineContext cache ----------------
   //    Called by Stage_PositionMgmt once per pipeline cycle.
   //    Subsequent stages (Recovery, Dashboard) read ctx cache —
   //    zero additional MT5 API calls.
   void              ScanPositions(PipelineContext &ctx)
     {
      int    count  = 0;
      ulong  ticket = 0;
      int    total  = PositionsTotal();

      for(int i = 0; i < total; i++)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(m_symbol != "" && PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(m_magic  != 0  && PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;
         count++;
         if(ticket == 0) ticket = t; // Store first match
        }

      ctx.positions_count  = count;
      ctx.position_ticket  = ticket;
      m_cached_count       = count;
      m_cached_ticket      = ticket;
      m_cache_time         = TimeCurrent();
     }

   //--- Accessors (read cached values without re-scanning) ----------
   int               CachedCount()  const { return m_cached_count;  }
   ulong             CachedTicket() const { return m_cached_ticket; }
   bool              HasOpenPosition() const { return m_cached_count > 0; }

   //--- Per-position helpers (use after ScanPositions) --------------
   double            GetPositionProfit(ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket)) return 0.0;
      return PositionGetDouble(POSITION_PROFIT);
     }

   double            GetPositionSL(ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket)) return 0.0;
      return PositionGetDouble(POSITION_SL);
     }

   double            GetPositionTP(ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket)) return 0.0;
      return PositionGetDouble(POSITION_TP);
     }

   double            GetPositionOpenPrice(ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket)) return 0.0;
      return PositionGetDouble(POSITION_PRICE_OPEN);
     }

   ENUM_POSITION_TYPE GetPositionType(ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket)) return WRONG_VALUE;
      return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
     }

   //--- Batch query helpers ------------------------------------------
   double            TotalFloatingPnL() const
     {
      double pnl = 0.0;
      int total  = PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(m_magic != 0 && PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         pnl += PositionGetDouble(POSITION_PROFIT);
        }
      return pnl;
     }
  };

#endif // __TRADE_POSITION_MANAGER_MQH__
