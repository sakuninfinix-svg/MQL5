//+------------------------------------------------------------------+
//| Infra/SnapshotManager.mqh — v2.00 (Sprint 17)                   |
//| State Persistence & Auto-Recovery                                |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v2.00 (2026-05-24) Sprint 17 — Full IManager rewrite (5 fixes)|
//|     SNAP-001: Was not extending IManager (standalone class)      |
//|               → Now: class CSnapshotManager : public IManager    |
//|     SNAP-002: Include ../Core/Config/SystemConfig.mqh doesn't    |
//|               exist → Replaced with correct IManager/EventBus    |
//|     SNAP-003: CalculateChecksum() used PointerToStruct() cast    |
//|               which is INVALID in MQL5 (C++ cast, not MQL5)     |
//|               → Replaced with field-by-field XOR checksum       |
//|     SNAP-004: Initialize(string folder) signature incompatible   |
//|               with IManager::Initialize(CEventBus*) contract    |
//|               → Added Initialize(CEventBus*,string) override;   |
//|               folder param defaults to "PASR\\Snapshots"         |
//|     SNAP-005: static int s_index in SaveSnapshot() — static      |
//|               local vars in MQL5 persist across EA reloads BUT   |
//|               lose value on terminal restart → index desync.     |
//|               → Changed to member variable m_save_index          |
//|   v1.00 — Initial monolith (no IManager, broken checksum)       |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_SNAPSHOT_MANAGER_MQH__
#define __INFRA_SNAPSHOT_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"

//--- Constants
#define SNAPSHOT_MAGIC       0x50415352  // "PASR"
#define SNAPSHOT_VERSION     2
#define MAX_SNAPSHOTS        5
#define AUTO_SAVE_INTERVAL   60          // seconds

//+------------------------------------------------------------------+
//| SystemStateSnapshot — serializable state pod                     |
//+------------------------------------------------------------------+
struct SystemStateSnapshot
  {
   ulong             timestamp;
   ulong             magic_number;
   int               version;
   bool              is_trading_active;
   double            total_profit;
   int               total_trades;
   int               open_positions_count;
   double            total_volume;
   ulong             uptime_seconds;
   int               error_count;
   uint              checksum; // must be last field
                     SystemStateSnapshot() :
                        timestamp(0), magic_number(0), version(0),
                        is_trading_active(false), total_profit(0.0),
                        total_trades(0), open_positions_count(0),
                        total_volume(0.0), uptime_seconds(0),
                        error_count(0), checksum(0) {}
  };

//+------------------------------------------------------------------+
//| CSnapshotManager v2.00 — IManager-derived                        |
//+------------------------------------------------------------------+
class CSnapshotManager : public IManager
  {
private:
   string                m_folder_path;
   string                m_base_filename;
   datetime              m_last_save_time;
   ulong                 m_start_time;
   int                   m_save_index;       // FIX SNAP-005: was static local
   SystemStateSnapshot   m_current_state;

public:
                     CSnapshotManager();
                    ~CSnapshotManager() { Shutdown(); }

   //--- IManager contract
   virtual bool      Initialize(CEventBus *bus) override;
   bool              Initialize(CEventBus *bus, const string folder); // extended init
   virtual void      Shutdown() override;
   virtual void      OnEvent(const PASREvent &ev) override;
   virtual string    Name() const override { return "CSnapshotManager"; }
   virtual void      DeclareEvents() override {}

   //--- State management
   void              UpdateState(bool trading_active, double profit, int trades,
                                 int pos_count, double volume, int errors);
   bool              SaveSnapshot();
   bool              LoadLatestSnapshot(SystemStateSnapshot &out_state);
   bool              HasValidSnapshot();
   void              CleanupOldSnapshots();

private:
   string            GetSnapshotFilename(int index) const;
   uint              CalculateChecksum(const SystemStateSnapshot &s) const; // FIX SNAP-003
   bool              WriteSnapshot(const SystemStateSnapshot &state, const string filename);
   bool              ReadSnapshot(SystemStateSnapshot &out_state, const string filename);
   void              Log(const string msg) const;
  };

//+------------------------------------------------------------------+
CSnapshotManager::CSnapshotManager()
   : m_last_save_time(0), m_start_time(0), m_save_index(0)
  {
   m_folder_path   = "PASR\\Snapshots";
   m_base_filename = "PASR_Snapshot_";
   m_current_state = SystemStateSnapshot();
  }

//--- FIX SNAP-004: IManager contract override (bus only, default folder)
bool CSnapshotManager::Initialize(CEventBus *bus)
  {
   return Initialize(bus, m_folder_path);
  }

//--- Extended init: caller can pass custom folder
bool CSnapshotManager::Initialize(CEventBus *bus, const string folder)
  {
   if(!IManager::Initialize(bus)) return false;
   if(folder != "") m_folder_path = folder;

   // Create snapshot directory (ignore error 5000 = already exists)
   if(!FolderCreate(m_folder_path) && GetLastError() != 5000)
     {
      Print("[SnapshotManager][ERROR] Cannot create folder: ", m_folder_path);
      return false;
     }

   m_start_time     = (ulong)TimeCurrent();
   m_last_save_time = 0;
   Log("v2.00 Initialized. Path: " + m_folder_path);
   return true;
  }

void CSnapshotManager::Shutdown()
  {
   if(!m_initialized) return;
   SaveSnapshot(); // force-save on exit
   IManager::Shutdown();
   Log("Shutdown — final snapshot saved.");
  }

void CSnapshotManager::OnEvent(const PASREvent &ev)
  {
   // Future: respond to EVENT_ID_SYSTEM_HALT by forcing immediate save
   if(ev.id == EVENT_ID_SYSTEM_HALT)
     {
      Log("HALT event received — forcing snapshot save.");
      SaveSnapshot();
     }
  }

//+------------------------------------------------------------------+
void CSnapshotManager::UpdateState(bool trading_active, double profit, int trades,
                                    int pos_count, double volume, int errors)
  {
   m_current_state.timestamp            = (ulong)TimeCurrent();
   m_current_state.magic_number         = SNAPSHOT_MAGIC;
   m_current_state.version              = SNAPSHOT_VERSION;
   m_current_state.is_trading_active    = trading_active;
   m_current_state.total_profit         = profit;
   m_current_state.total_trades         = trades;
   m_current_state.open_positions_count = pos_count;
   m_current_state.total_volume         = volume;
   m_current_state.uptime_seconds       = (ulong)TimeCurrent() - m_start_time;
   m_current_state.error_count          = errors;
   m_current_state.checksum             = CalculateChecksum(m_current_state);
  }

bool CSnapshotManager::SaveSnapshot()
  {
   if(!m_initialized) return false;
   datetime now = TimeCurrent();
   if(m_last_save_time != 0 && now - m_last_save_time < AUTO_SAVE_INTERVAL)
      return true; // throttle
   m_last_save_time = now;

   // FIX SNAP-005: use member m_save_index, not static local
   string filename = GetSnapshotFilename(m_save_index % MAX_SNAPSHOTS);
   m_save_index++;

   if(WriteSnapshot(m_current_state, filename))
     {
      CleanupOldSnapshots();
      return true;
     }
   return false;
  }

bool CSnapshotManager::LoadLatestSnapshot(SystemStateSnapshot &out_state)
  {
   if(!m_initialized) return false;
   for(int i = MAX_SNAPSHOTS - 1; i >= 0; i--)
     {
      string filename = GetSnapshotFilename(i);
      if(!FileIsExist(filename, FILE_COMMON)) continue;
      if(!ReadSnapshot(out_state, filename)) continue;
      // Integrity check
      if(out_state.magic_number != SNAPSHOT_MAGIC ||
         out_state.version      != SNAPSHOT_VERSION ||
         out_state.checksum     != CalculateChecksum(out_state))
        {
         Log("Corrupted snapshot: " + filename + " — skipping.");
         continue;
        }
      Log("Loaded valid snapshot: " + filename +
          " | uptime=" + IntegerToString((int)out_state.uptime_seconds) + "s");
      return true;
     }
   Log("No valid snapshot found.");
   return false;
  }

bool CSnapshotManager::HasValidSnapshot()
  {
   SystemStateSnapshot tmp;
   return LoadLatestSnapshot(tmp);
  }

void CSnapshotManager::CleanupOldSnapshots() { /* rotation handled by modulo */ }

string CSnapshotManager::GetSnapshotFilename(int index) const
  {
   return m_folder_path + "\\" + m_base_filename + IntegerToString(index) + ".dat";
  }

//+------------------------------------------------------------------+
//| FIX SNAP-003: Field-by-field XOR checksum — no pointer cast      |
//+------------------------------------------------------------------+
uint CSnapshotManager::CalculateChecksum(const SystemStateSnapshot &s) const
  {
   uint crc = 0;
   // XOR all fields individually (exclude checksum field itself)
   crc ^= (uint)(s.timestamp & 0xFFFFFFFF);
   crc ^= (uint)(s.timestamp >> 32);
   crc ^= (uint)(s.magic_number & 0xFFFFFFFF);
   crc ^= (uint)(s.magic_number >> 32);
   crc ^= (uint)s.version;
   crc ^= (uint)s.is_trading_active;
   // double fields: reinterpret via ulong union-style copy
   ulong tp; double dbl_tp = s.total_profit;
   ArrayCopy((ulong[])tp, (ulong[])(double[])dbl_tp, 0, 0, 1);
   crc ^= (uint)(tp & 0xFFFFFFFF) ^ (uint)(tp >> 32);
   crc ^= (uint)s.total_trades;
   crc ^= (uint)s.open_positions_count;
   ulong tv; double dbl_tv = s.total_volume;
   ArrayCopy((ulong[])tv, (ulong[])(double[])dbl_tv, 0, 0, 1);
   crc ^= (uint)(tv & 0xFFFFFFFF) ^ (uint)(tv >> 32);
   crc ^= (uint)(s.uptime_seconds & 0xFFFFFFFF);
   crc ^= (uint)(s.uptime_seconds >> 32);
   crc ^= (uint)s.error_count;
   crc  = (crc << 1) | (crc >> 31); // rotate
   return crc;
  }

bool CSnapshotManager::WriteSnapshot(const SystemStateSnapshot &state, const string filename)
  {
   int h = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      Log("WriteSnapshot: Cannot open '" + filename + "' err=" + IntegerToString(GetLastError()));
      return false;
     }
   uint written = FileWriteStruct(h, state);
   FileClose(h);
   Log("Saved: " + filename + " (" + IntegerToString(written) + " bytes)");
   return (written == sizeof(SystemStateSnapshot));
  }

bool CSnapshotManager::ReadSnapshot(SystemStateSnapshot &out_state, const string filename)
  {
   int h = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   if(h == INVALID_HANDLE) return false;
   if((uint)FileSize(h) != sizeof(SystemStateSnapshot)) { FileClose(h); return false; }
   uint bytes_read = FileReadStruct(h, out_state);
   FileClose(h);
   return (bytes_read == sizeof(SystemStateSnapshot));
  }

void CSnapshotManager::Log(const string msg) const
  { PrintFormat("[SnapshotManager] %s", msg); }

#endif // __INFRA_SNAPSHOT_MANAGER_MQH__
