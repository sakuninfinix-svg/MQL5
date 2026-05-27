//+------------------------------------------------------------------+
//| Analysis/Pattern/Core/IPatternStage.mqh — v1.01                  |
//| Self-contained pattern pipeline stage interface                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_PATTERN_CORE_IPATTERN_STAGE_MQH__
#define __ANALYSIS_PATTERN_CORE_IPATTERN_STAGE_MQH__

class CPatternContext;

enum ENUM_STAGE_STATUS
  {
   STAGE_OK    = 0,
   STAGE_SKIP  = 1,
   STAGE_FAIL  = 2,
   STAGE_ABORT = 3
  };

class IPatternStage
  {
protected:
   string m_name;
   bool   m_enabled;

public:
   IPatternStage() : m_name("PatternStage"), m_enabled(true) {}
   virtual ~IPatternStage() {}

   void SetName(const string name) { m_name = name; }
   string GetName() const { return m_name; }
   void Enable(bool enabled = true) { m_enabled = enabled; }
   bool IsEnabled() const { return m_enabled; }

   virtual ENUM_STAGE_STATUS Process(CPatternContext &ctx) = 0;
   virtual bool Init() { return true; }
   virtual void Shutdown() {}
   virtual string GetDescription() const { return m_name; }
  };

void LogStageMessage(const string stage_name, const string message)
  {
   Print("[PatternPipeline::", stage_name, "] ", message);
  }

#endif // __ANALYSIS_PATTERN_CORE_IPATTERN_STAGE_MQH__
