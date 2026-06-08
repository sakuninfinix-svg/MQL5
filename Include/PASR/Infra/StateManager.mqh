//+------------------------------------------------------------------+
//| Infra/StateManager.mqh — v2.01                                   |
//| Binary-file persistence: saves/loads EA state across restarts.   |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_STATE_MANAGER_MQH__
#define __INFRA_STATE_MANAGER_MQH__

#include "AccountSnapshot.mqh"

#define STATE_FILE_VERSION  0x0200

struct PASRState
  {
   ushort  version;
   uint    crc;
   double  equityPeak;
   double  dailyStartBalance;
   int     consecLoss;
   int     tradesToday;
   int     totalTrades;
   datetime lastTradeDate;
   datetime lastSaveTime;
   bool    circuitBroken;
   char    circuitReason[64];
  };

uint FNV1a32(uint &words[], int count)
  {
   uint hash = (uint)0x811c9dc5;
   for(int i = 0; i < count; i++)
     {
      hash ^= words[i];
      hash *= (uint)0x01000193;
     }
   return hash;
  }

class CStateManager
  {
private:
   string    m_filename;
   bool      m_initialised;
   bool      m_dirty;
   PASRState m_state;

   string BuildFilename(int magic, string sym) const
     {
      StringReplace(sym, "/", "_");
      StringReplace(sym, "+", "_");
      return StringFormat("PASR_State_%d_%s_v2.bin", magic, sym);
     }

   uint ComputeHash(PASRState &s) const
     {
      uint words[];
      ArrayResize(words, 10);
      words[0] = (uint)(s.equityPeak * 1000.0);
      words[1] = (uint)(s.dailyStartBalance * 1000.0);
      words[2] = (uint)s.consecLoss;
      words[3] = (uint)s.tradesToday;
      words[4] = (uint)s.totalTrades;
      words[5] = (uint)s.lastTradeDate;
      words[6] = (uint)s.lastSaveTime;
      words[7] = (uint)s.circuitBroken;
      words[8] = (uint)s.version;
      uint r0 = 0;
      uint r1 = 0;
      for(int i=0;i<4;i++) r0 |= ((uint)(uchar)s.circuitReason[i]) << (i*8);
      for(int i=0;i<4;i++) r1 |= ((uint)(uchar)s.circuitReason[i+4]) << (i*8);
      words[9] = r0 ^ r1;
      return FNV1a32(words, 10);
     }

   void ResetDefaults()
     {
      SAccountSnapshot account;
      account.Capture();
      double bal = account.valid ? account.balance : 0.0;
      m_state.version = STATE_FILE_VERSION;
      m_state.crc = 0;
      m_state.equityPeak = (bal > 0) ? bal : 10000.0;
      m_state.dailyStartBalance = bal;
      m_state.consecLoss = 0;
      m_state.tradesToday = 0;
      m_state.totalTrades = 0;
      m_state.lastTradeDate = 0;
      m_state.lastSaveTime = 0;
      m_state.circuitBroken = false;
      ArrayInitialize(m_state.circuitReason, 0);
     }

public:
   CStateManager() : m_filename(""), m_initialised(false), m_dirty(false) {}

   bool Init(int magic, string sym)
     {
      m_filename = BuildFilename(magic, sym);
      m_initialised = true;
      ResetDefaults();
      return true;
     }

   bool Load()
     {
      if(!m_initialised) return false;
      if(!FileIsExist(m_filename, FILE_COMMON))
        {
         Print("[State] No saved state — using defaults");
         return true;
        }

      int fh = FileOpen(m_filename, FILE_READ|FILE_BIN|FILE_COMMON);
      if(fh == INVALID_HANDLE)
        {
         PrintFormat("[State] Cannot open %s (err=%d)", m_filename, GetLastError());
         return false;
        }

      PASRState loaded;
      uint bytesRead = (uint)FileReadStruct(fh, loaded);
      FileClose(fh);

      if(bytesRead < sizeof(PASRState))
        {
         Print("[State] File too small — discarding");
         ResetDefaults();
         return false;
        }

      if(loaded.version != STATE_FILE_VERSION)
        {
         PrintFormat("[State] Version mismatch file=%04X cur=%04X — discarding", loaded.version, STATE_FILE_VERSION);
         ResetDefaults();
         return false;
        }

      uint expected = ComputeHash(loaded);
      if(loaded.crc != expected)
        {
         PrintFormat("[State] Hash mismatch file=%08X computed=%08X — discarding", loaded.crc, expected);
         ResetDefaults();
         return false;
        }

      m_state = loaded;
      PrintFormat("[State] Loaded OK — peak=%.2f loss=%d circuit=%s",
                  m_state.equityPeak, m_state.consecLoss,
                  m_state.circuitBroken ? "BROKEN" : "OK");
      return true;
     }

   bool Save()
     {
      if(!m_initialised) return false;
      m_state.lastSaveTime = TimeCurrent();
      m_state.crc = ComputeHash(m_state);

      int fh = FileOpen(m_filename, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(fh == INVALID_HANDLE)
        {
         PrintFormat("[State] Cannot write %s (err=%d)", m_filename, GetLastError());
         return false;
        }
      FileWriteStruct(fh, m_state);
      FileClose(fh);
      m_dirty = false;
      return true;
     }

   void OnDeinit() { if(m_dirty) Save(); }

   double   GetEquityPeak()        const { return m_state.equityPeak;        }
   double   GetDailyStartBalance() const { return m_state.dailyStartBalance; }
   int      GetConsecLoss()        const { return m_state.consecLoss;        }
   int      GetTradesToday()       const { return m_state.tradesToday;       }
   int      GetTotalTrades()       const { return m_state.totalTrades;       }
   datetime GetLastTradeDate()     const { return m_state.lastTradeDate;     }
   bool     IsCircuitBroken()      const { return m_state.circuitBroken;     }
   string   GetCircuitReason()     const { return CharArrayToString(m_state.circuitReason); }

   void SetEquityPeak(double v)        { m_state.equityPeak = v; m_dirty=true; }
   void SetDailyStartBalance(double v) { m_state.dailyStartBalance = v; m_dirty=true; }
   void IncrConsecLoss()               { m_state.consecLoss++; m_dirty=true; }
   void ResetConsecLoss()              { m_state.consecLoss=0; m_dirty=true; }
   void IncrTradesToday()              { m_state.tradesToday++; m_state.totalTrades++; m_dirty=true; }
   void ResetTradesToday()             { m_state.tradesToday=0; m_dirty=true; }
   void SetLastTradeDate(datetime d)   { m_state.lastTradeDate=d; m_dirty=true; }

   void TripCircuit(string reason)
     {
      m_state.circuitBroken = true;
      StringToCharArray(reason, m_state.circuitReason, 0, ArraySize(m_state.circuitReason));
      m_dirty = true;
      Save();
     }

   void ResetCircuit()
     {
      m_state.circuitBroken=false;
      ArrayInitialize(m_state.circuitReason,0);
      m_dirty=true;
     }

   void CheckDailyReset()
     {
      datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      datetime lastDate = m_state.lastTradeDate;
      if(today > lastDate)
        {
         SAccountSnapshot account;
         account.Capture();
         double bal = account.valid ? account.balance : m_state.dailyStartBalance;
         if(m_state.tradesToday > 0)
            PrintFormat("[State] Daily reset: trades=%d -> 0", m_state.tradesToday);
         m_state.dailyStartBalance = bal;
         m_state.tradesToday = 0;
         m_dirty = true;
         Save();
        }
     }
  };

#endif // __INFRA_STATE_MANAGER_MQH__
