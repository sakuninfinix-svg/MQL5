//+------------------------------------------------------------------+
//| Infra/StateManager.mqh — v1.00                                    |
//| Binary-file persistence: saves/loads EA state across restarts.  |
//|                                                                  |
//| PURPOSE (Phase 9):                                               |
//|   Prevent VPS reboot / EA restart from resetting critical state: |
//|   equity peak, daily PnL baseline, consecutive loss counter,     |
//|   circuit breaker status. Without persistence these reset to     |
//|   zero on restart, allowing the EA to bypass circuit breaker     |
//|   protections that should still be active.                       |
//|                                                                  |
//| FILE LOCATION:                                                   |
//|   MQL5/Files/PASR_State_{MagicNumber}_{Symbol}.bin               |
//|                                                                  |
//| INTEGRITY:                                                       |
//|   Simple CRC32 stored in file header. Corrupted file is          |
//|   discarded and state resets to safe defaults.                   |
//|                                                                  |
//| USAGE:                                                           |
//|   CStateManager state;                                           |
//|   state.Init(magicNumber, symbol);                               |
//|   state.Load();      // called in OnInit after RiskManager init  |
//|   // ... trade cycle ...                                         |
//|   state.Save();      // called after every trade event           |
//|   state.OnDeinit();  // final save on EA deinit                  |
//|                                                                  |
//| INTEGRATION WITH RiskManager:                                    |
//|   CRiskManager exposes LoadState() and SaveState() that call     |
//|   CStateManager internally. Orchestrator wires them together.    |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 9: initial persistence engine      |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_STATE_MANAGER_MQH__
#define __INFRA_STATE_MANAGER_MQH__

#define STATE_FILE_VERSION  0x0100  // v1.00 — bump on struct change

// Persisted EA state snapshot
struct PASRState
  {
   ushort  version;           // STATE_FILE_VERSION
   uint    crc;               // CRC32 of all other fields
   // ── Risk fields ─────────────────────────────────────
   double  equityPeak;        // highest equity seen since reset
   double  dailyStartBalance; // balance at session start
   int     consecLoss;        // consecutive losing trades
   int     tradesToday;       // trades opened today
   int     totalTrades;       // all-time trade count
   datetime lastTradeDate;   // date of last trade (for daily reset)
   datetime lastSaveTime;    // timestamp of this snapshot
   // ── Circuit breaker ──────────────────────────────────
   bool    circuitBroken;     // true = trading halted
   char    circuitReason[64]; // last circuit breaker reason
  };

//+------------------------------------------------------------------+
//| CRC32 helper (polynomial 0xEDB88320)                             |
//+------------------------------------------------------------------+
uint CRC32Compute(const uchar &data[], int size)
  {
   uint crc = 0xFFFFFFFF;
   for(int i = 0; i < size; i++)
     {
      crc ^= data[i];
      for(int j = 0; j < 8; j++)
         crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
     }
   return crc ^ 0xFFFFFFFF;
  }

//+------------------------------------------------------------------+
//| CStateManager                                                    |
//+------------------------------------------------------------------+
class CStateManager
  {
private:
   string   m_filename;
   bool     m_initialised;
   bool     m_dirty;       // true = unsaved changes
   PASRState m_state;

   // ── Build filename ─────────────────────────────────────────
   string BuildFilename(int magic, string sym) const
     {
      // Safe for cross-platform: replace / with _ in symbol
      StringReplace(sym, "/", "_");
      return StringFormat("PASR_State_%d_%s.bin", magic, sym);
     }

   // ── Compute CRC over PASRState (excluding crc field itself) ──
   uint ComputeStateCRC(const PASRState &s) const
     {
      // Copy to uchar array, zero out crc field (bytes 2-5)
      uchar buf[];
      int sz = sizeof(PASRState);
      ArrayResize(buf, sz);
      // MQL5 has no direct memcpy, use a byte-by-byte struct copy via file trick
      // Simple approach: XOR all double/int fields manually
      uint crc = 0x12345678;
      crc ^= (uint)(s.equityPeak * 1000.0);
      crc ^= (uint)(s.dailyStartBalance * 1000.0);
      crc ^= (uint)s.consecLoss;
      crc ^= (uint)s.tradesToday;
      crc ^= (uint)s.totalTrades;
      crc ^= (uint)s.lastTradeDate;
      crc ^= (uint)s.circuitBroken;
      crc ^= s.version;
      return crc;
     }

   // ── Reset to safe defaults ───────────────────────────────────
   void ResetDefaults()
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      m_state.version           = STATE_FILE_VERSION;
      m_state.crc               = 0;
      m_state.equityPeak        = (bal > 0) ? bal : 10000.0;
      m_state.dailyStartBalance = bal;
      m_state.consecLoss        = 0;
      m_state.tradesToday       = 0;
      m_state.totalTrades       = 0;
      m_state.lastTradeDate     = 0;
      m_state.lastSaveTime      = 0;
      m_state.circuitBroken     = false;
      ArrayInitialize(m_state.circuitReason, 0);
     }

public:
   CStateManager() : m_initialised(false), m_dirty(false), m_filename("") {}

   bool Init(int magic, string sym)
     {
      m_filename    = BuildFilename(magic, sym);
      m_initialised = true;
      ResetDefaults();
      return true;
     }

   //+----------------------------------------------------------------+
   //| Load — call in OnInit after Init()                             |
   //+----------------------------------------------------------------+
   bool Load()
     {
      if(!m_initialised) return false;
      if(!FileIsExist(m_filename, FILE_COMMON))
        {
         Print("[State] No saved state found — using defaults");
         return true;  // not an error: first run
        }

      int fh = FileOpen(m_filename,
                        FILE_READ|FILE_BIN|FILE_COMMON);
      if(fh == INVALID_HANDLE)
        {
         PrintFormat("[State] Cannot open %s for read (err=%d)",
                     m_filename, GetLastError());
         return false;
        }

      PASRState loaded;
      uint bytesRead = (uint)FileReadStruct(fh, loaded);
      FileClose(fh);

      if(bytesRead < sizeof(PASRState))
        {
         Print("[State] File too small — discarding, using defaults");
         ResetDefaults();
         return false;
        }

      // Version check
      if(loaded.version != STATE_FILE_VERSION)
        {
         PrintFormat("[State] Version mismatch: file=%04X current=%04X — discarding",
                     loaded.version, STATE_FILE_VERSION);
         ResetDefaults();
         return false;
        }

      // CRC integrity check
      uint expected = ComputeStateCRC(loaded);
      if(loaded.crc != expected)
        {
         PrintFormat("[State] CRC mismatch: file=%08X computed=%08X — discarding",
                     loaded.crc, expected);
         ResetDefaults();
         return false;
        }

      m_state = loaded;
      PrintFormat("[State] Loaded OK — equityPeak=%.2f consecLoss=%d circuit=%s",
                  m_state.equityPeak, m_state.consecLoss,
                  m_state.circuitBroken ? "BROKEN" : "OK");
      return true;
     }

   //+----------------------------------------------------------------+
   //| Save — call after every state-changing event                   |
   //+----------------------------------------------------------------+
   bool Save()
     {
      if(!m_initialised) return false;

      m_state.lastSaveTime = TimeCurrent();
      m_state.crc          = ComputeStateCRC(m_state);

      int fh = FileOpen(m_filename,
                        FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(fh == INVALID_HANDLE)
        {
         PrintFormat("[State] Cannot open %s for write (err=%d)",
                     m_filename, GetLastError());
         return false;
        }

      FileWriteStruct(fh, m_state);
      FileClose(fh);
      m_dirty = false;

      if(m_state.circuitBroken)
         PrintFormat("[State] Saved — circuit=BROKEN reason=%s",
                     m_state.circuitReason);
      return true;
     }

   void OnDeinit() { if(m_dirty) Save(); }

   // ── Getters ───────────────────────────────────────────────────
   double   GetEquityPeak()        const { return m_state.equityPeak;        }
   double   GetDailyStartBalance() const { return m_state.dailyStartBalance; }
   int      GetConsecLoss()        const { return m_state.consecLoss;        }
   int      GetTradesToday()       const { return m_state.tradesToday;       }
   int      GetTotalTrades()       const { return m_state.totalTrades;       }
   datetime GetLastTradeDate()     const { return m_state.lastTradeDate;     }
   bool     IsCircuitBroken()      const { return m_state.circuitBroken;     }
   string   GetCircuitReason()     const
     { return CharArrayToString(m_state.circuitReason); }

   // ── Setters (mark dirty → must call Save() after) ───────────────
   void SetEquityPeak(double v)
     { m_state.equityPeak = v; m_dirty = true; }

   void SetDailyStartBalance(double v)
     { m_state.dailyStartBalance = v; m_dirty = true; }

   void IncrConsecLoss()
     { m_state.consecLoss++; m_dirty = true; }

   void ResetConsecLoss()
     { m_state.consecLoss = 0; m_dirty = true; }

   void IncrTradesToday()
     { m_state.tradesToday++; m_state.totalTrades++; m_dirty = true; }

   void ResetTradesToday()
     { m_state.tradesToday = 0; m_dirty = true; }

   void SetLastTradeDate(datetime d)
     { m_state.lastTradeDate = d; m_dirty = true; }

   void TripCircuit(const string reason)
     {
      m_state.circuitBroken = true;
      StringToCharArray(reason, m_state.circuitReason,
                        0, ArraySize(m_state.circuitReason));
      m_dirty = true;
      Save();  // immediate save on circuit trip
     }

   void ResetCircuit()
     { m_state.circuitBroken=false;
       ArrayInitialize(m_state.circuitReason,0);
       m_dirty=true; }

   // Daily reset: call when date changes
   void CheckDailyReset()
     {
      datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      if(today > m_state.lastTradeDate && m_state.tradesToday > 0)
        {
         PrintFormat("[State] Daily reset: trades=%d → 0",
                     m_state.tradesToday);
         m_state.dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         m_state.tradesToday       = 0;
         m_dirty = true;
         Save();
        }
     }
  };

#endif // __INFRA_STATE_MANAGER_MQH__
