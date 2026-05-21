//+------------------------------------------------------------------+
//| Trade/TradePlan.mqh — v2.00                                       |
//| Trade plan struct + builder: entry, SL, TP1, TP2, BE, partial.  |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v2.00 (2026-05-21) — Phase 5+6:                                |
//|     + tp2           : second take profit (partial close target)  |
//|     + beLevel       : break-even trigger price                   |
//|     + partialClosePct: % lot to close at TP1 (default 50)        |
//|     + urgency       : copied from FinalSignal urgency tier       |
//|     + comment       : auto-generated from signal metadata        |
//|   v1.00 (2026-05-20) — initial plan struct                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_TRADE_PLAN_MQH__
#define __TRADE_TRADE_PLAN_MQH__

#include "../Core/IManager.mqh"
#include "../Signal/SignalManager.mqh"

struct TradePlan
  {
   bool             valid;
   ENUM_SIGNAL_DIR  direction;
   double           lot;
   double           entryPrice;
   double           sl;            // stop loss price
   double           tp;            // take profit 1 (full close default)
   double           tp2;           // take profit 2 (let rest run)
   double           beLevel;       // break-even trigger price
   double           slPoints;      // SL distance in points (for risk calc)
   double           partialClosePct; // % to close at TP1 (0=disable, default 50)
   ENUM_SIGNAL_URGENCY urgency;    // from FinalSignal
   string           comment;       // order comment (auto-generated)

   void Clear()
     {
      valid=false; direction=SIGNAL_NONE;
      lot=0; entryPrice=0; sl=0; tp=0; tp2=0; beLevel=0;
      slPoints=0; partialClosePct=50.0;
      urgency=SIGNAL_URGENCY_MEDIUM;
      comment="PASR";
     }
  };

//+------------------------------------------------------------------+
//| CTradePlan — builds a TradePlan from a FinalSignal               |
//+------------------------------------------------------------------+
class CTradePlan
  {
private:
   IDataManager    *m_data;
   CEventBus       *m_bus;
   StrategyConfig   m_cfg;

   double NormalizePrice(double price) const
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      return (step > 0) ? MathRound(price / step) * step : price;
     }

public:
   CTradePlan() : m_data(NULL), m_bus(NULL) {}

   void Init(IDataManager *data, CEventBus *bus)
     { m_data = data; m_bus = bus; }

   void SetCfg(const StrategyConfig &cfg) { m_cfg = cfg; }

   TradePlan Build(const FinalSignal &sig, double lot)
     {
      TradePlan plan;
      plan.Clear();

      if(sig.direction == SIGNAL_NONE) return plan;

      double atr     = (m_data != NULL) ? m_data.GetATRPoints() : 0;
      double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(atr <= 0 || point <= 0) return plan;

      double slDist  = atr * m_cfg.Risk.SLMultiplier * point;
      double tp1Dist = atr * m_cfg.Risk.TPMultiplier  * point;

      // TP2 = 2× TP1 distance (configurable in future via cfg.Risk.TP2Multiplier)
      double tp2Dist = tp1Dist * 2.0;

      // Break-even trigger: halfway between entry and TP1
      double beDist  = tp1Dist * 0.5;

      plan.direction       = sig.direction;
      plan.lot             = lot;
      plan.urgency         = sig.urgency;
      plan.partialClosePct = 50.0;  // default: close half at TP1

      if(sig.direction == SIGNAL_BUY)
        {
         plan.entryPrice = ask;
         plan.sl         = NormalizePrice(ask - slDist);
         plan.tp         = NormalizePrice(ask + tp1Dist);
         plan.tp2        = NormalizePrice(ask + tp2Dist);
         plan.beLevel    = NormalizePrice(ask + beDist);
        }
      else
        {
         plan.entryPrice = bid;
         plan.sl         = NormalizePrice(bid + slDist);
         plan.tp         = NormalizePrice(bid - tp1Dist);
         plan.tp2        = NormalizePrice(bid - tp2Dist);
         plan.beLevel    = NormalizePrice(bid - beDist);
        }

      plan.slPoints = slDist / point;

      // Auto comment: encodes signal metadata
      plan.comment = StringFormat("PASR|%s|%.0f|%d",
                                  sig.direction==SIGNAL_BUY?"B":"S",
                                  sig.score * 100,
                                  sig.confluence);

      plan.valid = (plan.sl > 0 && plan.tp > 0 && plan.lot > 0);
      return plan;
     }
  };

#endif // __TRADE_TRADE_PLAN_MQH__
