//+------------------------------------------------------------------+
//| Infra/PerformanceReport.mqh — v1.03                              |
//| Minimal compile-safe HTML performance report.                    |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_PERFORMANCE_REPORT_MQH__
#define __INFRA_PERFORMANCE_REPORT_MQH__

#include "JournalManager.mqh"

class CPerformanceReport
  {
private:
   CJournalManager *m_journal;
   string           m_filePrefix;

   string TD(string value) const
     {
      return "<td>" + value + "</td>";
     }

   string FmtPct(double v) const
     {
      return StringFormat("%.1f%%", v * 100.0);
     }

   string FmtRR(double v) const
     {
      return StringFormat("%.2fR", v);
     }

   string FmtCcy(double v) const
     {
      return StringFormat("%.2f", v);
     }

   string BuildRegimeRows() const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID) return "";
      string rows = "";
      EMarketRegime regimes[6];
      regimes[0] = REGIME_TREND_UP;
      regimes[1] = REGIME_TREND_DOWN;
      regimes[2] = REGIME_RANGE;
      regimes[3] = REGIME_VOLATILE;
      regimes[4] = REGIME_SQUEEZE;
      regimes[5] = REGIME_TRANSITION;

      for(int i = 0; i < 6; i++)
        {
         TradeStat s = m_journal.GetStatsByRegime(regimes[i]);
         if(s.totalTrades == 0) continue;
         rows += "<tr>";
         rows += TD(MarketRegimeName(regimes[i]));
         rows += TD(IntegerToString(s.totalTrades));
         rows += TD(FmtPct(s.winRate));
         rows += TD(FmtRR(s.avgRR));
         rows += TD(FmtCcy(s.totalPnL));
         rows += "</tr>";
        }
      return rows;
     }

   string BuildSessionRows() const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID) return "";
      string rows = "";
      ENUM_TRADING_SESSION sessions[5];
      string names[5];
      sessions[0] = SESSION_TOKYO;    names[0] = "Tokyo";
      sessions[1] = SESSION_LONDON;   names[1] = "London";
      sessions[2] = SESSION_NEW_YORK; names[2] = "NewYork";
      sessions[3] = SESSION_OVERLAP;  names[3] = "Overlap";
      sessions[4] = SESSION_SYDNEY;   names[4] = "Sydney";

      for(int i = 0; i < 5; i++)
        {
         TradeStat s = m_journal.GetStatsBySession(sessions[i]);
         if(s.totalTrades == 0) continue;
         rows += "<tr>";
         rows += TD(names[i]);
         rows += TD(IntegerToString(s.totalTrades));
         rows += TD(FmtPct(s.winRate));
         rows += TD(FmtRR(s.avgRR));
         rows += TD(FmtCcy(s.totalPnL));
         rows += "</tr>";
        }
      return rows;
     }

   string BuildTradeRows() const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID) return "";
      string rows = "";
      int n = MathMin(50, m_journal.GetCount());
      for(int i = 0; i < n; i++)
        {
         JournalEntry e;
         if(!m_journal.GetEntry(i, e)) continue;
         string dir = "NONE";
         if(e.direction == SIGNAL_BUY) dir = "BUY";
         else if(e.direction == SIGNAL_SELL) dir = "SELL";
         rows += "<tr>";
         rows += TD(TimeToString(e.timeClose, TIME_DATE|TIME_MINUTES));
         rows += TD(dir);
         rows += TD(FmtCcy(e.pnl));
         rows += TD(FmtRR(e.rr));
         rows += TD(DoubleToString(e.aiScore, 2));
         rows += "</tr>";
        }
      return rows;
     }

public:
   CPerformanceReport() : m_journal(NULL), m_filePrefix("PASR_Report") {}

   void SetJournal(CJournalManager *j) { m_journal = j; }
   void SetFilePrefix(string s) { if(s != "") m_filePrefix = s; }

   bool ExportHTML() const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID)
        {
         Print("[Report] No journal set");
         return false;
        }

      TradeStat overall = m_journal.GetStats();
      string html = "<html><head><meta charset='utf-8'><title>PASR Report</title></head><body>";
      html += "<h1>PASR Performance Report</h1>";
      html += "<h2>Overview</h2>";
      html += "<p>Total trades: " + IntegerToString(overall.totalTrades) + "</p>";
      html += "<p>Win rate: " + FmtPct(overall.winRate) + "</p>";
      html += "<p>Total PnL: " + FmtCcy(overall.totalPnL) + "</p>";
      html += "<h2>By Regime</h2><table>" + BuildRegimeRows() + "</table>";
      html += "<h2>By Session</h2><table>" + BuildSessionRows() + "</table>";
      html += "<h2>Recent Trades</h2><table>" + BuildTradeRows() + "</table>";
      html += "</body></html>";

      string fn = m_filePrefix + "_report.html";
      int h = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         Print("[Report] Failed to open report file: ", GetLastError());
         return false;
        }
      FileWriteString(h, html);
      FileClose(h);
      Print("[Report] Exported: ", fn);
      return true;
     }
  };

#endif // __INFRA_PERFORMANCE_REPORT_MQH__
