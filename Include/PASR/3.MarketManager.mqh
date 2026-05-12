//+------------------------------------------------------------------+
//|               Price Action & Support Resistance V1               |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#ifndef __MARKET_MANAGER_MQH__
#define __MARKET_MANAGER_MQH__

#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#include "IManager.mqh"
#include "10.DataManager.mqh"

class MarketManager : public IManager
{
private:
   string m_baseCurr;
   string m_profitCurr;

   // --- Internal State Variables ---
   string m_newsStatus;
   datetime m_nextNewsTime;
   datetime m_lastBarTime;
   datetime m_dayAnchor;
   datetime m_lastNewsCheck;
   bool m_lastNewsResult;
   datetime m_lastWebFetch;
   datetime m_webNewsTimes[];
   int m_sessionStarts[7];
   int m_sessionEnds[7];
   datetime m_lastEntryBarTime;
   datetime m_lastLossBarTime;
   int m_consecutiveLosses;

   bool m_gateOpen;
   bool m_entryAllowed;
   double m_lastSpread;
   double m_lastATR;
   MqlTick m_lastTick;
   bool m_hasLastTick;

   void FetchWebNews();
   void UpdateGateState(const MqlTick &tick);

public:
   MarketManager() : IManager("MarketManager", 100), m_gateOpen(true), m_entryAllowed(true), m_lastSpread(0.0), m_lastATR(0.0), m_hasLastTick(false)
   {
      m_baseCurr = SymbolInfoString(m_symbol, SYMBOL_CURRENCY_BASE);
      m_profitCurr = SymbolInfoString(m_symbol, SYMBOL_CURRENCY_PROFIT);
      ZeroMemory(m_sessionStarts);
      ZeroMemory(m_sessionEnds);
      ZeroMemory(m_lastTick);
   }
   ~MarketManager();

   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache();
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      RefreshConfigCache();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
   }

   virtual void OnPriceUpdate(PriceUpdateEvent *e) override;
   virtual void OnNewBar(NewBarEvent *e) override;

   virtual bool Init() override;
   bool PassesGate(const MqlTick &tick, double &currentSpread, double currentATR);
   bool IsTradingSession();
   bool IsNewsTime();
   bool IsEntryCooldownActive();
   void UpdateLossStreak(double netProfit);
   string GetNewsStatus() const { return m_newsStatus; }
   datetime GetNextNewsTime() const { return m_nextNewsTime; }

   // --- Methods to update internal state ---
   void UpdateLastEntryBarTime(datetime time) { m_lastEntryBarTime = time; }
   void SetLastBarTime(datetime time) { m_lastBarTime = time; }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      if (CFG.news.use)
         FetchWebNews();
   }
};
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
MarketManager::~MarketManager()
{
   ArrayFree(m_webNewsTimes);
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
bool MarketManager::Init()
{
   if (!IManager::Init())
      return false;

   // Cache is already refreshed by IManager::Init()
   for (int i = 0; i < 7; i++)
   {
      string session = CFG.market.sessions[i];
      if (session == "0" || session == "")
      {
         m_sessionStarts[i] = -1;
         m_sessionEnds[i] = -1;
      }
      else if (session == "00:00-24:00")
      {
         m_sessionStarts[i] = 0;
         m_sessionEnds[i] = 1440;
      }
      else
      {
         string parts[];
         if (StringSplit(session, '-', parts) == 2)
         {
            m_sessionStarts[i] = m_data.ParseHM(parts[0]);
            m_sessionEnds[i] = m_data.ParseHM(parts[1]);
         }
         else
         {
            m_sessionStarts[i] = 0;
            m_sessionEnds[i] = 1440;
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| PassesGate - Combines all market filters                         |
//+------------------------------------------------------------------+
bool MarketManager::PassesGate(const MqlTick &tick, double &currentSpread, double currentATR)
{
   if (!IsTradingSession())
   {
      m_data.DebugLog(m_debugMode, "Trading session is closed.");
      return false;
   }

   double bid = tick.bid;
   double ask = tick.ask;
   currentSpread = (ask - bid) / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if (currentSpread > CFG.market.maxSpread)
   {
      m_data.DebugLog(m_debugMode, "Spread too high: " + DoubleToString(currentSpread, 1));
      return false;
   }

   if (currentATR < CFG.market.atrMin || currentATR > CFG.market.atrMax)
   {
      if (m_debugMode)
      {
         string reason = (currentATR < CFG.market.atrMin) ? "Too Low" : "Too High";
         PrintFormat("[%s] ATR Gate Blocked: Current %.1f (Min: %.1f, Max: %.1f) - %s",
                     m_name, currentATR, CFG.market.atrMin, CFG.market.atrMax, reason);
      }
      return false;
   }

   if (IsNewsTime())
      return false;

   return true;
}

void MarketManager::OnPriceUpdate(PriceUpdateEvent *e)
{
   if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
      return;

   m_lastTick = e->tick;
   m_hasLastTick = true;
   UpdateGateState(m_lastTick);
}

void MarketManager::OnNewBar(NewBarEvent *e)
{
   if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
      return;

   if (!m_hasLastTick)
   {
      if (!SymbolInfoTick(m_symbol, m_lastTick)) return;
      m_hasLastTick = true;
   }
   
   UpdateGateState(m_lastTick);
}

//+------------------------------------------------------------------+
//| Consolidated Market Gate Logic                                   |
//+------------------------------------------------------------------+
void MarketManager::UpdateGateState(const MqlTick &tick)
{
   double currentSpread = 0.0;
   double currentATR = (CheckPointer(m_data) != POINTER_INVALID) ? m_data.GetATRPoints() : 0.0;
   bool gateOpen = (currentATR > 0) ? PassesGate(tick, currentSpread, currentATR) : false;

   bool entryAllowed = !IsEntryCooldownActive();
   bool stateChanged = (gateOpen != m_gateOpen) || 
                       (entryAllowed != m_entryAllowed) ||
                       (MathAbs(currentSpread - m_lastSpread) > 0.1) ||
                       (MathAbs(currentATR - m_lastATR) > 0.1);

   m_gateOpen = gateOpen;
   m_entryAllowed = entryAllowed;
   m_lastSpread = currentSpread;
   m_lastATR = currentATR;

   if (stateChanged || m_debugMode)
   {
      if (m_debugMode)
         PrintFormat("[%s] MarketGate updated on NewBar - gateOpen=%s entryAllowed=%s spread=%.1f atr=%.2f",
                     m_name,
                     m_gateOpen ? "true" : "false",
                     m_entryAllowed ? "true" : "false",
                     m_lastSpread,
                     m_lastATR);
      MarketGateEvent *evt = new MarketGateEvent(m_gateOpen, m_lastSpread, m_lastATR, m_entryAllowed);
      DispatchEvent(evt);
   }
}

//+------------------------------------------------------------------+
//| IsTradingSession                                                 |
//+------------------------------------------------------------------+
bool MarketManager::IsTradingSession()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   int startMin = m_sessionStarts[now.day_of_week];
   int endMin = m_sessionEnds[now.day_of_week];

   if (startMin < 0)
      return false;
   if (startMin == 0 && endMin == 1440)
      return true;

   int currMin = now.hour * 60 + now.min;
   if (startMin <= endMin)
      return (currMin >= startMin && currMin <= endMin);
   return (currMin >= startMin || currMin <= endMin);
}

//+------------------------------------------------------------------+
//| FetchWebNews - Mendapatkan data berita via WebRequest            |
//+------------------------------------------------------------------+
void MarketManager::FetchWebNews()
{
   if (MQLInfoInteger(MQL_TESTER))
      return;
   if (TimeCurrent() < m_lastWebFetch + 1800)
      return; // Fetch every 30 mins
   char data[], result[];
   string headers;
   int res = WebRequest("GET", CFG.news.url, NULL, NULL, 5000, data, 0, result, headers);

   if (res != 200)
   {
      m_data.DebugLog(m_debugMode, "WebNews Fetch Failed. HTTP Status: " + (string)res + ", MQL Error: " + (string)GetLastError());
      return;
   }

   string content = CharArrayToString(result);
   ArrayFree(m_webNewsTimes);
   string tagOpen = "<event>", tagClose = "</event>";
   int pos = 0;
   while ((pos = StringFind(content, tagOpen, pos)) >= 0)
   {
      int endPos = StringFind(content, tagClose, pos);
      if (endPos < 0)
         break;

      string eventData = StringSubstr(content, pos, endPos - pos);
      bool isHighImpact = (StringFind(eventData, "High") >= 0 || 
                           (CFG.news.level >= NEWS_HIGH_MEDIUM && StringFind(eventData, "Medium") >= 0));

      bool isRelevant = (StringFind(eventData, m_baseCurr) >= 0 ||
                         StringFind(eventData, m_profitCurr) >= 0 ||
                         StringFind(eventData, "USD") >= 0);

      if (isHighImpact && isRelevant)
      {
         int datePos = StringFind(eventData, "<date>");
         int timePos = StringFind(eventData, "<time>");
         if (datePos >= 0 && timePos >= 0)
         {
            int dateEnd = StringFind(eventData, "</date>", datePos);
            int timeEnd = StringFind(eventData, "</time>", timePos);
            string dateRaw = StringSubstr(eventData, datePos, dateEnd - datePos);
            string timeRaw = StringSubstr(eventData, timePos, timeEnd - timePos);
            string dStr = m_data.StripTags(dateRaw);
            string tStr = m_data.StripTags(timeRaw);
            string dParts[];
            if (StringSplit(dStr, '-', dParts) == 3 && dParts[0] != "" && dParts[1] != "" && dParts[2] != "")
            {
               dStr = dParts[2] + "." + dParts[0] + "." + dParts[1];
               if (dStr == "..")
                  continue;
            }

            string timeOnly = tStr;
            StringReplace(timeOnly, " AM", "");
            StringReplace(timeOnly, " PM", "");
            int sep = StringFind(timeOnly, ":");
            if (sep < 0)
               continue;

            int hr = (int)StringToInteger(StringSubstr(timeOnly, 0, sep));
            int mn = (int)StringToInteger(StringSubstr(timeOnly, sep + 1));

            if (StringFind(tStr, "PM") >= 0 && hr != 12)
               hr += 12;
            else if (StringFind(tStr, "AM") >= 0 && hr == 12)
               hr = 0;
            string finalTime = StringFormat("%02d:%02d", hr, mn);
            datetime eventTime = StringToTime(dStr + " " + finalTime);
            if (eventTime > 0)
            {
               int sz = ArraySize(m_webNewsTimes);
               ArrayResize(m_webNewsTimes, sz + 1, 10); // Use reserve to prevent O(N^2) allocations
               m_webNewsTimes[sz] = eventTime;
            }
         }
      }
      pos = endPos + StringLen(tagClose);
   }
   m_lastWebFetch = TimeCurrent();
}

//+------------------------------------------------------------------+
//| IsNewsTime                                                       |
//+------------------------------------------------------------------+
bool MarketManager::IsNewsTime()
{
   if (CFG.news.level == NEWS_OFF)
   {
      m_newsStatus = "News filter OFF";
      return (m_lastNewsResult = false);
   }

   if (TimeCurrent() < m_lastNewsCheck + 60 && m_lastNewsCheck > 0)
      return m_lastNewsResult;

   m_lastNewsCheck = TimeCurrent();
   m_lastNewsResult = false;
   m_newsStatus = "Market Clear";

   // Use cached news from FetchWebNews (called via Heartbeat)
   datetime now = TimeGMT(); // Web feeds usually use GMT
   for (int i = 0; i < ArraySize(m_webNewsTimes); i++)
   {
      if (now >= m_webNewsTimes[i] - (CFG.news.freeze * 60) &&
          now <= m_webNewsTimes[i] + (CFG.news.freeze * 60))
      {
         m_nextNewsTime = m_webNewsTimes[i];
         m_newsStatus = "WEB NEWS ACTIVE";
         m_lastNewsResult = true;
         return true;
      }
   }

   // 2. Jika Web tidak mendeteksi, gunakan Kalender Native sebagai lapis kedua
   m_nextNewsTime = 0;
   datetime gmtNow = TimeGMT(); // Native calendar also uses GMT
   datetime timeFrom = gmtNow - (CFG.news.freeze * 60);
   datetime timeTo = gmtNow + (CFG.news.freeze * 60);

   MqlCalendarValue values[];
   string currencies[2] = {m_baseCurr, m_profitCurr};

   for (int c = 0; c < 2; c++)
   {
      if (currencies[c] == "")
         continue;
      if (CalendarValueHistory(values, timeFrom, timeTo, NULL, currencies[c]) > 0)
      {
         for (int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if (CalendarEventById(values[i].event_id, event))
            {
               bool shouldBlock = false;
               if ((int)CFG.news.level >= 1 && event.importance == CALENDAR_IMPORTANCE_HIGH)
                  shouldBlock = true;
               else if ((int)CFG.news.level >= 2 && event.importance == CALENDAR_IMPORTANCE_MODERATE)
                  shouldBlock = true;
               else if ((int)CFG.news.level >= 3 && event.importance == CALENDAR_IMPORTANCE_LOW)
                  shouldBlock = true;

               if (shouldBlock)
               {
                  m_nextNewsTime = values[i].time;
                  m_newsStatus = "NEWS ACTIVE: " + event.name;
                  m_data.DebugLog(m_debugMode, "News blocked: " + m_newsStatus);
                  m_lastNewsResult = true;
                  return m_lastNewsResult;
               }
            }
         }
      }
   }

   return m_lastNewsResult;
}

//+------------------------------------------------------------------+
//| IsEntryCooldownActive                                            |
//+------------------------------------------------------------------+
bool MarketManager::IsEntryCooldownActive()
{
   MqlRates rates[];
   if (CopyRates(m_symbol, m_period, 0, 1, rates) <= 0)
      return false;
   datetime currBar = rates[0].time;

   if (m_lastEntryBarTime > 0)
   {
      int barsSinceEntry = (int)((currBar - m_lastEntryBarTime) / PeriodSeconds(m_period));
      if (barsSinceEntry < CFG.risk.entryCooldownBars)
      {
         m_data.DebugLog(m_debugMode, "Entry cooldown active (bars: " + (string)barsSinceEntry + ")");
         return true;
      }
   }

   if (m_consecutiveLosses >= CFG.risk.maxConsecutiveLoss)
   {
      int barsSinceLoss = (int)((currBar - m_lastLossBarTime) / PeriodSeconds(m_period));
      if (barsSinceLoss < CFG.risk.lossCooldownBars)
      {
         m_data.DebugLog(m_debugMode, "Loss cooldown active (bars: " + (string)barsSinceLoss + ")");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| UpdateLossStreak                                                 |
//+------------------------------------------------------------------+
void MarketManager::UpdateLossStreak(double netProfit)
{
   if (netProfit < 0)
   {
      m_consecutiveLosses++;
      MqlRates rates[];
      if (CopyRates(m_symbol, m_period, 0, 1, rates) > 0)
         m_lastLossBarTime = rates[0].time;

      string msg = "Loss Detected! Net Profit: " + DoubleToString(netProfit, 2) +
                   " | Consecutive Losses: " + (string)m_consecutiveLosses;
      if (m_consecutiveLosses >= CFG.risk.maxConsecutiveLoss)
         msg += " | Cooldown Active.";
      m_data.DebugLog(m_debugMode, msg);
   }
   else if (netProfit > 0)
   {
      m_consecutiveLosses = 0;
      m_data.DebugLog(m_debugMode, "Profit Detected! Resetting loss counter.");
   }

   // Update status izin entry dan kirim event jika terjadi perubahan state
   bool entryAllowed = !IsEntryCooldownActive();
   if (entryAllowed != m_entryAllowed)
   {
      m_entryAllowed = entryAllowed;
      if (m_debugMode)
         PrintFormat("[%s] Izin entry berubah menjadi %s akibat hasil trade terakhir.", 
                     m_name, m_entryAllowed ? "DIIZINKAN" : "DIBLOKIR");
                     
      MarketGateEvent *evt = new MarketGateEvent(m_gateOpen, m_lastSpread, m_lastATR, m_entryAllowed);
      DispatchEvent(evt);
   }
}

#endif