//+------------------------------------------------------------------+
//|                                              PerformanceTracker.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Performance Statistics Tracking Module                |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __PERFORMANCE_TRACKER_MQH__
#define __PERFORMANCE_TRACKER_MQH__

#include "2.Config.mqh"

//+------------------------------------------------------------------+
//| Performance statistics with multiple time windows                |
//+------------------------------------------------------------------+
struct PerformanceWindow
{
   datetime startTime;
   datetime endTime;
   int totalTrades;
   int wins;
   int losses;
   double grossProfit;
   double grossLoss;
   double netProfit;
   double maxDrawdown;
   double peakEquity;
   
   void Reset()
   {
      ZeroMemory(this);
      startTime = TimeCurrent();
   }
   
   double WinRate() const
   {
      return (totalTrades > 0) ? (double)wins / totalTrades * 100.0 : 0.0;
   }
   
   double ProfitFactor() const
   {
      if (MathAbs(grossLoss) < _Point) return (grossProfit > 0) ? 999.99 : 0.0;
      return grossProfit / MathAbs(grossLoss);
   }
   
   double AvgWin() const
   {
      return (wins > 0) ? grossProfit / wins : 0.0;
   }
   
   double AvgLoss() const
   {
      return (losses > 0) ? MathAbs(grossLoss) / losses : 0.0;
   }
};

//+------------------------------------------------------------------+
//| Multi-window Performance Tracker                                 |
//+------------------------------------------------------------------+
class PerformanceTracker
{
private:
   PerformanceWindow m_lifetime;    // All-time stats
   PerformanceWindow m_session;     // Current session (MT4/5 restart)
   PerformanceWindow m_rolling7d;   // Last 7 days rolling window
   PerformanceWindow m_rolling30d;  // Last 30 days rolling window
   
   datetime m_lastUpdate;
   ulong m_magicNumber;
   string m_symbol;
   
   // Trade history cache for rolling windows
   struct TradeRecord
   {
      datetime time;
      double profit;
      bool isWin;
      string comment;
   };
   
   TradeRecord m_tradeHistory[];
   int m_maxHistoryDays;

public:
   PerformanceTracker() : m_lastUpdate(0), m_magicNumber(0), m_maxHistoryDays(30)
   {
      ArraySetAsSeries(m_tradeHistory, true);
      ResetAll();
   }
   
   ~PerformanceTracker()
   {
      ArrayFree(m_tradeHistory);
   }
   
   void Initialize(ulong magic, const string symbol)
   {
      m_magicNumber = magic;
      m_symbol = symbol;
      m_session.Reset();
      LoadTradeHistory();
   }
   
   void ResetAll()
   {
      m_lifetime.Reset();
      m_session.Reset();
      m_rolling7d.Reset();
      m_rolling30d.Reset();
      m_lastUpdate = TimeCurrent();
   }
   
   void UpdateFromHistory()
   {
      if (!HistorySelect(0, TimeCurrent()))
         return;
      
      int total = HistoryDealsTotal();
      for (int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket <= 0) continue;
         
         if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magicNumber)
            continue;
         if (HistoryDealGetString(ticket, DEAL_SYMBOL) != m_symbol)
            continue;
         if (HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;
         
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION) + 
                        HistoryDealGetDouble(ticket, DEAL_SWAP);
         string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
         
         // Check if already processed
         bool alreadyProcessed = false;
         for (int j = 0; j < ArraySize(m_tradeHistory); j++)
         {
            if (m_tradeHistory[j].time == dealTime && 
                MathAbs(m_tradeHistory[j].profit - profit) < _Point)
            {
               alreadyProcessed = true;
               break;
            }
         }
         
         if (alreadyProcessed) continue;
         
         // Add to history
         int idx = ArraySize(m_tradeHistory);
         ArrayResize(m_tradeHistory, idx + 1);
         m_tradeHistory[idx].time = dealTime;
         m_tradeHistory[idx].profit = profit;
         m_tradeHistory[idx].isWin = (profit > 0);
         m_tradeHistory[idx].comment = comment;
         
         // Update all windows
         UpdateWindows(dealTime, profit, comment);
      }
      
      m_lastUpdate = TimeCurrent();
      CleanupOldHistory();
   }
   
   void UpdateWindows(datetime time, double profit, const string comment)
   {
      // Lifetime stats
      m_lifetime.totalTrades++;
      m_lifetime.netProfit += profit;
      if (profit > 0)
      {
         m_lifetime.wins++;
         m_lifetime.grossProfit += profit;
      }
      else
      {
         m_lifetime.losses++;
         m_lifetime.grossLoss += profit;
      }
      
      // Session stats (since last reset)
      if (time >= m_session.startTime)
      {
         m_session.totalTrades++;
         m_session.netProfit += profit;
         if (profit > 0)
         {
            m_session.wins++;
            m_session.grossProfit += profit;
         }
         else
         {
            m_session.losses++;
            m_session.grossLoss += profit;
         }
      }
      
      // Rolling 7-day stats
      datetime cutoff7d = TimeCurrent() - (7 * 86400);
      if (time >= cutoff7d)
      {
         m_rolling7d.totalTrades++;
         m_rolling7d.netProfit += profit;
         if (profit > 0)
         {
            m_rolling7d.wins++;
            m_rolling7d.grossProfit += profit;
         }
         else
         {
            m_rolling7d.losses++;
            m_rolling7d.grossLoss += profit;
         }
      }
      
      // Rolling 30-day stats
      datetime cutoff30d = TimeCurrent() - (30 * 86400);
      if (time >= cutoff30d)
      {
         m_rolling30d.totalTrades++;
         m_rolling30d.netProfit += profit;
         if (profit > 0)
         {
            m_rolling30d.wins++;
            m_rolling30d.grossProfit += profit;
         }
         else
         {
            m_rolling30d.losses++;
            m_rolling30d.grossLoss += profit;
         }
      }
   }
   
   void CleanupOldHistory()
   {
      datetime cutoff = TimeCurrent() - (m_maxHistoryDays * 86400);
      int newSize = 0;
      for (int i = 0; i < ArraySize(m_tradeHistory); i++)
      {
         if (m_tradeHistory[i].time >= cutoff)
            newSize++;
      }
      
      if (newSize < ArraySize(m_tradeHistory))
      {
         TradeRecord temp[];
         ArrayCopy(temp, m_tradeHistory, 0, 0, newSize);
         ArrayFree(m_tradeHistory);
         ArrayCopy(m_tradeHistory, temp);
         ArrayFree(temp);
      }
   }
   
   void LoadTradeHistory()
   {
      ArrayFree(m_tradeHistory);
      datetime startTime = TimeCurrent() - (m_maxHistoryDays * 86400);
      
      if (!HistorySelect(startTime, TimeCurrent()))
         return;
      
      int total = HistoryDealsTotal();
      for (int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket <= 0) continue;
         
         if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magicNumber)
            continue;
         if (HistoryDealGetString(ticket, DEAL_SYMBOL) != m_symbol)
            continue;
         if (HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;
         
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION) + 
                        HistoryDealGetDouble(ticket, DEAL_SWAP);
         string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
         
         int idx = ArraySize(m_tradeHistory);
         ArrayResize(m_tradeHistory, idx + 1);
         m_tradeHistory[idx].time = dealTime;
         m_tradeHistory[idx].profit = profit;
         m_tradeHistory[idx].isWin = (profit > 0);
         m_tradeHistory[idx].comment = comment;
      }
      
      // Recalculate all windows from loaded history
      RecalculateAllWindows();
   }
   
   void RecalculateAllWindows()
   {
      // Reset all windows
      m_lifetime.Reset();
      m_session.Reset();
      m_rolling7d.Reset();
      m_rolling30d.Reset();
      
      // Replay all trades
      for (int i = 0; i < ArraySize(m_tradeHistory); i++)
      {
         UpdateWindows(m_tradeHistory[i].time, m_tradeHistory[i].profit, m_tradeHistory[i].comment);
      }
   }
   
   // Getters for different time windows
   PerformanceWindow GetLifetime() const { return m_lifetime; }
   PerformanceWindow GetSession() const { return m_session; }
   PerformanceWindow GetRolling7D() const { return m_rolling7d; }
   PerformanceWindow GetRolling30D() const { return m_rolling30d; }
   
   // Convenience methods
   int GetTotalTrades() const { return m_lifetime.totalTrades; }
   double GetNetProfit() const { return m_lifetime.netProfit; }
   double GetWinRate() const { return m_lifetime.WinRate(); }
   double GetProfitFactor() const { return m_lifetime.ProfitFactor(); }
   
   datetime GetLastUpdate() const { return m_lastUpdate; }
   
   void PrintStats()
   {
      Print("=== PERFORMANCE STATISTICS ===");
      Print("Lifetime: ", m_lifetime.totalTrades, " trades, Win Rate: ", DoubleToString(m_lifetime.WinRate(), 2), 
            "%, Net: ", DoubleToString(m_lifetime.netProfit, 2), 
            ", PF: ", DoubleToString(m_lifetime.ProfitFactor(), 2));
      Print("Session: ", m_session.totalTrades, " trades, Net: ", DoubleToString(m_session.netProfit, 2));
      Print("7-Day Rolling: ", m_rolling7d.totalTrades, " trades, Win Rate: ", DoubleToString(m_rolling7d.WinRate(), 2), 
            "%, Net: ", DoubleToString(m_rolling7d.netProfit, 2));
      Print("30-Day Rolling: ", m_rolling30d.totalTrades, " trades, Net: ", DoubleToString(m_rolling30d.netProfit, 2));
      Print("==============================");
   }
};

#endif
