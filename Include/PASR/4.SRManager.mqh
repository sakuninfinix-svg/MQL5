//+------------------------------------------------------------------+
//|                                                    SRManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Support & Resistance Zone Management Module           |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __SR_MANAGER_MQH__
#define __SR_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"

class SRManager : public IManager
{
private:
   double m_targetSupport;
   double m_targetResistance;
   double m_htfSupport;
   double m_htfResistance;
   bool m_isSupportBroken;
   bool m_isResistanceBroken;
   double m_supBufferMult;
   double m_resBufferMult;
   int m_supHtfAlignment; // 1: Aligned, 0: Neutral, -1: Contra
   int m_resHtfAlignment;
   int m_supStrength; // NEW: Zone strength (touch count)
   int m_resStrength;
   
   // Helper: Cek apakah level sudah ditembus oleh harga Close bar yang sudah tertutup
   bool IsBroken(double price, bool isSupport, int bars)
   {
      if (price <= 0) return false;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      // Mengambil bar yang sudah tertutup (mulai dari shift 1)
      if (CopyRates(m_symbol, m_period, 1, bars, rates) < bars) return false;

      for (int i = 0; i < bars; i++)
      {
         if (isSupport && rates[i].close < price) return true;
         if (!isSupport && rates[i].close > price) return true;
      }
      return false;
   }

   // Helper: Mencari Swing Fractal terdekat dengan CopyHigh/CopyLow (MQL5 Best Practice)
   double FindNearestSwing(bool isSupport, int maxBars, int &foundShift, const double &highs[], const double &lows[])
   {
      foundShift = -1;
      int available = MathMin(maxBars, ArraySize(highs) - 2);

      for (int i = 2; i <= available; i++)
      {
         if (isSupport)
         {
            if (lows[i] < lows[i + 1] && lows[i] < lows[i - 1])
            {
               foundShift = i;
               return lows[i];
            }
         }
         else
         {
            if (highs[i] > highs[i + 1] && highs[i] > highs[i - 1])
            {
               foundShift = i;
               return highs[i];
            }
         }
      }
      return 0;
   }

   // Helper untuk menggambar garis
   void DrawOrMoveHLine(string name, double price, color clr)
   {
      // Performa: Cek apakah harga berubah sebelum update objek
      if (ObjectFind(0, name) >= 0)
      {
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if (MathAbs(ObjectGetDouble(0, name, OBJPROP_PRICE) - price) < point)
            return;
      }

      if (ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }

public:
   SRManager() : IManager("SRManager", 20),
                 m_targetSupport(0),
                 m_targetResistance(0),
                 m_htfSupport(0),
                 m_htfResistance(0),
                 m_isSupportBroken(false),
                 m_isResistanceBroken(false),
                 m_supBufferMult(0.5),
                 m_resBufferMult(0.5),
                 m_supHtfAlignment(0),
                 m_resHtfAlignment(0),
                 m_supStrength(0),
                 m_resStrength(0) {}

   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache(); // Sync m_debugMode dari base class
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      RefreshConfigCache();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_NEW_BAR);
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      const ConfigSnapshot cfg = m_data.GetConfigCache();
      datetime times[];
      if (CopyTime(m_symbol, m_period, 0, 1, times) <= 0)
         return;
      
      double extRes = 0, extSup = 0, swRes = 0, swSup = 0;
      int swResShift = -1, swSupShift = -1;
      int lookback = MathMax(cfg.sr_lookback, cfg.swing_lookback) + 2;
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);

      if (CopyHigh(m_symbol, m_period, 1, lookback, highs) <= 0 || CopyLow(m_symbol, m_period, 1, lookback, lows) <= 0)
         return;

      extRes = highs[ArrayMaximum(highs, 0, cfg.sr_lookback)];
      extSup = lows[ArrayMinimum(lows, 0, cfg.sr_lookback)];

      // 2. Ambil Data Swing (Fractal terdekat < 50 bar)
      swRes = FindNearestSwing(false, cfg.swing_lookback, swResShift, highs, lows);
      swSup = FindNearestSwing(true, cfg.swing_lookback, swSupShift, highs, lows);

      // Logic Pemilihan berdasarkan Mode
      if (cfg.sr_mode == SR_EXTREME)
      {
         m_targetResistance = extRes;
         m_targetSupport = extSup;
      }
      else if (cfg.sr_mode == SR_SWING)
      {
         m_targetResistance = (swRes > 0) ? swRes : extRes;
         m_targetSupport = (swSup > 0) ? swSup : extSup;
      }
      else
      {
         // Evaluasi Resistance
         if (swRes > 0 && !IsBroken(swRes, false, 5) && (IsBroken(extRes, false, 10) || swResShift < 15))
            m_targetResistance = swRes;
         else
            m_targetResistance = extRes;
         // Evaluasi Support
         if (swSup > 0 && !IsBroken(swSup, true, 5) && (IsBroken(extSup, true, 10) || swSupShift < 15))
            m_targetSupport = swSup;
         else
            m_targetSupport = extSup;
      }

      UpdateHTFZones();
      CheckZoneStatus(m_data.GetATRPoints());

      if(m_debugMode) {
         DrawOrMoveHLine("ResLine", m_targetResistance, clrRed);
         DrawOrMoveHLine("SupLine", m_targetSupport, clrBlue);
      }

      ZoneUpdateEvent *zoneEvent = new ZoneUpdateEvent(
          m_targetSupport, m_targetResistance, m_htfSupport, m_htfResistance,
          m_isSupportBroken, m_isResistanceBroken,
          m_supBufferMult, m_resBufferMult,
          m_supHtfAlignment, m_resHtfAlignment,
          m_supStrength, m_resStrength,
          m_data.GetATRPoints());
      DispatchEvent(zoneEvent);
   }
   void CheckZoneStatus(double atrPoints)
   {
      const ConfigSnapshot cfg = m_data.GetConfigCache();
      if (m_targetSupport <= 0 || m_targetResistance <= 0)
         return;

      // Filter "rusak" dinamis berdasarkan mode
      int barsToCheck = (cfg.sr_mode == SR_EXTREME) ? 10 : 5;
      m_isSupportBroken = IsBroken(m_targetSupport, true, barsToCheck);
      m_isResistanceBroken = IsBroken(m_targetResistance, false, barsToCheck);

      // Jika mode EXTREME, gunakan buffer statis agar lebih "Safe" sesuai filosofi Extreme SR
      if (cfg.sr_mode == SR_EXTREME)
      {
         m_resBufferMult = m_supBufferMult = (cfg.entry_mode == MODE_SAFE) ? 0.5 : 0.8;
         return;
      }

      // Hitung Touch Count untuk menentukan Buffer Mult dengan CopyHigh/CopyLow
      int supTouches = 0, resTouches = 0;
      double touchZone = (atrPoints * cfg.touch_buffer_atr) * _Point;

      double lows[], highs[];
      ArraySetAsSeries(lows, true);
      ArraySetAsSeries(highs, true);

      if (CopyLow(m_symbol, m_period, 1, cfg.sr_lookback, lows) > 0 &&
          CopyHigh(m_symbol, m_period, 1, cfg.sr_lookback, highs) > 0)
      {
         for (int i = 0; i < cfg.sr_lookback; i++)
         {
            if (MathAbs(lows[i] - m_targetSupport) < touchZone)
               supTouches++;
            if (MathAbs(highs[i] - m_targetResistance) < touchZone)
               resTouches++;
         }
      }

      // Store zone strength
      m_supStrength = supTouches;
      m_resStrength = resTouches;

      // Tentukan Multiplier Dinamis untuk Support
      if (m_isSupportBroken) m_supBufferMult = cfg.buffer_mult_weak;
      else if (supTouches >= cfg.min_touches_strong) m_supBufferMult = cfg.buffer_mult_strong;
      else if (supTouches <= 1) m_supBufferMult = cfg.atr_buffer_mult;
      else m_supBufferMult = 0.65;

      // Tentukan Multiplier Dinamis untuk Resistance
      if (m_isResistanceBroken) m_resBufferMult = cfg.buffer_mult_weak;
      else if (resTouches >= cfg.min_touches_strong) m_resBufferMult = cfg.buffer_mult_strong;
      else if (resTouches <= 1)
         m_resBufferMult = cfg.atr_buffer_mult;
      else
         m_resBufferMult = 0.65;

      // --- HTF Alignment Integration -
      m_resHtfAlignment = 0;

      if (cfg.use_mtf && m_htfSupport > 0 && m_htfResistance > 0)
      {
         double htfZoneBuffer = (atrPoints * cfg.atr_buffer_mult) * _Point;
         
         // Support Alignment
         if (m_targetSupport <= m_htfSupport + htfZoneBuffer && m_targetSupport >= m_htfSupport - htfZoneBuffer)
            m_supHtfAlignment = 1;
         else if (m_targetSupport >= m_htfResistance - htfZoneBuffer)
            m_supHtfAlignment = -1;
         else
            m_supHtfAlignment = 0;

         // Resistance Alignment
         if (m_targetResistance >= m_htfResistance - htfZoneBuffer && m_targetResistance <= m_htfResistance + htfZoneBuffer)
            m_resHtfAlignment = 1;
         else if (m_targetResistance <= m_htfSupport + htfZoneBuffer)
            m_resHtfAlignment = -1;
         else
            m_resHtfAlignment = 0;
      }
   }

   void UpdateHTFZones()
   {
      const ConfigSnapshot cfg = m_data.GetConfigCache();
      if (!cfg.use_mtf) return;

      double htfHighs[], htfLows[];
      ArraySetAsSeries(htfHighs, true);
      ArraySetAsSeries(htfLows, true);

      if (CopyHigh(m_symbol, cfg.htf, 1, cfg.htf_lookback, htfHighs) > 0 &&
          CopyLow(m_symbol, cfg.htf, 1, cfg.htf_lookback, htfLows) > 0)
      {
         m_htfResistance = htfHighs[ArrayMaximum(htfHighs)];
         m_htfSupport = htfLows[ArrayMinimum(htfLows)];
      }
   }

   bool IsTradableRange(double atrPoints)
   {
      const ConfigSnapshot cfg = m_data.GetConfigCache();
      double spread = GetGlobalSpread();
      if(spread < 0) spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); // Fallback

      double minRange = MathMax(atrPoints * cfg.min_range_atr, spread * 5.0);
      double rangePts = (m_targetResistance - m_targetSupport) / _Point;

      return (rangePts >= minRange);
   }

   // Getters
   double Support() const { return m_targetSupport; }
   double Resistance() const { return m_targetResistance; }
   double HTFSupport() const { return m_htfSupport; }
   double HTFResistance() const { return m_htfResistance; }
   bool IsSupportBroken() const { return m_isSupportBroken; }
   bool IsResistanceBroken() const { return m_isResistanceBroken; }
   double SupBufferMult() const { return m_supBufferMult; }
   double ResBufferMult() const { return m_resBufferMult; }
   int SupHtfAlignment() const { return m_supHtfAlignment; }
   int ResHtfAlignment() const { return m_resHtfAlignment; }
   int SupStrength() const { return m_supStrength; }
   int ResStrength() const { return m_resStrength; }
};

#endif