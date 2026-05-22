//+------------------------------------------------------------------+
//| Infra/JournalManager.mqh — v1.00                                 |
//| Per-trade CSV journal + in-memory performance analytics.         |
//|                                                                  |
//| RESPONSIBILITIES:                                                |
//|   • Log every closed trade to monthly CSV file                   |
//|   • In-memory ring buffer (500 entries) for fast stats           |
//|   • Aggregate stats: winRate, avgRR, PF, maxDD, streaks          |
//|   • Breakdown by regime and session                              |
//|   • Daily PnL tracker with midnight reset                        |
//|                                                                  |
//| CSV COLUMNS:                                                     |
//|   ticket, time_open, time_close, symbol, direction,              |
//|   entry, sl, tp1, tp2, close_price, pnl, rr, lots,              |
//|   duration_min, regime, session, ai_score, drift,               |
//|   ensemble_model, be_done, partial_done, runner_active,          |
//|   f00..f25 (26 feature dims)                                     |
//|                                                                  |
//| USAGE:                                                           |
//|   OnPositionClosed() — call from Orchestrator/OnTradeTransaction  |
//|   GetStats()         — aggregate TradeStat                       |
//|   GetDailyPnL()      — array of last 30 daily PnL values         |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 10 initial                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_JOURNAL_MANAGER_MQH__
#define __INFRA_JOURNAL_MANAGER_MQH__

#include "AdaptiveConfig.mqh"
#include "../Signal/AI/AITypes.mqh"
#include "../Signal/AI/AIFeatureBuilder.mqh"
#include "../Trade/TradePlan.mqh"

#define JOURNAL_BUF_SIZE   500
#define JOURNAL_DAILY_SIZE  30

//+------------------------------------------------------------------+
//| JournalEntry — one closed trade record                           |
//+------------------------------------------------------------------+
struct JournalEntry
  {
   // Identity
   ulong    ticket;
   datetime timeOpen;
   datetime timeClose;
   string   symbol;
   // Trade geometry
   ENUM_SIGNAL_DIR direction;
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   closePrice;
   double   lots;
   // Outcome
   double   pnl;           // in account currency
   double   rr;            // actual R:R (pnl / initial risk per lot)
   int      durationMin;
   bool     isWin;
   // Context at open
   ENUM_MARKET_REGIME  regime;
   ENUM_TRADING_SESSION session;
   double   aiScore;
   double   driftScore;
   int      ensembleModel; // 0=Trend 1=MeanRev 2=Momentum
   // Phase flags
   bool     beDone;
   bool     partialDone;
   bool     runnerActive;
   // Feature snapshot (18 dims)
   double   features[AI_FEATURE_DIM];
  };

//+------------------------------------------------------------------+
//| TradeStat — aggregated performance metrics                       |
//+------------------------------------------------------------------+
struct TradeStat
  {
   int    totalTrades;
   int    wins;
   int    losses;
   double winRate;         // [0,1]
   double avgRR;
   double avgWinRR;
   double avgLossRR;
   double profitFactor;    // gross profit / gross loss
   double totalPnL;
   double maxDrawdown;     // peak-to-trough in currency
   int    maxConsecLoss;
   int    maxConsecWin;
   double avgAIScore;
   double avgDuration;     // minutes
  };

//+------------------------------------------------------------------+
//| CJournalManager                                                  |
//+------------------------------------------------------------------+
class CJournalManager
  {
private:
   JournalEntry m_buf[JOURNAL_BUF_SIZE];
   int          m_head;        // ring buffer write pointer
   int          m_count;       // entries written (capped at JOURNAL_BUF_SIZE)
   int          m_totalTrades; // lifetime trade count

   // Daily PnL ring buffer
   double   m_dailyPnL[JOURNAL_DAILY_SIZE];
   int      m_dailyHead;
   double   m_todayPnL;
   datetime m_todayDate;

   // Equity tracking
   double   m_peakEquity;
   double   m_maxDrawdown;

   // CSV file
   string   m_csvPrefix;  // default "PASR_Journal"
   bool     m_csvEnabled;

   string CSVFilename() const
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return StringFormat("%s_%04d%02d.csv",
                          m_csvPrefix, dt.year, dt.mon);
     }

   void WriteCsvHeader(int h) const
     {
      FileWrite(h,
        "ticket","time_open","time_close","symbol","direction",
        "entry","sl","tp1","tp2","close_price","pnl","rr","lots",
        "duration_min","regime","session","ai_score","drift",
        "ensemble_model","be_done","partial_done","runner_active",
        "f00","f01","f02","f03","f04","f05","f06","f07",
        "f08","f09","f10","f11","f12","f13","f14","f15","f16","f17",
        "f18","f19","f20","f21","f22","f23","f24","f25");
     }

   void AppendCSVRow(int h, const JournalEntry &e) const
     {
      string dir = (e.direction == SIGNAL_BUY) ? "BUY" : "SELL";
      string regStr;
      switch(e.regime)
        {
         case REGIME_TRENDING:  regStr="Trending";  break;
         case REGIME_RANGING:   regStr="Ranging";   break;
         case REGIME_VOLATILE:  regStr="Volatile";  break;
         case REGIME_QUIET:     regStr="Quiet";     break;
         default:               regStr="Unknown";   break;
        }
      string sesStr;
      switch(e.session)
        {
         case SESSION_ASIAN:   sesStr="Asian";   break;
         case SESSION_LONDON:  sesStr="London";  break;
         case SESSION_NEWYORK: sesStr="NewYork"; break;
         case SESSION_OVERLAP: sesStr="Overlap"; break;
         default:              sesStr="Off";     break;
        }
      string emStr;
      switch(e.ensembleModel)
        {
         case 0: emStr="Trend";    break;
         case 1: emStr="MeanRev";  break;
         case 2: emStr="Momentum"; break;
         default:emStr="None";     break;
        }
      FileWrite(h,
        IntegerToString(e.ticket),
        TimeToString(e.timeOpen),
        TimeToString(e.timeClose),
        e.symbol, dir,
        DoubleToString(e.entry,5),
        DoubleToString(e.sl,5),
        DoubleToString(e.tp1,5),
        DoubleToString(e.tp2,5),
        DoubleToString(e.closePrice,5),
        DoubleToString(e.pnl,2),
        DoubleToString(e.rr,3),
        DoubleToString(e.lots,2),
        IntegerToString(e.durationMin),
        regStr, sesStr,
        DoubleToString(e.aiScore,4),
        DoubleToString(e.driftScore,4),
        emStr,
        IntegerToString(e.beDone?1:0),
        IntegerToString(e.partialDone?1:0),
        IntegerToString(e.runnerActive?1:0),
        // 18 features
        DoubleToString(e.features[0],3),  DoubleToString(e.features[1],3),
        DoubleToString(e.features[2],3),  DoubleToString(e.features[3],3),
        DoubleToString(e.features[4],3),  DoubleToString(e.features[5],3),
        DoubleToString(e.features[6],3),  DoubleToString(e.features[7],3),
        DoubleToString(e.features[8],3),  DoubleToString(e.features[9],3),
        DoubleToString(e.features[10],3), DoubleToString(e.features[11],3),
        DoubleToString(e.features[12],3), DoubleToString(e.features[13],3),
        DoubleToString(e.features[14],3), DoubleToString(e.features[15],3),
        DoubleToString(e.features[16],3), DoubleToString(e.features[17],3));
     }

   void UpdateDailyPnL(double pnl)
     {
      datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      if(today != m_todayDate)
        {
         // New day: push yesterday's total
         m_dailyPnL[m_dailyHead] = m_todayPnL;
         m_dailyHead = (m_dailyHead + 1) % JOURNAL_DAILY_SIZE;
         m_todayPnL  = 0;
         m_todayDate = today;
        }
      m_todayPnL += pnl;
     }

   void UpdateDrawdown(double pnl)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance > m_peakEquity) m_peakEquity = balance;
      double dd = m_peakEquity - balance;
      if(dd > m_maxDrawdown) m_maxDrawdown = dd;
     }

public:
   CJournalManager()
      : m_head(0), m_count(0), m_totalTrades(0),
        m_dailyHead(0), m_todayPnL(0), m_todayDate(0),
        m_peakEquity(0), m_maxDrawdown(0),
        m_csvPrefix("PASR_Journal"), m_csvEnabled(true)
     {
      ArrayInitialize(m_dailyPnL, 0);
      m_peakEquity = AccountInfoDouble(ACCOUNT_BALANCE);
      m_todayDate  = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
     }

   void SetCSVEnabled(bool b)       { m_csvEnabled = b; }
   void SetCSVPrefix(string s)      { m_csvPrefix  = s; }

   //+----------------------------------------------------------------+
   //| OnPositionClosed — primary entry point from Orchestrator       |
   //+----------------------------------------------------------------+
   void OnPositionClosed(
         ulong ticket,
         datetime timeOpen,
         const TradePlan &plan,
         double closePrice,
         double pnl,
         ENUM_MARKET_REGIME regime,
         ENUM_TRADING_SESSION session,
         double aiScore,
         double driftScore,
         int ensembleModel,
         const FeatureVector &fv,
         bool beDone,
         bool partialDone,
         bool runnerActive)
     {
      JournalEntry e;
      e.ticket       = ticket;
      e.timeOpen     = timeOpen;
      e.timeClose    = TimeCurrent();
      e.symbol       = _Symbol;
      e.direction    = plan.direction;
      e.entry        = plan.entryPrice;
      e.sl           = plan.sl;
      e.tp1          = plan.tp;
      e.tp2          = plan.tp2;
      e.closePrice   = closePrice;
      e.lots         = plan.lot;
      e.pnl          = pnl;
      e.beDone       = beDone;
      e.partialDone  = partialDone;
      e.runnerActive = runnerActive;
      e.regime       = regime;
      e.session      = session;
      e.aiScore      = aiScore;
      e.driftScore   = driftScore;
      e.ensembleModel= ensembleModel;
      e.isWin        = (pnl > 0);

      // Duration
      e.durationMin = (int)((e.timeClose - timeOpen) / 60);

      // R:R — initial risk in price units
      double riskPts = MathAbs(plan.entryPrice - plan.sl);
      double pnlPts  = MathAbs(closePrice - plan.entryPrice);
      e.rr = (riskPts > 0)
             ? ((pnl > 0 ? 1 : -1) * pnlPts / riskPts)
             : 0;

      // Feature snapshot
      for(int i=0; i<AI_FEATURE_DIM; i++) e.features[i] = fv.f[i];

      // Store in ring buffer
      m_buf[m_head] = e;
      m_head  = (m_head + 1) % JOURNAL_BUF_SIZE;
      if(m_count < JOURNAL_BUF_SIZE) m_count++;
      m_totalTrades++;

      UpdateDailyPnL(pnl);
      UpdateDrawdown(pnl);

      // Append to CSV
      if(m_csvEnabled)
        {
         string fn = CSVFilename();
         bool newFile = !FileIsExist(fn, FILE_COMMON);
         int h = FileOpen(fn, FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI|
                          (newFile?0:FILE_READ));
         if(h != INVALID_HANDLE)
           {
            if(newFile) WriteCsvHeader(h);
            else        FileSeek(h, 0, SEEK_END);
            AppendCSVRow(h, e);
            FileClose(h);
           }
         else
            PrintFormat("[Journal] CSV open failed: %d", GetLastError());
        }

      PrintFormat("[Journal] #%d %s %s PnL=%.2f RR=%.2f AI=%.2f %s",
                  m_totalTrades,
                  e.direction==SIGNAL_BUY?"BUY":"SELL",
                  e.isWin?"WIN":"LOSS",
                  pnl, e.rr, aiScore,
                  e.beDone?"[BE]":"");
     }

   //+----------------------------------------------------------------+
   //| GetStats — aggregate over last N trades (0 = all in buffer)    |
   //+----------------------------------------------------------------+
   TradeStat GetStats(int last = 0) const
     {
      TradeStat s;
      ZeroMemory(s);
      int n = (last == 0 || last > m_count) ? m_count : last;
      if(n == 0) return s;

      double grossProfit=0, grossLoss=0, sumRR=0, sumWinRR=0, sumLossRR=0;
      double sumAI=0, sumDur=0;
      double equity=0, peak=0;
      int consecWin=0, consecLoss=0, maxCW=0, maxCL=0;

      for(int i = 0; i < n; i++)
        {
         // Walk backward from latest
         int idx = (m_head - 1 - i + JOURNAL_BUF_SIZE) % JOURNAL_BUF_SIZE;
         const JournalEntry &e = m_buf[idx];
         s.totalTrades++;
         equity += e.pnl;
         if(equity > peak) peak = equity;
         double dd = peak - equity;
         if(dd > s.maxDrawdown) s.maxDrawdown = dd;

         if(e.isWin)
           {
            s.wins++; grossProfit += e.pnl;
            sumWinRR += e.rr;
            consecWin++; consecLoss=0;
            if(consecWin > maxCW) maxCW=consecWin;
           }
         else
           {
            s.losses++; grossLoss -= e.pnl;
            sumLossRR += e.rr;
            consecLoss++; consecWin=0;
            if(consecLoss > maxCL) maxCL=consecLoss;
           }
         sumRR   += e.rr;
         sumAI   += e.aiScore;
         sumDur  += e.durationMin;
        }

      s.winRate        = (double)s.wins / s.totalTrades;
      s.avgRR          = sumRR / n;
      s.avgWinRR       = (s.wins  > 0) ? sumWinRR  / s.wins   : 0;
      s.avgLossRR      = (s.losses> 0) ? sumLossRR / s.losses : 0;
      s.profitFactor   = (grossLoss > 0) ? grossProfit / grossLoss : 99.0;
      s.totalPnL       = equity;
      s.maxConsecLoss  = maxCL;
      s.maxConsecWin   = maxCW;
      s.avgAIScore     = sumAI  / n;
      s.avgDuration    = sumDur / n;
      return s;
     }

   //+----------------------------------------------------------------+
   //| GetStatsByRegime — filter stats for one regime                 |
   //+----------------------------------------------------------------+
   TradeStat GetStatsByRegime(ENUM_MARKET_REGIME regime) const
     {
      TradeStat s; ZeroMemory(s);
      double gp=0, gl=0;
      for(int i=0; i<m_count; i++)
        {
         const JournalEntry &e = m_buf[i];
         if(e.regime != regime) continue;
         s.totalTrades++;
         if(e.isWin){ s.wins++; gp+=e.pnl; }
         else       { s.losses++; gl-=e.pnl; }
         s.totalPnL   += e.pnl;
         s.avgRR      += e.rr;
         s.avgAIScore += e.aiScore;
        }
      if(s.totalTrades > 0)
        {
         s.winRate      = (double)s.wins / s.totalTrades;
         s.avgRR       /= s.totalTrades;
         s.avgAIScore  /= s.totalTrades;
         s.profitFactor = (gl>0) ? gp/gl : 99.0;
        }
      return s;
     }

   //+----------------------------------------------------------------+
   //| GetStatsBySession                                               |
   //+----------------------------------------------------------------+
   TradeStat GetStatsBySession(ENUM_TRADING_SESSION session) const
     {
      TradeStat s; ZeroMemory(s);
      double gp=0, gl=0;
      for(int i=0; i<m_count; i++)
        {
         const JournalEntry &e = m_buf[i];
         if(e.session != session) continue;
         s.totalTrades++;
         if(e.isWin){ s.wins++; gp+=e.pnl; }
         else       { s.losses++; gl-=e.pnl; }
         s.totalPnL   += e.pnl;
         s.avgRR      += e.rr;
         s.avgAIScore += e.aiScore;
        }
      if(s.totalTrades > 0)
        {
         s.winRate      = (double)s.wins / s.totalTrades;
         s.avgRR       /= s.totalTrades;
         s.avgAIScore  /= s.totalTrades;
         s.profitFactor = (gl>0) ? gp/gl : 99.0;
        }
      return s;
     }

   //+----------------------------------------------------------------+
   //| Daily PnL array for equity curve                               |
   //+----------------------------------------------------------------+
   void GetDailyPnL(double &out[]) const
     {
      ArrayResize(out, JOURNAL_DAILY_SIZE);
      for(int i=0; i<JOURNAL_DAILY_SIZE; i++)
         out[i] = m_dailyPnL[(m_dailyHead + i) % JOURNAL_DAILY_SIZE];
      // append today's running total
      out[JOURNAL_DAILY_SIZE-1] = m_todayPnL;
     }

   // Accessors for PerformanceReport
   int          GetTotalTrades() const { return m_totalTrades; }
   int          GetCount()       const { return m_count; }
   double       GetMaxDrawdown() const { return m_maxDrawdown; }
   double       GetTodayPnL()    const { return m_todayPnL; }
   const JournalEntry* GetEntry(int i) const
     {
      if(i < 0 || i >= m_count) return NULL;
      int idx = (m_head - 1 - i + JOURNAL_BUF_SIZE) % JOURNAL_BUF_SIZE;
      return &m_buf[idx];
     }
   
   //+----------------------------------------------------------------+
   //| Logging helpers for centralized logging                        |
   //+----------------------------------------------------------------+
   void LogInfo(const string msg) const
     {
      PrintFormat("[PASR][INFO] %s", msg);
     }
   
   void LogWarn(const string msg) const
     {
      PrintFormat("[PASR][WARN] %s", msg);
     }
   
   void LogError(const string msg, const int errCode = 0) const
     {
      if(errCode != 0)
         PrintFormat("[PASR][ERROR] %s | Code: %d", msg, errCode);
      else
         PrintFormat("[PASR][ERROR] %s", msg);
     }
  };

#endif // __INFRA_JOURNAL_MANAGER_MQH__
