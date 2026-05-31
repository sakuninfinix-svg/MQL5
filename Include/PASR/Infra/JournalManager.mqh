//+------------------------------------------------------------------+
//| Infra/JournalManager.mqh — v2.04                                 |
//| Per-trade CSV journal + in-memory performance analytics.         |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_JOURNAL_MANAGER_MQH__
#define __INFRA_JOURNAL_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "../Data/RegimeTypes.mqh"
#include "../AI/AITypes.mqh"
#include "../Trade/TradePlan.mqh"

#define JOURNAL_BUF_SIZE    500
#define JOURNAL_DAILY_SIZE   30

struct JournalEntry
  {
   ulong    ticket;
   datetime timeOpen;
   datetime timeClose;
   string   symbol;
   ENUM_SIGNAL_DIR direction;
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   closePrice;
   double   lots;
   double   pnl;
   double   rr;
   int      durationMin;
   bool     isWin;
   EMarketRegime regime;
   ENUM_TRADING_SESSION session;
   double   aiScore;
   double   driftScore;
   int      ensembleModel;
   bool     beDone;
   bool     partialDone;
   bool     runnerActive;
   double   features[AI_FEATURE_DIM];

   void Clear()
     {
      ticket=0; timeOpen=0; timeClose=0; symbol=""; direction=SIGNAL_NONE;
      entry=0; sl=0; tp1=0; tp2=0; closePrice=0; lots=0; pnl=0; rr=0;
      durationMin=0; isWin=false; regime=REGIME_UNKNOWN; session=SESSION_UNKNOWN;
      aiScore=0; driftScore=0; ensembleModel=-1; beDone=false; partialDone=false; runnerActive=false;
      ArrayInitialize(features, 0.0);
     }
  };

struct TradeStat
  {
   int    totalTrades;
   int    wins;
   int    losses;
   double winRate;
   double avgRR;
   double avgWinRR;
   double avgLossRR;
   double profitFactor;
   double totalPnL;
   double maxDrawdown;
   int    maxConsecLoss;
   int    maxConsecWin;
   double avgAIScore;
   double avgDuration;
  };

class CJournalManager : public IManager
  {
private:
   JournalEntry m_buf[JOURNAL_BUF_SIZE];
   int          m_head;
   int          m_count;
   int          m_totalTrades;
   double       m_dailyPnL[JOURNAL_DAILY_SIZE];
   int          m_dailyHead;
   double       m_todayPnL;
   datetime     m_todayDate;
   double       m_peakEquity;
   double       m_maxDrawdown;
   string       m_csvPrefix;
   bool         m_csvEnabled;

   datetime MidnightFloor(datetime t) const
     { return (datetime)((long)t - (long)t % 86400L); }

   string CSVFilename() const
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return StringFormat("%s_%04d%02d.csv", m_csvPrefix, dt.year, dt.mon);
     }

   string Bool01(bool v) const { return v ? "1" : "0"; }

   string SessionName(ENUM_TRADING_SESSION s) const
     {
      switch(s)
        {
         case SESSION_TOKYO:    return "Tokyo";
         case SESSION_LONDON:   return "London";
         case SESSION_NEW_YORK: return "NewYork";
         case SESSION_OVERLAP:  return "Overlap";
         case SESSION_SYDNEY:   return "Sydney";
         default:               return "Unknown";
        }
     }

   string DirectionName(ENUM_SIGNAL_DIR d) const
     {
      if(d == SIGNAL_BUY) return "BUY";
      if(d == SIGNAL_SELL) return "SELL";
      return "NONE";
     }

   string EnsembleName(int model) const
     {
      switch(model)
        {
         case 0: return "Trend";
         case 1: return "MeanRev";
         case 2: return "Momentum";
         default:return "None";
        }
     }

   string CsvEscape(string s) const
     {
      StringReplace(s, "\"", "\"\"");
      return "\"" + s + "\"";
     }

   string CsvHeader() const
     {
      string line = "ticket,time_open,time_close,symbol,direction,entry,sl,tp1,tp2,close_price,pnl,rr,lots,duration_min,regime,session,ai_score,drift,ensemble_model,be_done,partial_done,runner_active";
      for(int i=0; i<AI_FEATURE_DIM; i++) line += StringFormat(",f%02d", i);
      return line + "\r\n";
     }

   string CsvRow(JournalEntry &e) const
     {
      string line = IntegerToString((long)e.ticket) + "," +
                    CsvEscape(TimeToString(e.timeOpen, TIME_DATE|TIME_SECONDS)) + "," +
                    CsvEscape(TimeToString(e.timeClose, TIME_DATE|TIME_SECONDS)) + "," +
                    CsvEscape(e.symbol) + "," + CsvEscape(DirectionName(e.direction)) + "," +
                    DoubleToString(e.entry,5) + "," + DoubleToString(e.sl,5) + "," +
                    DoubleToString(e.tp1,5) + "," + DoubleToString(e.tp2,5) + "," +
                    DoubleToString(e.closePrice,5) + "," + DoubleToString(e.pnl,2) + "," +
                    DoubleToString(e.rr,3) + "," + DoubleToString(e.lots,2) + "," +
                    IntegerToString(e.durationMin) + "," + CsvEscape(MarketRegimeName(e.regime)) + "," +
                    CsvEscape(SessionName(e.session)) + "," + DoubleToString(e.aiScore,4) + "," +
                    DoubleToString(e.driftScore,4) + "," + CsvEscape(EnsembleName(e.ensembleModel)) + "," +
                    Bool01(e.beDone) + "," + Bool01(e.partialDone) + "," + Bool01(e.runnerActive);
      for(int i=0; i<AI_FEATURE_DIM; i++) line += "," + DoubleToString(e.features[i],3);
      return line + "\r\n";
     }

   void AppendToCSV(JournalEntry &e)
     {
      if(!m_csvEnabled) return;
      string fn = CSVFilename();
      bool newFile = !FileIsExist(fn, FILE_COMMON);
      int h = FileOpen(fn, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         PASRLogError("Journal", "CSV open failed: " + IntegerToString(GetLastError()));
         return;
        }
      if(newFile || FileSize(h) == 0) FileWriteString(h, CsvHeader());
      FileSeek(h, 0, SEEK_END);
      FileWriteString(h, CsvRow(e));
      FileClose(h);
     }

   void UpdateDailyPnL(double pnl)
     {
      datetime today = MidnightFloor(TimeCurrent());
      if(today != m_todayDate)
        {
         m_dailyPnL[m_dailyHead] = m_todayPnL;
         m_dailyHead = (m_dailyHead + 1) % JOURNAL_DAILY_SIZE;
         m_todayPnL = 0.0;
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

   void StoreEntry(JournalEntry &e)
     {
      m_buf[m_head] = e;
      m_head = (m_head + 1) % JOURNAL_BUF_SIZE;
      if(m_count < JOURNAL_BUF_SIZE) m_count++;
      m_totalTrades++;
      UpdateDailyPnL(e.pnl);
      UpdateDrawdown(e.pnl);
      AppendToCSV(e);
     }

public:
   CJournalManager()
      : IManager(), m_head(0), m_count(0), m_totalTrades(0),
        m_dailyHead(0), m_todayPnL(0), m_todayDate(0),
        m_peakEquity(0), m_maxDrawdown(0),
        m_csvPrefix("PASR_Journal"), m_csvEnabled(true)
     {
      ArrayInitialize(m_dailyPnL, 0.0);
      m_peakEquity = AccountInfoDouble(ACCOUNT_BALANCE);
      m_todayDate = MidnightFloor(TimeCurrent());
     }

   virtual string HandlerName() const override { return "JournalManager"; }

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_TRADE_CLOSE); }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      PASRLogInfo("Journal", "Initialized. CSV=" + (m_csvEnabled ? "ON" : "OFF"));
      return true;
     }

   virtual void Deinit() override
     {
      if(!m_initialized) return;
      PASRLogInfo("Journal", StringFormat("Deinit. Total trades: %d", m_totalTrades));
      IManager::Deinit();
     }

   void Shutdown() { Deinit(); }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id != EVENT_ID_TRADE_CLOSE) return;
      JournalEntry e;
      e.Clear();
      e.ticket = ev.ticket;
      e.timeClose = TimeCurrent();
      e.symbol = _Symbol;
      e.pnl = ev.profit;
      e.isWin = (ev.profit > 0.0);
      e.regime = REGIME_UNKNOWN;
      e.session = SESSION_UNKNOWN;
      StoreEntry(e);
     }

   void SetCSVEnabled(bool b) { m_csvEnabled = b; }
   void SetCSVPrefix(string s) { if(s != "") m_csvPrefix = s; }

   void OnPositionClosed(ulong ticket, datetime timeOpen, TradePlan &plan,
                         double closePrice, double pnl, EMarketRegime regime,
                         ENUM_TRADING_SESSION session, double aiScore,
                         double driftScore, int ensembleModel,
                         SAIFeatureVector &fv, bool beDone,
                         bool partialDone, bool runnerActive)
     {
      JournalEntry e;
      e.Clear();
      e.ticket = ticket;
      e.timeOpen = timeOpen;
      e.timeClose = TimeCurrent();
      e.symbol = _Symbol;
      e.direction = plan.direction;
      e.entry = plan.entryPrice;
      e.sl = plan.sl;
      e.tp1 = plan.tp;
      e.tp2 = plan.tp2;
      e.closePrice = closePrice;
      e.lots = plan.lot;
      e.pnl = pnl;
      e.beDone = beDone;
      e.partialDone = partialDone;
      e.runnerActive = runnerActive;
      e.regime = regime;
      e.session = session;
      e.aiScore = aiScore;
      e.driftScore = driftScore;
      e.ensembleModel = ensembleModel;
      e.isWin = (pnl > 0.0);
      e.durationMin = (timeOpen > 0) ? (int)((e.timeClose - timeOpen) / 60) : 0;
      double riskPts = MathAbs(plan.entryPrice - plan.sl);
      double pnlPts = MathAbs(closePrice - plan.entryPrice);
      e.rr = (riskPts > 0) ? ((pnl > 0 ? 1 : -1) * pnlPts / riskPts) : 0;
      for(int i=0; i<AI_FEATURE_DIM; i++) e.features[i] = fv.features[i];
      StoreEntry(e);
      PASRLogInfo("Journal", StringFormat("#%d %s %s PnL=%.2f RR=%.2f AI=%.2f%s",
                  m_totalTrades, DirectionName(e.direction), e.isWin?"WIN":"LOSS",
                  pnl, e.rr, aiScore, e.beDone?" [BE]":""));
     }

   void LogEntry(PipelineContext &ctx)
     {
      if(!m_initialized) return;
      if(m_debugMode)
         PASRLogInfo("Journal", StringFormat("Pipeline ctx: signal=%d ai=%.3f regime=%s",
                     (int)ctx.signal.direction, ctx.ai_score, MarketRegimeName(ctx.regime)));
     }

   TradeStat GetStats(int last = 0) const
     {
      TradeStat s; ZeroMemory(s);
      int n = (last == 0 || last > m_count) ? m_count : last;
      if(n == 0) return s;
      double grossProfit=0, grossLoss=0, sumRR=0, sumWinRR=0, sumLossRR=0;
      double sumAI=0, sumDur=0, equity=0, peak=0;
      int consecWin=0, consecLoss=0, maxCW=0, maxCL=0;
      for(int i = 0; i < n; i++)
        {
         int idx = (m_head - 1 - i + JOURNAL_BUF_SIZE) % JOURNAL_BUF_SIZE;
         JournalEntry e = m_buf[idx];
         s.totalTrades++;
         equity += e.pnl;
         if(equity > peak) peak = equity;
         double dd = peak - equity;
         if(dd > s.maxDrawdown) s.maxDrawdown = dd;
         if(e.isWin)
           { s.wins++; grossProfit += e.pnl; sumWinRR += e.rr; consecWin++; consecLoss=0; if(consecWin > maxCW) maxCW=consecWin; }
         else
           { s.losses++; grossLoss -= e.pnl; sumLossRR += e.rr; consecLoss++; consecWin=0; if(consecLoss > maxCL) maxCL=consecLoss; }
         sumRR += e.rr; sumAI += e.aiScore; sumDur += e.durationMin;
        }
      s.winRate = (double)s.wins / s.totalTrades;
      s.avgRR = sumRR / n;
      s.avgWinRR = (s.wins > 0) ? sumWinRR / s.wins : 0;
      s.avgLossRR = (s.losses > 0) ? sumLossRR / s.losses : 0;
      s.profitFactor = (grossLoss > 0) ? grossProfit / grossLoss : 99.0;
      s.totalPnL = equity;
      s.maxConsecLoss = maxCL;
      s.maxConsecWin = maxCW;
      s.avgAIScore = sumAI / n;
      s.avgDuration = sumDur / n;
      return s;
     }

   TradeStat GetStatsByRegime(EMarketRegime regime) const
     {
      TradeStat s; ZeroMemory(s);
      double gp=0, gl=0;
      for(int i=0; i<m_count; i++)
        {
         JournalEntry e = m_buf[i];
         if(e.regime != regime) continue;
         s.totalTrades++;
         if(e.isWin){ s.wins++; gp+=e.pnl; } else { s.losses++; gl-=e.pnl; }
         s.totalPnL += e.pnl; s.avgRR += e.rr; s.avgAIScore += e.aiScore;
        }
      if(s.totalTrades > 0)
        {
         s.winRate=(double)s.wins/s.totalTrades; s.avgRR/=s.totalTrades; s.avgAIScore/=s.totalTrades;
         s.profitFactor=(gl>0)?gp/gl:99.0;
        }
      return s;
     }

   TradeStat GetStatsBySession(ENUM_TRADING_SESSION session) const
     {
      TradeStat s; ZeroMemory(s);
      double gp=0, gl=0;
      for(int i=0; i<m_count; i++)
        {
         JournalEntry e = m_buf[i];
         if(e.session != session) continue;
         s.totalTrades++;
         if(e.isWin){ s.wins++; gp+=e.pnl; } else { s.losses++; gl-=e.pnl; }
         s.totalPnL += e.pnl; s.avgRR += e.rr; s.avgAIScore += e.aiScore;
        }
      if(s.totalTrades > 0)
        {
         s.winRate=(double)s.wins/s.totalTrades; s.avgRR/=s.totalTrades; s.avgAIScore/=s.totalTrades;
         s.profitFactor=(gl>0)?gp/gl:99.0;
        }
      return s;
     }

   void GetDailyPnL(double &out[]) const
     {
      ArrayResize(out, JOURNAL_DAILY_SIZE);
      for(int i=0; i<JOURNAL_DAILY_SIZE; i++) out[i] = m_dailyPnL[(m_dailyHead + i) % JOURNAL_DAILY_SIZE];
      out[JOURNAL_DAILY_SIZE-1] = m_todayPnL;
     }

   int GetTotalTrades() const { return m_totalTrades; }
   int GetCount() const { return m_count; }
   double GetMaxDrawdown() const { return m_maxDrawdown; }
   double GetTodayPnL() const { return m_todayPnL; }

   bool GetEntry(int i, JournalEntry &out) const
     {
      if(i < 0 || i >= m_count) return false;
      int idx = (m_head - 1 - i + JOURNAL_BUF_SIZE) % JOURNAL_BUF_SIZE;
      out = m_buf[idx];
      return true;
     }
  };

#endif // __INFRA_JOURNAL_MANAGER_MQH__
