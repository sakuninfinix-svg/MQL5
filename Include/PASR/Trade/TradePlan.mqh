//+------------------------------------------------------------------+
//| Trade/TradePlan.mqh — v2.01                                      |
//| Trade plan struct + optional builder for pipeline signals         |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_TRADE_PLAN_MQH__
#define __TRADE_TRADE_PLAN_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"

enum ENUM_SIGNAL_URGENCY
  {
   SIGNAL_URGENCY_LOW    = 0,
   SIGNAL_URGENCY_MEDIUM = 1,
   SIGNAL_URGENCY_HIGH   = 2
  };

struct TradePlan
  {
   bool             valid;
   ENUM_SIGNAL_DIR  direction;
   double           lot;
   double           entryPrice;
   double           sl;
   double           tp;
   double           tp2;
   double           beLevel;
   double           slPoints;
   double           partialClosePct;
   ENUM_SIGNAL_URGENCY urgency;
   string           comment;

   void Clear()
     {
      valid=false; direction=SIGNAL_NONE;
      lot=0; entryPrice=0; sl=0; tp=0; tp2=0; beLevel=0;
      slPoints=0; partialClosePct=50.0;
      urgency=SIGNAL_URGENCY_MEDIUM;
      comment="PASR";
     }
  };

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

   TradePlan Build(const SSignal &sig, double lot)
     {
      TradePlan plan;
      plan.Clear();

      if(sig.direction == SIGNAL_NONE) return plan;

      double atr     = (m_data != NULL) ? m_data.GetATRPoints() : 0;
      double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(atr <= 0 || point <= 0 || ask <= 0 || bid <= 0) return plan;

      double slPoints = sig.slPoints > 0.0 ? sig.slPoints : atr * m_cfg.Risk.SLMultiplier;
      double tpPoints = sig.tpPoints > 0.0 ? sig.tpPoints : atr * m_cfg.Risk.TPMultiplier;
      double slDist   = slPoints * point;
      double tp1Dist  = tpPoints * point;
      double tp2Dist  = tp1Dist * 2.0;
      double beDist   = tp1Dist * 0.5;

      plan.direction       = sig.direction;
      plan.lot             = lot;
      plan.urgency         = (sig.confidence >= 0.75) ? SIGNAL_URGENCY_HIGH
                           : (sig.confidence >= 0.45) ? SIGNAL_URGENCY_MEDIUM
                           : SIGNAL_URGENCY_LOW;
      plan.partialClosePct = MathMax(0.0, MathMin(100.0, m_cfg.Risk.PartialClosePct * 100.0));

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

      plan.slPoints = slPoints;
      plan.comment = StringFormat("PASR|%s|%.0f|%s",
                                  sig.direction==SIGNAL_BUY?"B":"S",
                                  sig.confidence * 100.0,
                                  sig.primarySource);

      plan.valid = (plan.sl > 0 && plan.tp > 0 && plan.lot > 0);
      return plan;
     }
  };

#endif // __TRADE_TRADE_PLAN_MQH__