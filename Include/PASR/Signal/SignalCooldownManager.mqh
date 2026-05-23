//+------------------------------------------------------------------+
//| Signal/SignalCooldownManager.mqh — v1.00                         |
//| Manages signal cooldowns and failed zone tracking                |
//|                                                                  |
//| PURPOSE:                                                         |
//|   - Prevent duplicate signals in same direction within N bars    |
//|   - Track zones that caused StopLoss to prevent re-entry         |
//|   - Safe memory management using CArrayObj                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_COOLDOWN_MANAGER_MQH__
#define __SIGNAL_COOLDOWN_MANAGER_MQH__

#include <Arrays\ArrayObj.mqh>
#include "../Data/SRStruct.mqh"
#include "SignalConfig.mqh"

//+------------------------------------------------------------------+
//| Signal Cooldown Structure                                        |
//| Prevents duplicate signals in same direction within N bars       |
//+------------------------------------------------------------------+
struct SignalCooldownItem
  {
   double   price;              // Price level of signal
   datetime expiry;             // Expiry timestamp
   ENUM_SIGNAL_DIR direction;   // Direction of the signal
   
   void Set(double p, datetime exp, ENUM_SIGNAL_DIR dir)
     {
      price  = p;
      expiry = exp;
      direction = dir;
     }
     
   bool IsActive(datetime now) const
     {
      return (now < expiry);
     }
     
   bool IsSameDirection(ENUM_SIGNAL_DIR dir) const
     {
      return direction == dir;
     }
  };

//+------------------------------------------------------------------+
//| Failed Zone Structure                                            |
//| Tracks zones that caused StopLoss to prevent immediate re-entry  |
//+------------------------------------------------------------------+
struct FailedZoneItem
  {
   double   priceLevel;         // Price level of failed zone
   datetime failTime;           // Time of failure
   int      failBar;            // Bar index of failure
   ENUM_SIGNAL_DIR failDir;     // Direction that failed
   int      cooldownRemaining;  // Bars remaining in cooldown
   
   void Set(double price, datetime time, int bar, ENUM_SIGNAL_DIR dir, int cooldown)
     {
      priceLevel      = price;
      failTime        = time;
      failBar         = bar;
      failDir         = dir;
      cooldownRemaining = cooldown;
     }
     
   bool IsActive() const
     {
      return cooldownRemaining > 0;
     }
     
   void Tick()
     {
      if(cooldownRemaining > 0) cooldownRemaining--;
     }
     
   bool IsExpired(datetime now, int periodSeconds) const
     {
      return (now > failTime + (cooldownRemaining * periodSeconds));
     }
  };

//+------------------------------------------------------------------+
//| CSignalCooldownManager - Cooldown & Zone Failure Manager         |
//+------------------------------------------------------------------+
class CSignalCooldownManager
  {
private:
   CArrayObj m_cooldowns;           // Active signal cooldowns
   CArrayObj m_failedZones;         // Failed zone tracking
   const CSignalConfig *m_config;
   
   // Zone reuse tracking (per-bar)
   double   m_lastBuyZonePrice;
   double   m_lastSellZonePrice;
   datetime m_lastBuyZoneBar;
   datetime m_lastSellZoneBar;
   
   //+------------------------------------------------------------------+
   //| Internal: Check price within tolerance                           |
   //+------------------------------------------------------------------+
   bool IsPriceWithinTolerance(double price1, double price2, double tolerance) const
     {
      return MathAbs(price1 - price2) <= tolerance;
     }
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CSignalCooldownManager() : m_lastBuyZonePrice(0),
                              m_lastSellZonePrice(0),
                              m_lastBuyZoneBar(0),
                              m_lastSellZoneBar(0),
                              m_config(NULL)
     {
     }
   
   //+------------------------------------------------------------------+
   //| Initialize with config                                           |
   //+------------------------------------------------------------------+
   void Init(const CSignalConfig &config)
     {
      m_config = &config;
     }
   
   //+------------------------------------------------------------------+
   //| Destructor - cleanup                                             |
   //+------------------------------------------------------------------+
   ~CSignalCooldownManager()
     {
      Clear();
     }
   
   //+------------------------------------------------------------------+
   //| Clear all cooldowns and failed zones                             |
   //+------------------------------------------------------------------+
   void Clear()
     {
      m_cooldowns.Clear();
      m_failedZones.Clear();
     }
   
   //+------------------------------------------------------------------+
   //| Check if signal cooldown is active for given price/direction     |
   //+------------------------------------------------------------------+
   bool IsSignalCooldownActive(double price, ENUM_SIGNAL_DIR direction, double atrPoints)
     {
      if(m_config == NULL) return false;
      
      datetime now = TimeCurrent();
      double tol = atrPoints * m_config->GetZoneReuseATR() * _Point;
      int cooldownBars = m_config->GetSignalCooldownBars();
      
      if(cooldownBars <= 0) return false;
      
      for(int i = m_cooldowns.Total() - 1; i >= 0; i--)
        {
         SignalCooldownItem *item = (SignalCooldownItem*)m_cooldowns.At(i);
         if(item == NULL) continue;
         
         // Skip expired cooldowns
         if(now > item.expiry)
           {
            m_cooldowns.Delete(i);
            continue;
           }
         
         // Check if same direction and within price tolerance
         if(item.IsSameDirection(direction) && 
            IsPriceWithinTolerance(price, item.price, tol))
           {
            return true;
           }
        }
      
      return false;
     }
   
   //+------------------------------------------------------------------+
   //| Register a new signal cooldown                                   |
   //+------------------------------------------------------------------+
   void RegisterSignalCooldown(double price, ENUM_SIGNAL_DIR direction)
     {
      if(m_config == NULL) return;
      
      SignalCooldownItem *item = new SignalCooldownItem();
      if(item == NULL) return;
      
      int cooldownBars = m_config->GetSignalCooldownBars();
      datetime expiry = TimeCurrent() + (cooldownBars * PeriodSeconds());
      
      item.Set(price, expiry, direction);
      m_cooldowns.Add(item);
      
      if(m_config != NULL && m_config->GetDebugMode())
        {
         PrintFormat("[SignalCooldown] Registered %s cooldown @ %.5f for %d bars",
                    (direction == SIGNAL_BUY ? "BUY" : "SELL"),
                    price, cooldownBars);
        }
     }
   
   //+------------------------------------------------------------------+
   //| Check if zone reuse is blocked (same bar + same zone)            |
   //+------------------------------------------------------------------+
   bool IsZoneReuseBlocked(bool isBuy, double zonePrice, double atrPoints)
     {
      if(m_config == NULL) return false;
      
      datetime currBar = iTime(_Symbol, _Period, 0);
      double tol = atrPoints * m_config->GetZoneReuseATR() * _Point;
      
      if(isBuy)
        {
         return (m_lastBuyZoneBar == currBar && 
                 IsPriceWithinTolerance(zonePrice, m_lastBuyZonePrice, tol));
        }
      
      return (m_lastSellZoneBar == currBar && 
              IsPriceWithinTolerance(zonePrice, m_lastSellZonePrice, tol));
     }
   
   //+------------------------------------------------------------------+
   //| Register zone usage (to prevent duplicate signals on same bar)   |
   //+------------------------------------------------------------------+
   void RegisterZoneUse(bool isBuy, double zonePrice)
     {
      datetime currBar = iTime(_Symbol, _Period, 0);
      
      if(isBuy)
        {
         m_lastBuyZonePrice = zonePrice;
         m_lastBuyZoneBar = currBar;
        }
      else
        {
         m_lastSellZonePrice = zonePrice;
         m_lastSellZoneBar = currBar;
        }
     }
   
   //+------------------------------------------------------------------+
   //| Check if pattern failure cooldown is active                      |
   //+------------------------------------------------------------------+
   bool IsPatternFailureBlocked(bool isBuy, double zonePrice, double atrPoints)
     {
      if(m_config == NULL) return false;
      
      double tol = atrPoints * m_config->GetZoneReuseATR() * _Point;
      ENUM_SIGNAL_DIR checkDir = isBuy ? SIGNAL_BUY : SIGNAL_SELL;
      
      for(int i = m_failedZones.Total() - 1; i >= 0; i--)
        {
         FailedZoneItem *item = (FailedZoneItem*)m_failedZones.At(i);
         if(item == NULL) continue;
         
         // Check if same direction and within price tolerance
         if(item.failDir == checkDir && 
            IsPriceWithinTolerance(zonePrice, item.priceLevel, tol))
           {
            return true;
           }
        }
      
      return false;
     }
   
   //+------------------------------------------------------------------+
   //| Register a pattern failure                                       |
   //+------------------------------------------------------------------+
   void RegisterFailure(bool isBuy, double zonePrice)
     {
      if(m_config == NULL) return;
      
      FailedZoneItem *item = new FailedZoneItem();
      if(item == NULL) return;
      
      int cooldownBars = m_config->GetPatternFailureCooldownBars();
      
      item.Set(zonePrice, 
               TimeCurrent(), 
               iBars(_Symbol, _Period) - 1,
               isBuy ? SIGNAL_BUY : SIGNAL_SELL,
               cooldownBars);
      
      m_failedZones.Add(item);
      
      if(m_config->GetDebugMode())
        {
         PrintFormat("[SignalCooldown] Level %.5f registered as FAILED. Cooldown %d candles.",
                    zonePrice, cooldownBars);
        }
     }
   
   //+------------------------------------------------------------------+
   //| Cleanup expired cooldowns                                        |
   //+------------------------------------------------------------------+
   void CleanupExpired()
     {
      datetime now = TimeCurrent();
      
      // Cleanup signal cooldowns
      for(int i = m_cooldowns.Total() - 1; i >= 0; i--)
        {
         SignalCooldownItem *item = (SignalCooldownItem*)m_cooldowns.At(i);
         if(item == NULL) continue;
         
         if(now > item.expiry)
           {
            m_cooldowns.Delete(i);
           }
        }
      
      // Cleanup failed zones
      int periodSeconds = PeriodSeconds();
      for(int i = m_failedZones.Total() - 1; i >= 0; i--)
        {
         FailedZoneItem *item = (FailedZoneItem*)m_failedZones.At(i);
         if(item == NULL) continue;
         
         if(now > item.failTime + (item.cooldownRemaining * periodSeconds))
           {
            m_failedZones.Delete(i);
           }
        }
     }
   
   //+------------------------------------------------------------------+
   //| Tick failed zone cooldowns (decrement counters)                  |
   //+------------------------------------------------------------------+
   void TickFailedZones()
     {
      for(int i = m_failedZones.Total() - 1; i >= 0; i--)
        {
         FailedZoneItem *item = (FailedZoneItem*)m_failedZones.At(i);
         if(item != NULL && item.IsActive())
           {
            item.Tick();
            
            // Remove if expired
            if(!item.IsActive())
              {
               m_failedZones.Delete(i);
              }
           }
        }
     }
   
   //+------------------------------------------------------------------+
   //| Get count of active cooldowns                                    |
   //+------------------------------------------------------------------+
   int GetActiveCooldownCount() const
     {
      return m_cooldowns.Total();
     }
   
   //+------------------------------------------------------------------+
   //| Get count of active failed zones                                 |
   //+------------------------------------------------------------------+
   int GetActiveFailedZoneCount() const
     {
      return m_failedZones.Total();
     }
  };

#endif // __SIGNAL_COOLDOWN_MANAGER_MQH__
