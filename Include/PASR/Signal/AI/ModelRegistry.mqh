//+------------------------------------------------------------------+
//| AI/ModelRegistry.mqh — v1.00                                      |
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
//| CHANGE LOG:                                                      |
//|   v1.00 (2026-05-21) — Phase 8 initial                           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_MODEL_REGISTRY_MQH__
#define __AI_MODEL_REGISTRY_MQH__

#define MODEL_REG_MAX     8
#define MODEL_REG_VERSION 0x0100

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

   string BuildFilename(int magic, string sym) const
     { StringReplace(sym,"/","_");
       return StringFormat("PASR_ModelReg_%d_%s.bin", magic, sym); }

   uint ComputeCRC() const
     { uint crc = 0xABCD1234;
       crc ^= (uint)m_reg.count;
       crc ^= (uint)m_reg.activeIdx;
       for(int i=0;i<m_reg.count;i++)
         { crc ^= (uint)(m_reg.models[i].winRate*10000);
           crc ^= (uint)m_reg.models[i].totalTrades;
           crc ^= (uint)m_reg.models[i].id; }
       return crc; }

public:
   CModelRegistry() : m_initialised(false) {}

   bool Init(int magic, string sym)
     { m_filename = BuildFilename(magic, sym);
       m_reg.version   = MODEL_REG_VERSION;
       m_reg.count     = 0;
       m_reg.activeIdx = -1;
       m_initialised   = true;
       return true; }

   bool Load()
     { if(!m_initialised) return false;
       if(!FileIsExist(m_filename, FILE_COMMON)) return true;
       int fh = FileOpen(m_filename, FILE_READ|FILE_BIN|FILE_COMMON);
       if(fh==INVALID_HANDLE) return false;
       FileReadStruct(fh, m_reg); FileClose(fh);
       if(m_reg.version != MODEL_REG_VERSION)
         { m_reg.count=0; m_reg.activeIdx=-1; return false; }
       uint expected = ComputeCRC();
       if(m_reg.crc != expected)
         { Print("[ModelReg] CRC mismatch — registry cleared");
           m_reg.count=0; m_reg.activeIdx=-1; return false; }
       PrintFormat("[ModelReg] Loaded: %d versions, active=%d",
                   m_reg.count, m_reg.activeIdx);
       return true; }

   bool Save()
     { if(!m_initialised) return false;
       m_reg.crc = ComputeCRC();
       int fh = FileOpen(m_filename, FILE_WRITE|FILE_BIN|FILE_COMMON);
       if(fh==INVALID_HANDLE) return false;
       FileWriteStruct(fh, m_reg); FileClose(fh);
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
  };

#endif // __AI_MODEL_REGISTRY_MQH__
