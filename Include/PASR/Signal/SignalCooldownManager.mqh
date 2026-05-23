//+------------------------------------------------------------------+
//| Signal/SignalCooldownManager.mqh — v1.01 (BUG-025 FIXED)        |
//| Manages signal cooldowns and failed zone tracking                |
//|                                                                  |
//| FIX v1.01:                                                       |
//|  BUG-025 — IsPatternFailureBlocked() checked cooldownRemaining   |
//|    field but Tick() was never driven by CleanupExpired().        |
//|    Two independent expiry mechanisms (bar-counter vs timestamp)  |
//|    diverged silently — zones never expired.                      |
//|    Fixed: unified expiry on timestamp only (like signal cooldown)|
//|    FailedZoneItem.IsExpired() is the single source of truth.     |
//|    TickFailedZones() + Tick() kept for backward compat but no    |
//|    longer used for expiry decision.                              |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_COOLDOWN_MANAGER_MQH__
#define __SIGNAL_COOLDOWN_MANAGER_MQH__

#include <Arrays\ArrayObj.mqh>
#include "../Data/SRStruct.mqh"
#include "SignalConfig.mqh"

struct SignalCooldownItem
  {
   double          price;
   datetime        expiry;
   ENUM_SIGNAL_DIR direction;

   void Set(double p, datetime exp, ENUM_SIGNAL_DIR dir)
     { price = p; expiry = exp; direction = dir; }

   bool IsActive(datetime now)                const { return (now < expiry); }
   bool IsSameDirection(ENUM_SIGNAL_DIR dir)  const { return direction == dir; }
  };

struct FailedZoneItem
  {
   double          priceLevel;
   datetime        failTime;
   int             failBar;
   ENUM_SIGNAL_DIR failDir;
   int             cooldownRemaining; // kept for reference; expiry uses timestamp
   datetime        expiryTime;        // BUG-025 FIX: authoritative expiry field

   void Set(double price, datetime time, int bar,
            ENUM_SIGNAL_DIR dir, int cooldown, int periodSeconds)
     {
      priceLevel        = price;
      failTime          = time;
      failBar           = bar;
      failDir           = dir;
      cooldownRemaining = cooldown;
      // BUG-025 FIX: compute expiry once at registration
      expiryTime        = time + (cooldown * periodSeconds);
     }

   bool IsActive()                                 const { return cooldownRemaining > 0; }
   void Tick() { if(cooldownRemaining > 0) cooldownRemaining--; }

   // BUG-025 FIX: timestamp-based expiry (single source of truth)
   bool IsExpiredByTime(datetime now) const { return (now >= expiryTime); }
  };

class CSignalCooldownManager
  {
private:
   CArrayObj               m_cooldowns;
   CArrayObj               m_failedZones;
   const CSignalConfig    *m_config;

   double   m_lastBuyZonePrice;
   double   m_lastSellZonePrice;
   datetime m_lastBuyZoneBar;
   datetime m_lastSellZoneBar;

   bool IsPriceWithinTolerance(double p1, double p2, double tol) const
     { return MathAbs(p1 - p2) <= tol; }

public:
   CSignalCooldownManager() : m_lastBuyZonePrice(0),  m_lastSellZonePrice(0),
                              m_lastBuyZoneBar(0),    m_lastSellZoneBar(0),
                              m_config(NULL) {}

   void Init(const CSignalConfig &config) { m_config = &config; }

   ~CSignalCooldownManager() { Clear(); }

   void Clear() { m_cooldowns.Clear(); m_failedZones.Clear(); }

   bool IsSignalCooldownActive(double price, ENUM_SIGNAL_DIR direction, double atrPoints)
     {
      if(m_config == NULL) return false;
      datetime now = TimeCurrent();
      double tol = atrPoints * m_config.GetZoneReuseATR() * _Point;
      if(m_config.GetSignalCooldownBars() <= 0) return false;

      for(int i = m_cooldowns.Total() - 1; i >= 0; i--)
        {
         SignalCooldownItem *item = (SignalCooldownItem*)m_cooldowns.At(i);
         if(item == NULL) continue;
         if(now > item.expiry) { m_cooldowns.Delete(i); continue; }
         if(item.IsSameDirection(direction) &&
            IsPriceWithinTolerance(price, item.price, tol))
            return true;
        }
      return false;
     }

   void RegisterSignalCooldown(double price, ENUM_SIGNAL_DIR direction)
     {
      if(m_config == NULL) return;
      SignalCooldownItem *item = new SignalCooldownItem();
      if(item == NULL) return;
      int cooldownBars = m_config.GetSignalCooldownBars();
      item.Set(price, TimeCurrent() + cooldownBars * PeriodSeconds(), direction);
      m_cooldowns.Add(item);
      if(m_config.GetDebugMode())
         PrintFormat("[Cooldown] Registered %s @ %.5f for %d bars",
                    direction == SIGNAL_BUY ? "BUY" : "SELL", price, cooldownBars);
     }

   bool IsZoneReuseBlocked(bool isBuy, double zonePrice, double atrPoints)
     {
      if(m_config == NULL) return false;
      datetime currBar = iTime(_Symbol, _Period, 0);
      double tol = atrPoints * m_config.GetZoneReuseATR() * _Point;
      if(isBuy)
         return (m_lastBuyZoneBar  == currBar &&
                 IsPriceWithinTolerance(zonePrice, m_lastBuyZonePrice, tol));
      return   (m_lastSellZoneBar == currBar &&
                 IsPriceWithinTolerance(zonePrice, m_lastSellZonePrice, tol));
     }

   void RegisterZoneUse(bool isBuy, double zonePrice)
     {
      datetime currBar = iTime(_Symbol, _Period, 0);
      if(isBuy) { m_lastBuyZonePrice  = zonePrice; m_lastBuyZoneBar  = currBar; }
      else      { m_lastSellZonePrice = zonePrice; m_lastSellZoneBar = currBar; }
     }

   // BUG-025 FIX: expiry check now uses expiryTime (timestamp) not cooldownRemaining
   bool IsPatternFailureBlocked(bool isBuy, double zonePrice, double atrPoints)
     {
      if(m_config == NULL) return false;
      datetime now = TimeCurrent();
      double tol = atrPoints * m_config.GetZoneReuseATR() * _Point;
      ENUM_SIGNAL_DIR checkDir = isBuy ? SIGNAL_BUY : SIGNAL_SELL;

      for(int i = m_failedZones.Total() - 1; i >= 0; i--)
        {
         FailedZoneItem *item = (FailedZoneItem*)m_failedZones.At(i);
         if(item == NULL) continue;
         // BUG-025 FIX: use timestamp-based expiry
         if(item.IsExpiredByTime(now)) { m_failedZones.Delete(i); continue; }
         if(item.failDir == checkDir &&
            IsPriceWithinTolerance(zonePrice, item.priceLevel, tol))
            return true;
        }
      return false;
     }

   void RegisterFailure(bool isBuy, double zonePrice)
     {
      if(m_config == NULL) return;
      FailedZoneItem *item = new FailedZoneItem();
      if(item == NULL) return;
      int cooldownBars = m_config.GetPatternFailureCooldownBars();
      // BUG-025 FIX: pass PeriodSeconds() so expiryTime is computed on registration
      item.Set(zonePrice, TimeCurrent(),
               iBars(_Symbol, _Period) - 1,
               isBuy ? SIGNAL_BUY : SIGNAL_SELL,
               cooldownBars, PeriodSeconds());
      m_failedZones.Add(item);
      if(m_config.GetDebugMode())
         PrintFormat("[Cooldown] Zone %.5f marked FAILED. Cooldown %d candles.",
                    zonePrice, cooldownBars);
     }

   void CleanupExpired()
     {
      datetime now = TimeCurrent();
      for(int i = m_cooldowns.Total()  - 1; i >= 0; i--)
        {
         SignalCooldownItem *item = (SignalCooldownItem*)m_cooldowns.At(i);
         if(item != NULL && now > item.expiry) m_cooldowns.Delete(i);
        }
      // BUG-025 FIX: use IsExpiredByTime() for failed zones
      for(int i = m_failedZones.Total() - 1; i >= 0; i--)
        {
         FailedZoneItem *item = (FailedZoneItem*)m_failedZones.At(i);
         if(item != NULL && item.IsExpiredByTime(now)) m_failedZones.Delete(i);
        }
     }

   // Kept for backward compat — no longer drives expiry decision
   void TickFailedZones()
     {
      for(int i = m_failedZones.Total() - 1; i >= 0; i--)
        {
         FailedZoneItem *item = (FailedZoneItem*)m_failedZones.At(i);
         if(item != NULL && item.IsActive()) item.Tick();
        }
     }

   int GetActiveCooldownCount()   const { return m_cooldowns.Total();   }
   int GetActiveFailedZoneCount() const { return m_failedZones.Total(); }
  };

#endif // __SIGNAL_COOLDOWN_MANAGER_MQH__
