//+------------------------------------------------------------------+
//|                                              RiskCalculator.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|               Risk & Lot Calculation Module for PASR EA          |
//+------------------------------------------------------------------+
#ifndef __RISK_CALCULATOR_MQH__
#define __RISK_CALCULATOR_MQH__

#property strict
#include "2.Config.mqh"

//+------------------------------------------------------------------+
//| RiskCalculator - Independent Risk Management Module              |
//| Handles: Lot calculation, SL/TP validation, Risk assessment      |
//+------------------------------------------------------------------+
class RiskCalculator
{
private:
   struct RiskConfig
   {
      bool useAutoLot;
      double riskPct;
      double lotSize;
      double minTPDistanceATR;
      ulong magicNum;
   } m_cfg;

public:
   RiskCalculator()
   {
      LoadConfig();
   }

   // Load configuration from global CFG
   void LoadConfig()
   {
      m_cfg.useAutoLot = CFG.UseAutoLot;
      m_cfg.riskPct = CFG.RiskPct;
      m_cfg.lotSize = CFG.LotSize;
      m_cfg.minTPDistanceATR = CFG.MinTPDistanceATR;
      m_cfg.magicNum = CFG.MagicNum;
   }

   // Validate SL and TP distances
   bool ValidateDistances(double slDistancePoints, double tpDistancePoints,
                          double atrPoints, string &reason) const
   {
      if (slDistancePoints <= 0)
      {
         reason = "Invalid SL distance";
         return false;
      }

      double minSL = 10.0; // Minimum 10 points SL
      if (slDistancePoints < minSL)
      {
         reason = "SL too close (" + DoubleToString(slDistancePoints, 1) + " < " + DoubleToString(minSL, 1) + ")";
         return false;
      }

      if (tpDistancePoints > 0)
      {
         double minTP = atrPoints * m_cfg.minTPDistanceATR;
         if (tpDistancePoints < minTP)
         {
            reason = "TP too close to entry";
            return false;
         }

         // Check R:R ratio (minimum 1:1)
         if (tpDistancePoints < slDistancePoints * 0.9)
         {
            reason = "Risk/Reward ratio too low (< 1:1)";
            return false;
         }
      }

      reason = "OK";
      return true;
   }

   // Calculate lot size based on risk parameters
   double CalculateLotSize(double slDistancePoints, double signalQuality = 1.0) const
   {
      double lot = 0.0;

      if (m_cfg.useAutoLot)
      {
         // Auto lot calculation based on risk percentage
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

         if (tickValue <= 0 || tickSize <= 0 || equity <= 0 || slDistancePoints <= 0)
         {
            return 0.0;
         }

         double riskMoney = equity * (m_cfg.riskPct / 100.0);
         double lossPerLot = (slDistancePoints * _Point / tickSize) * tickValue;

         if (lossPerLot > 0)
         {
            lot = riskMoney / lossPerLot;
         }
      }
      else
      {
         // Fixed lot size
         lot = m_cfg.lotSize;
      }

      // Apply signal quality multiplier (for high quality signals)
      if (signalQuality > 1.0)
      {
         lot *= signalQuality;
      }

      // Normalize lot size
      lot = NormalizeVolume(_Symbol, lot);

      return lot;
   }

   // Normalize volume according to broker specifications
   double NormalizeVolume(string symbol, double volume) const
   {
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

      if (step <= 0)
         step = 0.01;

      // Round to nearest step
      volume = MathFloor((volume + 1e-12) / step) * step;

      // Apply min/max limits
      volume = MathMax(volume, minVol);
      if (maxVol > 0.0)
      {
         volume = MathMin(volume, maxVol);
      }

      return volume;
   }

   // Calculate position risk in account currency
   double CalculatePositionRisk(double volume, double slDistancePoints) const
   {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if (tickValue <= 0 || tickSize <= 0)
      {
         return 0.0;
      }

      double riskPerLot = (slDistancePoints * _Point / tickSize) * tickValue;
      return riskPerLot * volume;
   }

   // Get risk percentage of current position
   double GetRiskPercentage(double volume, double slDistancePoints) const
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if (equity <= 0)
         return 0.0;

      double riskMoney = CalculatePositionRisk(volume, slDistancePoints);
      return (riskMoney / equity) * 100.0;
   }
};

#endif
