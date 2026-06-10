//+------------------------------------------------------------------+
//| Orchestration/Stages/DataSyncStage.mqh                          |
//| Pipeline stage: synchronize market data                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __ORCHESTRATION_DATA_SYNC_STAGE_MQH__
#define __ORCHESTRATION_DATA_SYNC_STAGE_MQH__

#include "PipelineStageBase.mqh"

class CDataSyncStage : public CPipelineStageBase
  {
private:
   IDataManager *m_data;

public:
   CDataSyncStage() : CPipelineStageBase("DataSync"), m_data(NULL) {}

   // Init is NOT part of IPipelineStage — no 'override' here
   bool Init(IDataManager *data)
     {
      m_data = data;
      return (m_data != NULL);
     }
   void Bind(IDataManager *data)
      {
         m_data = data;
      }
   // FIX: match IPipelineStage abstract signature exactly:
   //   ENUM_STAGE_RESULT Execute(PipelineContext &ctx)
   virtual ENUM_STAGE_RESULT Execute(PipelineContext &ctx) override
     {
      if(!m_enabled) return STAGE_SKIP;
      if(m_data == NULL)
        {
         if(m_debug) Print("[DataSyncStage] DataManager is NULL");
         return STAGE_ABORT;
        }
      if(!m_data.IsInitialized())
        {
         if(m_debug) Print("[DataSyncStage] DataManager not ready");
         return STAGE_SKIP;
        }
      return STAGE_OK;
     }

   // FIX: IPipelineStage uses Name() as pure virtual — no StageName()
   virtual string Name() const override { return "DataSync"; }
  };

#endif // __ORCHESTRATION_DATA_SYNC_STAGE_MQH__
