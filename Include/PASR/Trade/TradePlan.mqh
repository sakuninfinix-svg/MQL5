//+------------------------------------------------------------------+
//|                                          Trade/TradePlan.mqh    |
//|                          Copyright 2026, Agsicentre             |
//|   PASR Layer 5 — Trade: TradePlan struct (SRP extracted)        |
//|                                                                  |
//|   Extracted from: 6.ExecutionManager.mqh                        |
//|   Reason: TradePlan is a pure data struct. Keeping it inside     |
//|   ExecutionManager violates SRP and prevents SignalManager from  |
//|   building plans without including the full execution layer.     |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __TRADE_TRADE_PLAN_MQH__
#define __TRADE_TRADE_PLAN_MQH__

//+------------------------------------------------------------------+
//| TradePlan — immutable signal-to-execution data contract          |
//+------------------------------------------------------------------+
struct TradePlan
{
   double   entry;       ///< Target entry price (0 = market)
   double   sl;          ///< Stop loss price
   double   tp;          ///< Take profit price
   double   lot;         ///< Calculated lot size
   int      direction;   ///< +1 = BUY, -1 = SELL
   string   label;       ///< Order comment
   bool     isPending;   ///< true = place limit/stop order
   datetime expiry;      ///< Pending order expiry (ORDER_TIME_SPECIFIED)

   void Reset() { ZeroMemory(this); }

   bool IsValid() const
   {
      if(lot  <= 0)       return false;
      if(sl   <= 0)       return false;
      if(direction == 0)  return false;
      if(direction != 1 && direction != -1) return false;
      return true;
   }
};

#endif // __TRADE_TRADE_PLAN_MQH__
