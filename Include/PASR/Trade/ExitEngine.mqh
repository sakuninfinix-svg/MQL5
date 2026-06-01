//+------------------------------------------------------------------+
//| ExitEngine.mqh                                             v2.11 |
//| Smart Exit Logic for Position Management                         |
//+------------------------------------------------------------------+
#ifndef PASR_EXIT_ENGINE_MQH
#define PASR_EXIT_ENGINE_MQH

#include "../Core/IManager.mqh"
#include "PositionManager.mqh"

#define CHANDELIER_ATR_MULT          3.0
#define CHANDELIER_PERIOD            22
#define TIME_EXIT_BARS               10
#define PROFIT_FADE_THRESHOLD        70.0
#define PROFIT_FADE_SHORT_THRESHOLD  35.0
#define STRUCTURE_BREAK_LOOKBACK     5
#define STRUCTURE_BREAK_ATR_FACTOR   0.30

enum ExitReason
  {
   EXIT_NONE           = 0,
   EXIT_CHANDLER_HIT,
   EXIT_TIME_EXPIRED,
   EXIT_STRUCTURE_BREAK,
   EXIT_PROFIT_FADE,
   EXIT_REVERSAL_SIGNAL,
   EXIT_EMERGENCY
  };

struct ExitSignal
  {
   ExitReason reason;
   double     trigger_price;
   double     current_profit;
   int        bars_held;
   string     description;

   void Clear()
     {
      reason = EXIT_NONE;
      trigger_price = 0.0;
      current_profit = 0.0;
      bars_held = 0;
      description = "";
     }
  };

struct ExitSnapshot
  {
   bool       indicatorsReady;
   ulong      chandelierExits;
   ulong      timeExits;
   ulong      structureExits;
   ulong      fadeExits;
   ulong      totalExits;
   ExitSignal lastSignal;
   datetime   lastCheckTime;
   string     lastSymbol;
   int        lastPositionType;

   void Clear()
     {
      indicatorsReady = false;
      chandelierExits = 0;
      timeExits = 0;
      structureExits = 0;
      fadeExits = 0;
      totalExits = 0;
      lastSignal.Clear();
      lastCheckTime = 0;
      lastSymbol = "";
      lastPositionType = -1;
     }
  };

class CExitEngine : public IManager
  {
private:
   ulong m_chandelier_exits;
   ulong m_time_exits;
   ulong m_structure_exits;
   ulong m_fade_exits;
   int   m_hATR;
   int   m_hRSI;
   bool  m_indicatorsReady;
   ExitSnapshot m_snapshot;

   void RefreshSnapshotBase(const string symbol = "", ENUM_ORDER_TYPE position_type = ORDER_TYPE_BUY)
     {
      m_snapshot.indicatorsReady = m_indicatorsReady;
      m_snapshot.chandelierExits = m_chandelier_exits;
      m_snapshot.timeExits = m_time_exits;
      m_snapshot.structureExits = m_structure_exits;
      m_snapshot.fadeExits = m_fade_exits;
      m_snapshot.totalExits = m_chandelier_exits + m_time_exits + m_structure_exits + m_fade_exits;
      if(symbol != "") m_snapshot.lastSymbol = symbol;
      m_snapshot.lastPositionType = (int)position_type;
      m_snapshot.lastCheckTime = TimeCurrent();
     }

   void RefreshSnapshot(const string symbol, ENUM_ORDER_TYPE position_type, ExitSignal &signal)
     {
      RefreshSnapshotBase(symbol, position_type);
      m_snapshot.lastSignal = signal;
     }

   bool InitIndicators()
     {
      if(m_hATR == INVALID_HANDLE) m_hATR = iATR(_Symbol, PERIOD_CURRENT, CHANDELIER_PERIOD);
      if(m_hRSI == INVALID_HANDLE) m_hRSI = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
      return (m_hATR != INVALID_HANDLE && m_hRSI != INVALID_HANDLE);
     }

   void CleanupIndicators()
     {
      if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
      if(m_hRSI != INVALID_HANDLE) { IndicatorRelease(m_hRSI); m_hRSI = INVALID_HANDLE; }
      m_indicatorsReady = false;
      RefreshSnapshotBase();
     }

   double GetATRValue()
     {
      if(m_hATR == INVALID_HANDLE) return 0.0;
      double buf[1];
      if(CopyBuffer(m_hATR, 0, 1, 1, buf) <= 0) return 0.0;
      return buf[0];
     }

   bool GetRSIValues(double &current, double &prev)
     {
      current = 0.0; prev = 0.0;
      if(m_hRSI == INVALID_HANDLE) return false;
      double buf[2];
      if(CopyBuffer(m_hRSI, 0, 1, 2, buf) < 2) return false;
      current = buf[0];
      prev = buf[1];
      return true;
     }

public:
   CExitEngine()
      : IManager(), m_chandelier_exits(0), m_time_exits(0),
        m_structure_exits(0), m_fade_exits(0),
        m_hATR(INVALID_HANDLE), m_hRSI(INVALID_HANDLE),
        m_indicatorsReady(false)
     { m_snapshot.Clear(); }

   ~CExitEngine() { CleanupIndicators(); }

   virtual string HandlerName() const override { return "ExitEngine"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(!InitIndicators())
        {
         Print("[Exit] Failed to init indicator handles");
         CleanupIndicators();
         IManager::Deinit();
         return false;
        }
      m_indicatorsReady = true;
      RefreshSnapshotBase();
      PrintFormat("[Exit] v2.11 Init OK — Chandelier ATR=%.1f Period=%d", CHANDELIER_ATR_MULT, CHANDELIER_PERIOD);
      return true;
     }

   virtual void Deinit() override
     {
      CleanupIndicators();
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_EMERGENCY_STOP);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_EMERGENCY_STOP && m_debugMode)
         Print("[Exit] EMERGENCY_STOP received — RecoveryManager owns emergency closing.");
     }

   virtual void OnPriceUpdate() override {}
   virtual void OnNewBar() override {}

   ExitSignal CheckExit(const string symbol, ENUM_ORDER_TYPE position_type,
                        double entry_price, double current_price,
                        datetime entry_time=0)
     {
      ExitSignal signal;
      signal.Clear();
      if(!IsInitialized() || !m_indicatorsReady)
        {
         RefreshSnapshot(symbol, position_type, signal);
         return signal;
        }

      double profit_pts = (position_type == ORDER_TYPE_BUY)
                          ? current_price - entry_price
                          : entry_price - current_price;

      double exit_level = 0.0;
      if(CheckChandelierExit(symbol, position_type, current_price, exit_level))
        {
         signal.reason = EXIT_CHANDLER_HIT;
         signal.trigger_price = exit_level;
         signal.current_profit = profit_pts;
         signal.description = StringFormat("Chandelier stop %.5f", exit_level);
         m_chandelier_exits++;
         RefreshSnapshot(symbol, position_type, signal);
         return signal;
        }

      if(CheckStructureBreak(symbol, position_type))
        {
         signal.reason = EXIT_STRUCTURE_BREAK;
         signal.trigger_price = current_price;
         signal.current_profit = profit_pts;
         signal.description = "Market structure broken by close+ATR filter";
         m_structure_exits++;
         RefreshSnapshot(symbol, position_type, signal);
         return signal;
        }

      if(profit_pts > 0.0 && CheckProfitFade(symbol, position_type))
        {
         signal.reason = EXIT_PROFIT_FADE;
         signal.trigger_price = current_price;
         signal.current_profit = profit_pts;
         signal.description = "Momentum exhaustion";
         m_fade_exits++;
         RefreshSnapshot(symbol, position_type, signal);
         return signal;
        }

      int barsHeld = GetBarsSinceEntry(entry_time);
      if(entry_time > 0 && profit_pts <= 0.0 && CheckTimeExit(symbol, entry_time, TIME_EXIT_BARS))
        {
         signal.reason = EXIT_TIME_EXPIRED;
         signal.trigger_price = current_price;
         signal.current_profit = profit_pts;
         signal.bars_held = barsHeld;
         signal.description = StringFormat("Time exit: %d bars held", barsHeld);
         m_time_exits++;
         RefreshSnapshot(symbol, position_type, signal);
         return signal;
        }

      RefreshSnapshot(symbol, position_type, signal);
      return signal;
     }

   bool CheckChandelierExit(const string symbol, ENUM_ORDER_TYPE pos_type, double current_price, double &exit_level)
     {
      exit_level = CalculateChandelierLevel(symbol, pos_type);
      if(exit_level == 0.0) return false;
      return (pos_type == ORDER_TYPE_BUY) ? current_price <= exit_level : current_price >= exit_level;
     }

   double CalculateChandelierLevel(const string symbol, ENUM_ORDER_TYPE pos_type)
     {
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      if(CopyHigh(symbol, PERIOD_CURRENT, 1, CHANDELIER_PERIOD, highs) < CHANDELIER_PERIOD) return 0.0;
      if(CopyLow(symbol, PERIOD_CURRENT, 1, CHANDELIER_PERIOD, lows) < CHANDELIER_PERIOD) return 0.0;
      double atr = GetATRValue();
      if(atr <= 0.0) return 0.0;
      if(pos_type == ORDER_TYPE_BUY)
        {
         double hh = highs[0];
         for(int i=1; i<CHANDELIER_PERIOD; i++) if(highs[i] > hh) hh = highs[i];
         return hh - atr * CHANDELIER_ATR_MULT;
        }
      double ll = lows[0];
      for(int i=1; i<CHANDELIER_PERIOD; i++) if(lows[i] < ll) ll = lows[i];
      return ll + atr * CHANDELIER_ATR_MULT;
     }

   bool CheckTimeExit(const string symbol, datetime entry_time, int min_bars)
     {
      if(entry_time == 0) return false;
      return GetBarsSinceEntry(entry_time) >= min_bars;
     }

   bool CheckStructureBreak(const string symbol, ENUM_ORDER_TYPE pos_type)
     {
      int needed = STRUCTURE_BREAK_LOOKBACK + 3;
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(symbol, PERIOD_CURRENT, 1, needed, closes) < needed) return false;
      double atr = GetATRValue();
      if(atr <= 0.0) return false;
      double threshold = atr * STRUCTURE_BREAK_ATR_FACTOR;
      double currentClose = closes[0];
      double swingRef = closes[STRUCTURE_BREAK_LOOKBACK];
      if(pos_type == ORDER_TYPE_BUY)
         return currentClose < swingRef - threshold;
      return currentClose > swingRef + threshold;
     }

   bool CheckProfitFade(const string symbol, ENUM_ORDER_TYPE pos_type)
     {
      double cur, prv;
      if(!GetRSIValues(cur, prv)) return false;
      if(pos_type == ORDER_TYPE_BUY) return (prv >= 70.0 && cur < PROFIT_FADE_THRESHOLD);
      return (prv <= 30.0 && cur > PROFIT_FADE_SHORT_THRESHOLD);
     }

   int GetBarsSinceEntry(datetime entry_time)
     {
      if(entry_time == 0) return 0;
      int idx = iBarShift(_Symbol, PERIOD_CURRENT, entry_time);
      return (idx < 0) ? 0 : idx;
     }

   ExitSnapshot GetSnapshot() const { return m_snapshot; }

   void PrintStats()
     {
      ulong total = m_chandelier_exits + m_time_exits + m_structure_exits + m_fade_exits;
      PrintFormat("[Exit] === STATS === Chandelier:%d Time:%d Structure:%d Fade:%d Total:%d",
                  m_chandelier_exits, m_time_exits, m_structure_exits, m_fade_exits, total);
     }

   void PrintDiagnostics() const
     {
      PrintFormat("[ExitDiag] ready=%s total=%I64u chand=%I64u time=%I64u struct=%I64u fade=%I64u lastReason=%d profit=%.2f bars=%d desc=%s",
                  m_snapshot.indicatorsReady ? "true" : "false",
                  m_snapshot.totalExits,
                  m_snapshot.chandelierExits,
                  m_snapshot.timeExits,
                  m_snapshot.structureExits,
                  m_snapshot.fadeExits,
                  (int)m_snapshot.lastSignal.reason,
                  m_snapshot.lastSignal.current_profit,
                  m_snapshot.lastSignal.bars_held,
                  m_snapshot.lastSignal.description);
     }
  };

#endif // PASR_EXIT_ENGINE_MQH
