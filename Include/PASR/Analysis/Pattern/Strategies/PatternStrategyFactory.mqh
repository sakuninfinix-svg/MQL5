//+------------------------------------------------------------------+
//|                                   PatternStrategyFactory.mqh     |
//|                                 Copyright 2024, PASR Framework   |
//|                                     https://pasr-framework.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Framework"
#property link      "https://pasr-framework.com"
#property version   "2.0.0"
#property description "Factory for creating pattern detection strategies"

#include "IPatternStrategy.mqh"
#include "PinbarStrategy.mqh"
#include "EngulfingStrategy.mqh"
#include "../Config/PatternConfig.mqh"

//+------------------------------------------------------------------+
//| Pattern Strategy Factory                                         |
//+------------------------------------------------------------------+
class CPatternStrategyFactory
{
private:
   CArrayObj            m_strategies;          // Pool of strategy instances
   CPatternConfigManager *m_configManager;     // Configuration manager
   
public:
   void Init(CPatternConfigManager *configManager)
   {
      m_configManager = configManager;
      m_strategies.Clear();
      
      // Create default strategies
      CreateAllStrategies();
   }
   
   ~CPatternStrategyFactory()
   {
      m_strategies.Clear();
   }
   
   // Create all available strategies
   void CreateAllStrategies()
   {
      // Pinbar strategy
      CPinbarStrategy *pinbar = new CPinbarStrategy();
      if(pinbar != NULL)
      {
         pinbar.Init();
         if(m_configManager != NULL)
            pinbar.SetParameters(m_configManager.GetPinbarParams());
         m_strategies.Add(pinbar);
      }
      
      // Engulfing strategy
      CEngulfingStrategy *engulfing = new CEngulfingStrategy();
      if(engulfing != NULL)
      {
         engulfing.Init();
         if(m_configManager != NULL)
            engulfing.SetParameters(m_configManager.GetEngulfingParams());
         m_strategies.Add(engulfing);
      }
      
      // Add more strategies here as they are implemented
      // CInsideBarStrategy, CFakeyStrategy, etc.
   }
   
   // Get strategy by pattern type
   IPatternStrategy* GetStrategy(ENUM_PATTERN_TYPE patternType)
   {
      for(int i = 0; i < m_strategies.Total(); i++)
      {
         IPatternStrategy *strategy = (IPatternStrategy*)m_strategies.At(i);
         if(strategy != NULL && strategy.GetPatternType() == patternType)
            return strategy;
      }
      return NULL;
   }
   
   // Get all strategies
   CArrayObj* GetAllStrategies()
   {
      return &m_strategies;
   }
   
   // Detect patterns using all strategies
   CArrayObj* DetectAllPatterns(int shift, 
                               const CPatternContext &context)
   {
      CArrayObj *results = new CArrayObj();
      if(results == NULL)
         return NULL;
      
      for(int i = 0; i < m_strategies.Total(); i++)
      {
         IPatternStrategy *strategy = (IPatternStrategy*)m_strategies.At(i);
         if(strategy == NULL)
            continue;
         
         ENUM_PATTERN_TYPE ptype = strategy.GetPatternType();
         SPatternParams params;
         
         // Get appropriate params based on pattern type
         if(m_configManager != NULL)
         {
            switch(ptype)
            {
               case PATTERN_PINBAR:
                  params = m_configManager.GetPinbarParams();
                  break;
               case PATTERN_ENGULFING:
                  params = m_configManager.GetEngulfingParams();
                  break;
               case PATTERN_INSIDE_BAR:
                  params = m_configManager.GetInsideBarParams();
                  break;
               case PATTERN_FAKEY:
                  params = m_configManager.GetFakeyParams();
                  break;
               default:
                  params = m_configManager.GetDefaultParams();
            }
         }
         else
         {
            params.Init();
         }
         
         SPatternResult result = strategy.Detect(shift, context, params);
         
         if(result.IsValid())
         {
            // Store result in array (need to wrap in object)
            // For now, just add a pointer to a copy
            SPatternResult *resultPtr = new SPatternResult;
            *resultPtr = result;
            results.Add(resultPtr);
         }
      }
      
      return results;
   }
   
   // Register custom strategy
   bool RegisterStrategy(IPatternStrategy *strategy)
   {
      if(strategy == NULL)
         return false;
      
      strategy.Init();
      m_strategies.Add(strategy);
      return true;
   }
   
   // Remove strategy by type
   bool RemoveStrategy(ENUM_PATTERN_TYPE patternType)
   {
      for(int i = 0; i < m_strategies.Total(); i++)
      {
         IPatternStrategy *strategy = (IPatternStrategy*)m_strategies.At(i);
         if(strategy != NULL && strategy.GetPatternType() == patternType)
         {
            m_strategies.Delete(i);
            return true;
         }
      }
      return false;
   }
   
   // Update configuration for all strategies
   void UpdateConfiguration()
   {
      if(m_configManager == NULL)
         return;
      
      for(int i = 0; i < m_strategies.Total(); i++)
      {
         IPatternStrategy *strategy = (IPatternStrategy*)m_strategies.At(i);
         if(strategy == NULL)
            continue;
         
         ENUM_PATTERN_TYPE ptype = strategy.GetPatternType();
         
         if(ptype == PATTERN_PINBAR)
         {
            CPinbarStrategy *pinbar = (CPinbarStrategy*)strategy;
            pinbar.SetParameters(m_configManager.GetPinbarParams());
         }
         else if(ptype == PATTERN_ENGULFING)
         {
            CEngulfingStrategy *engulfing = (CEngulfingStrategy*)strategy;
            engulfing.SetParameters(m_configManager.GetEngulfingParams());
         }
         // Add more as needed
      }
   }
   
   // Get statistics
   int GetStrategyCount() const
   {
      return m_strategies.Total();
   }
   
   string GetStrategyList() const
   {
      string list = "";
      for(int i = 0; i < m_strategies.Total(); i++)
      {
         IPatternStrategy *strategy = (IPatternStrategy*)m_strategies.At(i);
         if(strategy != NULL)
         {
            if(i > 0)
               list += ", ";
            list += strategy.GetName();
         }
      }
      return list;
   }
};
