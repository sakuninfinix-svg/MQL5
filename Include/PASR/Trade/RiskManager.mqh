//+------------------------------------------------------------------+
//| Trade/RiskManager.mqh — v2.03                                    |
//| Copyright 2026, Agsicentre                                       |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v2.03 (2026-05-24):                                           |
//|     BUG-T05: Daily reset now uses server-date midnight via       |
//|              StringToTime(TimeToString(TimeCurrent(),DATE))      |
//|              instead of UTC modulo arithmetic.                   |
//|   v2.02 (2026-05-24) Sprint 3B:                                 |
//|     BUG-T13: OnTradeClosed() removed m_dailyLoss accumulation.  |
//|   v2.01 (2026-05-24) — BUG-T06:                                |
//|     OnEvent(POSITION_UPDATE): only update dailyLoss when         |
//|     ev.profit != 0.0 to prevent silent P&L corruption.          |
//|   v2.00 (2026-05-23) — BUG-015: Init() super-call guard.        |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RISK_MANAGER_MQH__
#define __TRADE_RISK_MANAGER_MQH__

#include "../Core/IManager.mqh"

struct RiskCheckResult
  {
   bool   allowed;
   double suggestedLot;
   string reason;
   RiskCheckResult() : allowed(false), suggestedLot(0), reason("") {}
  };

class CRiskManager : public IManager
  {
private:
   double  m_riskPct;
   double  m_maxDDPct;
   double  m_dailyLossPct;
   int     m_maxOpenTrades;
   int     m_maxConsecLoss;
   double  m_maxSpreadPts;
   double  m_minLot;
   double  m_maxLot;
   double  m_lotStep;

   int     m_openTrades;
   int     m_consecLoss;
   double  m_dailyLoss;
   double  m_peakEquity;
   datetime m_lastResetDay;
   bool    m_circuitBroken;

   double AccountBalance()    const { return ::AccountInfoDouble(ACCOUNT_BALANCE);     }
   double AccountEquity()     const { return ::AccountInfoDouble(ACCOUNT_EQUITY);      }
   double AccountFreeMargin() const { return ::AccountInfoDouble(ACCOUNT_MARGIN_FREE); }

   datetime ServerDateMidnight() const
     {
      return StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
     }

   void CheckDailyReset()
     {
      datetime today = ServerDateMidnight();
      if(today > m_lastResetDay)
        {
         m_dailyLoss = 0;
         m_lastResetDay = today;
         if(m_debugMode) Print("[Risk] Daily P&L reset.");
        }
     }

   double NormaliseLot(double raw) const
     {
      if(m_lotStep <= 0) return MathMax(m_minLot, MathMin(m_maxLot, raw));
      double stepped = MathFloor(raw / m_lotStep) * m_lotStep;
      return NormalizeDouble(MathMax(m_minLot, MathMin(m_maxLot, stepped)), 2);
     }

   bool SpreadOK() const
     {
      if(m_maxSpreadPts <= 0) return true;
      double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                      - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
      return spread <= m_maxSpreadPts;
     }

   bool ReadConfig()
     {
      if(m_data == NULL) { Print("[Risk] ERROR: DataManager NULL"); return false; }
      const StrategyConfig *cfg = m_data.GetConfig();
      if(cfg == NULL) { Print("[Risk] ERROR: GetConfig() NULL"); return false; }
      m_riskPct       = cfg.Risk.RiskPct;
      m_maxDDPct      = cfg.Risk.MaxDrawdownPct;
      m_dailyLossPct  = cfg.Risk.DailyLossPct;
      m_maxOpenTrades = cfg.Risk.MaxOpenTrades;
      m_maxConsecLoss = cfg.Risk.MaxConsecLoss;
      m_maxSpreadPts  = cfg.Execution.MaxSpreadPoints;
      return true;
     }

public:
   CRiskManager() : IManager(),
      m_riskPct(1.0), m_maxDDPct(10.0), m_dailyLossPct(3.0),
      m_maxOpenTrades(3), m_maxConsecLoss(5), m_maxSpreadPts(30),
      m_minLot(0.01), m_maxLot(10.0), m_lotStep(0.01),
      m_openTrades(0), m_consecLoss(0), m_dailyLoss(0),
      m_peakEquity(0), m_lastResetDay(0), m_circuitBroken(false)
     {}

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_NEW_BAR); AddEvent(EVENT_ID_POSITION_UPDATE); AddEvent(EVENT_ID_CONFIG_RELOAD); }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      ReadConfig();
      m_minLot       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      m_maxLot       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      m_lotStep      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      m_peakEquity   = AccountEquity();
      m_lastResetDay = ServerDateMidnight();
      PrintFormat("[Risk] v2.03 Init OK: risk=%.1f%% maxDD=%.1f%% daily=%.1f%% maxTrades=%d",
                  m_riskPct, m_maxDDPct, m_dailyLossPct, m_maxOpenTrades);
      return true;
     }

   virtual string HandlerName() const override { return "RiskManager"; }

   virtual void OnNewBar() override
     { CheckDailyReset(); double eq = AccountEquity(); if(eq > m_peakEquity) m_peakEquity = eq; }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_POSITION_UPDATE:
            if(ev.profit != 0.0)
               m_dailyLoss += ev.profit;
            { double eq = AccountEquity(); if(eq > m_peakEquity) m_peakEquity = eq; }
            break;
         case EVENT_ID_NEW_BAR:       OnNewBar();    break;
         case EVENT_ID_CONFIG_RELOAD: ReadConfig();  break;
         default: break;
        }
     }

   RiskCheckResult Check(double slPoints = 0) const
     {
      RiskCheckResult r;
      if(m_circuitBroken) { r.reason = "CircuitBroken"; return r; }
      if(m_openTrades >= m_maxOpenTrades)
        { r.reason = StringFormat("MaxTrades(%d/%d)", m_openTrades, m_maxOpenTrades); return r; }
      double bal = AccountBalance();
      if(bal > 0 && m_dailyLossPct > 0)
        { double dlPct = (m_dailyLoss / bal) * 100.0;
          if(dlPct <= -m_dailyLossPct)
            { r.reason = StringFormat("DailyLoss(%.1f%%>=%.1f%%)", -dlPct, m_dailyLossPct); return r; } }
      if(m_peakEquity > 0 && m_maxDDPct > 0)
        { double ddPct = (1.0 - AccountEquity() / m_peakEquity) * 100.0;
          if(ddPct >= m_maxDDPct)
            { r.reason = StringFormat("MaxDD(%.1f%%>=%.1f%%)", ddPct, m_maxDDPct); return r; } }
      if(m_maxConsecLoss > 0 && m_consecLoss >= m_maxConsecLoss)
        { r.reason = StringFormat("ConsecLoss(%d>=%d)", m_consecLoss, m_maxConsecLoss); return r; }
      if(!SpreadOK())
        { double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
          r.reason = StringFormat("SpreadTooWide(%.1f>%.1fpts)", sp, m_maxSpreadPts); return r; }
      double lot = 0;
      if(slPoints > 0)
        { lot = CalcLot(slPoints);
          if(lot < m_minLot) { r.reason = StringFormat("LotBelowMin(%.4f<%.4f)", lot, m_minLot); return r; }
          double marginReq = 0;
          OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginReq);
          if(marginReq > 0 && AccountFreeMargin() < marginReq * 1.2)
            { r.reason = StringFormat("InsufficientMargin(free=%.2f req=%.2f)", AccountFreeMargin(), marginReq * 1.2); return r; } }
      r.allowed = true; r.suggestedLot = lot; r.reason = "OK";
      return r;
     }

   double CalcLot(double slPoints) const
     {
      if(slPoints <= 0) return m_minLot;
      double balance   = AccountBalance();
      double riskAmount = balance * m_riskPct / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0) return m_minLot;
      double pointValue = tickValue / (tickSize / _Point);
      if(pointValue <= 0) return m_minLot;
      return NormaliseLot(riskAmount / (slPoints * pointValue));
     }

   void OnTradeOpened()
     { m_openTrades++;
       if(m_debugMode) PrintFormat("[Risk] Opened. Open=%d", m_openTrades); }

   void OnTradeClosed(double profit = 0)
     {
      m_openTrades = MathMax(0, m_openTrades - 1);
      if(profit < 0) m_consecLoss++; else m_consecLoss = 0;
      if(m_maxConsecLoss > 0 && m_consecLoss >= m_maxConsecLoss)
        { m_circuitBroken = true;
          PrintFormat("[Risk] CIRCUIT BREAKER: %d consec losses.", m_consecLoss); }
      double bal = AccountBalance();
      if(bal > 0 && m_dailyLossPct > 0)
         if((-m_dailyLoss / bal * 100.0) >= m_dailyLossPct)
           { m_circuitBroken = true; Print("[Risk] CIRCUIT BREAKER: daily loss limit."); }
      if(m_debugMode)
         PrintFormat("[Risk] Closed profit=%.2f Open=%d consec=%d daily=%.2f",
                     profit, m_openTrades, m_consecLoss, m_dailyLoss);
     }

   void ResetCircuit()  { m_circuitBroken = false; m_consecLoss = 0; Print("[Risk] Circuit reset."); }

   bool   IsCircuitBroken() const { return m_circuitBroken; }
   int    GetOpenTrades()   const { return m_openTrades;    }
   int    GetConsecLoss()   const { return m_consecLoss;    }
   double GetDailyLoss()    const { return m_dailyLoss;     }
   double GetDailyLossPct() const
     { double b = AccountBalance(); return (b > 0) ? (-m_dailyLoss / b * 100.0) : 0; }
   double GetDrawdownPct()  const
     { return (m_peakEquity > 0) ? (1.0 - AccountEquity() / m_peakEquity) * 100.0 : 0; }
   bool IsTradingAllowed() const { return !m_circuitBroken && Check(0).allowed; }
   bool IsTradingAllowed(const string) const { return IsTradingAllowed(); }
  };

#endif // __TRADE_RISK_MANAGER_MQH__
