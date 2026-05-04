//+------------------------------------------------------------------+
//| PatternManager.mqh                                               |
//| Copyright 2026, Agsicentre                                       |
//+------------------------------------------------------------------+
#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

#property strict

#include "2.Config.mqh"

    class PatternManager
{
private:
   struct PatternVote
   {
      bool valid;
      ENUM_PATTERN_TYPE type;
      int dir; // 1 = buy, -1 = sell
      double extreme;
      double score;
      string label;
   };

public:
   bool Detect(const MqlRates &rates[],
               const int shift,
               const double atrPoints,
               ENUM_PATTERN_TYPE &outType,
               int &outDir,
               double &outExtreme,
               double &outScore,
               string &outReason)
   {
      outType = PATTERN_NONE;
      outDir = 0;
      outExtreme = 0.0;
      outScore = 0.0;
      outReason = "";

      if (shift < 1 || atrPoints <= 0)
      {
         outReason = "Invalid shift/ATR";
         return false;
      }

      // Prinsip MQL5: Pastikan pengecekan batas dilakukan terhadap ukuran array rates
      if (shift + 2 >= ArraySize(rates))
      {
         outReason = "Insufficient bar history";
         return false;
      }

      PatternVote votes[8];
      for (int i = 0; i < 8; i++)
         ResetVote(votes[i]);

      EvaluatePinbar(rates, shift, atrPoints, votes[0]);
      EvaluateEngulfing(rates, shift, atrPoints, votes[1]);
      EvaluateBottom(rates, shift, atrPoints, votes[2]);
      EvaluateFakey(rates, shift, atrPoints, votes[3]);
      EvaluateInsideBar(rates, shift, atrPoints, votes[4]);
      EvaluateMorningStar(rates, shift, atrPoints, votes[5]);
      EvaluateThreeInside(rates, shift, atrPoints, votes[6]);
      EvaluateRailroadTracks(rates, shift, atrPoints, votes[7]);

      double buyScore = 0.0;
      double sellScore = 0.0;

      for (int i = 0; i < 5; i++)
      {
         if (!votes[i].valid)
            continue;

         if (votes[i].dir == 1)
         {
            if(CFG.UsePatternConfluence)
               buyScore += votes[i].score;
            else
               buyScore = MathMax(buyScore, votes[i].score);
         }
         else if (votes[i].dir == -1)
         {
            if(CFG.UsePatternConfluence)
               sellScore += votes[i].score;
            else
               sellScore = MathMax(sellScore, votes[i].score);
         }
      }

      double totalScore = MathMax(buyScore, sellScore);
      double conflictScore = MathMin(buyScore, sellScore);
      double dominanceGap = totalScore - conflictScore;

      if (dominanceGap < CFG.MinDominanceGap)
      {
         outReason = StringFormat("Confluence conflict | buy=%.2f sell=%.2f", buyScore, sellScore);
         return false;
      }

      outScore = totalScore;
      outDir = (buyScore > sellScore) ? 1 : -1;

      int bestIdx = FindBestVote(votes, outDir);
      if (bestIdx < 0)
      {
         outReason = "No dominant directional pattern";
         return false;
      }

      outType = votes[bestIdx].type;
      outExtreme = votes[bestIdx].extreme;

      string stack = "";
      if (CFG.UsePatternConfluence)
         stack = " | Stack: " + BuildConfluenceLabel(votes, outDir);

      outReason = votes[bestIdx].label + 
                  StringFormat(" | Confluence %.2f | %s", totalScore, stack);

      return true;
   }

private:
   void ResetVote(PatternVote &v)
   {
      v.valid = false;
      v.type = PATTERN_NONE;
      v.dir = 0;
      v.extreme = 0.0;
      v.score = 0.0;
      v.label = "";
   }

   int FindBestVote(PatternVote &votes[], int dir)
   {
      int best = -1;
      double bestScore = 0.0;

      for (int i = 0; i < ArraySize(votes); i++)
      {
         if (!votes[i].valid || votes[i].dir != dir)
            continue;

         if (votes[i].score > bestScore)
         {
            bestScore = votes[i].score;
            best = i;
         }
      }
      return best;
   }

   string BuildConfluenceLabel(const PatternVote &votes[], int dir)
   {
      string txt = "";
      for (int i = 0; i < ArraySize(votes); i++)
      {
         if (!votes[i].valid || votes[i].dir != dir)
            continue;

         if (txt != "")
            txt += " + ";

         txt += votes[i].label;
      }
      return txt;
   }

   double CandleOpen(const MqlRates &rates[], int shift) { return rates[shift].open; }
   double CandleHigh(const MqlRates &rates[], int shift) { return rates[shift].high; }
   double CandleLow(const MqlRates &rates[], int shift) { return rates[shift].low; }
   double CandleClose(const MqlRates &rates[], int shift) { return rates[shift].close; }

   double CandleRange(const MqlRates &rates[], int shift)
   {
      return CandleHigh(rates, shift) - CandleLow(rates, shift);
   }

   double CandleBody(const MqlRates &rates[], int shift)
   {
      return MathAbs(CandleClose(rates, shift) - CandleOpen(rates, shift));
   }

   double UpperWick(const MqlRates &rates[], int shift)
   {
      return CandleHigh(rates, shift) - MathMax(CandleOpen(rates, shift), CandleClose(rates, shift));
   }

   double LowerWick(const MqlRates &rates[], int shift)
   {
      return MathMin(CandleOpen(rates, shift), CandleClose(rates, shift)) - CandleLow(rates, shift);
   }

   bool IsBullish(const MqlRates &rates[], int shift)
   {
      return CandleClose(rates, shift) > CandleOpen(rates, shift);
   }

   bool IsBearish(const MqlRates &rates[], int shift)
   {
      return CandleClose(rates, shift) < CandleOpen(rates, shift);
   }

   bool IsInsideBar(const MqlRates &rates[], int shift)
   {
      return CandleHigh(rates, shift) < CandleHigh(rates, shift + 1) &&
             CandleLow(rates, shift) > CandleLow(rates, shift + 1);
   }

   double NormalizeATRFactor(const double value, const double atrPoints)
   {
      double atrPrice = atrPoints * _Point;
      if (atrPrice <= 0.0)
         return 0.0;
      return value / atrPrice;
   }

   void AddStrengthFromRejection(const MqlRates &rates[], const int shift, const double atrPoints, const int dir, double &score)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0)
         return;

      double majorWick = (dir == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
      double wickPct = majorWick / range;
      double bodyPct = CandleBody(rates, shift) / range;
      double atrFactor = NormalizeATRFactor(range, atrPoints);

      if (wickPct >= 0.50)
         score += 0.20;
      if (wickPct >= 0.60)
         score += 0.10;
      if (bodyPct <= 0.35)
         score += 0.10;
      if (atrFactor >= 0.60)
         score += 0.10;
   }

   void AddStrengthFromFollowThrough(const MqlRates &rates[], const int shift, const int dir, double &score)
   {
      double prevClose = CandleClose(rates, shift + 1);
      double curClose = CandleClose(rates, shift);

      if (dir == 1 && curClose > prevClose)
         score += 0.10;
      if (dir == -1 && curClose < prevClose)
         score += 0.10;
   }

   void EvaluatePinbar(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0)
         return;

      double bodyMid = (CandleOpen(rates, shift) + CandleClose(rates, shift)) / 2.0;
      double upper = UpperWick(rates, shift);
      double lower = LowerWick(rates, shift);

      int dir = 0;
      double extreme = 0.0;

      if (CandleClose(rates, shift) > bodyMid && lower > (upper > 0 ? upper * 2.0 : _Point))
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if (CandleClose(rates, shift) < bodyMid && upper > (lower > 0 ? lower * 2.0 : _Point))
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return;

      vote.valid = true;
      vote.type = PATTERN_PINBAR;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = 1.00;
      vote.label = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";

      AddStrengthFromRejection(rates, shift, atrPoints, dir, vote.score);
      AddStrengthFromFollowThrough(rates, shift, dir, vote.score);
   }

   void EvaluateEngulfing(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      double o1 = CandleOpen(rates, shift), c1 = CandleClose(rates, shift);
      double o2 = CandleOpen(rates, shift + 1), c2 = CandleClose(rates, shift + 1);

      bool prevBearish = c2 < o2;
      bool prevBullish = c2 > o2;

      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if (prevBearish && c1 > o1 && c1 > o2 && o1 < c2)
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if (prevBullish && c1 < o1 && c1 < o2 && o1 > c2)
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return;

      double body1 = CandleBody(rates, shift);
      double body2 = CandleBody(rates, shift + 1);
         if (body2 > 0.0 && body1 >= body2 * CFG.EngulfingBodyMult)
            score += 0.20;
      if (NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.70)
         score += 0.15;

      vote.valid = true;
      vote.type = PATTERN_ENGULFING;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Engulf Bull" : "Engulf Bear";

      AddStrengthFromFollowThrough(rates, shift, dir, vote.score);
   }

   void EvaluateBottom(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      double h1 = CandleHigh(rates, shift);
      double l1 = CandleLow(rates, shift);
      double h2 = CandleHigh(rates, shift + 1);
      double l2 = CandleLow(rates, shift + 1);

      double tol = MathMax(atrPoints * 0.10 * _Point, 3 * _Point);

      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if (MathAbs(l1 - l2) <= tol && IsBullish(rates, shift))
      {
         dir = 1;
         extreme = MathMin(l1, l2);
      }
      else if (MathAbs(h1 - h2) <= tol && IsBearish(rates, shift))
      {
         dir = -1;
         extreme = MathMax(h1, h2);
      }
      else
         return;

      if (NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.50)
         score += 0.10;
      if (CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= 0.35)
         score += 0.10;

      vote.valid = true;
      vote.type = PATTERN_BOTTOM;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
   }

   void EvaluateFakey(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      // shift     : false-break candle
      double h0 = CandleHigh(rates, shift);
      double l0 = CandleLow(rates, shift);
      double c0 = CandleClose(rates, shift);
      double o0 = CandleOpen(rates, shift);
      // shift + 1 : inside bar
      double h1 = CandleHigh(rates, shift + 1);
      double l1 = CandleLow(rates, shift + 1);
      // shift + 2 : mother bar
      double h2 = CandleHigh(rates, shift + 2);
      double l2 = CandleLow(rates, shift + 2);

      bool insideStructure = (h1 < h2 && l1 > l2);
      if (!insideStructure)
         return;

      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if (l0 < l1 && c0 > l1 && c0 > o0)
      {
         dir = 1;
         extreme = l0;
      }
      else if (h0 > h1 && c0 < h1 && c0 < o0)
      {
         dir = -1;
         extreme = h0;
      }
      else
         return;

      if (NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.60)
         score += 0.15;
      if (CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= 0.40)
         score += 0.10;

      vote.valid = true;
      vote.type = PATTERN_FAKEY;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
   }

   void EvaluateInsideBar(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      if (!IsInsideBar(rates, shift))
         return;

      double motherHigh = CandleHigh(rates, shift + 1);
      double motherLow = CandleLow(rates, shift + 1);
      double motherMid = (motherHigh + motherLow) / 2.0;
      double childClose = CandleClose(rates, shift);
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;

      if (childClose > motherMid)
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if (childClose < motherMid)
      {
         dir = -1;
         extreme = CandleHigh(rates, shift);
      }
      else
         return;

      double motherRange = CandleRange(rates, shift + 1);
      double childRange = CandleRange(rates, shift);

      if (motherRange > 0.0 && childRange / motherRange <= 0.65)
         score += 0.15;
      if (NormalizeATRFactor(motherRange, atrPoints) >= 0.70)
         score += 0.10;

      vote.valid = true;
      vote.type = PATTERN_INSIDE_BAR_BREAKOUT;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Inside Bull" : "Inside Bear";
   }

   void EvaluateMorningStar(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      // Morning Star (Bullish): Bearish candle + Small middle candle (gap down) + Bullish candle (gap up, close > middle)
      // Evening Star (Bearish): Bullish candle + Small middle candle (gap up) + Bearish candle (gap down, close < middle)
      
      if (shift + 2 >= ArraySize(rates))
         return;

      double o0 = CandleOpen(rates, shift), c0 = CandleClose(rates, shift);
      double o1 = CandleOpen(rates, shift + 1), c1 = CandleClose(rates, shift + 1);
      double o2 = CandleOpen(rates, shift + 2), c2 = CandleClose(rates, shift + 2);
      
      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift + 1);
      double body2 = CandleBody(rates, shift + 2);
      double range1 = CandleRange(rates, shift + 1);
      
      double gapThreshold = CFG.StarGapThreshold * atrPoints * _Point;
      int lookback = CFG.StarMiddleBarLookback;
      
      // Check middle bar is small (star)
      bool isSmallMiddle = (body1 < body0 * 0.5) && (body1 < body2 * 0.5);
      if (!isSmallMiddle)
         return;
      
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;
      
      // Morning Star: c2 < o2 (bearish) -> c1 small -> c0 > o0 (bullish) with gaps
      bool morningGap1 = (c2 < o2) && (MathMax(o1, c1) < c2 - gapThreshold);
      bool morningGap2 = (c0 > o0) && (MathMin(o0, c0) > MathMax(o1, c1) + gapThreshold);
      bool morningClose = c0 > (o2 + c2) / 2.0;
      
      if (morningGap1 && morningGap2 && morningClose)
      {
         dir = 1;
         extreme = MathMin(CandleLow(rates, shift + 2), CandleLow(rates, shift + 1));
         score += 0.20; // Bonus for gap confirmation
      }
      
      // Evening Star: c2 > o2 (bullish) -> c1 small -> c0 < o0 (bearish) with gaps
      bool eveningGap1 = (c2 > o2) && (MathMin(o1, c1) > c2 + gapThreshold);
      bool eveningGap2 = (c0 < o0) && (MathMax(o0, c0) < MathMin(o1, c1) - gapThreshold);
      bool eveningClose = c0 < (o2 + c2) / 2.0;
      
      if (eveningGap1 && eveningGap2 && eveningClose)
      {
         dir = -1;
         extreme = MathMax(CandleHigh(rates, shift + 2), CandleHigh(rates, shift + 1));
         score += 0.20; // Bonus for gap confirmation
      }
      
      if (dir == 0)
         return;
      
      // Add strength from ATR
      if (NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.60)
         score += 0.15;
      
      // Add strength from close position
      double closePosition = (dir == 1) ? 
         (c0 - CandleLow(rates, shift)) / MathMax(CandleRange(rates, shift), _Point) :
         (CandleHigh(rates, shift) - c0) / MathMax(CandleRange(rates, shift), _Point);
      
      if (closePosition >= 0.60)
         score += 0.10;
      
      vote.valid = true;
      vote.type = PATTERN_MORNING_STAR;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Morning Star" : "Evening Star";
   }

   void EvaluateThreeInside(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      // Three Inside Up: Large bearish + Inside bar (bullish close) + Bullish breakout above bar 1 high
      // Three Inside Down: Large bullish + Inside bar (bearish close) + Bearish breakout below bar 1 low
      
      if (shift + 2 >= ArraySize(rates))
         return;

      double h0 = CandleHigh(rates, shift), l0 = CandleLow(rates, shift);
      double h1 = CandleHigh(rates, shift + 1), l1 = CandleLow(rates, shift + 1);
      double h2 = CandleHigh(rates, shift + 2), l2 = CandleLow(rates, shift + 2);
      double c0 = CandleClose(rates, shift), o0 = CandleOpen(rates, shift);
      double c1 = CandleClose(rates, shift + 1), o1 = CandleOpen(rates, shift + 1);
      double c2 = CandleClose(rates, shift + 2), o2 = CandleOpen(rates, shift + 2);
      
      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift + 1);
      double body2 = CandleBody(rates, shift + 2);
      
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;
      
      // Three Inside Up
      bool insideUp_1 = IsBearish(rates, shift + 2) && body0 > 0;
      bool insideUp_2 = IsInsideBar(rates, shift + 1) && c1 > o1; // Inside bar with bullish close
      bool insideUp_3 = c0 > h2; // Breakout above mother bar high
      
      if (insideUp_1 && insideUp_2 && insideUp_3)
      {
         dir = 1;
         extreme = MathMin(l1, l2);
         score += 0.15; // Bonus for confirmed breakout
      }
      
      // Three Inside Down
      bool insideDown_1 = IsBullish(rates, shift + 2) && body0 > 0;
      bool insideDown_2 = IsInsideBar(rates, shift + 1) && c1 < o1; // Inside bar with bearish close
      bool insideDown_3 = c0 < l2; // Breakout below mother bar low
      
      if (insideDown_1 && insideDown_2 && insideDown_3)
      {
         dir = -1;
         extreme = Math.Max(h1, h2);
         score += 0.15; // Bonus for confirmed breakout
      }
      
      if (dir == 0)
         return;
      
      // Add strength from ATR
      if (NormalizeATRFactor(CandleRange(rates, shift), atrPoints) >= 0.60)
         score += 0.10;
      
      // Add strength from body ratio
      if (body2 > 0 && body0 / body2 >= 1.3)
         score += 0.10;
      
      vote.valid = true;
      vote.type = PATTERN_THREE_INSIDE;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Three Inside Up" : "Three Inside Down";
   }

   void EvaluateRailroadTracks(const MqlRates &rates[], const int shift, const double atrPoints, PatternVote &vote)
   {
      // Railroad Tracks Bullish: Long bearish candle followed by long bullish candle (similar body size, opposite direction)
      // Railroad Tracks Bearish: Long bullish candle followed by long bearish candle (similar body size, opposite direction)
      
      if (shift + 1 >= ArraySize(rates))
         return;

      double c0 = CandleClose(rates, shift), o0 = CandleOpen(rates, shift);
      double c1 = CandleClose(rates, shift + 1), o1 = CandleOpen(rates, shift + 1);
      
      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift + 1);
      
      double minRatio = CFG.RailroadMinBodyRatio;
      
      int dir = 0;
      double extreme = 0.0;
      double score = 1.00;
      
      // Both bodies must be significant
      if (body0 <= _Point || body1 <= _Point)
         return;
      
      // Check body size similarity (within reasonable ratio)
      double bodyRatio = MathMax(body0, body1) / Math.Min(body0, body1);
      if (bodyRatio > minRatio)
         return; // Bodies too different in size
      
      // Railroad Tracks Bullish: Bar 2 bearish, Bar 1 bullish, similar bodies
      bool railBull = IsBearish(rates, shift + 1) && IsBullish(rates, shift);
      if (railBull)
      {
         dir = 1;
         extreme = Math.Min(CandleLow(rates, shift + 1), CandleLow(rates, shift));
         score += 0.10;
      }
      
      // Railroad Tracks Bearish: Bar 2 bullish, Bar 1 bearish, similar bodies
      bool railBear = IsBullish(rates, shift + 1) && IsBearish(rates, shift);
      if (railBear)
      {
         dir = -1;
         extreme = Math.Max(CandleHigh(rates, shift + 1), CandleHigh(rates, shift));
         score += 0.10;
      }
      
      if (dir == 0)
         return;
      
      // Add strength from ATR
      double avgBody = (body0 + body1) / 2.0;
      double atrPrice = atrPoints * _Point;
      if (atrPrice > 0 && avgBody >= atrPrice * 0.7)
         score += 0.15;
      
      // Add strength from wick rejection
      if (dir == 1 && LowerWick(rates, shift + 1) > body1 * 0.3)
         score += 0.10;
      if (dir == -1 && UpperWick(rates, shift + 1) > body1 * 0.3)
         score += 0.10;
      
      vote.valid = true;
      vote.type = PATTERN_RAILROAD_TRACKS;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.label = (dir == 1) ? "Railroad Bull" : "Railroad Bear";
   }
};

#endif