//+------------------------------------------------------------------+
//| Infra/PerformanceReport.mqh — v1.00                              |
//| Generates self-contained HTML performance report from journal.   |
//|                                                                  |
//| OUTPUT: PASR_Report_YYYYMMDD.html in MQL5/Files/Common/          |
//|         Fully offline, no CDN, dark-themed, responsive.          |
//|                                                                  |
//| SECTIONS:                                                        |
//|   1. Executive KPI cards (winRate, PF, avgRR, maxDD, trades)     |
//|   2. Equity curve — SVG sparkline from 30-day daily PnL          |
//|   3. Regime performance table                                     |
//|   4. Session performance table                                    |
//|   5. AI Score distribution (10-bucket histogram)                 |
//|   6. Last 50 trades table (color-coded WIN/LOSS rows)            |
//|                                                                  |
//| USAGE:                                                           |
//|   CPerformanceReport report;                                     |
//|   report.SetJournal(&journal);                                   |
//|   report.ExportHTML();  // call on demand or OnDeinit            |
//|                                                                  |
//| CHANGE LOG:                                                       |
//|   v1.00 (2026-05-21) — Phase 10 initial                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_PERFORMANCE_REPORT_MQH__
#define __INFRA_PERFORMANCE_REPORT_MQH__

#include "JournalManager.mqh"

//+------------------------------------------------------------------+
//| CPerformanceReport                                               |
//+------------------------------------------------------------------+
class CPerformanceReport
  {
private:
   CJournalManager *m_journal;  // non-owning
   string           m_filePrefix;

   string H(string tag, string cls, string content) const
     { return "<"+tag+(cls!=""?" class='"+cls+"'":"")+">"+content+"</"+tag+">"; }

   string TD(string v, string cls="") const { return H("td",cls,v); }
   string TH(string v) const               { return H("th","",v); }

   string FmtPct(double v) const  { return StringFormat("%.1f%%", v*100); }
   string FmtRR(double v)  const  { return StringFormat("%.2fR",  v); }
   string FmtCcy(double v) const  { return StringFormat("%.2f",   v); }
   string FmtInt(int v)    const  { return IntegerToString(v); }

   // Build SVG equity curve from daily PnL array
   string BuildEquitySVG(const double &daily[], int n) const
     {
      int W=500, H2=80;
      double cumMin=0, cumMax=0, cum=0;
      double cumArr[];
      ArrayResize(cumArr, n);
      for(int i=0;i<n;i++)
        { cum+=daily[i]; cumArr[i]=cum;
          if(cum<cumMin) cumMin=cum;
          if(cum>cumMax) cumMax=cum; }
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
      return StringFormat(
         "<svg viewBox='0 0 %d %d' width='100%%' height='%d' "
         "preserveAspectRatio='none'>"
         "<polyline points='%s' fill='none' stroke='%s' "
         "stroke-width='2' stroke-linejoin='round'/></svg>",
         W, H2, H2, pts, color);
     }

   // Build 10-bucket AI Score histogram bars
   string BuildAIHistogram() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      int buckets[10]; ArrayInitialize(buckets, 0);
      int n = m_journal.GetCount();
      for(int i=0;i<n;i++)
        {
         const JournalEntry *e = m_journal.GetEntry(i);
         if(e==NULL) continue;
         int b = (int)(e.aiScore * 10);
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
         bars += StringFormat(
            "<div class='hbar'>"
            "<div class='hlabel'>%s</div>"
            "<div class='hfill' style='width:%.0f%%'></div>"
            "<div class='hval'>%d</div></div>",
            label, pct, buckets[i]);
        }
      return bars;
     }

   // Regime performance rows
   string BuildRegimeRows() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      string rows="";
      ENUM_MARKET_REGIME regimes[4] =
        { REGIME_TRENDING, REGIME_RANGING, REGIME_VOLATILE, REGIME_QUIET };
      string regNames[4] = { "Trending", "Ranging", "Volatile", "Quiet" };
      for(int i=0;i<4;i++)
        {
         TradeStat s = m_journal.GetStatsByRegime(regimes[i]);
         if(s.totalTrades == 0) continue;
         string cls = (s.winRate >= 0.5) ? "win" : "loss";
         rows += "<tr>"
              + TD(regNames[i])
              + TD(FmtInt(s.totalTrades))
              + TD(FmtPct(s.winRate), cls)
              + TD(FmtRR(s.avgRR))
              + TD(FmtRR(s.profitFactor))
              + TD(FmtCcy(s.totalPnL), cls)
              + "</tr>";
        }
      return rows;
     }

   // Session performance rows
   string BuildSessionRows() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      string rows="";
      ENUM_TRADING_SESSION sessions[4] =
        { SESSION_ASIAN, SESSION_LONDON, SESSION_NEWYORK, SESSION_OVERLAP };
      string sesNames[4] = { "Asian", "London", "New York", "Overlap" };
      for(int i=0;i<4;i++)
        {
         TradeStat s = m_journal.GetStatsBySession(sessions[i]);
         if(s.totalTrades == 0) continue;
         string cls = (s.winRate >= 0.5) ? "win" : "loss";
         rows += "<tr>"
              + TD(sesNames[i])
              + TD(FmtInt(s.totalTrades))
              + TD(FmtPct(s.winRate), cls)
              + TD(FmtRR(s.avgRR))
              + TD(StringFormat("%.2f", s.avgAIScore))
              + TD(FmtCcy(s.totalPnL), cls)
              + "</tr>";
        }
      return rows;
     }

   // Last 50 trade rows
   string BuildTradeRows() const
     {
      if(CheckPointer(m_journal)==POINTER_INVALID) return "";
      string rows="";
      int n = MathMin(50, m_journal.GetCount());
      for(int i=0;i<n;i++)
        {
         const JournalEntry *e = m_journal.GetEntry(i);
         if(e==NULL) continue;
         string cls = e.isWin ? "win" : "loss";
         string dir = (e.direction==SIGNAL_BUY) ? "▲ BUY" : "▼ SELL";
         string flags = (e.beDone?"BE ":"")
                      + (e.partialDone?"PC ":"")
                      + (e.runnerActive?"RUN":"");
         rows += "<tr class='" + cls + "'>"
              + TD(TimeToString(e.timeOpen, TIME_DATE|TIME_MINUTES))
              + TD(dir)
              + TD(DoubleToString(e.entry,5))
              + TD(DoubleToString(e.closePrice,5))
              + TD(FmtCcy(e.pnl), cls)
              + TD(FmtRR(e.rr))
              + TD(StringFormat("%.2f", e.aiScore))
              + TD(flags)
              + "</tr>";
        }
      return rows;
     }

public:
   CPerformanceReport() : m_journal(NULL), m_filePrefix("PASR_Report") {}

   void SetJournal(CJournalManager *j) { m_journal = j; }
   void SetFilePrefix(string s)        { m_filePrefix = s; }

   //+----------------------------------------------------------------+
   //| ExportHTML — generate and write the HTML report                |
   //+----------------------------------------------------------------+
   bool ExportHTML() const
     {
      if(CheckPointer(m_journal) == POINTER_INVALID)
        { Print("[Report] No journal set"); return false; }

      TradeStat overall = m_journal.GetStats();
      double dailyPnL[];
      m_journal.GetDailyPnL(dailyPnL);
      string svgCurve = BuildEquitySVG(dailyPnL, JOURNAL_DAILY_SIZE);

      // ── CSS ───────────────────────────────────────────────────────
      string css = ""
        "*{box-sizing:border-box;margin:0;padding:0}"
        "body{background:#0f0f13;color:#d4d4d8;font:14px/1.6 'Consolas',monospace;padding:24px}"
        "h1{font-size:20px;color:#e4e4e7;margin-bottom:16px}"
        "h2{font-size:14px;color:#a1a1aa;text-transform:uppercase;letter-spacing:.08em;"
           "margin:28px 0 10px;border-bottom:1px solid #27272a;padding-bottom:4px}"
        ".kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-bottom:16px}"
        ".kpi{background:#18181b;border:1px solid #27272a;border-radius:8px;padding:14px 16px}"
        ".kpi-label{font-size:11px;color:#71717a;margin-bottom:4px}"
        ".kpi-val{font-size:22px;font-weight:700;color:#e4e4e7}"
        ".kpi-val.green{color:#4ade80}.kpi-val.red{color:#f87171}"
        ".equity-box{background:#18181b;border:1px solid #27272a;border-radius:8px;"
           "padding:14px;margin-bottom:8px}"
        "table{width:100%;border-collapse:collapse;margin-bottom:8px}"
        "th{background:#18181b;color:#71717a;font-size:11px;text-transform:uppercase;"
           "padding:8px 10px;text-align:left;border-bottom:1px solid #27272a}"
        "td{padding:7px 10px;border-bottom:1px solid #1e1e24;font-size:13px}"
        "tr.win td{background:#052e16;} tr.loss td{background:#2d0a0a}"
        "td.win{color:#4ade80;font-weight:600} td.loss{color:#f87171;font-weight:600}"
        ".hbar{display:flex;align-items:center;gap:8px;margin:3px 0}"
        ".hlabel{width:70px;font-size:11px;color:#71717a;flex-shrink:0}"
        ".hfill{height:14px;background:#4f46e5;border-radius:2px;min-width:2px}"
        ".hval{font-size:11px;color:#a1a1aa}";

      // ── HTML body ────────────────────────────────────────────────
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      string ts = StringFormat("%04d-%02d-%02d %02d:%02d",
                               dt.year,dt.mon,dt.day,dt.hour,dt.min);
      string body = "";
      body += "<h1>PASR EA — Performance Report <small style='font-size:13px;color:#71717a'>" + ts + "</small></h1>";

      // KPI cards
      string wr_cls   = (overall.winRate >= 0.5)     ? "green" : "red";
      string pnl_cls  = (overall.totalPnL >= 0)      ? "green" : "red";
      string pf_cls   = (overall.profitFactor >= 1.0)? "green" : "red";
      body += "<div class='kpis'>";
      body += "<div class='kpi'><div class='kpi-label'>Win Rate</div><div class='kpi-val "+wr_cls+"'>"+FmtPct(overall.winRate)+"</div></div>";
      body += "<div class='kpi'><div class='kpi-label'>Profit Factor</div><div class='kpi-val "+pf_cls+"'>"+StringFormat("%.2f",overall.profitFactor)+"</div></div>";
      body += "<div class='kpi'><div class='kpi-label'>Avg RR</div><div class='kpi-val'>"+FmtRR(overall.avgRR)+"</div></div>";
      body += "<div class='kpi'><div class='kpi-label'>Max DD</div><div class='kpi-val red'>"+FmtCcy(overall.maxDrawdown)+"</div></div>";
      body += "<div class='kpi'><div class='kpi-label'>Total Trades</div><div class='kpi-val'>"+FmtInt(overall.totalTrades)+"</div></div>";
      body += "<div class='kpi'><div class='kpi-label'>Net PnL</div><div class='kpi-val "+pnl_cls+"'>"+FmtCcy(overall.totalPnL)+"</div></div>";
      body += "<div class='kpi'><div class='kpi-label'>Avg AI Score</div><div class='kpi-val'>"+StringFormat("%.2f",overall.avgAIScore)+"</div></div>";
      body += "<div class='kpi'><div class='kpi-label'>Max Consec Loss</div><div class='kpi-val red'>"+FmtInt(overall.maxConsecLoss)+"</div></div>";
      body += "</div>";

      // Equity curve
      body += "<h2>Equity Curve (30 days)</h2>";
      body += "<div class='equity-box'>" + svgCurve + "</div>";

      // Regime table
      body += "<h2>Performance by Regime</h2>";
      body += "<table><tr>"+TH("Regime")+TH("Trades")+TH("Win%")+TH("Avg RR")+TH("Prof.F")+TH("PnL")+"</tr>";
      body += BuildRegimeRows();
      body += "</table>";

      // Session table
      body += "<h2>Performance by Session</h2>";
      body += "<table><tr>"+TH("Session")+TH("Trades")+TH("Win%")+TH("Avg RR")+TH("Avg AI")+TH("PnL")+"</tr>";
      body += BuildSessionRows();
      body += "</table>";

      // AI Score histogram
      body += "<h2>AI Score Distribution</h2>";
      body += "<div>" + BuildAIHistogram() + "</div>";

      // Last 50 trades
      body += "<h2>Last 50 Trades</h2>";
      body += "<table><tr>"
           + TH("Time") + TH("Dir") + TH("Entry")
           + TH("Close") + TH("PnL") + TH("RR")
           + TH("AI") + TH("Flags") + "</tr>";
      body += BuildTradeRows();
      body += "</table>";

      // ── Assemble ─────────────────────────────────────────────────
      string html = "<!DOCTYPE html><html lang='en'><head>"
                  + "<meta charset='UTF-8'>"
                  + "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                  + "<title>PASR Report " + ts + "</title>"
                  + "<style>" + css + "</style>"
                  + "</head><body>"
                  + body
                  + "</body></html>";

      // ── Write file ───────────────────────────────────────────────
      string fn = StringFormat("%s_%04d%02d%02d.html",
                               m_filePrefix, dt.year, dt.mon, dt.day);
      int h = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h == INVALID_HANDLE)
        { PrintFormat("[Report] File open failed: %d", GetLastError()); return false; }
      FileWriteString(h, html);
      FileClose(h);
      PrintFormat("[Report] Exported: %s (%d bytes)", fn, StringLen(html));
      return true;
     }
  };

#endif // __INFRA_PERFORMANCE_REPORT_MQH__
