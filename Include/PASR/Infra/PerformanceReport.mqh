//+------------------------------------------------------------------+
//| Infra/PerformanceReport.mqh — v1.02                              |
//| Generates self-contained HTML performance report from journal.   |
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

   string H(string tag, string cls, string content) const
     { return "<"+tag+(cls!=""?" class='"+cls+"'":"")+">"+content+"</"+tag+">"; }

   string TD(string v, string cls="") const { return H("td",cls,v); }
   string TH(string v) const               { return H("th","",v); }
   string FmtPct(double v) const           { return StringFormat("%.1f%%", v*100); }
   string FmtRR(double v)  const           { return StringFormat("%.2fR",  v); }
   string FmtCcy(double v) const           { return StringFormat("%.2f",   v); }
   string FmtInt(int v)    const           { return IntegerToString(v); }

   string BuildEquitySVG(double &daily[], int n) const
     {
      if(n <= 1) return "";
      int W=500, H2=80;
      double cumMin=0, cumMax=0, cum=0;
      double cumArr[];
      ArrayResize(cumArr, n);
      for(int i=0;i<n;i++)
        {
         cum+=daily[i];
         cumArr[i]=cum;
         if(cum<cumMin) cumMin=cum;
         if(cum>cumMax) cumMax=cum;
        }
      double rng = cumMax-cumMin;
      if(rng==0) rng=1;
      string pts="";
      for(int i=0;i<n;i++)
        {
         double x = (double)i/(n-1)*W;
         double y = H2 - ((cumArr[i]-cumMin)/rng)*(H2-4);
         pts += StringFormat("%.1f,%.1f ", x, y);
        }
      string color = (cum >= 0) ? "#4ade80" : "#f87171";
      return StringFormat("<svg viewBox='0 0 %d %d' width='100%%' height='%d' preserveAspectRatio='none'><polyline points='%s' fill='none' stroke='%s' stroke-width='2' stroke-linejoin='round'/></svg>",
                          W, H2, H2, pts, color);
     }

   string BuildAIHistogram() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      int buckets[10]; ArrayInitialize(buckets, 0);
      int n = m_journal.GetCount();
      for(int i=0;i<n;i++)
        {
         JournalEntry e;
         if(!m_journal.GetEntry(i, e)) continue;
         int b = (int)(e.aiScore * 10);
         if(b<0) b=0;
         if(b>9) b=9;
         buckets[b]++;
        }
      int maxB=1;
      for(int i=0;i<10;i++) if(buckets[i]>maxB) maxB=buckets[i];
      string bars="";
      for(int i=0;i<10;i++)
        {
         double pct = (double)buckets[i]/maxB*100;
         string label = StringFormat("%.1f-%.1f", i*0.1, (i+1)*0.1);
         bars += StringFormat("<div class='hbar'><div class='hlabel'>%s</div><div class='hfill' style='width:%.0f%%'></div><div class='hval'>%d</div></div>",
                              label, pct, buckets[i]);
        }
      return bars;
     }

   string BuildRegimeRows() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      string rows="";
      EMarketRegime regimes[6] = { REGIME_TREND_UP, REGIME_TREND_DOWN, REGIME_RANGE, REGIME_VOLATILE, REGIME_SQUEEZE, REGIME_TRANSITION };
      for(int i=0;i<6;i++)
        {
         TradeStat s = m_journal.GetStatsByRegime(regimes[i]);
         if(s.totalTrades == 0) continue;
         string cls = (s.winRate >= 0.5) ? "win" : "loss";
         rows += "<tr>" + TD(MarketRegimeName(regimes[i])) + TD(FmtInt(s.totalTrades)) +
                 TD(FmtPct(s.winRate), cls) + TD(FmtRR(s.avgRR)) +
                 TD(StringFormat("%.2f", s.profitFactor)) + TD(FmtCcy(s.totalPnL), cls) + "</tr>";
        }
      return rows;
     }

   string BuildSessionRows() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      string rows="";
      ENUM_TRADING_SESSION sessions[5] = { SESSION_TOKYO, SESSION_LONDON, SESSION_NEW_YORK, SESSION_OVERLAP, SESSION_SYDNEY };
      string sesNames[5] = { "Tokyo", "London", "New York", "Overlap", "Sydney" };
      for(int i=0;i<5;i++)
        {
         TradeStat s = m_journal.GetStatsBySession(sessions[i]);
         if(s.totalTrades == 0) continue;
         string cls = (s.winRate >= 0.5) ? "win" : "loss";
         rows += "<tr>" + TD(sesNames[i]) + TD(FmtInt(s.totalTrades)) +
                 TD(FmtPct(s.winRate), cls) + TD(FmtRR(s.avgRR)) +
                 TD(StringFormat("%.2f", s.avgAIScore)) + TD(FmtCcy(s.totalPnL), cls) + "</tr>";
        }
      return rows;
     }

   string BuildTradeRows() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      string rows="";
      int n = MathMin(50, m_journal.GetCount());
      for(int i=0;i<n;i++)
        {
         JournalEntry e;
         if(!m_journal.GetEntry(i, e)) continue;
         string cls = e.isWin ? "win" : "loss";
         string dir = (e.direction==SIGNAL_BUY) ? "BUY" : (e.direction==SIGNAL_SELL ? "SELL" : "NONE");
         string flags = (e.beDone?"BE ":"") + (e.partialDone?"PC ":"") + (e.runnerActive?"RUN":"");
         rows += "<tr class='" + cls + "'>" + TD(TimeToString(e.timeOpen, TIME_DATE|TIME_MINUTES)) +
                 TD(dir) + TD(DoubleToString(e.entry,5)) + TD(DoubleToString(e.closePrice,5)) +
                 TD(FmtCcy(e.pnl), cls) + TD(FmtRR(e.rr)) + TD(StringFormat("%.2f", e.aiScore)) + TD(flags) + "</tr>";
        }
      return rows;
     }

public:
   CPerformanceReport() : m_journal(NULL), m_filePrefix("PASR_Report") {}

   void SetJournal(CJournalManager *j) { m_journal = j; }
   void SetFilePrefix(string s)        { if(s != "") m_filePrefix = s; }

   bool ExportHTML() const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID)
        {
         Print("[Report] No journal set");
         return false;
        }

      TradeStat overall = m_journal.GetStats();
      double dailyPnL[];
      m_journal.GetDailyPnL(dailyPnL);
      string svgCurve = BuildEquitySVG(dailyPnL, JOURNAL_DAILY_SIZE);

      string html = "<html><head><meta charset='utf-8'><title>PASR Report</title></head><body>";
      html += "<h1>PASR Performance Report</h1>";
      html += "<h2>Overview</h2>";
      html += "<p>Total trades: " + IntegerToString(overall.totalTrades) + "</p>";
      html += "<p>Win rate: " + FmtPct(overall.winRate) + "</p>";
      html += "<p>Total PnL: " + FmtCcy(overall.totalPnL) + "</p>";
      html += "<h2>Equity</h2>" + svgCurve;
      html += "<h2>AI Score Histogram</h2>" + BuildAIHistogram();
      html += "<h2>By Regime</h2><table>" + BuildRegimeRows() + "</table>";
      html += "<h2>By Session</h2><table>" + BuildSessionRows() + "</table>";
      html += "<h2>Recent Trades</h2><table>" + BuildTradeRows() + "</table>";
      html += "</body></html>";

      string fn = m_filePrefix + "_" + TimeToString(TimeCurrent(), TIME_DATE) + ".html";
      StringReplace(fn, ".", "");
      StringReplace(fn, ":", "");
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
