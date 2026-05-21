//+------------------------------------------------------------------+
//| Trade/TradePlan.mqh — v2.00                                      |
//| Risk-based trade plan: TP/SL/Lot from ATR + config multipliers.  |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_TRADE_PLAN_MQH__
#define __TRADE_TRADE_PLAN_MQH__

#include "../Core/IManager.mqh"
#include "../Signal/SignalManager.mqh"

struct TradePlan
  {
   bool    valid;
   int     direction;   // +1 buy, -1 sell
   double  entryPrice;
   double  stopLoss;
   double  takeProfit;
   double  lot;
   double  rr;          // risk:reward ratio
   double  slPoints;
   double  tpPoints;
   string  reason;

   void Clear()
     { valid=false; direction=0; entryPrice=0; stopLoss=0;
       takeProfit=0; lot=0; rr=0; slPoints=0; tpPoints=0; reason=""; }
  };

//+------------------------------------------------------------------+
//| CTradePlan — builds TradePlan from signal + ATR                  |
//+------------------------------------------------------------------+
class CTradePlan : public IManager
  {
public:
   CTradePlan() : IManager() {}

   virtual void DeclareEvents() override {}

   // Build a TradePlan from a confirmed FinalSignal.
   // SL = ATR * SLMultiplier; TP = SL * TPMultiplier.
   TradePlan Build(const FinalSignal &sig, double lot)
     {
      TradePlan plan;
      plan.Clear();

      if(sig.direction == SIGNAL_NONE) return plan;

      double atr       = m_data.GetATRPoints() * _Point;
      double slMult    = m_cfg.Risk.SLMultiplier;
      double tpMult    = m_cfg.Risk.TPMultiplier;
      double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

      double slDist    = MathMax(atr * slMult, stopLevel * 1.1);
      double tpDist    = slDist * tpMult;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      plan.direction  = sig.direction;
      plan.lot        = lot;
      plan.slPoints   = slDist / _Point;
      plan.tpPoints   = tpDist / _Point;
      plan.rr         = tpMult;

      if(sig.direction == SIGNAL_BUY)
        {
         plan.entryPrice = ask;
         plan.stopLoss   = NormalizeDouble(ask - slDist, _Digits);
         plan.takeProfit = NormalizeDouble(ask + tpDist, _Digits);
        }
      else
        {
         plan.entryPrice = bid;
         plan.stopLoss   = NormalizeDouble(bid + slDist, _Digits);
         plan.takeProfit = NormalizeDouble(bid - tpDist, _Digits);
        }

      plan.reason = StringFormat("%s ATR=%.5f SL=%.5f TP=%.5f",
                                  sig.sources, atr, plan.stopLoss, plan.takeProfit);
      plan.valid  = true;
      return plan;
     }
  };

typedef CTradePlan TradePlan_Builder;  // avoid name clash with struct
#endif
