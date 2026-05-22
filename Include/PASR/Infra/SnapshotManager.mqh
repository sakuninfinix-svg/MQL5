//+------------------------------------------------------------------+
//| SnapshotManager.mqh                                              |
//| Copyright 2024, PASR Architecture                                |
//| State Persistence & Auto-Recovery                                |
//+------------------------------------------------------------------+
#property copyright "2024, PASR Architecture"
#property link      "https://pasr.quant"
#property version   "1.00"

#include <File.mqh>
#include "../Core/Config/SystemConfig.mqh"

//--- Constants
#define SNAPSHOT_MAGIC       0x50415352  // "PASR"
#define SNAPSHOT_VERSION     1
#define MAX_SNAPSHOTS        5
#define AUTO_SAVE_INTERVAL   60          // Seconds

//+------------------------------------------------------------------+
//| Structure: SystemStateSnapshot                                   |
//+------------------------------------------------------------------+
struct SystemStateSnapshot
{
   ulong      timestamp;
   ulong      magic_number;
   int        version;
   
   // Global State
   bool       is_trading_active;
   double     total_profit;
   int        total_trades;
   
   // Position State (Simplified for demo - in real impl, serialize full position list)
   int        open_positions_count;
   double     total_volume;
   
   // Runtime Metrics
   ulong      uptime_seconds;
   int        error_count;
   
   // Checksum for integrity
   uint       checksum;
};

//+------------------------------------------------------------------+
//| Class CSnapshotManager                                           |
//+------------------------------------------------------------------+
class CSnapshotManager
{
private:
   string             m_folder_path;
   string             m_base_filename;
   datetime           m_last_save_time;
   ulong              m_start_time;
   bool               m_initialized;
   
   // Current state cache
   SystemStateSnapshot m_current_state;
   
public:
   CSnapshotManager();
   ~CSnapshotManager();
   
   bool Initialize(const string folder);
   void Shutdown();
   
   // State Management
   void UpdateState(bool trading_active, double profit, int trades, int pos_count, double volume, int errors);
   bool SaveSnapshot();
   bool LoadLatestSnapshot(SystemStateSnapshot &out_state);
   
   // Utilities
   bool HasValidSnapshot();
   void CleanupOldSnapshots();
   
private:
   string GetSnapshotFilename(int index);
   uint CalculateChecksum(const SystemStateSnapshot &state);
   bool WriteSnapshot(const SystemStateSnapshot &state, const string filename);
   bool ReadSnapshot(SystemStateSnapshot &out_state, const string filename);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSnapshotManager::CSnapshotManager()
{
   m_initialized = false;
   m_last_save_time = 0;
   m_start_time = TimeCurrent();
   m_folder_path = "";
   m_base_filename = "PASR_Snapshot_";
   ZeroMemory(m_current_state);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSnapshotManager::~CSnapshotManager()
{
   Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSnapshotManager::Initialize(const string folder)
{
   if(folder == "") return false;
   
   m_folder_path = folder;
   if(!DirCreate(m_folder_path))
   {
      if(GetLastError() != 5000) // Already exists
      {
         Print("SNAPSHOT:: Error creating folder: ", m_folder_path);
         return false;
      }
   }
   
   m_initialized = true;
   m_start_time = TimeCurrent();
   Print("SNAPSHOT:: Initialized. Path: ", m_folder_path);
   return true;
}

//+------------------------------------------------------------------+
//| Shutdown                                                         |
//+------------------------------------------------------------------+
void CSnapshotManager::Shutdown()
{
   if(m_initialized)
   {
      SaveSnapshot(); // Force save on exit
      m_initialized = false;
      Print("SNAPSHOT:: Shutdown complete.");
   }
}

//+------------------------------------------------------------------+
//| Update State                                                     |
//+------------------------------------------------------------------+
void CSnapshotManager::UpdateState(bool trading_active, double profit, int trades, 
                                   int pos_count, double volume, int errors)
{
   m_current_state.timestamp = (ulong)TimeCurrent();
   m_current_state.magic_number = SNAPSHOT_MAGIC;
   m_current_state.version = SNAPSHOT_VERSION;
   m_current_state.is_trading_active = trading_active;
   m_current_state.total_profit = profit;
   m_current_state.total_trades = trades;
   m_current_state.open_positions_count = pos_count;
   m_current_state.total_volume = volume;
   m_current_state.uptime_seconds = TimeCurrent() - m_start_time;
   m_current_state.error_count = errors;
   m_current_state.checksum = CalculateChecksum(m_current_state);
}

//+------------------------------------------------------------------+
//| Save Snapshot                                                    |
//+------------------------------------------------------------------+
bool CSnapshotManager::SaveSnapshot()
{
   if(!m_initialized) return false;
   
   datetime now = TimeCurrent();
   // Throttle saves
   if(now - m_last_save_time < AUTO_SAVE_INTERVAL && m_last_save_time != 0)
      return true; // Skip, not enough time passed
      
   m_last_save_time = now;
   
   // Rotate filename index
   static int s_index = 0;
   string filename = GetSnapshotFilename(s_index % MAX_SNAPSHOTS);
   s_index++;
   
   if(WriteSnapshot(m_current_state, filename))
   {
      CleanupOldSnapshots();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Load Latest Snapshot                                             |
//+------------------------------------------------------------------+
bool CSnapshotManager::LoadLatestSnapshot(SystemStateSnapshot &out_state)
{
   if(!m_initialized) return false;
   
   // Try from newest to oldest
   for(int i = MAX_SNAPSHOTS - 1; i >= 0; i--)
   {
      string filename = GetSnapshotFilename(i);
      if(FileIsExist(filename))
      {
         if(ReadSnapshot(out_state, filename))
         {
            // Validate integrity
            if(out_state.magic_number != SNAPSHOT_MAGIC || 
               out_state.version != SNAPSHOT_VERSION ||
               out_state.checksum != CalculateChecksum(out_state))
            {
               Print("SNAPSHOT:: Corrupted snapshot detected: ", filename);
               continue; // Try next
            }
            
            Print("SNAPSHOT:: Loaded valid snapshot: ", filename, 
                  " | Uptime: ", out_state.uptime_seconds, "s");
            return true;
         }
      }
   }
   
   Print("SNAPSHOT:: No valid snapshot found.");
   return false;
}

//+------------------------------------------------------------------+
//| Has Valid Snapshot                                               |
//+------------------------------------------------------------------+
bool CSnapshotManager::HasValidSnapshot()
{
   SystemStateSnapshot temp;
   return LoadLatestSnapshot(temp);
}

//+------------------------------------------------------------------+
//| Cleanup Old Snapshots                                            |
//+------------------------------------------------------------------+
void CSnapshotManager::CleanupOldSnapshots()
{
   // Simple rotation: keep only last MAX_SNAPSHOTS
   // Handled by modulo logic in SaveSnapshot
}

//+------------------------------------------------------------------+
//| Get Snapshot Filename                                            |
//+------------------------------------------------------------------+
string CSnapshotManager::GetSnapshotFilename(int index)
{
   return m_folder_path + "\\" + m_base_filename + IntegerToString(index) + ".dat";
}

//+------------------------------------------------------------------+
//| Calculate Checksum                                               |
//+------------------------------------------------------------------+
uint CSnapshotManager::CalculateChecksum(const SystemStateSnapshot &state)
{
   // Simple XOR checksum (replace with CRC32 for production)
   uint crc = 0;
   uchar &data = *(uchar*)::PointerToStruct(state);
   int size = sizeof(SystemStateSnapshot) - sizeof(uint); // Exclude checksum field itself
   
   for(int i = 0; i < size; i++)
   {
      crc ^= (uint)data[i];
      crc = (crc << 1) | (crc >> 31);
   }
   return crc;
}

//+------------------------------------------------------------------+
//| Write Snapshot to File                                           |
//+------------------------------------------------------------------+
bool CSnapshotManager::WriteSnapshot(const SystemStateSnapshot &state, const string filename)
{
   int handle = FileOpen(filename, FILE_WRITE | FILE_BIN);
   if(handle == INVALID_HANDLE)
   {
      Print("SNAPSHOT:: Failed to open file for writing: ", filename, " Error: ", GetLastError());
      return false;
   }
   
   FileWriteBuffer(handle, 0, state, sizeof(SystemStateSnapshot));
   FileClose(handle);
   
   Print("SNAPSHOT:: Saved state to: ", filename);
   return true;
}

//+------------------------------------------------------------------+
//| Read Snapshot from File                                          |
//+------------------------------------------------------------------+
bool CSnapshotManager::ReadSnapshot(SystemStateSnapshot &out_state, const string filename)
{
   if(!FileIsExist(filename)) return false;
   
   int handle = FileOpen(filename, FILE_READ | FILE_BIN);
   if(handle == INVALID_HANDLE)
   {
      Print("SNAPSHOT:: Failed to open file for reading: ", filename);
      return false;
   }
   
   if(FileSize(handle) != sizeof(SystemStateSnapshot))
   {
      FileClose(handle);
      return false;
   }
   
   FileReadBuffer(handle, 0, out_state, sizeof(SystemStateSnapshot));
   FileClose(handle);
   
   return true;
}
