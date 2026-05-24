//+------------------------------------------------------------------+
//| Infra/SnapshotManager.mqh — v2.01                                |
//| State Persistence & Auto-Recovery                                |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_SNAPSHOT_MANAGER_MQH__
#define __INFRA_SNAPSHOT_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"

#define SNAPSHOT_MAGIC       0x50415352
#define SNAPSHOT_VERSION     2
#define MAX_SNAPSHOTS        5
#define AUTO_SAVE_INTERVAL   60

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
   uint              checksum;
                     SystemStateSnapshot() :
                        timestamp(0), magic_number(0), version(0),
                        is_trading_active(false), total_profit(0.0),
                        total_trades(0), open_positions_count(0),
                        total_volume(0.0), uptime_seconds(0),
                        error_count(0), checksum(0) {}
  };

class CSnapshotManager : public IManager
  {
private:
   string                m_folder_path;
   string                m_base_filename;
   datetime              m_last_save_time;
   ulong                 m_start_time;
   int                   m_save_index;
   SystemStateSnapshot   m_current_state;

   uint MixDouble(uint crc, double value) const
     {
      string s = DoubleToString(value, 8);
      for(int i = 0; i < StringLen(s); i++)
        {
         crc ^= (uint)StringGetCharacter(s, i);
         crc = (crc << 5) | (crc >> 27);
        }
      return crc;
     }

public:
   CSnapshotManager()
      : IManager(), m_last_save_time(0), m_start_time(0), m_save_index(0)
     {
      m_folder_path   = "PASR\\Snapshots";
      m_base_filename = "PASR_Snapshot_";
      m_current_state = SystemStateSnapshot();
     }

   ~CSnapshotManager() { Deinit(); }

   virtual string HandlerName() const override { return "SnapshotManager"; }

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_SYSTEM_HALT); }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      return ConfigureFolder(m_folder_path);
     }

   bool Init(IDataManager *data, CEventBus *bus, const string folder)
     {
      if(folder != "") m_folder_path = folder;
      if(!IManager::Init(data, bus)) return false;
      return ConfigureFolder(m_folder_path);
     }

   bool ConfigureFolder(const string folder)
     {
      if(folder != "") m_folder_path = folder;
      if(!FolderCreate(m_folder_path) && GetLastError() != 5000)
        {
         Print("[SnapshotManager][ERROR] Cannot create folder: ", m_folder_path);
         return false;
        }
      m_start_time     = (ulong)TimeCurrent();
      m_last_save_time = 0;
      Log("v2.01 Initialized. Path: " + m_folder_path);
      return true;
     }

   virtual void Deinit() override
     {
      if(!m_initialized) return;
      SaveSnapshot();
      IManager::Deinit();
      Log("Deinit — final snapshot saved.");
     }

   void Shutdown() { Deinit(); }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_SYSTEM_HALT)
        {
         Log("HALT event received — forcing snapshot save.");
         SaveSnapshot();
        }
     }

   void UpdateState(bool trading_active, double profit, int trades,
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

   bool SaveSnapshot()
     {
      if(!m_initialized) return false;
      datetime now = TimeCurrent();
      if(m_last_save_time != 0 && now - m_last_save_time < AUTO_SAVE_INTERVAL)
         return true;
      m_last_save_time = now;

      string filename = GetSnapshotFilename(m_save_index % MAX_SNAPSHOTS);
      m_save_index++;
      if(WriteSnapshot(m_current_state, filename))
        {
         CleanupOldSnapshots();
         return true;
        }
      return false;
     }

   bool LoadLatestSnapshot(SystemStateSnapshot &out_state)
     {
      if(!m_initialized) return false;
      for(int i = MAX_SNAPSHOTS - 1; i >= 0; i--)
        {
         string filename = GetSnapshotFilename(i);
         if(!FileIsExist(filename, FILE_COMMON)) continue;
         if(!ReadSnapshot(out_state, filename)) continue;
         if(out_state.magic_number != SNAPSHOT_MAGIC ||
            out_state.version != SNAPSHOT_VERSION ||
            out_state.checksum != CalculateChecksum(out_state))
           {
            Log("Corrupted snapshot: " + filename + " — skipping.");
            continue;
           }
         Log("Loaded valid snapshot: " + filename);
         return true;
        }
      Log("No valid snapshot found.");
      return false;
     }

   bool HasValidSnapshot()
     {
      SystemStateSnapshot tmp;
      return LoadLatestSnapshot(tmp);
     }

   void CleanupOldSnapshots() {}

private:
   string GetSnapshotFilename(int index) const
     { return m_folder_path + "\\" + m_base_filename + IntegerToString(index) + ".dat"; }

   uint CalculateChecksum(const SystemStateSnapshot &s) const
     {
      uint crc = 0;
      crc ^= (uint)(s.timestamp & 0xFFFFFFFF);
      crc ^= (uint)(s.timestamp >> 32);
      crc ^= (uint)(s.magic_number & 0xFFFFFFFF);
      crc ^= (uint)(s.magic_number >> 32);
      crc ^= (uint)s.version;
      crc ^= (uint)s.is_trading_active;
      crc = MixDouble(crc, s.total_profit);
      crc ^= (uint)s.total_trades;
      crc ^= (uint)s.open_positions_count;
      crc = MixDouble(crc, s.total_volume);
      crc ^= (uint)(s.uptime_seconds & 0xFFFFFFFF);
      crc ^= (uint)(s.uptime_seconds >> 32);
      crc ^= (uint)s.error_count;
      crc = (crc << 1) | (crc >> 31);
      return crc;
     }

   bool WriteSnapshot(const SystemStateSnapshot &state, const string filename)
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

   bool ReadSnapshot(SystemStateSnapshot &out_state, const string filename)
     {
      int h = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
      if(h == INVALID_HANDLE) return false;
      if((uint)FileSize(h) != sizeof(SystemStateSnapshot)) { FileClose(h); return false; }
      uint bytes_read = FileReadStruct(h, out_state);
      FileClose(h);
      return (bytes_read == sizeof(SystemStateSnapshot));
     }

   void Log(const string msg) const
     { PrintFormat("[SnapshotManager] %s", msg); }
  };

#endif // __INFRA_SNAPSHOT_MANAGER_MQH__
