//+------------------------------------------------------------------+
//|                                             IPatternStage.mqh    |
//|                                 Copyright 2024, PASR Architecture|
//|                                     https://pasr-architecture.com|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr-architecture.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Interface untuk Pattern Pipeline Stage                           |
//+------------------------------------------------------------------+
#include "..\..\Core\Config\Types.mqh"

// Forward declaration
class CPatternContext;

//+------------------------------------------------------------------+
//| Enum untuk status eksekusi stage                                 |
//+------------------------------------------------------------------+
enum ENUM_STAGE_STATUS
{
   STAGE_OK       = 0,  // Stage berhasil
   STAGE_SKIP     = 1,  // Stage di-skip (kondisi tidak terpenuhi)
   STAGE_FAIL     = 2,  // Stage gagal (error)
   STAGE_ABORT    = 3   // Stage abort (hentikan pipeline)
};

//+------------------------------------------------------------------+
//| Interface Base untuk semua Pattern Stage                         |
//+------------------------------------------------------------------+
class IPatternStage
{
protected:
   string m_name;
   bool   m_enabled;
   
public:
   IPatternStage() : m_enabled(true) {}
   virtual ~IPatternStage() {}
   
   // Set nama stage
   void SetName(const string name) { m_name = name; }
   string GetName() const { return m_name; }
   
   // Enable/Disable stage
   void Enable(bool enabled = true) { m_enabled = enabled; }
   bool IsEnabled() const { return m_enabled; }
   
   //+------------------------------------------------------------------+
   //| Method utama yang harus diimplementasikan oleh subclass          |
   //+------------------------------------------------------------------+
   virtual ENUM_STAGE_STATUS Process(CPatternContext &ctx) = 0;
   
   //+------------------------------------------------------------------+
   //| Optional: Initialization                                         |
   //+------------------------------------------------------------------+
   virtual bool Init() { return true; }
   
   //+------------------------------------------------------------------+
   //| Optional: Cleanup                                                |
   //+------------------------------------------------------------------+
   virtual void Shutdown() {}
   
   //+------------------------------------------------------------------+
   //| Get description                                                  |
   //+------------------------------------------------------------------+
   virtual string GetDescription() const { return m_name; }
};

//+------------------------------------------------------------------+
//| Helper function untuk logging stage                              |
//+------------------------------------------------------------------+
void LogStageMessage(const string stage_name, const string message, ENUM_LOG_LEVEL level = LOG_INFO)
{
   string prefix = "[PatternPipeline::" + stage_name + "] ";
   
   switch(level)
   {
      case LOG_DEBUG:
         PrintDebug(prefix + message);
         break;
      case LOG_WARNING:
         PrintWarning(prefix + message);
         break;
      case LOG_ERROR:
         PrintError(prefix + message);
         break;
      default:
         PrintInfo(prefix + message);
   }
}
//+------------------------------------------------------------------+
