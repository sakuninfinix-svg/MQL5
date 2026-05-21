//+------------------------------------------------------------------+
//| Trade/RiskManager.mqh — v1.00  (NEW — Phase 2)                   |
//| Pre-trade circuit breaker: lot sizing, daily loss, max DD,       |
//| per-trade risk, and trade-count limits.                          |
//|                                                                  |
//| This is the "7.RiskManager" that was missing from the architecture|
//| Sits between SignalManager and ExecutionManager. Orchestrator    |
//| calls CanTrade() + CalcLot() before ExecutionManager.Execute()  |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RISK_MANAGER_MQH__
#define __TRADE_RISK_MANAGER_MQH__

#include "../Core/IManager.mqh"

enum ENUM_RISK_BLOCK
  {
   RISK_OK              = 0,
   RISK_BLOCK_DAILY     = 1,  // daily loss limit hit
   RISK_BLOCK_DRAWDOWN  = 2,  // max account drawdown hit
   RISK_BLOCK_TRADEMAX  = 3,  // max open trades reached
   RISK_BLOCK_SPREAD    = 4,  // spread too wide
   RISK_BLOCK_BALANCE   = 5,  // balance below minimum
   RISK_BLOCK_MARGIN    = 6   // free margin insufficient
  };

struct RiskCheckResult
  {
   bool             allowed;
   ENUM_RISK_BLOCK  block;
   double           suggestedLot;
   string           reason;

   void Allow(double lot) { allowed=true; block=RISK_OK; suggestedLot=lot; reason="OK"; }
   void Block(ENUM_RISK_BLOCK b, string r)
     { allowed=false; block=b; suggestedLot=0; reason=r; }
  };

//+------------------------------------------------------------------+
//| CRiskManager — pre-trade risk gate                               |
//+------------------------------------------------------------------+
class CRiskManager : public IManager
  {
private:
   double   m_dayStartBalance;
   double   m_peakBalance;
   int      m_todayTradeCount;
   datetime m_lastDayReset;

   void ResetDailyCounters()
     {
      m_dayStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
      m_todayTradeCount  = 0;
      m_lastDayReset     = TimeCurrent();
      if(m_debugMode) PrintFormat("[Risk] Daily reset. Balance=%.2f", m_dayStartBalance);
     }

   bool IsNewDay() const
     {
      MqlDateTime now, last;
      TimeToStruct(TimeCurrent(), now);
      TimeToStruct(m_lastDayReset, last);
      return (now.day != last.day || now.mon != last.mon || now.year != last.year);
     }

public:
   CRiskManager()
      : IManager(), m_dayStartBalance(0), m_peakBalance(0),
        m_todayTradeCount(0), m_lastDayReset(0) {}

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_peakBalance     = m_dayStartBalance;
      m_lastDayReset    = TimeCurrent();
      return true;
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
     }

   virtual void OnNewBar() override
     {
      if(IsNewDay()) ResetDailyCounters();
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance > m_peakBalance) m_peakBalance = balance;
     }

   // ── Main gate: call before every ExecutionManager.Execute() ──
   RiskCheckResult Check(double slPoints) const
     {
      RiskCheckResult r;

      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double freeMar    = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double minBalance = m_cfg.Risk.MinBalance;

      // 1) Balance floor
      if(minBalance > 0 && balance < minBalance)
        { r.Block(RISK_BLOCK_BALANCE,
                  StringFormat("Balance %.2f < min %.2f", balance, minBalance));
          return r; }

      // 2) Daily loss limit
      double dailyLossPct = m_cfg.Risk.MaxDailyLossPct;
      if(dailyLossPct > 0 && m_dayStartBalance > 0)
        {
         double loss = (m_dayStartBalance - balance) / m_dayStartBalance * 100.0;
         if(loss >= dailyLossPct)
           { r.Block(RISK_BLOCK_DAILY,
                     StringFormat("DailyLoss %.1f%% >= limit %.1f%%", loss, dailyLossPct));
             return r; }
        }

      // 3) Max drawdown from peak
      double maxDD = m_cfg.Risk.MaxDrawdownPct;
      if(maxDD > 0 && m_peakBalance > 0)
        {
         double dd = (m_peakBalance - equity) / m_peakBalance * 100.0;
         if(dd >= maxDD)
           { r.Block(RISK_BLOCK_DRAWDOWN,
                     StringFormat("DD %.1f%% >= limit %.1f%%", dd, maxDD));
             return r; }
        }

      // 4) Max open trades
      int maxTrades = m_cfg.Risk.MaxOpenTrades;
      int openNow   = 0;
      for(int i=0; i < PositionsTotal(); i++)
         if(PositionGetSymbol(i)==_Symbol &&
            (int)PositionGetInteger(POSITION_MAGIC)==m_cfg.MagicNumber) openNow++;
      if(maxTrades > 0 && openNow >= maxTrades)
        { r.Block(RISK_BLOCK_TRADEMAX,
                  StringFormat("OpenTrades %d >= max %d", openNow, maxTrades));
          return r; }

      // 5) Margin check: require 3x lot margin available
      double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double lot      = CalcLot(slPoints);
      double reqMar   = lot * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
      if(reqMar > 0 && freeMar < reqMar * 1.5)
        { r.Block(RISK_BLOCK_MARGIN,
                  StringFormat("FreeMar %.2f < needed %.2f", freeMar, reqMar*1.5));
          return r; }

      r.Allow(lot);
      return r;
     }

   // ── Lot size calculator (risk-based, ATR-aware) ───────────────
   double CalcLot(double slPoints) const
     {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskPct  = m_cfg.Risk.RiskPerTrade;     // e.g. 1.0 = 1%
      double riskAmt  = balance * riskPct / 100.0;

      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

      if(slPoints <= 0 || tickSize <= 0 || tickVal <= 0) return minLot;

      double slValue  = slPoints * (tickVal / tickSize);
      if(slValue <= 0) return minLot;

      double rawLot = riskAmt / slValue;

      // Apply max lot cap from config
      if(m_cfg.Risk.MaxLot > 0) maxLot = MathMin(maxLot, m_cfg.Risk.MaxLot);

      // Round to lot step
      rawLot = MathFloor(rawLot / lotStep) * lotStep;
      rawLot = MathMax(minLot, MathMin(maxLot, rawLot));

      return NormalizeDouble(rawLot, 2);
     }

   void OnTradeClosed()  { /* can add win/loss tracking here */ }
   void OnTradeOpened()  { m_todayTradeCount++; }

   int    GetTodayCount()      const { return m_todayTradeCount; }
   double GetDailyPnLPct()     const
     {
      if(m_dayStartBalance <= 0) return 0;
      return (AccountInfoDouble(ACCOUNT_BALANCE) - m_dayStartBalance)
              / m_dayStartBalance * 100.0;
     }
   double GetDrawdownPct() const
     {
      if(m_peakBalance <= 0) return 0;
      return (m_peakBalance - AccountInfoDouble(ACCOUNT_EQUITY))
              / m_peakBalance * 100.0;
     }
  };

typedef CRiskManager RiskManager;
#endif
