//+------------------------------------------------------------------+
//| Trade/PositionManager.mqh — v1.00                                |
//| Runtime position lifecycle: BE, partial close, trailing stop.    |
//|                                                                  |
//| RESPONSIBILITIES:                                                |
//|   • Break-even mover   : shift SL to entry+buffer at beLevel     |
//|   • Partial close      : close partialClosePct% lot at TP1       |
//|   • Runner management  : let remaining lot trail to TP2          |
//|   • Trailing stop      : ATR / swing / fixed-step modes          |
//|   • Position registry  : per-ticket state prevents double-action |
//|                                                                  |
//| EVENTS FIRED:                                                    |
//|   EVENT_BE_ACTIVATED     — when BE is moved for a ticket         |
//|   EVENT_PARTIAL_CLOSED   — when partial close executed           |
//|   EVENT_RUNNER_ACTIVE    — when ticket enters runner mode        |
//|                                                                  |
//| USAGE:                                                           |
//|   Call OnTick() every tick from Orchestrator.                    |
//|   Call OnTradeTransaction() when a position closes.              |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 6 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_POSITION_MANAGER_MQH__
#define __TRADE_POSITION_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "TradePlan.mqh"
#include <Trade/Trade.mqh>

#define PM_MAX_POSITIONS 32

// Trailing mode selector
enum ENUM_TRAIL_MODE
  {
   TRAIL_NONE       = 0,
   TRAIL_ATR        = 1,   // SL trails at price - ATR*factor
   TRAIL_SWING      = 2,   // SL trails last swing low/high (N bars)
   TRAIL_FIXED_STEP = 3    // SL trails by fixed pip step
  };

// Per-ticket state in the registry
struct PositionRecord
  {
   ulong   ticket;
   bool    active;
   // TradePlan snapshot (frozen at open)
   double  entryPrice;
   double  sl;
   double  tp1;
   double  tp2;
   double  beLevel;
   double  partialClosePct;
   ENUM_SIGNAL_DIR direction;
   // State flags
   bool    beDone;         // BE already moved
   bool    partialDone;    // partial close already executed
   bool    runnerActive;   // running to TP2
   double  trailSL;        // current trailing SL price
  };

//+------------------------------------------------------------------+
//| CPositionManager                                                 |
//+------------------------------------------------------------------+
class CPositionManager : public IManager
  {
private:
   CTrade          m_trade;
   PositionRecord  m_registry[PM_MAX_POSITIONS];
   int             m_count;
   ENUM_TRAIL_MODE m_trailMode;
   double          m_trailAtrFactor;  // for TRAIL_ATR
   int             m_trailSwingBars;  // for TRAIL_SWING
   double          m_trailFixedPts;   // for TRAIL_FIXED_STEP
   double          m_beBufferPts;     // extra pts beyond entry for BE

   // ── Registry helpers ─────────────────────────────────────────────
   int FindRecord(ulong ticket) const
     {
      for(int i = 0; i < m_count; i++)
         if(m_registry[i].ticket == ticket && m_registry[i].active)
            return i;
      return -1;
     }

   int NewSlot()
     {
      for(int i = 0; i < PM_MAX_POSITIONS; i++)
         if(!m_registry[i].active) return i;
      return -1;
     }

   // ── Normalize SL/TP price to tick size ───────────────────────────
   double NormPrice(double p) const
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      return (step > 0) ? MathRound(p / step) * step : p;
     }

   // ── Modify SL of an open position ────────────────────────────────
   bool ModifySL(ulong ticket, double newSL)
     {
      if(!PositionSelectByTicket(ticket)) return false;
      double tp = PositionGetDouble(POSITION_TP);
      bool ok = m_trade.PositionModify(ticket, NormPrice(newSL), tp);
      if(!ok)
         PrintFormat("[PM] ModifySL ticket=%d failed retcode=%d",
                     ticket, m_trade.ResultRetcode());
      return ok;
     }

   // ── Partial close ─────────────────────────────────────────────────
   bool DoPartialClose(PositionRecord &rec)
     {
      if(!PositionSelectByTicket(rec.ticket)) return false;
      double totalLot = PositionGetDouble(POSITION_VOLUME);
      double closeLot = NormalizeDouble(
                           totalLot * rec.partialClosePct / 100.0,
                           (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double stepLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      // Round to lot step
      closeLot = MathFloor(closeLot / stepLot) * stepLot;
      if(closeLot < minLot)
        {
         if(m_debugMode)
            PrintFormat("[PM] Partial skip: closeLot=%.2f < minLot=%.2f",
                        closeLot, minLot);
         return false;
        }
      bool ok = m_trade.PositionClosePartial(rec.ticket, closeLot);
      if(ok)
        {
         PrintFormat("[PM] ✓ Partial close ticket=%d lot=%.2f (%.0f%%)",
                     rec.ticket, closeLot, rec.partialClosePct);
         PASREvent ev; ev.id = EVENT_ID_PARTIAL_CLOSED;
         ev.ticket = rec.ticket; ev.priority = 5;
         DispatchEvent(ev);
        }
      return ok;
     }

   // ── Trailing: compute new trail SL ───────────────────────────────
   double CalcTrailSL(const PositionRecord &rec) const
     {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double atr   = (m_data != NULL) ? m_data.GetATRPoints() * point : 0;
      double price = (rec.direction == SIGNAL_BUY) ? bid : ask;
      double newSL = 0;

      switch(m_trailMode)
        {
         case TRAIL_ATR:
           {
            double dist = atr * m_trailAtrFactor;
            newSL = (rec.direction == SIGNAL_BUY)
                    ? price - dist
                    : price + dist;
            break;
           }
         case TRAIL_SWING:
           {
            // Trail to N-bar swing low (BUY) or swing high (SELL)
            if(rec.direction == SIGNAL_BUY)
              {
               double swing = iLow(_Symbol, PERIOD_CURRENT, 1);
               for(int b = 2; b <= m_trailSwingBars; b++)
                  swing = MathMin(swing, iLow(_Symbol, PERIOD_CURRENT, b));
               newSL = swing - (2.0 * point);
              }
            else
              {
               double swing = iHigh(_Symbol, PERIOD_CURRENT, 1);
               for(int b = 2; b <= m_trailSwingBars; b++)
                  swing = MathMax(swing, iHigh(_Symbol, PERIOD_CURRENT, b));
               newSL = swing + (2.0 * point);
              }
            break;
           }
         case TRAIL_FIXED_STEP:
           {
            double dist = m_trailFixedPts * point;
            newSL = (rec.direction == SIGNAL_BUY)
                    ? price - dist
                    : price + dist;
            break;
           }
         default:
            return 0;
        }
      return NormPrice(newSL);
     }

   // ── Process one position each tick ───────────────────────────────
   void ProcessPosition(PositionRecord &rec)
     {
      if(!PositionSelectByTicket(rec.ticket)) return;
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price = (rec.direction == SIGNAL_BUY) ? bid : ask;
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double curSL = PositionGetDouble(POSITION_SL);

      // 1) Break-even
      if(!rec.beDone && rec.beLevel > 0)
        {
         bool beTrigger = (rec.direction == SIGNAL_BUY)
                          ? (bid >= rec.beLevel)
                          : (ask <= rec.beLevel);
         if(beTrigger)
           {
            double beSL = rec.entryPrice +
                          (rec.direction==SIGNAL_BUY ? 1:-1) *
                          m_beBufferPts * point;
            // Only move SL if it improves (closer to current price)
            bool better = (rec.direction==SIGNAL_BUY)
                          ? (beSL > curSL)
                          : (beSL < curSL || curSL == 0);
            if(better && ModifySL(rec.ticket, beSL))
              {
               rec.beDone  = true;
               rec.trailSL = beSL;
               PrintFormat("[PM] BE activated ticket=%d SL=%.5f",
                           rec.ticket, beSL);
               PASREvent ev; ev.id=EVENT_ID_BE_ACTIVATED;
               ev.ticket=rec.ticket; ev.priority=5;
               DispatchEvent(ev);
              }
           }
        }

      // 2) Partial close at TP1
      if(!rec.partialDone && rec.tp1 > 0 && rec.partialClosePct > 0)
        {
         bool tp1Hit = (rec.direction==SIGNAL_BUY)
                       ? (bid >= rec.tp1)
                       : (ask <= rec.tp1);
         if(tp1Hit && DoPartialClose(rec))
           {
            rec.partialDone  = true;
            rec.runnerActive = true;
            // Move TP to TP2 for runner
            if(rec.tp2 > 0 && PositionSelectByTicket(rec.ticket))
              {
               m_trade.PositionModify(rec.ticket, PositionGetDouble(POSITION_SL), rec.tp2);
               PrintFormat("[PM] Runner active ticket=%d TP2=%.5f",
                           rec.ticket, rec.tp2);
               PASREvent ev; ev.id=EVENT_ID_RUNNER_ACTIVE;
               ev.ticket=rec.ticket; ev.priority=4;
               DispatchEvent(ev);
              }
           }
        }

      // 3) Trailing stop (only after BE, only on confirmed bar close)
      if(rec.beDone && m_trailMode != TRAIL_NONE)
        {
         static datetime lastBar = 0;
         datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
         if(curBar != lastBar || m_trailMode == TRAIL_ATR)
           {
            // ATR trail can update on tick; swing/fixed only on new bar
            if(m_trailMode == TRAIL_ATR || curBar != lastBar)
              {
               lastBar = curBar;
               double newTrail = CalcTrailSL(rec);
               if(newTrail <= 0) return;
               bool improved = (rec.direction==SIGNAL_BUY)
                               ? (newTrail > rec.trailSL)
                               : (newTrail < rec.trailSL || rec.trailSL==0);
               if(improved)
                 {
                  if(ModifySL(rec.ticket, newTrail))
                    {
                     if(m_debugMode)
                        PrintFormat("[PM] Trail ticket=%d SL: %.5f→%.5f",
                                    rec.ticket, rec.trailSL, newTrail);
                     rec.trailSL = newTrail;
                    }
                 }
              }
           }
        }
     }

public:
   CPositionManager()
      : IManager(), m_count(0),
        m_trailMode(TRAIL_ATR),
        m_trailAtrFactor(1.5),
        m_trailSwingBars(5),
        m_trailFixedPts(20.0),
        m_beBufferPts(2.0)
     {
      ArrayInitialize(m_registry, 0);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_trade.SetExpertMagicNumber(m_cfg.MagicNumber);
      m_trade.SetAsyncMode(false);
      return true;
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_BE_ACTIVATED);
      AddEvent(EVENT_ID_PARTIAL_CLOSED);
      AddEvent(EVENT_ID_RUNNER_ACTIVE);
     }

   // Register a new position after execution
   void Register(ulong ticket, const TradePlan &plan)
     {
      int slot = FindRecord(ticket);
      if(slot >= 0) return;  // already registered
      slot = NewSlot();
      if(slot < 0)
        { Print("[PM] Registry full — cannot register ticket ", ticket); return; }

      PositionRecord &r = m_registry[slot];
      r.active         = true;
      r.ticket         = ticket;
      r.entryPrice     = plan.entryPrice;
      r.sl             = plan.sl;
      r.tp1            = plan.tp;
      r.tp2            = plan.tp2;
      r.beLevel        = plan.beLevel;
      r.partialClosePct= plan.partialClosePct;
      r.direction      = plan.direction;
      r.beDone         = false;
      r.partialDone    = false;
      r.runnerActive   = false;
      r.trailSL        = plan.sl;

      if(slot >= m_count) m_count = slot + 1;
      PrintFormat("[PM] Registered ticket=%d dir=%s be=%.5f tp1=%.5f tp2=%.5f",
                  ticket,
                  plan.direction==SIGNAL_BUY?"BUY":"SELL",
                  plan.beLevel, plan.tp, plan.tp2);
     }

   // Called every tick by Orchestrator
   virtual void OnTick() override
     {
      for(int i = 0; i < m_count; i++)
         if(m_registry[i].active)
            ProcessPosition(m_registry[i]);
     }

   // Called when a position closes (OnTradeTransaction)
   void OnPositionClosed(ulong ticket)
     {
      int idx = FindRecord(ticket);
      if(idx >= 0)
        {
         m_registry[idx].active = false;
         PrintFormat("[PM] Deregistered ticket=%d", ticket);
        }
     }

   // Config setters
   void SetTrailMode(ENUM_TRAIL_MODE m)  { m_trailMode       = m;    }
   void SetTrailAtrFactor(double f)      { m_trailAtrFactor  = f;    }
   void SetTrailSwingBars(int n)         { m_trailSwingBars  = n;    }
   void SetTrailFixedPts(double p)       { m_trailFixedPts   = p;    }
   void SetBEBuffer(double pts)          { m_beBufferPts     = pts;  }

   int  GetRegistryCount() const { return m_count; }
   
   // Check if symbol has any open position in registry
   bool HasOpenPosition(const string symbol) const
     {
      for(int i = 0; i < m_count; i++)
        {
         if(!m_registry[i].active) continue;
         
         // Get position symbol from ticket
         if(!PositionSelectByTicket(m_registry[i].ticket)) continue;
         
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         if(posSymbol == symbol) return true;
        }
      return false;
     }
   
   // Check if symbol has open position of specific type
   bool HasOpenPosition(const string symbol, ENUM_POSITION_TYPE type) const
     {
      for(int i = 0; i < m_count; i++)
        {
         if(!m_registry[i].active) continue;
         
         if(!PositionSelectByTicket(m_registry[i].ticket)) continue;
         
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         if(posSymbol != symbol) continue;
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(posType == type) return true;
        }
      return false;
     }
  };

typedef CPositionManager PositionManager;
#endif // __TRADE_POSITION_MANAGER_MQH__
