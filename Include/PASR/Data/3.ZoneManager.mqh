//+------------------------------------------------------------------+
//|                                                 3.ZoneManager.mqh |
//|                                       Copyright 2026, Agsicentre   |
//|            Support/Resistance Zone Management Module               |
//+------------------------------------------------------------------+
//| PURPOSE: Manages SR zones as objects, handles zone breaks,        |
//|          provides zone-based entry/exit logic.                    |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.00"
#property strict

#ifndef __ZONE_MANAGER_MQH__
#define __ZONE_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Infrastructure/10.DataManager.mqh"
#include "4.SRManager.mqh"

//+------------------------------------------------------------------+
//| Zone State Enumeration                                           |
//+------------------------------------------------------------------+
enum ENUM_ZONE_STATE
{
   ZONE_STATE_ACTIVE,      // Zone is valid and untested
   ZONE_STATE_TESTED,      // Zone was tested but held
   ZONE_STATE_BROKEN,      // Zone was broken (price penetrated)
   ZONE_STATE_FLIP         // Zone flipped from S to R or R to S
};

//+------------------------------------------------------------------+
//| Price Zone Structure                                             |
//+------------------------------------------------------------------+
struct PriceZone
{
   double           top;
   double           bottom;
   double           midpoint;
   ENUM_POSITION_TYPE type;     // POSITION_TYPE_BUY (support) or SELL (resistance)
   ENUM_ZONE_STATE  state;
   int              touchCount;
   int              testCount;
   datetime         lastTestTime;
   double           lastTestPrice;
   double           strength;    // 0-100 score
   string           label;
   
   PriceZone() : top(0), bottom(0), midpoint(0), type(POSITION_TYPE_BUY),
                 state(ZONE_STATE_ACTIVE), touchCount(0), testCount(0),
                 lastTestTime(0), lastTestPrice(0), strength(50.0) {}
   
   bool Contains(double price) const
   {
      return (price >= bottom && price <= top);
   }
   
   double DistanceFrom(double price) const
   {
      if(price < bottom) return bottom - price;
      if(price > top) return price - top;
      return 0.0; // Inside zone
   }
   
   void UpdateMidpoint()
   {
      midpoint = (top + bottom) / 2.0;
   }
};

//+------------------------------------------------------------------+
//| ZoneManager Class                                                |
//+------------------------------------------------------------------+
class ZoneManager : public IManager
{
private:
   PriceZone  m_zones[];
   int        m_maxZones;
   double     m_zoneBufferATR;
   
public:
   ZoneManager() : m_maxZones(20), m_zoneBufferATR(1.0)
   {
      ArrayResize(m_zones, m_maxZones);
   }
   
   virtual ~ZoneManager()
   {
      ArrayFree(m_zones);
   }
   
   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      
      m_symbol = _Symbol;
      ArrayResize(m_zones, m_maxZones);
      
      Log("✅ ZoneManager initialized with capacity " + IntegerToString(m_maxZones));
      return true;
   }
   
   //--- Zone Creation ---
   int CreateZone(double top, double bottom, ENUM_POSITION_TYPE type, double strength = 50.0)
   {
      // Find empty slot
      int slot = -1;
      for(int i = 0; i < m_maxZones; i++)
      {
         if(m_zones[i].top == 0 && m_zones[i].bottom == 0)
         {
            slot = i;
            break;
         }
      }
      
      if(slot < 0)
      {
         Log("⚠️ Zone array full, cannot create new zone");
         return -1;
      }
      
      m_zones[slot].top = top;
      m_zones[slot].bottom = bottom;
      m_zones[slot].type = type;
      m_zones[slot].strength = strength;
      m_zones[slot].state = ZONE_STATE_ACTIVE;
      m_zones[slot].UpdateMidpoint();
      m_zones[slot].label = (type == POSITION_TYPE_BUY ? "Support" : "Resistance") + 
                            "_" + IntegerToString(slot);
      
      Log("📍 Created zone: " + m_zones[slot].label + 
          " [" + DoubleToString(bottom, _Digits) + "-" + DoubleToString(top, _Digits) + "]");
      
      return slot;
   }
   
   //--- Zone Updates ---
   void UpdateZoneState(int zoneIndex, double currentPrice)
   {
      if(zoneIndex < 0 || zoneIndex >= m_maxZones) return;
      
      PriceZone &zone = m_zones[zoneIndex];
      
      // Check if price touched zone
      if(zone.Contains(currentPrice))
      {
         zone.testCount++;
         zone.lastTestTime = TimeCurrent();
         zone.lastTestPrice = currentPrice;
         
         if(zone.state == ZONE_STATE_ACTIVE)
            zone.state = ZONE_STATE_TESTED;
      }
      
      // Check for zone break (simplified - can be enhanced)
      double breakThreshold = zone.midpoint;
      if(zone.type == POSITION_TYPE_BUY)
      {
         // Support break: price closes below zone
         if(currentPrice < zone.bottom - (m_zoneBufferATR * Point()))
            zone.state = ZONE_STATE_BROKEN;
      }
      else
      {
         // Resistance break: price closes above zone
         if(currentPrice > zone.top + (m_zoneBufferATR * Point()))
            zone.state = ZONE_STATE_BROKEN;
      }
   }
   
   //--- Zone Queries ---
   int FindNearestZone(double price, ENUM_POSITION_TYPE type) const
   {
      int nearestIdx = -1;
      double nearestDist = DBL_MAX;
      
      for(int i = 0; i < m_maxZones; i++)
      {
         if(m_zones[i].top == 0 && m_zones[i].bottom == 0) continue; // Empty slot
         if(m_zones[i].type != type) continue;
         if(m_zones[i].state == ZONE_STATE_BROKEN) continue;
         
         double dist = m_zones[i].DistanceFrom(price);
         if(dist < nearestDist)
         {
            nearestDist = dist;
            nearestIdx = i;
         }
      }
      
      return nearestIdx;
   }
   
   PriceZone* GetZone(int index)
   {
      if(index < 0 || index >= m_maxZones) return NULL;
      return &m_zones[index];
   }
   
   //--- Zone Cleanup ---
   void RemoveBrokenZones()
   {
      for(int i = 0; i < m_maxZones; i++)
      {
         if(m_zones[i].state == ZONE_STATE_BROKEN)
         {
            ZeroMemory(m_zones[i]);
         }
      }
   }
   
   //--- Configuration ---
   void SetMaxZones(int max) 
   { 
      m_maxZones = MathMax(5, MathMin(50, max)); 
      ArrayResize(m_zones, m_maxZones);
   }
   
   void SetZoneBufferATR(double buffer) { m_zoneBufferATR = buffer; }
   
   //--- Event Handlers ---
   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_ZONE_UPDATE);
   }
   
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      
      double currentPrice = e.tick.bid;
      
      // Update all active zones
      for(int i = 0; i < m_maxZones; i++)
      {
         if(m_zones[i].top > 0 || m_zones[i].bottom > 0)
            UpdateZoneState(i, currentPrice);
      }
      
      // Emit zone update event for dashboard
      EmitZoneUpdate();
   }
   
   void EmitZoneUpdate()
   {
      // Find key zones for event
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      int nearestSup = FindNearestZone(currentPrice, POSITION_TYPE_BUY);
      int nearestRes = FindNearestZone(currentPrice, POSITION_TYPE_SELL);
      
      double supPrice = (nearestSup >= 0) ? m_zones[nearestSup].midpoint : 0;
      double resPrice = (nearestRes >= 0) ? m_zones[nearestRes].midpoint : 0;
      
      ZoneUpdateEvent *zoneEvent = new ZoneUpdateEvent(
         supPrice, resPrice,
         0, 0,  // HTF values (can be populated if needed)
         false, false,  // Broken flags
         1.0, 1.0,  // Buffer multipliers
         0, 0,  // HTF alignment
         50, 50,  // Strength
         m_zoneBufferATR,
         (nearestSup >= 0) ? m_zones[nearestSup].strength : 50.0,
         (nearestRes >= 0) ? m_zones[nearestRes].strength : 50.0
      );
      
      if(CheckPointer(zoneEvent) != POINTER_INVALID)
         DispatchEvent(zoneEvent);
   }
};

#endif // __ZONE_MANAGER_MQH__
