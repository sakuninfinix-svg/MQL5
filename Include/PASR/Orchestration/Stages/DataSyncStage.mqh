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
   // REMOVED: bool m_enabled — inherited from CPipelineStageBase
   // REMOVED: bool m_debug   — inherited from CPipelineStageBase
   IDataManager *m_data;

public:
   CDataSyncStage() : CPipelineStageBase("DataSync"), m_data(NULL) {}

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!CPipelineStageBase::Init(data, bus)) return false;
      m_data = data;
      return true;
   }

   virtual bool Execute(SPipelineContext &ctx) override
   {
      if(!m_enabled) return true;

      if(m_data == NULL)
      {
         if(m_debug) Print("[DataSyncStage] DataManager is NULL");
         return false;
      }

      if(!m_data->IsReady())
      {
         if(m_debug) Print("[DataSyncStage] DataManager not ready");
         return false;
      }

      ctx.data_ready = true;
      return true;
   }

   virtual string StageName() const override { return "DataSync"; }
};

#endif // __ORCHESTRATION_DATA_SYNC_STAGE_MQH__
