//+------------------------------------------------------------------+
//| AI/ModelRegistry.mqh — v2.00                                      |
//| Model versioning: save, load, promote, compare model versions.  |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Tracks up to 8 model versions per symbol+magic. Each version  |
//|   stores: id, trainDate, win rate, total trades, source label.  |
//|   Orchestrator calls GetBestVersion() / Promote() to decide     |
//|   which model weights to load into AIInference.                 |
//|                                                                  |
//| FILE:                                                            |
//|   MQL5/Files/PASR_ModelReg_{magic}_{symbol}.bin                 |
//|                                                                  |
//| OPTIMIZATIONS v2.00:                                             |
//|   - Retry logic for I/O operations with exponential backoff     |
//|   - Enhanced CRC32 algorithm for better collision resistance    |
//|   - Version check optimization before full read                 |
//|   - Magic number validation for file integrity                  |
//|   - Automatic backup creation on corruption detected            |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v2.00 (2026-05-21) — Retry logic + enhanced integrity checks  |
//|   v1.01 (2026-05-21) — Enhanced CRC + version check optimization |
//|   v1.00 (2026-05-21) — Phase 8 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_MODEL_REGISTRY_MQH__
#define __AI_MODEL_REGISTRY_MQH__

#define MODEL_REG_MAX        8
#define MODEL_REG_VERSION    0x0200  // v2.00
#define MODEL_REG_MAGIC      0xDEADBEEF  // Magic number for file validation
#define MODEL_REG_MAX_RETRIES 3
#define MODEL_REG_RETRY_DELAY_MS 100

struct ModelVersion
  {
   ushort  id;                // sequential 1-based ID
   datetime trainDate;        // when model was trained/promoted
   double  winRate;           // 0.0-1.0
   int     totalTrades;       // trades used for this metric
   double  profitFactor;      // gross profit / gross loss
   double  sharpeProxy;       // mean/stddev of trade returns
   bool    active;            // currently loaded in inference
   char    source[32];        // "backtest", "live", "walkfwd"
   char    notes[64];         // free-form tag
  };

struct ModelRegistryFile
  {
   ushort        version;
   uint          magic;       // Magic number for validation
   uint          crc;
   int           count;
   int           activeIdx;
   ModelVersion  models[MODEL_REG_MAX];
  };

class CModelRegistry
  {
private:
   ModelRegistryFile m_reg;
   string            m_filename;
   bool              m_initialised;
   int               m_retryCount;
   int               m_corruptionCount;

   string BuildFilename(int magic, string sym) const
     { StringReplace(sym,"/","_");
       return StringFormat("PASR_ModelReg_%d_%s.bin", magic, sym); }
   
   // Create backup of corrupted file
   void CreateBackup()
     {
      if(!FileIsExist(m_filename, FILE_COMMON)) return;
      
      string backupName = m_filename + ".bak";
      FileCopy(m_filename, FILE_COMMON, backupName, FILE_COMMON);
      PrintFormat("[ModelReg] Created backup: %s", backupName);
      m_corruptionCount++;
     }
   
   // Enhanced CRC32 with better mixing and magic number
   uint ComputeCRC() const
     { 
      uint crc = 0x811C9DC5;  // FNV-1a offset basis
      // Include magic in CRC
      crc ^= MODEL_REG_MAGIC;
      crc = (crc * 0x01000193);  // FNV prime
      
      crc ^= (uint)m_reg.count * 16777619;
      crc = (crc * 0x01000193);
      crc ^= (uint)m_reg.activeIdx * 16777619;
      
      for(int i=0; i<m_reg.count; i++)
        { 
          crc ^= (uint)(m_reg.models[i].winRate * 10000) * 16777619;
          crc = (crc * 0x01000193);
          crc ^= (uint)m_reg.models[i].totalTrades * 16777619;
          crc = (crc * 0x01000193);
          crc ^= (uint)m_reg.models[i].id * 16777619;
          crc = (crc * 0x01000193);
          crc ^= (uint)(m_reg.models[i].profitFactor * 1000) * 16777619;
          crc = (crc * 0x01000193);
          // Rotate bits for better distribution
          crc = (crc << 13) | (crc >> 19);
          crc ^= (crc >> 17);
        }
      // Final mix
      crc ^= (crc >> 16);
      crc *= 0xed5e4cbf;
      crc ^= (crc >> 13);
      crc *= 0xc4ceb9fe;
      crc ^= (crc >> 16);
      return crc; 
     }
   
   // Retry wrapper for file operations
   template<typename T>
   T FileOperationWithRetry(T (func)(), const string opName)
     {
      int retries = 0;
      while(retries < MODEL_REG_MAX_RETRIES)
        {
         T result = func();
         if(result != NULL || GetLastError() == 0)
           return result;
         
         retries++;
         m_retryCount++;
         Sleep(MODEL_REG_RETRY_DELAY_MS * retries);  // Exponential backoff
        }
      PrintFormat("[ModelReg] %s failed after %d retries", opName, MODEL_REG_MAX_RETRIES);
      return NULL;
     }

public:
   CModelRegistry() : m_initialised(false), m_retryCount(0), m_corruptionCount(0) {}

   bool Init(int magic, string sym)
     { m_filename = BuildFilename(magic, sym);
       m_reg.version   = MODEL_REG_VERSION;
       m_reg.magic     = MODEL_REG_MAGIC;
       m_reg.count     = 0;
       m_reg.activeIdx = -1;
       m_initialised   = true;
       return true; }

   bool Load()
     { 
      if(!m_initialised) return false;
      if(!FileIsExist(m_filename, FILE_COMMON)) return true;
      
      int fh = INVALID_HANDLE;
      for(int retry=0; retry<MODEL_REG_MAX_RETRIES; retry++)
        {
         fh = FileOpen(m_filename, FILE_READ|FILE_BIN|FILE_COMMON);
         if(fh != INVALID_HANDLE) break;
         Sleep(MODEL_REG_RETRY_DELAY_MS * (retry+1));
        }
      
      if(fh == INVALID_HANDLE) 
        {
         PrintFormat("[ModelReg] Load failed after %d retries", MODEL_REG_MAX_RETRIES);
         m_retryCount++;
         return false;
        }
      
      // Check version first before full read
      ushort fileVersion = (ushort)FileReadShort(fh);
      uint fileMagic = FileReadInteger(fh);
      
      if(fileVersion != MODEL_REG_VERSION)
        { 
          FileClose(fh);
          PrintFormat("[ModelReg] Version mismatch: file=%X expected=%X — clearing",
                      fileVersion, MODEL_REG_VERSION);
          CreateBackup();
          m_reg.count=0; m_reg.activeIdx=-1; 
          return false; 
        }
      
      if(fileMagic != MODEL_REG_MAGIC)
        {
          FileClose(fh);
          PrintFormat("[ModelReg] Magic mismatch: file=%X expected=%X — corruption detected",
                      fileMagic, MODEL_REG_MAGIC);
          CreateBackup();
          m_reg.count=0; m_reg.activeIdx=-1;
          return false;
        }
      
      // Reset handle and read full struct
      FileSeek(fh, 0, SEEK_SET);
      FileReadStruct(fh, m_reg); 
      FileClose(fh);
      
      uint expected = ComputeCRC();
      if(m_reg.crc != expected)
        { 
          PrintFormat("[ModelReg] CRC mismatch (expected=%X got=%X) — registry cleared",
                      expected, m_reg.crc);
          CreateBackup();
          m_reg.count=0; m_reg.activeIdx=-1; 
          m_corruptionCount++;
          return false; 
        }
      PrintFormat("[ModelReg] Loaded: %d versions, active=%d",
                  m_reg.count, m_reg.activeIdx);
      return true; 
     }

   bool Save()
     { if(!m_initialised) return false;
       m_reg.crc = ComputeCRC();
       m_reg.magic = MODEL_REG_MAGIC;
       
       int fh = INVALID_HANDLE;
       for(int retry=0; retry<MODEL_REG_MAX_RETRIES; retry++)
         {
          fh = FileOpen(m_filename, FILE_WRITE|FILE_BIN|FILE_COMMON);
          if(fh != INVALID_HANDLE) break;
          Sleep(MODEL_REG_RETRY_DELAY_MS * (retry+1));
         }
       
       if(fh == INVALID_HANDLE)
         {
          PrintFormat("[ModelReg] Save failed after %d retries", MODEL_REG_MAX_RETRIES);
          m_retryCount++;
          return false;
         }
       
       FileWriteStruct(fh, m_reg); 
       FileClose(fh);
       return true; }

   // Register a new model version; returns assigned id
   ushort Register(double winRate, int trades, double pf,
                   double sharpe, const string source,
                   const string notes="")
     { if(m_reg.count >= MODEL_REG_MAX)
         { // Evict worst performing model
           int worst=0;
           for(int i=1;i<MODEL_REG_MAX;i++)
             if(m_reg.models[i].winRate < m_reg.models[worst].winRate) worst=i;
           // Do not evict active model
           if(worst == m_reg.activeIdx) return 0;
           m_reg.models[worst] = ModelVersion();
           m_reg.count--;
         }
       int slot = m_reg.count++;
       ModelVersion &mv = m_reg.models[slot];
       mv.id           = (ushort)(slot + 1);
       mv.trainDate    = TimeCurrent();
       mv.winRate      = MathMax(0.0, MathMin(1.0, winRate));
       mv.totalTrades  = trades;
       mv.profitFactor = pf;
       mv.sharpeProxy  = sharpe;
       mv.active       = false;
       StringToCharArray(source, mv.source, 0, ArraySize(mv.source));
       StringToCharArray(notes,  mv.notes,  0, ArraySize(mv.notes));
       Save();
       PrintFormat("[ModelReg] Registered v%d: WR=%.1f%% trades=%d PF=%.2f",
                   mv.id, mv.winRate*100, trades, pf);
       return mv.id; }

   // Promote a version by slot index
   bool Promote(int idx)
     { if(idx<0||idx>=m_reg.count) return false;
       if(m_reg.activeIdx>=0) m_reg.models[m_reg.activeIdx].active=false;
       m_reg.activeIdx = idx;
       m_reg.models[idx].active = true;
       PrintFormat("[ModelReg] Promoted v%d (WR=%.1f%%)",
                   m_reg.models[idx].id, m_reg.models[idx].winRate*100);
       return Save(); }

   bool PromoteBest()
     { if(m_reg.count==0) return false;
       int best=0;
       for(int i=1;i<m_reg.count;i++)
         if(m_reg.models[i].winRate > m_reg.models[best].winRate) best=i;
       return Promote(best); }

   const ModelVersion* GetActive() const
     { if(m_reg.activeIdx<0||m_reg.activeIdx>=m_reg.count) return NULL;
       return &m_reg.models[m_reg.activeIdx]; }

   const ModelVersion* GetBest() const
     { if(m_reg.count==0) return NULL;
       int best=0;
       for(int i=1;i<m_reg.count;i++)
         if(m_reg.models[i].winRate>m_reg.models[best].winRate) best=i;
       return &m_reg.models[best]; }

   int  Count()       const { return m_reg.count; }
   int  ActiveIdx()   const { return m_reg.activeIdx; }
   
   // Statistics for monitoring
   int    GetRetryCount() const { return m_retryCount; }
   int    GetCorruptionCount() const { return m_corruptionCount; }
   void   ResetStats() { m_retryCount=0; m_corruptionCount=0; }
  };

#endif // __AI_MODEL_REGISTRY_MQH__
