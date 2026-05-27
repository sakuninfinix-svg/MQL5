//+------------------------------------------------------------------+
//| Trade/PositionManager.mqh — v3.01 (Pipeline Integrated)         |
//| Open position scanner and cache manager for Stage_PositionMgmt  |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v3.01 (2026-05-27) Phase 1 audit fix:                         |
//|     - Removed stale ../Core/PASR.Types.mqh include.              |
//|     - Added PositionSelectByTicket() after PositionGetTicket()   |
//|       before reading position properties.                        |
//|   v3.00 (2026-05-24) Sprint 3A:                                 |
//|     BUG-T09: Rewrite API to match IManager::Init(data,bus) /   |
//|              Deinit() — old Initialize(bus) was not a true      |
//|              override; m_data was never set (NULL crash risk).  |
//|     BUG-T10: DeclareEvents() now uses AddEvent() pattern        |
//|              instead of direct m_bus.Subscribe(). Removed       |
//|              manual Unsubscribe in Shutdown(). Fixed event ID   |
//|              from non-existent TRADE_CLOSED/OPENED to correct   |
//|              EVENT_ID_POSITION_UPDATE. Double-subscribe removed. |
//|   v2.00 (2026-05-23) Sprint 5:                                  |
//|     - Added ScanPositions(PipelineContext &ctx)                 |
//|     - Fills ctx.positions_count and ctx.position_ticket         |
//|     - Single MT5 PositionsTotal() call per pipeline cycle       |
//|     - Magic number filter: only counts positions with InpMagic  |
//|     - Replaces ad-hoc PositionGetTicket loop in pipeline        |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_POSITION_MANAGER_MQH__
#define __TRADE_POSITION_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"

//+------------------------------------------------------------------+
//| CPositionManager — Pipeline-aware position scanner              |
//+------------------------------------------------------------------+
class CPositionManager : public IManager
  {
private:
   long              m_magic;          // EA magic number filter (set from m_cfg)
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

   virtual string HandlerName() const override { return "CPositionManager"; }

   //--- BUG-T09 FIX: Properly override IManager::Init(data, bus).
   //    Old Initialize(CEventBus*) was not a true virtual override —
   //    IManager never called it, so m_data stayed NULL forever.
   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      // Populate filters from config (safe: IManager::Init guarantees m_data != NULL)
      m_magic  = (long)m_cfg.MagicNumber;
      m_symbol = _Symbol;
      m_cached_count  = 0;
      m_cached_ticket = 0;
      m_cache_time    = 0;
      Print("[PosMgr] v3.01 Init OK — magic=", m_magic, " sym=", m_symbol);
      return true;
     }

   //--- BUG-T09 FIX: Properly override IManager::Deinit().
   //    IManager::Deinit() handles Unsubscribe from EventBus.
   virtual void Deinit() override
     {
      IManager::Deinit();
     }

   //--- BUG-T10 FIX: Use AddEvent() — not direct m_bus.Subscribe().
   //    The old code called m_bus.Subscribe(GetPointer(this)) directly,
   //    causing double-subscription (IManager::Init already subscribes).
   //    Also fixed event IDs: EVENT_ID_TRADE_CLOSED / EVENT_ID_TRADE_OPENED
   //    do not exist in ENUM_PASR_EVENT_ID. Correct ID is POSITION_UPDATE.
   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_POSITION_UPDATE); // Trade open/close notification
      AddEvent(EVENT_ID_NEW_BAR);         // Bar-level cache validity check
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_POSITION_UPDATE:
            // Invalidate cache — force rescan on next ScanPositions() call
            m_cached_count = -1;
            break;
         case EVENT_ID_NEW_BAR:
            // Optional: reset cache age on each new bar boundary
            // (ScanPositions will repopulate on next pipeline cycle)
            break;
         default:
            break;
        }
     }

   //--- Configuration (manual override if needed, normally from Init) ---
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
         if(!PositionSelectByTicket(t)) continue;
         if(m_symbol != "" && PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(m_magic  != 0  && PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;
         count++;
         if(ticket == 0) ticket = t; // Store first match
        }

      ctx.positions_count  = count;
      ctx.position_ticket  = ticket;
      ctx.has_position     = (count > 0);
      m_cached_count       = count;
      m_cached_ticket      = ticket;
      m_cache_time         = TimeCurrent();
     }

   //--- Accessors (read cached values without re-scanning) ----------
   int               CachedCount()      const { return m_cached_count;  }
   ulong             CachedTicket()     const { return m_cached_ticket; }
   bool              HasOpenPosition()  const { return m_cached_count > 0; }
   bool              CacheIsValid()     const { return m_cached_count >= 0; }

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

   datetime          GetPositionOpenTime(ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket)) return 0;
      return (datetime)PositionGetInteger(POSITION_TIME);
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
         if(!PositionSelectByTicket(t)) continue;
         if(m_magic != 0 && PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         pnl += PositionGetDouble(POSITION_PROFIT);
        }
      return pnl;
     }
  };

#endif // __TRADE_POSITION_MANAGER_MQH__