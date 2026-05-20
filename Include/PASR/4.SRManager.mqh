//+------------------------------------------------------------------+
//|                                                    SRManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Support & Resistance Zone Management Module           |
//|                  Enhanced with Zone & Strength Scoring           |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __SR_MANAGER_MQH__
#define __SR_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"

//+------------------------------------------------------------------+
//| Enum for SR Zone Strength                                        |
//+------------------------------------------------------------------+
enum ENUM_SR_STRENGTH
{
   SR_VERY_WEAK    = 0,  // Score < 20
   SR_WEAK         = 1,  // Score 20-39
   SR_MODERATE     = 2,  // Score 40-59
   SR_STRONG       = 3,  // Score 60-79
   SR_VERY_STRONG  = 4   // Score >= 80
};

//+------------------------------------------------------------------+
//| Struct representing a single SR Level/Zone                       |
//+------------------------------------------------------------------+
struct SRLevel
{
   double             price;              // Central price of the zone
   double             top;                // Top boundary of zone (for resistance)
   double             bottom;             // Bottom boundary of zone (for support)
   ENUM_SR_STRENGTH   strength;           // Strength grade
   int                touchCount;         // Number of times price touched this zone
   ENUM_TIMEFRAMES    timeframeFound;     // Timeframe where level was detected
   bool               isFresh;            // True if not tested recently (last 10 bars)
   bool               isFlip;             // True if this is a flip level (SBR/RBS)
   double             score;              // Calculated score 0-100
   datetime           lastTouchTime;      // Last time price touched this zone
   int                lastTouchShift;     // Bar shift of last touch
   
   // Constructor
   SRLevel() : price(0), top(0), bottom(0), strength(SR_VERY_WEAK), 
               touchCount(0), timeframeFound(PERIOD_CURRENT), 
               isFresh(true), isFlip(false), score(0), 
               lastTouchTime(0), lastTouchShift(-1) {}
               
   // Helper: Check if price is within zone
   bool IsPriceInZone(double checkPrice, double bufferPoints) const
   {
      double extendedTop    = top    + bufferPoints;
      double extendedBottom = bottom - bufferPoints;
      return (checkPrice >= extendedBottom && checkPrice <= extendedTop);
   }
   
   // Helper: Get zone midpoint
   double Midpoint() const { return (top + bottom) / 2.0; }
};

//+------------------------------------------------------------------+
//| Struct for SR Evaluation Result                                  |
//+------------------------------------------------------------------+
struct SRResult
{
   bool               found;              // Whether SR level was found
   ENUM_POSITION_TYPE type;               // POSITION_TYPE_BUY (support) or SELL (resistance)
   double             distance;           // Distance from current price in points
   ENUM_SR_STRENGTH   strengthGrade;      // Strength classification
   double             rejectionQuality;   // Quality of rejection (0-1)
   string             reasoning;          // Detailed explanation
   SRLevel            level;              // The actual SR level data
   
   // Constructor
   SRResult() : found(false), type(POSITION_TYPE_BUY), distance(0), 
                strengthGrade(SR_VERY_WEAK), rejectionQuality(0) {}
                
   // Helper: Check if signal is actionable
   bool IsActionable(double minScore = 0.5) const
   {
      return found && (rejectionQuality >= minScore);
   }
};

//+------------------------------------------------------------------+
//| SRManager Class - Enhanced with Zone & Strength Scoring          |
//+------------------------------------------------------------------+
class SRManager : public IManager
{
private:
   // Legacy members (backward compatibility)
   double m_targetSupport;
   double m_targetResistance;
   double m_htfSupport;
   double m_htfResistance;
   bool m_isSupportBroken;
   bool m_isResistanceBroken;
   double m_supBufferMult;
   double m_resBufferMult;
   int m_supHtfAlignment;
   int m_resHtfAlignment;
   int m_supStrength;
   int m_resStrength;
   double m_supScore;
   double m_resScore;
   
   // New enhanced members
   SRLevel m_levels[];              // Array of detected SR levels
   int m_levelCount;                // Number of valid levels
   datetime m_lastScanTime;         // Last time multi-timeframe scan was performed
   int m_signalStabilityCount;      // For debouncing
   SRResult m_lastResult;           // Last evaluation result
   
   // Multi-timeframe arrays
   ENUM_TIMEFRAMES m_mtfArray[4];   // M15, H1, H4, D1
   double m_mtfWeights[4];          // Weights for each timeframe
   
   // Constants
   static const int MAX_LEVELS = 20;
   static const double ZONE_MERGE_THRESHOLD_POINTS = 10.0;
   
   // Helper: Calculate SR Zone Score based on multiple factors
   double CalculateZoneScore(double zonePrice, bool isSupport, int touchCount, 
                             double atrPoints, int htfAlignment, bool isBroken)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double score = 30.0; // [PATCH SR-12] Base lowered from 50 to 30 for more discrimination
      
      // Touch count bonus (more touches = stronger zone, but diminishing returns)
      if(touchCount >= cfg.min_touches_strong)
         score += 25.0 * MathMin(1.0, (double)touchCount / (cfg.min_touches_strong * 2));
      else if(touchCount <= 1)
         score -= 10.0;
      
      // HTF Alignment bonus
      if(htfAlignment == 1)
         score += 20.0; // Aligned with HTF
      else if(htfAlignment == -1)
         score -= 20.0; // Contra HTF
      
      // Broken zone penalty
      if(isBroken)
         score -= 30.0;
      
      // Fresh zone bonus (not tested recently) - reduced from 10 to 5
      if(touchCount == 0)
         score += 5.0;
      
      // Normalize to 0-100 range
      return MathMax(0.0, MathMin(100.0, score));
   }
   
   // Helper: Convert numeric score to ENUM_SR_STRENGTH
   ENUM_SR_STRENGTH ScoreToStrength(double score)
   {
      if(score >= 80) return SR_VERY_STRONG;
      if(score >= 60) return SR_STRONG;
      if(score >= 40) return SR_MODERATE;
      if(score >= 20) return SR_WEAK;
      return SR_VERY_WEAK;
   }
   
   // Helper: Cek apakah level sudah ditembus oleh harga Close bar yang sudah tertutup
   bool IsBroken(double price, bool isSupport, int bars)
   {
      if(price <= 0) return false;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      // LOOK-AHEAD BIAS FIX: bar yang sudah tertutup (mulai dari shift 1)
      if(CopyRates(m_symbol, m_period, 1, bars, rates) < bars) return false;

      for(int i = 0; i < bars; i++)
      {
         if(isSupport  && rates[i].close < price) return true;
         if(!isSupport && rates[i].close > price) return true;
      }
      return false;
   }
   
   // [PATCH SR-10] Fixed: cross detection logic was inverted
   bool IsFlipLevel(double price, const MqlRates rates[], int lookback)
   {
      if(price <= 0 || ArraySize(rates) < lookback) return false;
      
      int crossesAbove = 0;
      int crossesBelow = 0;
      
      for(int i = 1; i < lookback; i++)
      {
         // Close crosses above price level (breakout up)
         if(rates[i-1].close < price && rates[i].close > price)
            crossesAbove++;
         // Close crosses below price level (breakout down)
         if(rates[i-1].close > price && rates[i].close < price)
            crossesBelow++;
      }
      
      // Flip: both directions happened
      return (crossesAbove >= 1 && crossesBelow >= 1);
   }
   
   // [PATCH SR-03] Fixed available bound: -3 instead of -2 to prevent lows[i+1] OOB
   double FindNearestSwing(bool isSupport, int maxBars, int &foundShift, const double &highs[], const double &lows[])
   {
      foundShift = -1;
      int available = MathMin(maxBars, ArraySize(highs) - 3); // -3: i+1 safe at i==available

      for(int i = 2; i <= available; i++)
      {
         if(isSupport)
         {
            if(lows[i] < lows[i + 1] && lows[i] < lows[i - 1])
            {
               foundShift = i;
               return lows[i];
            }
         }
         else
         {
            if(highs[i] > highs[i + 1] && highs[i] > highs[i - 1])
            {
               foundShift = i;
               return highs[i];
            }
         }
      }
      return 0;
   }
   
   // Enhanced: Scan for swing high/low in specific timeframe
   bool ScanTimeframeSwings(ENUM_TIMEFRAMES tf, const MqlRates rates[], 
                           SRLevel &outSupport, SRLevel &outResistance, double atrPrice)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      int lookback = cfg.sr_lookback;
      
      if(ArraySize(rates) < lookback + 2) return false;
      
      double highs[], lows[];
      ArrayResize(highs, ArraySize(rates));
      ArrayResize(lows, ArraySize(rates));
      
      for(int i = 0; i < ArraySize(rates); i++)
      {
         highs[i] = rates[i].high;
         lows[i]  = rates[i].low;
      }
      
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      
      int supShift = -1, resShift = -1;
      double swingSup = FindNearestSwing(true,  lookback, supShift, highs, lows);
      double swingRes = FindNearestSwing(false, lookback, resShift, highs, lows);
      
      double extSup = lows [ArrayMinimum(lows,  0, lookback)];
      double extRes = highs[ArrayMaximum(highs, 0, lookback)];
      
      double finalSup = (swingSup > 0 && !IsBroken(swingSup, true,  5)) ? swingSup : extSup;
      double finalRes = (swingRes > 0 && !IsBroken(swingRes, false, 5)) ? swingRes : extRes;
      
      if(finalSup <= 0 || finalRes <= 0) return false;
      
      // [PATCH SR-02] Zone boundaries: atrPrice is already in price units, NO extra *_Point
      outSupport.price          = finalSup;
      outSupport.bottom         = finalSup - (atrPrice * 0.2);
      outSupport.top            = finalSup + (atrPrice * 0.3);
      outSupport.timeframeFound = tf;
      outSupport.isFlip         = IsFlipLevel(finalSup, rates, lookback);
      outSupport.touchCount     = CountTouches(finalSup, true,  lookback, rates, atrPrice);
      outSupport.isFresh        = (outSupport.touchCount <= 1);
      outSupport.lastTouchShift = supShift;
      
      outResistance.price          = finalRes;
      outResistance.bottom         = finalRes - (atrPrice * 0.3);
      outResistance.top            = finalRes + (atrPrice * 0.2);
      outResistance.timeframeFound = tf;
      outResistance.isFlip         = IsFlipLevel(finalRes, rates, lookback);
      outResistance.touchCount     = CountTouches(finalRes, false, lookback, rates, atrPrice);
      outResistance.isFresh        = (outResistance.touchCount <= 1);
      outResistance.lastTouchShift = resShift;
      
      int htfAlignSup = 0, htfAlignRes = 0;
      outSupport.score    = CalculateLevelScore(outSupport,    htfAlignSup, atrPrice);
      outResistance.score = CalculateLevelScore(outResistance, htfAlignRes, atrPrice);
      
      outSupport.strength    = ScoreToStrength(outSupport.score);
      outResistance.strength = ScoreToStrength(outResistance.score);
      
      return true;
   }
   
   // [PATCH SR-02] touchZone: atrPrice already in price units, NO extra *_Point
   int CountTouches(double price, bool isSupport, int lookback, const MqlRates rates[], double atrPrice)
   {
      if(price <= 0 || ArraySize(rates) < lookback) return 0;
      
      double touchZone = atrPrice * 0.5; // price units
      int touches = 0;
      
      for(int i = 0; i < lookback && i < ArraySize(rates); i++)
      {
         if(isSupport)
         {
            if(MathAbs(rates[i].low  - price) <= touchZone) touches++;
         }
         else
         {
            if(MathAbs(rates[i].high - price) <= touchZone) touches++;
         }
      }
      return touches;
   }
   
   // [PATCH SR-12] Base score lowered, fresh bonus reduced for better discrimination
   double CalculateLevelScore(const SRLevel &level, int &htfAlignment, double atrPrice)
   {
      double score = 30.0; // Base lowered from 50
      
      // Touch count component (max 30 points)
      double touchScore;
      if(level.touchCount == 0)
         touchScore = 5.0;  // Fresh: minimal bonus, not 10
      else
         touchScore = MathMin(30.0, level.touchCount * 8.0);
      score += touchScore;
      
      // Timeframe weight component (max 20 points)
      double tfWeight = GetTimeframeWeight(level.timeframeFound);
      score += tfWeight * 20.0;
      
      // Flip level bonus (15 points)
      if(level.isFlip)
         score += 15.0;
      
      // Freshness bonus (5 points) - reduced from 10
      if(level.isFresh)
         score += 5.0;
      
      htfAlignment = 0; // To be set by caller
      
      return MathMax(0.0, MathMin(100.0, score));
   }
   
   // Helper: Get weight for timeframe (D1 highest, M15 lowest)
   double GetTimeframeWeight(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_D1:  return 1.0;
         case PERIOD_H4:  return 0.8;
         case PERIOD_H1:  return 0.6;
         case PERIOD_M15: return 0.4;
         default:         return 0.5;
      }
   }
   
   // [PATCH SR-07] Merge now propagates isFlip, isFresh, lastTouchTime
   void MergeNearbyLevels(SRLevel &levels[], int &count, double mergeThresholdPoints)
   {
      if(count < 2) return;
      
      bool merged = true;
      while(merged)
      {
         merged = false;
         for(int i = 0; i < count - 1 && !merged; i++)
         {
            for(int j = i + 1; j < count && !merged; j++)
            {
               double distancePoints = MathAbs(levels[i].price - levels[j].price) / _Point;
               if(distancePoints <= mergeThresholdPoints)
               {
                  levels[i].price      = (levels[i].price + levels[j].price) / 2.0;
                  levels[i].top        = MathMax(levels[i].top,    levels[j].top);
                  levels[i].bottom     = MathMin(levels[i].bottom, levels[j].bottom);
                  levels[i].touchCount += levels[j].touchCount;
                  levels[i].score      = MathMax(levels[i].score,  levels[j].score);
                  levels[i].strength   = ScoreToStrength(levels[i].score);
                  
                  // [PATCH SR-07] Propagate flip/fresh metadata
                  levels[i].isFlip        = levels[i].isFlip || levels[j].isFlip;
                  levels[i].isFresh       = levels[i].isFresh && levels[j].isFresh;
                  levels[i].lastTouchTime = MathMax(levels[i].lastTouchTime, levels[j].lastTouchTime);
                  
                  // Keep higher timeframe
                  if(GetTimeframeWeight(levels[j].timeframeFound) > GetTimeframeWeight(levels[i].timeframeFound))
                     levels[i].timeframeFound = levels[j].timeframeFound;
                  
                  // Compact array
                  for(int k = j; k < count - 1; k++)
                     levels[k] = levels[k + 1];
                  
                  count--;
                  merged = true;
               }
            }
         }
      }
   }
   
   void DrawOrMoveHLine(string name, double price, color clr)
   {
      if(ObjectFind(0, name) >= 0)
      {
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if(MathAbs(ObjectGetDouble(0, name, OBJPROP_PRICE) - price) < point)
            return;
      }

      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetDouble (0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
   
   string BuildReasoning(const SRResult &result)
   {
      if(!result.found) return "No valid SR level detected";
      
      string reason = "";
      reason += StringFormat("Type: %s | ",       (result.type == POSITION_TYPE_BUY) ? "Support" : "Resistance");
      reason += StringFormat("Strength: %s | ",    EnumToString(result.strengthGrade));
      reason += StringFormat("Score: %.1f/100 | ", result.level.score);
      reason += StringFormat("Touches: %d | ",     result.level.touchCount);
      reason += StringFormat("TF: %s | ",           EnumToString(result.level.timeframeFound));
      if(result.level.isFlip)  reason += "Flip Level (SBR/RBS) | ";
      if(result.level.isFresh) reason += "Fresh Level | ";
      reason += StringFormat("Rejection Quality: %.2f", result.rejectionQuality);
      return reason;
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
                 m_resStrength(0),
                 m_levelCount(0),
                 m_lastScanTime(0),
                 m_signalStabilityCount(0)
   {
      m_mtfArray[0] = PERIOD_M15;
      m_mtfArray[1] = PERIOD_H1;
      m_mtfArray[2] = PERIOD_H4;
      m_mtfArray[3] = PERIOD_D1;
      
      m_mtfWeights[0] = 0.4;
      m_mtfWeights[1] = 0.6;
      m_mtfWeights[2] = 0.8;
      m_mtfWeights[3] = 1.0;
      
      ArrayResize(m_levels, MAX_LEVELS);
   }

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
      AddEvent(EVENT_ID_NEW_BAR);
   }

   //+------------------------------------------------------------------+
   //| Main Evaluation Method                                           |
   //| [PATCH SR-01] Removed dead 'Config' parameter, use StrategyConfig|
   //| [PATCH SR-04] Scan throttled to closed bar time (shift 1)        |
   //+------------------------------------------------------------------+
   SRResult Evaluate(const MqlRates rates[], int shift, double atrPrice)
   {
      SRResult result;
      
      if(ArraySize(rates) < 10 || atrPrice <= 0)
      {
         result.reasoning = "Invalid input: insufficient data or ATR";
         return result;
      }
      
      // [PATCH SR-04] Use closed bar time to throttle scan, not active bar
      datetime closedBarTime = iTime(m_symbol, m_period, 1);
      if(closedBarTime != m_lastScanTime || m_levelCount == 0)
      {
         ScanMultiTimeframe(rates, atrPrice);
         m_lastScanTime = closedBarTime;
      }
      
      SRLevel nearestSup, nearestRes;
      if(FindNearestSignificantLevels(rates[shift].close, nearestSup, nearestRes))
      {
         double distSup = (rates[shift].close - nearestSup.price) / _Point;
         double distRes = (nearestRes.price - rates[shift].close) / _Point;
         
         if(distSup <= distRes && distSup > 0)
         {
            result.found            = true;
            result.type             = POSITION_TYPE_BUY;
            result.distance         = distSup;
            result.strengthGrade    = nearestSup.strength;
            result.rejectionQuality = CalculateRejectionQuality(nearestSup, rates, shift, atrPrice);
            result.level            = nearestSup;
         }
         else if(distRes > 0)
         {
            result.found            = true;
            result.type             = POSITION_TYPE_SELL;
            result.distance         = distRes;
            result.strengthGrade    = nearestRes.strength;
            result.rejectionQuality = CalculateRejectionQuality(nearestRes, rates, shift, atrPrice);
            result.level            = nearestRes;
         }
      }
      
      result.reasoning = BuildReasoning(result);
      
      if(result.found && result.rejectionQuality > 0.5)
      {
         if(m_lastResult.found && 
            m_lastResult.type == result.type && 
            MathAbs(m_lastResult.level.price - result.level.price) < 10 * _Point)
         {
            m_signalStabilityCount++;
         }
         else
         {
            m_signalStabilityCount = 1;
         }
      }
      else
      {
         m_signalStabilityCount = 0;
      }
      
      m_lastResult = result;
      UpdateLegacyMembers(result);
      
      return result;
   }
   
   //+------------------------------------------------------------------+
   //| Scan multiple timeframes for SR levels                           |
   //+------------------------------------------------------------------+
   void ScanMultiTimeframe(const MqlRates rates[], double atrPrice)
   {
      m_levelCount = 0;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      
      for(int i = 0; i < 4; i++)
      {
         ENUM_TIMEFRAMES tf = m_mtfArray[i];
         if(!cfg.use_mtf && tf != m_period) continue;
         
         MqlRates tfRates[];
         ArraySetAsSeries(tfRates, true);
         int copied = CopyRates(m_symbol, tf, 1, cfg.sr_lookback + 10, tfRates);
         if(copied < 10) continue;
         
         SRLevel sup, res;
         if(ScanTimeframeSwings(tf, tfRates, sup, res, atrPrice))
         {
            if(m_levelCount < MAX_LEVELS) m_levels[m_levelCount++] = sup;
            if(m_levelCount < MAX_LEVELS) m_levels[m_levelCount++] = res;
         }
      }
      
      if(m_levelCount >= 2)
         MergeNearbyLevels(m_levels, m_levelCount, ZONE_MERGE_THRESHOLD_POINTS);
      
      SortLevelsByScore();
   }
   
   void SortLevelsByScore()
   {
      for(int i = 0; i < m_levelCount - 1; i++)
         for(int j = i + 1; j < m_levelCount; j++)
            if(m_levels[j].score > m_levels[i].score)
            {
               SRLevel temp  = m_levels[i];
               m_levels[i]   = m_levels[j];
               m_levels[j]   = temp;
            }
   }
   
   bool FindNearestSignificantLevels(double currentPrice, SRLevel &outSup, SRLevel &outRes)
   {
      if(m_levelCount == 0) return false;
      
      double bestSupDist = DBL_MAX;
      double bestResDist = DBL_MAX;
      bool foundSup = false, foundRes = false;
      
      for(int i = 0; i < m_levelCount; i++)
      {
         double dist = currentPrice - m_levels[i].price;
         if(dist > 0 && dist < bestSupDist)
         { bestSupDist = dist; outSup = m_levels[i]; foundSup = true; }
         if(dist < 0 && MathAbs(dist) < bestResDist)
         { bestResDist = MathAbs(dist); outRes = m_levels[i]; foundRes = true; }
      }
      return (foundSup || foundRes);
   }
   
   // [PATCH SR-08] Base quality reset to 0.0 for proper discrimination
   double CalculateRejectionQuality(const SRLevel &level, const MqlRates rates[], int shift, double atrPrice)
   {
      if(ArraySize(rates) < shift + 5) return 0.0;
      
      double quality = 0.0; // Base 0, not 0.5
      
      // Factor 1: Strength contribution (40%)
      quality += (level.score / 100.0) * 0.4;
      
      // Factor 2: Recent rejection wicks (30%)
      double avgWickRatio = 0;
      int wickCount = 0;
      double touchZone = atrPrice * 0.5; // price units
      
      for(int i = shift; i < MathMin(shift + 5, ArraySize(rates)); i++)
      {
         if(MathAbs(rates[i].low  - level.price) <= touchZone ||
            MathAbs(rates[i].high - level.price) <= touchZone)
         {
            double body = MathAbs(rates[i].open - rates[i].close);
            double range = rates[i].high - rates[i].low;
            double wick  = range - body;
            if(body > 0)
            {
               avgWickRatio += wick / body;
               wickCount++;
            }
         }
      }
      if(wickCount > 0)
      {
         avgWickRatio /= wickCount;
         quality += MathMin(0.3, avgWickRatio * 0.15); // More conservative scaling
      }
      
      // Factor 3: Flip level bonus (20%)
      if(level.isFlip)  quality += 0.2;
      
      // Factor 4: Fresh level bonus (10%)
      if(level.isFresh) quality += 0.1;
      
      return MathMax(0.0, MathMin(1.0, quality));
   }
   
   void UpdateLegacyMembers(const SRResult &result)
   {
      if(result.found)
      {
         if(result.type == POSITION_TYPE_BUY)
         {
            m_targetSupport = result.level.price;
            m_supScore      = result.level.score;
            m_supStrength   = result.level.touchCount;
         }
         else
         {
            m_targetResistance = result.level.price;
            m_resScore         = result.level.score;
            m_resStrength      = result.level.touchCount;
         }
      }
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      datetime times[];
      if(CopyTime(m_symbol, m_period, 0, 1, times) <= 0) return;
      
      int lookback = MathMax(cfg.sr_lookback, cfg.swing_lookback) + 2;
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows,  true);

      if(CopyHigh(m_symbol, m_period, 1, lookback, highs) <= 0 ||
         CopyLow (m_symbol, m_period, 1, lookback, lows)  <= 0)
         return;

      double extRes = highs[ArrayMaximum(highs, 0, cfg.sr_lookback)];
      double extSup = lows [ArrayMinimum(lows,  0, cfg.sr_lookback)];

      int swResShift = -1, swSupShift = -1;
      double swRes = FindNearestSwing(false, cfg.swing_lookback, swResShift, highs, lows);
      double swSup = FindNearestSwing(true,  cfg.swing_lookback, swSupShift, highs, lows);

      if(cfg.sr_mode == SR_EXTREME)
      {
         m_targetResistance = extRes;
         m_targetSupport    = extSup;
      }
      else if(cfg.sr_mode == SR_SWING)
      {
         m_targetResistance = (swRes > 0) ? swRes : extRes;
         m_targetSupport    = (swSup > 0) ? swSup : extSup;
      }
      else
      {
         m_targetResistance = (swRes > 0 && !IsBroken(swRes, false, 5) && (IsBroken(extRes, false, 10) || swResShift < 15)) ? swRes : extRes;
         m_targetSupport    = (swSup > 0 && !IsBroken(swSup, true,  5) && (IsBroken(extSup, true,  10) || swSupShift < 15)) ? swSup : extSup;
      }

      UpdateHTFZones();
      CheckZoneStatus(m_data.GetATRPoints());
      CalculateScores(m_data.GetATRPoints());

      if(m_debugMode)
      {
         DrawOrMoveHLine("ResLine", m_targetResistance, clrRed);
         DrawOrMoveHLine("SupLine", m_targetSupport,    clrBlue);
      }

      ZoneUpdateEvent *zoneEvent = new ZoneUpdateEvent(
          m_targetSupport, m_targetResistance, m_htfSupport, m_htfResistance,
          m_isSupportBroken, m_isResistanceBroken,
          m_supBufferMult, m_resBufferMult,
          m_supHtfAlignment, m_resHtfAlignment,
          m_supStrength, m_resStrength,
          m_data.GetATRPoints(),
          m_supScore, m_resScore);
      DispatchEvent(zoneEvent);
   }
   
   void CheckZoneStatus(double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if(m_targetSupport <= 0 || m_targetResistance <= 0) return;

      int barsToCheck = (cfg.sr_mode == SR_EXTREME) ? 10 : 5;
      m_isSupportBroken    = IsBroken(m_targetSupport,    true,  barsToCheck);
      m_isResistanceBroken = IsBroken(m_targetResistance, false, barsToCheck);

      if(cfg.sr_mode == SR_EXTREME)
      {
         m_resBufferMult = m_supBufferMult = (cfg.entry_mode == MODE_SAFE) ? 0.5 : 0.8;
         return;
      }

      int supTouches = 0, resTouches = 0;
      double touchZone = (atrPoints * cfg.touch_buffer_atr) * _Point;
      double lows[], highs[];
      ArraySetAsSeries(lows,  true);
      ArraySetAsSeries(highs, true);

      if(CopyLow (m_symbol, m_period, 1, cfg.sr_lookback, lows)  > 0 &&
         CopyHigh(m_symbol, m_period, 1, cfg.sr_lookback, highs) > 0)
      {
         for(int i = 0; i < cfg.sr_lookback; i++)
         {
            if(MathAbs(lows [i] - m_targetSupport)    < touchZone) supTouches++;
            if(MathAbs(highs[i] - m_targetResistance) < touchZone) resTouches++;
         }
      }

      m_supStrength = supTouches;
      m_resStrength = resTouches;

      m_supBufferMult = m_isSupportBroken    ? cfg.buffer_mult_weak :
                        (supTouches >= cfg.min_touches_strong) ? cfg.buffer_mult_strong :
                        (supTouches <= 1)    ? cfg.atr_buffer_mult : 0.65;

      m_resBufferMult = m_isResistanceBroken ? cfg.buffer_mult_weak :
                        (resTouches >= cfg.min_touches_strong) ? cfg.buffer_mult_strong :
                        (resTouches <= 1)    ? cfg.atr_buffer_mult : 0.65;

      m_resHtfAlignment = 0;
      if(cfg.use_mtf && m_htfSupport > 0 && m_htfResistance > 0)
      {
         double htfZoneBuffer = (atrPoints * cfg.atr_buffer_mult) * _Point;
         
         m_supHtfAlignment = (m_targetSupport <= m_htfSupport + htfZoneBuffer && m_targetSupport >= m_htfSupport - htfZoneBuffer) ? 1 :
                             (m_targetSupport >= m_htfResistance - htfZoneBuffer) ? -1 : 0;

         m_resHtfAlignment = (m_targetResistance >= m_htfResistance - htfZoneBuffer && m_targetResistance <= m_htfResistance + htfZoneBuffer) ? 1 :
                             (m_targetResistance <= m_htfSupport + htfZoneBuffer) ? -1 : 0;
      }
   }
   
   void CalculateScores(double atrPoints)
   {
      m_supScore = CalculateZoneScore(m_targetSupport,    true,  m_supStrength, atrPoints, m_supHtfAlignment, m_isSupportBroken);
      m_resScore = CalculateZoneScore(m_targetResistance, false, m_resStrength, atrPoints, m_resHtfAlignment, m_isResistanceBroken);
      
      if(m_debugMode)
         PrintFormat("[SRManager] Scores - Sup: %.1f (T=%d,HTF=%d), Res: %.1f (T=%d,HTF=%d)",
                     m_supScore, m_supStrength, m_supHtfAlignment,
                     m_resScore, m_resStrength, m_resHtfAlignment);
   }

   // [PATCH SR-09] ArrayMaximum/ArrayMinimum with explicit count
   void UpdateHTFZones()
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if(!cfg.use_mtf) return;

      double htfHighs[], htfLows[];
      ArraySetAsSeries(htfHighs, true);
      ArraySetAsSeries(htfLows,  true);

      int copiedH = CopyHigh(m_symbol, cfg.htf, 1, cfg.htf_lookback, htfHighs);
      int copiedL = CopyLow (m_symbol, cfg.htf, 1, cfg.htf_lookback, htfLows);
      
      if(copiedH > 0) m_htfResistance = htfHighs[ArrayMaximum(htfHighs, 0, copiedH)];
      if(copiedL > 0) m_htfSupport    = htfLows [ArrayMinimum(htfLows,  0, copiedL)];
   }

   // [PATCH SR-05] Replaced undefined GetGlobalSpread() with inline spread calculation
   bool IsTradableRange(double atrPoints)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spread = (point > 0)
         ? (SymbolInfoDouble(m_symbol, SYMBOL_ASK) - SymbolInfoDouble(m_symbol, SYMBOL_BID)) / point
         : (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);

      double minRange = MathMax(atrPoints * cfg.min_range_atr, spread * 5.0);
      double rangePts = (m_targetResistance - m_targetSupport) / point;
      return (rangePts >= minRange);
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   SRLevel GetNearestStrongLevel(double currentPrice, bool preferSupport = true)
   {
      SRLevel result;
      double bestDist = DBL_MAX;
      for(int i = 0; i < m_levelCount; i++)
      {
         if(m_levels[i].strength < SR_MODERATE) continue;
         double dist = MathAbs(currentPrice - m_levels[i].price);
         if(dist < bestDist) { bestDist = dist; result = m_levels[i]; }
      }
      return result;
   }
   
   bool IsPriceAtSupport   (double p, double buf = 0) const { return m_targetSupport    > 0 && p >= m_targetSupport    - buf && p <= m_targetSupport    + buf; }
   bool IsPriceAtResistance(double p, double buf = 0) const { return m_targetResistance > 0 && p >= m_targetResistance - buf && p <= m_targetResistance + buf; }
   bool IsSignalStable(int requiredTicks = 3) const { return m_signalStabilityCount >= requiredTicks; }
   int  GetLevelCount() const { return m_levelCount; }
   SRLevel GetLevel(int index) const { return (index >= 0 && index < m_levelCount) ? m_levels[index] : SRLevel(); }

   double Support()          const { return m_targetSupport; }
   double Resistance()       const { return m_targetResistance; }
   double HTFSupport()       const { return m_htfSupport; }
   double HTFResistance()    const { return m_htfResistance; }
   bool   IsSupportBroken()  const { return m_isSupportBroken; }
   bool   IsResistanceBroken()const{ return m_isResistanceBroken; }
   double SupBufferMult()    const { return m_supBufferMult; }
   double ResBufferMult()    const { return m_resBufferMult; }
   int    SupHtfAlignment()  const { return m_supHtfAlignment; }
   int    ResHtfAlignment()  const { return m_resHtfAlignment; }
   int    SupStrength()      const { return m_supStrength; }
   int    ResStrength()      const { return m_resStrength; }
   double SupScore()         const { return m_supScore; }
   double ResScore()         const { return m_resScore; }
   SRResult GetLastResult()  const { return m_lastResult; }
   int    GetSignalStabilityCount() const { return m_signalStabilityCount; }
};

#endif
//+------------------------------------------------------------------+
