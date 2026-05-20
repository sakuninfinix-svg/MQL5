//+------------------------------------------------------------------+
//|                                                3.MarketManager.mqh |
//|                                       Copyright 2026, Agsicentre   |
//|            Market Data & Session Management Module                 |
//+------------------------------------------------------------------+
//| PURPOSE: Centralized market data access, session management,      |
//|          spread tracking, and trading hour validation.            |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.00"
#property strict

#ifndef __MARKET_MANAGER_MQH__
#define __MARKET_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"

//+------------------------------------------------------------------+
//| Market Session Definition                                        |
//+------------------------------------------------------------------+
struct MarketSession
{
   string name;
   int    openHour;
   int    openMinute;
   int    closeHour;
   int    closeMinute;
   bool   active;
   
   MarketSession() : openHour(0), openMinute(0), closeHour(0), closeMinute(0), active(false) {}
   
   bool IsWithinSession(datetime checkTime) const
   {
      MqlDateTime dt;
      TimeToStruct(checkTime, dt);
      
      int currentMinutes = dt.hour * 60 + dt.min;
      int openMinutes = openHour * 60 + openMinute;
      int closeMinutes = closeHour * 60 + closeMinute;
      
      if(openMinutes <= closeMinutes)
         return (currentMinutes >= openMinutes && currentMinutes <= closeMinutes);
      else
         return (currentMinutes >= openMinutes || currentMinutes <= closeMinutes); // Overnight session
   }
};

//+------------------------------------------------------------------+
//| MarketManager Class                                              |
//+------------------------------------------------------------------+
class MarketManager : public IManager
{
private:
   MarketSession m_sessions[7]; // One per day of week
   double       m_currentSpread;
   double       m_avgSpread;
   datetime     m_lastSpreadUpdate;
   bool         m_tradingAllowed;
   
public:
   MarketManager() : m_currentSpread(0), m_avgSpread(0), m_lastSpreadUpdate(0), m_tradingAllowed(true)
   {
      ZeroMemory(m_sessions);
   }
   
   virtual ~MarketManager() {}
   
   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      
      m_symbol = _Symbol;
      m_tradingAllowed = true;
      InitializeSessions();
      
      Log("✅ MarketManager initialized for " + m_symbol);
      return true;
   }
   
   virtual void Deinit() override
   {
      m_tradingAllowed = false;
      IManager::Deinit();
   }
   
   //--- Session Management ---
   void InitializeSessions()
   {
      // Default: 24/5 trading (can be overridden by config)
      for(int i = 0; i < 7; i++)
      {
         m_sessions[i].active = (i >= 1 && i <= 5); // Mon-Fri
         m_sessions[i].openHour = 0;
         m_sessions[i].openMinute = 0;
         m_sessions[i].closeHour = 23;
         m_sessions[i].closeMinute = 59;
         
         if(i == 0) m_sessions[i].name = "Sunday";
         else if(i == 1) m_sessions[i].name = "Monday";
         else if(i == 2) m_sessions[i].name = "Tuesday";
         else if(i == 3) m_sessions[i].name = "Wednesday";
         else if(i == 4) m_sessions[i].name = "Thursday";
         else if(i == 5) m_sessions[i].name = "Friday";
         else if(i == 6) m_sessions[i].name = "Saturday";
      }
   }
   
   bool IsTradingSession() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      int dayOfWeek = dt.day_of_week; // 0=Sun, 1=Mon, ..., 6=Sat
      if(dayOfWeek < 0 || dayOfWeek > 6) return false;
      
      return m_sessions[dayOfWeek].active && 
             m_sessions[dayOfWeek].IsWithinSession(TimeCurrent());
   }
   
   //--- Spread Management ---
   double GetCurrentSpread()
   {
      long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(spread >= 0)
      {
         m_currentSpread = (double)spread;
         m_lastSpreadUpdate = TimeCurrent();
      }
      return m_currentSpread;
   }
   
   double GetAverageSpread() const
   {
      return m_avgSpread;
   }
   
   void UpdateSpreadHistory(double spread)
   {
      // Simple moving average
      m_avgSpread = m_avgSpread * 0.95 + spread * 0.05;
   }
   
   bool IsSpreadAcceptable(double maxSpread) const
   {
      return GetCurrentSpread() <= maxSpread;
   }
   
   //--- Trading Control ---
   void SetTradingAllowed(bool allowed) { m_tradingAllowed = allowed; }
   bool IsTradingAllowed() const { return m_tradingAllowed && IsTradingSession(); }
   
   //--- Event Handlers ---
   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SESSION_CHANGE);
      AddEvent(EVENT_ID_MARKET_GATE);
   }
   
   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      // Update spread periodically
      GetCurrentSpread();
      UpdateSpreadHistory(m_currentSpread);
      
      // Check session changes
      static bool wasInSession = false;
      bool isInSession = IsTradingSession();
      
      if(wasInSession != isInSession)
      {
         wasInSession = isInSession;
         
         // Emit session change event
         SessionChangeEvent *sessionEvent = new SessionChangeEvent(isInSession, "TradingSession");
         if(CheckPointer(sessionEvent) != POINTER_INVALID)
            DispatchEvent(sessionEvent);
         
         Log("Session state changed: " + (isInSession ? "ACTIVE" : "INACTIVE"));
      }
      
      // Emit market gate status
      bool gateOpen = IsTradingAllowed() && IsSpreadAcceptable(Config().filters.maxSpread);
      MarketGateEvent *gateEvent = new MarketGateEvent(
         gateOpen,
         m_currentSpread,
         DataManager::Instance().GetATRPoints(),
         m_tradingAllowed
      );
      if(CheckPointer(gateEvent) != POINTER_INVALID)
         DispatchEvent(gateEvent);
   }
};

#endif // __MARKET_MANAGER_MQH__