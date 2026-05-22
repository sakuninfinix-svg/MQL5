//+------------------------------------------------------------------+
//| Trade/RiskManager.mqh — v1.00  (Phase 4 — FULL IMPLEMENTATION)  |
//| Copyright 2026, Agsicentre                                       |
//|                                                                  |
//| RESPONSIBILITIES:                                                |
//|  1. Lot sizing  — ATR-based fixed-fractional                     |
//|  2. Pre-trade gate  — Check() blocks entries when:              |
//|       a) Max open trades reached                                 |
//|       b) Daily loss limit hit  (circuit breaker)                 |
//|       c) Max drawdown hit      (circuit breaker)                 |
//|       d) Spread too wide                                         |
//|       e) Consecutive loss limit hit                              |
//|  3. Trade counters  — OnTradeOpened / OnTradeClosed             |
//|  4. Daily reset  — resets daily P&L counter at midnight         |
//+------------------------------------------------------------------+
#property strict
#ifndef __TRADE_RISK_MANAGER_MQH__
#define __TRADE_RISK_MANAGER_MQH__

#include "../Core/IManager.mqh"

//+------------------------------------------------------------------+
//| RiskCheckResult — returned by Check()                           |
//+------------------------------------------------------------------+
struct RiskCheckResult
  {
   bool   allowed;        // true = trade may proceed
   double suggestedLot;   // adjusted lot after risk calc
   string reason;         // human-readable block reason

   RiskCheckResult() : allowed(false), suggestedLot(0), reason("") {}
  };

//+------------------------------------------------------------------+
//| CRiskManager                                                     |
//+------------------------------------------------------------------+
class CRiskManager : public IManager
  {
private:
   // ── Config mirrors (read from StrategyConfig at Init)
   double  m_riskPct;          // e.g. 1.0 = 1% per trade
   double  m_maxDDPct;         // e.g. 10.0 = 10% max drawdown
   double  m_dailyLossPct;     // e.g. 3.0 = 3% daily loss limit
   int     m_maxOpenTrades;    // e.g. 3
   int     m_maxConsecLoss;    // e.g. 5 consecutive losses
   double  m_maxSpreadPts;     // e.g. 30 points
   double  m_minLot;           // broker minimum lot
   double  m_maxLot;           // broker maximum lot
   double  m_lotStep;          // broker lot step

   // ── Runtime state
   int     m_openTrades;       // currently open positions
   int     m_consecLoss;       // consecutive losing trades
   double  m_dailyLoss;        // accumulated P&L today (negative = loss)
   double  m_peakEquity;       // highest equity seen (for DD calc)
   datetime m_lastResetDay;    // date of last daily reset
   bool    m_circuitBroken;    // true = trading halted until manual reset

   // ── Account helpers
   double AccountBalance()  const { return ::AccountInfoDouble(ACCOUNT_BALANCE);  }
   double AccountEquity()   const { return ::AccountInfoDouble(ACCOUNT_EQUITY);   }
   double AccountFreeMargin()const{ return ::AccountInfoDouble(ACCOUNT_MARGIN_FREE); }

   // ── Daily reset ───────────────────────────────────────────
   void CheckDailyReset()
     {
      datetime now    = TimeCurrent();
      datetime today  = (datetime)((long)now - (long)now % 86400);
      if(today > m_lastResetDay)
        {
         m_dailyLoss    = 0;
         m_lastResetDay = today;
         // Do NOT reset consecLoss or circuitBroken across day boundary
         if(m_debugMode)
            Print("[Risk] Daily P&L reset.");
        }
     }

   // ── Lot normalisation ────────────────────────────────────────
   double NormaliseLot(double raw) const
     {
      if(m_lotStep <= 0) return MathMax(m_minLot, MathMin(m_maxLot, raw));
      double stepped = MathFloor(raw / m_lotStep) * m_lotStep;
      return NormalizeDouble(MathMax(m_minLot, MathMin(m_maxLot, stepped)), 2);
     }

   // ── Spread check ────────────────────────────────────────────
   bool SpreadOK() const
     {
      if(m_maxSpreadPts <= 0) return true;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double spreadPts = (ask - bid) / _Point;
      return spreadPts <= m_maxSpreadPts;
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
     {
      AddEvent(EVENT_ID_NEW_BAR);           // daily reset check
      AddEvent(EVENT_ID_POSITION_UPDATE);   // P&L tracking
      AddEvent(EVENT_ID_CONFIG_RELOAD);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;

      // Read config from DataManager
      if(m_data != NULL)
        {
         const StrategyConfig *cfg = m_data.GetConfig();
         if(cfg != NULL)
           {
            m_riskPct        = cfg.Risk.RiskPct;
            m_maxDDPct       = cfg.Risk.MaxDrawdownPct;
            m_dailyLossPct   = cfg.Risk.DailyLossPct;
            m_maxOpenTrades  = cfg.Risk.MaxOpenTrades;
            m_maxConsecLoss  = cfg.Risk.MaxConsecLoss;
            m_maxSpreadPts   = cfg.Execution.MaxSpreadPoints;
           }
        }

      // Broker lot constraints
      m_minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      m_maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      m_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      m_peakEquity  = AccountEquity();
      m_lastResetDay= (datetime)((long)TimeCurrent() - (long)TimeCurrent() % 86400);

      PrintFormat("[Risk] Init: risk=%.1f%% maxDD=%.1f%% dailyLoss=%.1f%% maxTrades=%d consecLoss=%d",
                  m_riskPct, m_maxDDPct, m_dailyLossPct, m_maxOpenTrades, m_maxConsecLoss);
      return true;
     }

   virtual void OnNewBar() override
     {
      CheckDailyReset();
      // Update peak equity
      double eq = AccountEquity();
      if(eq > m_peakEquity) m_peakEquity = eq;
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_POSITION_UPDATE)
        {
         // Accumulate closed P&L for daily tracking
         m_dailyLoss += ev.profit;
         // Update peak equity
         double eq = AccountEquity();
         if(eq > m_peakEquity) m_peakEquity = eq;
        }
      if(ev.id == EVENT_ID_CONFIG_RELOAD)
        {
         // Re-read config live
         if(m_data != NULL)
           {
            const StrategyConfig *cfg = m_data.GetConfig();
            if(cfg != NULL)
              {
               m_riskPct       = cfg.Risk.RiskPct;
               m_maxDDPct      = cfg.Risk.MaxDrawdownPct;
               m_dailyLossPct  = cfg.Risk.DailyLossPct;
               m_maxOpenTrades = cfg.Risk.MaxOpenTrades;
               m_maxConsecLoss = cfg.Risk.MaxConsecLoss;
              }
           }
        }
     }

   //+----------------------------------------------------------------+
   //| Check — main gate before any trade execution                  |
   //| slPoints: SL distance in points (0 = pre-check without lot)   |
   //+----------------------------------------------------------------+
   RiskCheckResult Check(double slPoints = 0) const
     {
      RiskCheckResult r;
      r.allowed      = false;
      r.suggestedLot = 0;
      r.reason       = "";

      // ── Gate 1: Circuit breaker
      if(m_circuitBroken)
        { r.reason = "CircuitBroken: trading halted"; return r; }

      // ── Gate 2: Max open trades
      if(m_openTrades >= m_maxOpenTrades)
        { r.reason = StringFormat("MaxTrades(%d/%d)", m_openTrades, m_maxOpenTrades); return r; }

      // ── Gate 3: Daily loss limit
      double bal = AccountBalance();
      if(bal > 0 && m_dailyLossPct > 0)
        {
         double dailyLossPct = (m_dailyLoss / bal) * 100.0;
         if(dailyLossPct <= -m_dailyLossPct)
           { r.reason = StringFormat("DailyLoss(%.1f%% >= %.1f%%)", -dailyLossPct, m_dailyLossPct); return r; }
        }

      // ── Gate 4: Max drawdown
      if(m_peakEquity > 0 && m_maxDDPct > 0)
        {
         double eq  = AccountEquity();
         double ddPct = (1.0 - eq / m_peakEquity) * 100.0;
         if(ddPct >= m_maxDDPct)
           { r.reason = StringFormat("MaxDD(%.1f%% >= %.1f%%)", ddPct, m_maxDDPct); return r; }
        }

      // ── Gate 5: Consecutive loss limit
      if(m_maxConsecLoss > 0 && m_consecLoss >= m_maxConsecLoss)
        { r.reason = StringFormat("ConsecLoss(%d >= %d)", m_consecLoss, m_maxConsecLoss); return r; }

      // ── Gate 6: Spread
      if(!SpreadOK())
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sp  = (ask-bid)/_Point;
         r.reason = StringFormat("SpreadTooWide(%.1f>%.1f pts)", sp, m_maxSpreadPts);
         return r;
        }

      // ── Lot calculation (only when slPoints provided)
      double lot = 0;
      if(slPoints > 0)
        {
         lot = CalcLot(slPoints);
         if(lot < m_minLot)
           { r.reason = StringFormat("LotBelowMin(%.4f<%.4f)", lot, m_minLot); return r; }

         // Free margin check: require 120% of margin for this lot
         double marginRequired = 0;
         if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot,
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK),
                             marginRequired))
            marginRequired = 0;  // if calc fails, skip margin gate

         if(marginRequired > 0 && AccountFreeMargin() < marginRequired * 1.2)
           { r.reason = StringFormat("InsufficientMargin(free=%.2f req=%.2f)",
                                      AccountFreeMargin(), marginRequired * 1.2);
             return r; }
        }

      r.allowed      = true;
      r.suggestedLot = lot;
      r.reason       = "OK";
      return r;
     }

   //+----------------------------------------------------------------+
   //| CalcLot — ATR fixed-fractional lot sizing                     |
   //| slPoints: stop-loss distance in points                        |
   //+----------------------------------------------------------------+
   double CalcLot(double slPoints) const
     {
      if(slPoints <= 0) return m_minLot;

      double balance    = AccountBalance();
      double riskAmount = balance * m_riskPct / 100.0;

      // Pip value per lot (currency normalised)
      double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0) return m_minLot;

      double pointValue = tickValue / (tickSize / _Point);  // value per 1 point per 1 lot
      if(pointValue <= 0) return m_minLot;

      double rawLot = riskAmount / (slPoints * pointValue);
      return NormaliseLot(rawLot);
     }

   //+----------------------------------------------------------------+
   //| OnTradeOpened — called by Orchestrator after successful order  |
   //+----------------------------------------------------------------+
   void OnTradeOpened()
     {
      m_openTrades++;
      if(m_debugMode)
         PrintFormat("[Risk] Trade opened. Open=%d", m_openTrades);
     }

   //+----------------------------------------------------------------+
   //| OnTradeClosed — called by Orchestrator on DEAL_ENTRY_OUT      |
   //+----------------------------------------------------------------+
   void OnTradeClosed(double profit = 0)
     {
      m_openTrades = MathMax(0, m_openTrades - 1);

      // Track consecutive losses
      if(profit < 0)
           m_consecLoss++;
      else m_consecLoss = 0;

      // Accumulate to daily tracker
      m_dailyLoss += profit;

      // Circuit breaker: trip on consecutive loss limit
      if(m_maxConsecLoss > 0 && m_consecLoss >= m_maxConsecLoss)
        {
         m_circuitBroken = true;
         PrintFormat("[Risk] CIRCUIT BREAKER TRIPPED: %d consecutive losses. Trading halted.",
                     m_consecLoss);
        }

      // Circuit breaker: trip on daily loss limit
      double bal = AccountBalance();
      if(bal > 0 && m_dailyLossPct > 0)
        {
         double dailyLossPct = (-m_dailyLoss / bal) * 100.0;
         if(dailyLossPct >= m_dailyLossPct)
           {
            m_circuitBroken = true;
            PrintFormat("[Risk] CIRCUIT BREAKER TRIPPED: daily loss %.1f%% >= limit %.1f%%.",
                        dailyLossPct, m_dailyLossPct);
           }
        }

      if(m_debugMode)
         PrintFormat("[Risk] Trade closed profit=%.2f. Open=%d consecLoss=%d dailyLoss=%.2f",
                     profit, m_openTrades, m_consecLoss, m_dailyLoss);
     }

   // Manual circuit reset (e.g. input button on dashboard)
   void ResetCircuit()
     {
      m_circuitBroken = false;
      m_consecLoss    = 0;
      Print("[Risk] Circuit breaker manually reset.");
     }

   // ── Status accessors
   bool   IsCircuitBroken()   const { return m_circuitBroken; }
   
   // ── Convenience method for backward compatibility (NEW v5.30)
   //     Returns true if trading is allowed (circuit breaker not triggered)
   //     Overload for multi-symbol support (NEW v6.10)
   bool   IsTradingAllowed()  const 
          { 
           // Quick check: if circuit is broken, trading is not allowed
           if(m_circuitBroken) return false;
           
           // Full check: use Check() with no SL to verify all gates
           RiskCheckResult result = Check(0);
           return result.allowed;
          }
   
   // ── Multi-symbol overload (NEW v6.10)
   //     Currently ignores symbol parameter (global risk checks only)
   //     Future versions may implement per-symbol risk counters
   bool   IsTradingAllowed(const string symbol)  const 
          { 
           // Symbol parameter accepted for API compatibility
           // Risk checks are currently global (account-wide)
           return IsTradingAllowed();
          }
   
   int    GetOpenTrades()     const { return m_openTrades;    }
   int    GetConsecLoss()     const { return m_consecLoss;    }
   double GetDailyLoss()      const { return m_dailyLoss;     }
   double GetDailyLossPct()   const
     {
      double b = AccountBalance();
      return (b > 0) ? (-m_dailyLoss / b * 100.0) : 0;
     }
   double GetDrawdownPct()    const
     {
      return (m_peakEquity>0) ? (1.0 - AccountEquity()/m_peakEquity)*100.0 : 0;
     }
  };

#endif // __TRADE_RISK_MANAGER_MQH__
