//+------------------------------------------------------------------+
//| Trade/RiskManager.mqh — v2.09                                    |
//| Copyright 2026, Agsicentre                                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RISK_MANAGER_MQH__
#define __TRADE_RISK_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"

struct RiskCheckResult
  {
   bool   allowed;
   double suggestedLot;
   string reason;
   RiskCheckResult() : allowed(false), suggestedLot(0), reason("") {}
  };

struct RiskPnLRecord
  {
   ulong    ticket;
   double   profit;
   datetime day;
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
   RiskPnLRecord m_accountedPnL[];

   double AccountBalance()    const { return ::AccountInfoDouble(ACCOUNT_BALANCE);     }
   double AccountEquity()     const { return ::AccountInfoDouble(ACCOUNT_EQUITY);      }
   double AccountFreeMargin() const { return ::AccountInfoDouble(ACCOUNT_MARGIN_FREE); }

   datetime ServerDateMidnight() const
     { return StringToTime(TimeToString(TimeCurrent(), TIME_DATE)); }

   double DailyLossPercent(double dailyPnl) const
     {
      double bal = AccountBalance();
      if(bal <= 0.0) return 0.0;
      return MathMax(0.0, -dailyPnl / bal * 100.0);
     }

   bool IsMaxDDActive() const
     {
      if(m_peakEquity <= 0.0 || m_maxDDPct <= 0.0) return false;
      double ddPct = (1.0 - AccountEquity() / m_peakEquity) * 100.0;
      return ddPct >= m_maxDDPct;
     }

   void ClearAccountedPnL()
     { ArrayResize(m_accountedPnL, 0); }

   bool IsPnLAccounted(ulong ticket, double profit) const
     {
      if(ticket == 0) return false;
      datetime today = ServerDateMidnight();
      for(int i=0; i<ArraySize(m_accountedPnL); i++)
        {
         if(m_accountedPnL[i].ticket == ticket &&
            m_accountedPnL[i].day == today &&
            MathAbs(m_accountedPnL[i].profit - profit) < 0.0000001)
            return true;
        }
      return false;
     }

   void MarkPnLAccounted(ulong ticket, double profit)
     {
      if(ticket == 0) return;
      int n = ArraySize(m_accountedPnL);
      ArrayResize(m_accountedPnL, n + 1);
      m_accountedPnL[n].ticket = ticket;
      m_accountedPnL[n].profit = profit;
      m_accountedPnL[n].day    = ServerDateMidnight();
     }

   void AccumulateClosedPnL(ulong ticket, double profit)
     {
      if(profit == 0.0) return;
      if(ticket > 0 && IsPnLAccounted(ticket, profit))
        {
         if(m_debugMode) PrintFormat("[Risk] Duplicate PnL ignored ticket=%I64u profit=%.2f", ticket, profit);
         return;
        }
      m_dailyLoss += profit;
      if(ticket > 0) MarkPnLAccounted(ticket, profit);
      CheckDailyLossBreaker(m_dailyLoss);
     }

   void CheckDailyReset()
     {
      datetime today = ServerDateMidnight();
      if(today > m_lastResetDay)
        {
         m_dailyLoss = 0.0;
         ClearAccountedPnL();
         m_lastResetDay = today;
         bool ddStillActive = IsMaxDDActive();
         if(!ddStillActive)
           {
            m_circuitBroken = false;
            m_consecLoss = 0;
            PrintFormat("[Risk] Daily reset: circuit cleared at %s", TimeToString(TimeCurrent()));
           }
         else if(m_debugMode)
            Print("[Risk] Daily reset: circuit kept because MaxDD is still active.");
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
      double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
      return spread <= m_maxSpreadPts;
     }

   void CheckDailyLossBreaker(double projectedDailyPnl)
     {
      if(m_dailyLossPct <= 0.0) return;
      if(DailyLossPercent(projectedDailyPnl) >= m_dailyLossPct)
        {
         m_circuitBroken = true;
         Print("[Risk] CIRCUIT BREAKER: daily loss limit.");
        }
     }

   bool ReadConfig()
     {
      if(m_data == NULL) { Print("[Risk] ERROR: DataManager NULL"); return false; }
      const StrategyConfig *cfg = m_data.GetConfig();
      if(cfg == NULL) { Print("[Risk] ERROR: GetConfig() NULL"); return false; }
      m_riskPct       = cfg.Risk.RiskPercent;
      m_dailyLossPct  = cfg.Risk.MaxDailyLossPct;
      m_maxDDPct      = cfg.Risk.MaxDrawdownPct;
      if(m_maxDDPct <= 0.0) m_maxDDPct = m_dailyLossPct * 2.0;
      m_maxOpenTrades = cfg.Risk.MaxOpenPositions;
      m_maxConsecLoss = cfg.Risk.MaxConsecLoss;
      m_maxSpreadPts  = cfg.Market.SpreadFilterPips * 10.0;
      return true;
     }

   double NormalizePrice(double price) const
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      return (step > 0.0) ? MathRound(price / step) * step : price;
     }

   void HandleTradeClosed(ulong ticket, double profit)
     {
      if(profit != 0.0 && ticket > 0 && IsPnLAccounted(ticket, profit))
        {
         if(m_debugMode) PrintFormat("[Risk] Duplicate trade-close ignored ticket=%I64u profit=%.2f", ticket, profit);
         return;
        }
      OnTradeClosed(profit);
      AccumulateClosedPnL(ticket, profit);
     }

public:
   CRiskManager() : IManager(),
      m_riskPct(1.0), m_maxDDPct(10.0), m_dailyLossPct(3.0),
      m_maxOpenTrades(3), m_maxConsecLoss(5), m_maxSpreadPts(30),
      m_minLot(0.01), m_maxLot(10.0), m_lotStep(0.01),
      m_openTrades(0), m_consecLoss(0), m_dailyLoss(0),
      m_peakEquity(0), m_lastResetDay(0), m_circuitBroken(false)
     { ArrayResize(m_accountedPnL, 0); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_POSITION_UPDATE);
      AddEvent(EVENT_ID_TRADE_OPEN);
      AddEvent(EVENT_ID_TRADE_CLOSE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      ReadConfig();
      m_minLot       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      m_maxLot       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      m_lotStep      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(m_minLot <= 0)  m_minLot = 0.01;
      if(m_maxLot <= 0)  m_maxLot = 100.0;
      if(m_lotStep <= 0) m_lotStep = 0.01;
      m_peakEquity   = AccountEquity();
      m_lastResetDay = ServerDateMidnight();
      ClearAccountedPnL();
      SyncOpenTradesFromBroker();
      PrintFormat("[Risk] v2.09 Init OK: risk=%.1f%% daily=%.1f%% maxDD=%.1f%% maxTrades=%d open=%d",
                  m_riskPct, m_dailyLossPct, m_maxDDPct, m_maxOpenTrades, m_openTrades);
      return true;
     }

   virtual string HandlerName() const override { return "RiskManager"; }

   virtual void OnNewBar() override
     { CheckDailyReset(); SyncOpenTradesFromBroker(); double eq = AccountEquity(); if(eq > m_peakEquity) m_peakEquity = eq; }

   virtual void OnEvent(const PASREvent &ev) override
     {
      switch(ev.id)
        {
         case EVENT_ID_TRADE_OPEN:
            OnTradeOpened();
            break;
         case EVENT_ID_TRADE_CLOSE:
            HandleTradeClosed(ev.ticket, ev.profit);
            break;
         case EVENT_ID_POSITION_UPDATE:
            if(ev.data1 == 1.0) SyncOpenTradesFromBroker();
            if(ev.profit != 0.0) HandleTradeClosed(ev.ticket, ev.profit);
            { double eq = AccountEquity(); if(eq > m_peakEquity) m_peakEquity = eq; }
            break;
         case EVENT_ID_NEW_BAR:       OnNewBar();    break;
         case EVENT_ID_CONFIG_RELOAD: ReadConfig();  break;
         default: break;
        }
     }

   RiskCheckResult Check(double slPoints = 0, ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY) const
     {
      RiskCheckResult r;
      if(m_circuitBroken) { r.reason = "CircuitBroken"; return r; }
      if(m_openTrades >= m_maxOpenTrades)
        { r.reason = StringFormat("MaxTrades(%d/%d)", m_openTrades, m_maxOpenTrades); return r; }
      double lossPct = DailyLossPercent(m_dailyLoss);
      if(m_dailyLossPct > 0.0 && lossPct >= m_dailyLossPct)
        { r.reason = StringFormat("DailyLoss(%.1f%%>=%.1f%%)", lossPct, m_dailyLossPct); return r; }
      if(IsMaxDDActive())
        { r.reason = StringFormat("MaxDD(%.1f%%>=%.1f%%)", GetDrawdownPct(), m_maxDDPct); return r; }
      if(m_maxConsecLoss > 0 && m_consecLoss >= m_maxConsecLoss)
        { r.reason = StringFormat("ConsecLoss(%d>=%d)", m_consecLoss, m_maxConsecLoss); return r; }
      if(!SpreadOK())
        {
         double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
         r.reason = StringFormat("SpreadTooWide(%.1f>%.1fpts)", sp, m_maxSpreadPts); return r;
        }

      double lot = (slPoints > 0) ? CalcLot(slPoints) : m_minLot;
      if(lot < m_minLot)
        { r.reason = StringFormat("LotBelowMin(%.4f<%.4f)", lot, m_minLot); return r; }

      double price = (orderType == ORDER_TYPE_SELL)
         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double marginReq = 0;
      OrderCalcMargin(orderType, _Symbol, lot, price, marginReq);
      if(marginReq > 0 && AccountFreeMargin() < marginReq * 1.2)
        { r.reason = StringFormat("InsufficientMargin(free=%.2f req=%.2f)", AccountFreeMargin(), marginReq * 1.2); return r; }

      r.allowed = true;
      r.suggestedLot = lot;
      r.reason = "OK";
      return r;
     }

   SRiskResult CheckRisk(const SSignal &signal) const
     {
      SRiskResult out;
      if(signal.direction == SIGNAL_NONE)
        { out.SetResult(false, 0.0, "NoSignal"); return out; }
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(ask <= 0 || bid <= 0 || point <= 0)
        { out.SetResult(false, 0.0, "InvalidPrice"); return out; }
      double entry = signal.entryPrice;
      if(entry <= 0.0) entry = (signal.direction == SIGNAL_BUY) ? ask : bid;
      double slPoints = signal.slPoints;
      if(slPoints <= 0.0)
        {
         double atrPts = (m_data != NULL) ? m_data.GetATRPoints() / point : 0.0;
         if(atrPts <= 0.0) atrPts = 100.0;
         slPoints = atrPts * m_cfg.Risk.SLMultiplier;
        }
      double tpPoints = signal.tpPoints;
      if(tpPoints <= 0.0)
         tpPoints = slPoints * MathMax(1.0, m_cfg.Risk.TPMultiplier / MathMax(0.1, m_cfg.Risk.SLMultiplier));
      ENUM_ORDER_TYPE orderType = (signal.direction == SIGNAL_SELL) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      RiskCheckResult base = Check(slPoints, orderType);
      out.SetResult(base.allowed, base.suggestedLot, base.reason);
      if(!base.allowed) return out;
      double sl = 0.0, tp = 0.0;
      if(signal.direction == SIGNAL_BUY)
        { sl = NormalizePrice(entry - slPoints * point); tp = NormalizePrice(entry + tpPoints * point); }
      else
        { sl = NormalizePrice(entry + slPoints * point); tp = NormalizePrice(entry - tpPoints * point); }
      out.SetPrices(entry, sl, tp, (ulong)m_cfg.MagicNumber);
      return out;
     }

   double CalcLot(double slPoints) const
     {
      if(slPoints <= 0) return m_minLot;
      double basis = MathMin(AccountBalance(), AccountEquity());
      double riskAmount = basis * m_riskPct / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0) return m_minLot;
      double pointValue = tickValue / (tickSize / _Point);
      if(pointValue <= 0) return m_minLot;
      return NormaliseLot(riskAmount / (slPoints * pointValue));
     }

   void OnTradeOpened()
     { SyncOpenTradesFromBroker(); if(m_debugMode) PrintFormat("[Risk] Opened. Open=%d", m_openTrades); }

   void OnTradeClosed(double profit = 0)
     {
      SyncOpenTradesFromBroker();
      if(profit < 0) m_consecLoss++; else m_consecLoss = 0;
      if(m_maxConsecLoss > 0 && m_consecLoss >= m_maxConsecLoss)
        { m_circuitBroken = true; PrintFormat("[Risk] CIRCUIT BREAKER: %d consec losses.", m_consecLoss); }
      CheckDailyLossBreaker(m_dailyLoss + profit);
     }

   void SyncOpenTradesFromBroker()
     {
      int count = 0;
      long magic = m_cfg.MagicNumber;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(magic > 0 && PositionGetInteger(POSITION_MAGIC) != magic) continue;
         count++;
        }
      m_openTrades = count;
     }

   void ResetCircuit()  { m_circuitBroken = false; m_consecLoss = 0; Print("[Risk] Circuit reset."); }

   bool   IsCircuitBroken() const { return m_circuitBroken; }
   int    GetOpenTrades()   const { return m_openTrades; }
   int    GetConsecLoss()   const { return m_consecLoss; }
   double GetDailyLoss()    const { return m_dailyLoss; }
   double GetDailyLossPct() const { return DailyLossPercent(m_dailyLoss); }
   double GetDrawdownPct() const
     { return (m_peakEquity > 0) ? (1.0 - AccountEquity() / m_peakEquity) * 100.0 : 0; }
   bool IsTradingAllowed() const { return !m_circuitBroken && Check(0).allowed; }
   bool IsTradingAllowed(const string) const { return IsTradingAllowed(); }
  };

#endif // __TRADE_RISK_MANAGER_MQH__