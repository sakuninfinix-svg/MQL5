//+------------------------------------------------------------------+
//|                                                 4.SRManager.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Support/Resistance Level Calculation Module           |
//+------------------------------------------------------------------+
//| PURPOSE: Calculates S/R levels from price action, swing points,  |
//|          volume profiles, and psychological levels.              |
//|          Provides zone confluence scoring for signal generation. |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.00"
#property strict

#ifndef __SR_MANAGER_MQH__
#define __SR_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Infrastructure/10.DataManager.mqh"

//+------------------------------------------------------------------+
//| SR Level Types                                                   |
//+------------------------------------------------------------------+
enum ENUM_SR_TYPE
{
   SR_TYPE_SWING_HIGH,      // Swing high resistance
   SR_TYPE_SWING_LOW,       // Swing low support
   SR_TYPE_PSYCHOLOGICAL,   // Round number level
   SR_TYPE_VOLUME_NODE,     // High volume node (POC)
   SR_TYPE_FIB_LEVEL,       // Fibonacci retracement
   SR_TYPE_PREVIOUS_DAY,    // Previous day H/L/C
   SR_TYPE_WEEKLY_LEVEL,    // Weekly H/L
   SR_TYPE_MONTHLY_LEVEL,   // Monthly H/L
   SR_TYPE_TRENDLINE        // Dynamic trendline intersection
};

//+------------------------------------------------------------------+
//| SR Strength Scoring                                              |
//+------------------------------------------------------------------+
enum ENUM_SR_STRENGTH
{
   SR_STRENGTH_WEAK,    // 1-2 touches, old level
   SR_STRENGTH_MODERATE,// 3-4 touches, recent test
   SR_STRENGTH_STRONG,  // 5+ touches, multiple timeframes
   SR_STRENGTH_MAJOR    // Major psychological + confluence
};

//+------------------------------------------------------------------+
//| SR Level Structure                                               |
//+------------------------------------------------------------------+
struct SRLevel
{
   double           price;
   double           upperBand;      // Zone upper boundary
   double           lowerBand;      // Zone lower boundary
   ENUM_SR_TYPE     type;
   ENUM_SR_STRENGTH strength;
   int              timeframe;      // TF where level was found
   int              touchCount;     // Number of price touches
   datetime         lastTestTime;   // Last time price tested level
   double           lastTestPrice;
   bool             isValid;        // Level still valid
   int              confluenceScore;// 0-100 confluence score
   string           label;
   
   SRLevel() : price(0), upperBand(0), lowerBand(0), type(SR_TYPE_SWING_HIGH),
               strength(SR_STRENGTH_WEAK), timeframe(0), touchCount(0),
               lastTestTime(0), lastTestPrice(0), isValid(true),
               confluenceScore(0) {}
   
   bool Contains(double p) const
   {
      return (p >= lowerBand && p <= upperBand);
   }
   
   double DistanceFrom(double p) const
   {
      if(p < lowerBand) return lowerBand - p;
      if(p > upperBand) return p - upperBand;
      return 0.0;
   }
   
   void UpdateBands(double atr, double bufferMult = 1.0)
   {
      double bandSize = atr * bufferMult;
      upperBand = price + bandSize;
      lowerBand = price - bandSize;
   }
   
   int GetStrengthScore() const
   {
      switch(strength)
      {
         case SR_STRENGTH_WEAK:     return 25;
         case SR_STRENGTH_MODERATE: return 50;
         case SR_STRENGTH_STRONG:   return 75;
         case SR_STRENGTH_MAJOR:    return 100;
         default: return 0;
      }
   }
};

//+------------------------------------------------------------------+
//| Confluence Result                                                |
//+------------------------------------------------------------------+
struct ConfluenceResult
{
   double   supportPrice;
   double   resistancePrice;
   int      supportConfluence;  // 0-100
   int      resistanceConfluence;
   int      totalLevelsFound;
   bool     isMajorZone;        // High confluence area
   
   ConfluenceResult() : supportPrice(0), resistancePrice(0),
                        supportConfluence(0), resistanceConfluence(0),
                        totalLevelsFound(0), isMajorZone(false) {}
};

//+------------------------------------------------------------------+
//| SRManager Class                                                  |
//+------------------------------------------------------------------+
class SRManager : public IManager
{
private:
   SRLevel  m_levels[];
   int      m_maxLevels;
   double   m_atrBufferMult;
   int      m_swingLookback;
   double   m_psychoStep;       // Step for psychological levels
   
   // Cache for performance
   datetime m_lastCalculationBar;
   double   m_cachedSupport;
   double   m_cachedResistance;
   
   // Handle for ATR indicator
   int      m_atrHandle;
   int      m_highHandle;
   int      m_lowHandle;
   
private:
   //--- Internal calculation methods
   void CalculateSwingLevels(int lookback)
   {
      int copiedHigh = CopyHigh(m_symbol, _Period, 0, lookback * 3, m_data.GetBufferHigh());
      int copiedLow  = CopyLow(m_symbol, _Period, 0, lookback * 3, m_data.GetBufferLow());
      
      if(copiedHigh < lookback * 3 || copiedLow < lookback * 3) return;
      
      const double &highs[] = m_data.GetBufferHigh();
      const double &lows[]  = m_data.GetBufferLow();
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      
      // Find swing highs (resistance)
      for(int i = lookback; i < lookback * 2; i++)
      {
         bool isSwingHigh = true;
         for(int j = 1; j <= lookback; j++)
         {
            if(i - j < 0 || i + j >= copiedHigh) { isSwingHigh = false; break; }
            if(highs[i] <= highs[i-j] || highs[i] <= highs[i+j])
            {
               isSwingHigh = false;
               break;
            }
         }
         
         if(isSwingHigh && highs[i] > 0)
            AddSRLevel(highs[i], SR_TYPE_SWING_HIGH, _Period);
      }
      
      // Find swing lows (support)
      for(int i = lookback; i < lookback * 2; i++)
      {
         bool isSwingLow = true;
         for(int j = 1; j <= lookback; j++)
         {
            if(i - j < 0 || i + j >= copiedLow) { isSwingLow = false; break; }
            if(lows[i] >= lows[i-j] || lows[i] >= lows[i+j])
            {
               isSwingLow = false;
               break;
            }
         }
         
         if(isSwingLow && lows[i] > 0)
            AddSRLevel(lows[i], SR_TYPE_SWING_LOW, _Period);
      }
   }
   
   void CalculatePsychologicalLevels(double currentPrice)
   {
      double step = m_psychoStep;
      if(step <= 0) step = CalculatePsychoStep(currentPrice);
      
      double basePrice = MathFloor(currentPrice / step) * step;
      
      // Add levels above and below current price
      for(int i = -5; i <= 5; i++)
      {
         double level = basePrice + (i * step);
         if(level > 0 && level != currentPrice)
            AddSRLevel(level, SR_TYPE_PSYCHOLOGICAL, _Period);
      }
   }
   
   double CalculatePsychoStep(double price) const
   {
      if(price >= 1000) return 100.0;
      if(price >= 100)  return 10.0;
      if(price >= 10)   return 1.0;
      if(price >= 1)    return 0.1;
      if(price >= 0.1)  return 0.01;
      return 0.001;
   }
   
   void CalculatePreviousDayLevels()
   {
      datetime todayStart = iTime(m_symbol, PERIOD_D1, 0);
      datetime yesterdayStart = iTime(m_symbol, PERIOD_D1, 1);
      
      if(todayStart == 0 || yesterdayStart == 0) return;
      
      double prevHigh = iHigh(m_symbol, PERIOD_D1, 1);
      double prevLow  = iLow(m_symbol, PERIOD_D1, 1);
      double prevClose = iClose(m_symbol, PERIOD_D1, 1);
      
      if(prevHigh > 0) AddSRLevel(prevHigh, SR_TYPE_PREVIOUS_DAY, PERIOD_D1);
      if(prevLow > 0)  AddSRLevel(prevLow, SR_TYPE_PREVIOUS_DAY, PERIOD_D1);
      if(prevClose > 0) AddSRLevel(prevClose, SR_TYPE_PREVIOUS_DAY, PERIOD_D1);
   }
   
   void AddSRLevel(double price, ENUM_SR_TYPE type, int tf)
   {
      // Check if level already exists (within tolerance)
      double tolerance = _Point * 10;
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid) continue;
         if(MathAbs(m_levels[i].price - price) < tolerance)
         {
            // Increment touch count if same level
            if(type == m_levels[i].type)
            {
               m_levels[i].touchCount++;
               m_levels[i].lastTestTime = TimeCurrent();
               m_levels[i].lastTestPrice = price;
               UpdateLevelStrength(m_levels[i]);
            }
            return;
         }
      }
      
      // Find empty slot or expand array
      int slot = -1;
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid)
         {
            slot = i;
            break;
         }
      }
      
      if(slot < 0)
      {
         int newSize = ArraySize(m_levels) + 10;
         ArrayResize(m_levels, newSize);
         slot = ArraySize(m_levels) - 10;
      }
      
      m_levels[slot].price = price;
      m_levels[slot].type = type;
      m_levels[slot].timeframe = tf;
      m_levels[slot].touchCount = 1;
      m_levels[slot].lastTestTime = TimeCurrent();
      m_levels[slot].lastTestPrice = price;
      m_levels[slot].isValid = true;
      m_levels[slot].label = GetLevelTypeName(type) + "_" + DoubleToString(price, _Digits);
      
      // Update bands based on current ATR
      double atr = GetCurrentATR();
      m_levels[slot].UpdateBands(atr, m_atrBufferMult);
      
      // Calculate initial strength
      UpdateLevelStrength(m_levels[slot]);
   }
   
   void UpdateLevelStrength(SRLevel &level)
   {
      int score = 0;
      
      // Touch count scoring
      if(level.touchCount >= 5)      score += 40;
      else if(level.touchCount >= 3) score += 25;
      else                           score += 10;
      
      // Timeframe importance
      if(level.timeframe >= PERIOD_W1) score += 30;
      else if(level.timeframe >= PERIOD_D1) score += 20;
      else if(level.timeframe >= PERIOD_H4) score += 10;
      
      // Type importance
      if(level.type == SR_TYPE_PSYCHOLOGICAL) score += 20;
      if(level.type == SR_TYPE_PREVIOUS_DAY)  score += 15;
      
      // Recency bonus
      datetime age = TimeCurrent() - level.lastTestTime;
      if(age < 86400)      score += 10;  // Tested within 1 day
      else if(age < 604800) score += 5;  // Tested within 1 week
      
      // Determine strength enum
      if(score >= 80)      level.strength = SR_STRENGTH_MAJOR;
      else if(score >= 60) level.strength = SR_STRENGTH_STRONG;
      else if(score >= 40) level.strength = SR_STRENGTH_MODERATE;
      else                 level.strength = SR_STRENGTH_WEAK;
      
      level.confluenceScore = MathMin(100, score);
   }
   
   double GetCurrentATR()
   {
      double atr[];
      if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) > 0)
         return atr[0];
      return _Point * 100; // Fallback
   }
   
   string GetLevelTypeName(ENUM_SR_TYPE type) const
   {
      switch(type)
      {
         case SR_TYPE_SWING_HIGH:    return "SH";
         case SR_TYPE_SWING_LOW:     return "SL";
         case SR_TYPE_PSYCHOLOGICAL: return "PSY";
         case SR_TYPE_VOLUME_NODE:   return "VOL";
         case SR_TYPE_FIB_LEVEL:     return "FIB";
         case SR_TYPE_PREVIOUS_DAY:  return "PD";
         case SR_TYPE_WEEKLY_LEVEL:  return "WK";
         case SR_TYPE_MONTHLY_LEVEL: return "MN";
         case SR_TYPE_TRENDLINE:     return "TL";
         default: return "UNK";
      }
   }
   
public:
   SRManager() : m_maxLevels(50), m_atrBufferMult(1.0), m_swingLookback(20),
                 m_psychoStep(0), m_lastCalculationBar(0),
                 m_cachedSupport(0), m_cachedResistance(0),
                 m_atrHandle(INVALID_HANDLE), m_highHandle(INVALID_HANDLE),
                 m_lowHandle(INVALID_HANDLE)
   {
      ArrayResize(m_levels, m_maxLevels);
   }
   
   virtual ~SRManager()
   {
      if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_highHandle != INVALID_HANDLE) IndicatorRelease(m_highHandle);
      if(m_lowHandle != INVALID_HANDLE) IndicatorRelease(m_lowHandle);
      ArrayFree(m_levels);
   }
   
   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      
      // Initialize indicators
      m_atrHandle = iATR(m_symbol, _Period, Config().atr_period);
      m_highHandle = iHigh(m_symbol, _Period, 0);
      m_lowHandle = iLow(m_symbol, _Period, 0);
      
      if(m_atrHandle == INVALID_HANDLE)
      {
         Log("❌ Failed to create ATR indicator");
         return false;
      }
      
      ArrayResize(m_levels, m_maxLevels);
      
      // Initial calculation
      RefreshSRLevels();
      
      Log("✅ SRManager initialized with " + IntegerToString(m_maxLevels) + " levels capacity");
      return true;
   }
   
   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_ZONE_UPDATE);
   }
   
   //--- Main refresh method called on new bar
   void RefreshSRLevels()
   {
      datetime currentBar = iTime(m_symbol, _Period, 0);
      if(currentBar == m_lastCalculationBar) return; // Already calculated for this bar
      m_lastCalculationBar = currentBar;
      
      // Clear old invalid levels
      CleanupOldLevels();
      
      // Calculate all level types
      CalculateSwingLevels(m_swingLookback);
      CalculatePsychologicalLevels(SymbolInfoDouble(m_symbol, SYMBOL_BID));
      CalculatePreviousDayLevels();
      
      // Update all level bands with current ATR
      double atr = GetCurrentATR();
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(m_levels[i].isValid)
            m_levels[i].UpdateBands(atr, m_atrBufferMult);
      }
      
      // Calculate confluence and cache key levels
      ConfluenceResult result = FindConfluence(SymbolInfoDouble(m_symbol, SYMBOL_BID));
      m_cachedSupport = result.supportPrice;
      m_cachedResistance = result.resistancePrice;
      
      // Emit update event
      EmitZoneUpdate(result);
   }
   
   void CleanupOldLevels()
   {
      datetime cutoff = TimeCurrent() - (90 * 86400); // 90 days
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid) continue;
         
         // Invalidate very old untested levels
         if(m_levels[i].lastTestTime > 0 && m_levels[i].lastTestTime < cutoff)
         {
            if(m_levels[i].touchCount < 2)
            {
               m_levels[i].isValid = false;
               ZeroMemory(m_levels[i]);
            }
         }
      }
   }
   
   //--- Find nearest S/R with confluence scoring
   ConfluenceResult FindConfluence(double currentPrice) const
   {
      ConfluenceResult result;
      
      double nearestSup = 0;
      double nearestRes = DBL_MAX;
      int supScore = 0;
      int resScore = 0;
      int totalLevels = 0;
      
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid) continue;
         
         totalLevels++;
         double dist = m_levels[i].DistanceFrom(currentPrice);
         int strengthScore = m_levels[i].GetStrengthScore();
         
         if(m_levels[i].price < currentPrice)
         {
            // Potential support
            if(dist < (currentPrice - nearestSup) || nearestSup == 0)
            {
               nearestSup = m_levels[i].price;
               supScore = strengthScore;
            }
            else if(dist < _Point * 50) // Within zone
            {
               supScore = MathMax(supScore, strengthScore);
            }
         }
         else if(m_levels[i].price > currentPrice)
         {
            // Potential resistance
            if((nearestRes == DBL_MAX || (m_levels[i].price - currentPrice) < (nearestRes - currentPrice)))
            {
               nearestRes = m_levels[i].price;
               resScore = strengthScore;
            }
            else if(dist < _Point * 50) // Within zone
            {
               resScore = MathMax(resScore, strengthScore);
            }
         }
      }
      
      result.supportPrice = nearestSup;
      result.resistancePrice = (nearestRes == DBL_MAX) ? 0 : nearestRes;
      result.supportConfluence = supScore;
      result.resistanceConfluence = resScore;
      result.totalLevelsFound = totalLevels;
      result.isMajorZone = (supScore >= 75 || resScore >= 75);
      
      return result;
   }
   
   //--- Get nearest support level
   SRLevel* GetNearestSupport(double currentPrice)
   {
      SRLevel *nearest = NULL;
      double maxDist = 0;
      
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid) continue;
         if(m_levels[i].price >= currentPrice) continue;
         
         double dist = currentPrice - m_levels[i].price;
         if(nearest == NULL || dist < maxDist)
         {
            nearest = &m_levels[i];
            maxDist = dist;
         }
      }
      
      return nearest;
   }
   
   //--- Get nearest resistance level
   SRLevel* GetNearestResistance(double currentPrice)
   {
      SRLevel *nearest = NULL;
      double minDist = DBL_MAX;
      
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid) continue;
         if(m_levels[i].price <= currentPrice) continue;
         
         double dist = m_levels[i].price - currentPrice;
         if(dist < minDist)
         {
            nearest = &m_levels[i];
            minDist = dist;
         }
      }
      
      return nearest;
   }
   
   //--- Check if price is in S/R zone
   bool IsInSRZone(double price, ENUM_SR_TYPE &foundType) const
   {
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid) continue;
         if(m_levels[i].Contains(price))
         {
            foundType = m_levels[i].type;
            return true;
         }
      }
      return false;
   }
   
   //--- Get all valid levels
   int GetValidLevels(SRLevel &outArray[]) const
   {
      int count = 0;
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(m_levels[i].isValid)
         {
            int idx = ArraySize(outArray);
            ArrayResize(outArray, idx + 1);
            outArray[idx] = m_levels[i];
            count++;
         }
      }
      return count;
   }
   
   //--- Configuration setters
   void SetMaxLevels(int max) 
   { 
      m_maxLevels = MathMax(10, MathMin(100, max)); 
      ArrayResize(m_levels, m_maxLevels);
   }
   
   void SetAtrBufferMult(double mult) { m_atrBufferMult = MathMax(0.5, MathMin(3.0, mult)); }
   void SetSwingLookback(int bars)    { m_swingLookback = MathMax(5, MathMin(50, bars)); }
   
   //--- Event handlers
   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      RefreshSRLevels();
   }
   
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      
      // Update touch counts if price tests levels
      double price = e.tick.bid;
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(!m_levels[i].isValid) continue;
         
         if(m_levels[i].Contains(price))
         {
            m_levels[i].touchCount++;
            m_levels[i].lastTestTime = TimeCurrent();
            m_levels[i].lastTestPrice = price;
            UpdateLevelStrength(m_levels[i]);
         }
      }
   }
   
   void EmitZoneUpdate(const ConfluenceResult &result)
   {
      ZoneUpdateEvent *zoneEvent = new ZoneUpdateEvent(
         result.supportPrice,
         result.resistancePrice,
         0, 0,  // HTF values (can be populated from higher TF analysis)
         false, false,  // Broken flags
         m_atrBufferMult, m_atrBufferMult,
         0, 0,  // HTF alignment
         result.supportConfluence, result.resistanceConfluence,
         GetCurrentATR(),
         result.supportConfluence,
         result.resistanceConfluence
      );
      
      if(CheckPointer(zoneEvent) != POINTER_INVALID)
         DispatchEvent(zoneEvent);
   }
   
   //--- Accessors
   double GetCachedSupport() const    { return m_cachedSupport; }
   double GetCachedResistance() const { return m_cachedResistance; }
   int GetTotalValidLevels() const
   {
      int count = 0;
      for(int i = 0; i < ArraySize(m_levels); i++)
         if(m_levels[i].isValid) count++;
      return count;
   }
};

#endif // __SR_MANAGER_MQH__
