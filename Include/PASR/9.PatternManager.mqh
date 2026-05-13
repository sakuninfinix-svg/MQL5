//+------------------------------------------------------------------+
//|                                              9.PatternManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Pattern Detection & Analysis Module                   |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

// Forward declarations only - no need for full IManager include
// PatternManager is a plain utility class, not an IManager subclass

struct FakeoutResult
{
   bool detected;         // Fakeout detected?
   int level;             // 1=Penetration, 2=Reversal, 3=Confirmed
   double penetrationPts; // Overshoot distance in points
   double confidence;     // 0.0-1.0 confidence score
   string reason;         // Diagnosis
};

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
      double slMult; // NEW: Recommended SL multiplier for this pattern
      string label;
   };

public:
   bool Detect(ENUM_PATTERN_TYPE &outType,
               const MqlRates &rates[],
               const int shift,
               const double _atrPoints,
               int &outDir,
               double &outExtreme,
               double &outScore,
               double &outSLMult,
               string &outReason)
   {
      outType = PATTERN_NONE;
      outDir = 0;
      outExtreme = 0.0;
      outScore = 0.0;
      outSLMult = 1.0;
      outReason = "";

      if (shift < 1 || _atrPoints <= 0)
      {
         outReason = "Invalid shift/ATR";
         return false;
      }

      if (shift + 3 >= ArraySize(rates))
      {
         outReason = "Insufficient bar history";
         return false;
      }

      PatternVote votes[10];
      for (int i = 0; i < 10; i++)
         ResetVote(votes[i]);

      EvaluatePinbar(rates, shift, _atrPoints, votes[0]);
      EvaluateEngulfing(rates, shift, _atrPoints, votes[1]);
      EvaluateBottom(rates, shift, _atrPoints, votes[2]);
      EvaluateFakey(rates, shift, _atrPoints, votes[3]);
      EvaluateInsideBar(rates, shift, _atrPoints, votes[4]);
      EvaluateMorningStar(rates, shift, _atrPoints, votes[5]);
      EvaluateThreeInside(rates, shift, _atrPoints, votes[6]);
      EvaluateRailroadTracks(rates, shift, _atrPoints, votes[7]);
      EvaluateDarkCloudPiercing(rates, shift, _atrPoints, votes[8]);
      EvaluateMarubozu(rates, shift, _atrPoints, votes[9]);

      double buyScore = 0.0;
      double sellScore = 0.0;

      for (int i = 0; i < 10; i++)
      {
         if (!votes[i].valid)
            continue;
         if (votes[i].dir == 1)
            buyScore = MathMax(buyScore, votes[i].score);
         else if (votes[i].dir == -1)
            sellScore = MathMax(sellScore, votes[i].score);
      }

      double totalScore = MathMax(buyScore, sellScore);
      double conflictScore = MathMin(buyScore, sellScore);
      double dominanceGap = totalScore - conflictScore;

      if (dominanceGap < CFG.pattern.minDominanceGap)
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
      outSLMult = votes[bestIdx].slMult;

      outReason = votes[bestIdx].label +
                  StringFormat(" | Score %.2f", totalScore);

      return true;
   }

   // Integrated Fakeout Detection Context
   struct FakeoutContext
   {
      ulong originalTicket;
      int direction;
      double slHitPrice;
      double entryPrice;
      double atrPoints;
      double slMultiplier; // Adaptive Overshoot Base
      MqlTick currentTick;
      MqlRates rates[];
   };

   // Integrated Fakeout Detection with Adaptive Zone
   static bool DetectFakeout(const FakeoutContext &ctx, FakeoutResult &result)
   {
      result.detected = false;
      result.level = 0;
      result.confidence = 0.0;

      // Adaptive Overshoot: Toleransi berdasarkan SLMult pola tersebut
      double maxOvershoot = ctx.atrPoints * ctx.slMultiplier * _Point;
      double penetration = (ctx.direction == 1) ? (ctx.slHitPrice - ctx.currentTick.bid) : (ctx.currentTick.ask - ctx.slHitPrice);

      if (penetration > maxOvershoot)
      {
         result.reason = "Momentum Breakout (Overshoot too deep)";
         return false;
      }

      bool bodyReversal = (ctx.direction == 1) ? (ctx.rates[0].close > ctx.rates[0].open) : (ctx.rates[0].close < ctx.rates[0].open);

      if (bodyReversal)
         result.level = 2;

      result.detected = (penetration > 0 && bodyReversal);
      result.confidence = 0.5 + (bodyReversal ? 0.3 : 0);
      result.reason = StringFormat("Fakeout Level %d | Pen: %.1f pts", result.level, penetration / _Point);

      return result.detected;
   }

private:
   void ResetVote(PatternVote &v)
   {
      v.valid = false;
      v.type = PATTERN_NONE;
      v.dir = 0;
      v.extreme = 0.0;
      v.score = 0.0;
      v.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
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

   double NormalizeATRFactor(const double value, const double _atrPoints)
   {
      double atrPrice = _atrPoints * _Point;
      if (atrPrice <= 0.0)
         return 0.0;
      return value / atrPrice;
   }

   void AddStrengthFromRejection(const MqlRates &rates[], const int shift, const double _atrPoints, const int dir, double &score)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0)
         return;

      double majorWick = (dir == 1) ? LowerWick(rates, shift) : UpperWick(rates, shift);
      double wickPct = majorWick / range;
      double bodyPct = CandleBody(rates, shift) / range;
      double atrFactor = NormalizeATRFactor(range, _atrPoints);

      if (wickPct >= CFG.pattern.wickRatioThreshold)
         score += CFG.pattern.bonusStrongWick;
      if (bodyPct <= CFG.pattern.bodyRatioThreshold) // Smaller body often indicates stronger rejection
         score += CFG.pattern.bonusStrongBody;
      if (atrFactor >= CFG.pattern.atrRangeThreshold)
         score += CFG.pattern.bonusStrongATR;
   }

   void AddStrengthFromFollowThrough(const MqlRates &rates[], const int shift, const int dir, double &score)
   {
      double prevClose = CandleClose(rates, shift + 1);
      double curClose = CandleClose(rates, shift);

      if ((dir == 1 && curClose > prevClose) || (dir == -1 && curClose < prevClose))
         score += CFG.pattern.bonusFollowThrough;
   }

   void EvaluatePinbar(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
   {
      double range = CandleRange(rates, shift);
      if (range <= 0.0)
         return;

      double bodyMid = (CandleOpen(rates, shift) + CandleClose(rates, shift)) / 2.0;
      double upper = UpperWick(rates, shift);
      double lower = LowerWick(rates, shift);

      int dir = 0;
      double extreme = 0.0;

      if (CandleClose(rates, shift) > bodyMid && lower > (upper > 0 ? upper * CFG.pattern.pinbarWickRatio : _Point))
      {
         dir = 1;
         extreme = CandleLow(rates, shift);
      }
      else if (CandleClose(rates, shift) < bodyMid && upper > (lower > 0 ? lower * CFG.pattern.pinbarWickRatio : _Point))
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
      vote.score = CFG.pattern.baseScore;
      vote.slMult = CFG.pattern.pinbarSLMult; // Pinbars get wider SL
      vote.label = (dir == 1) ? "Pinbar Bull" : "Pinbar Bear";

      AddStrengthFromRejection(rates, shift, _atrPoints, dir, vote.score);
      AddStrengthFromFollowThrough(rates, shift, dir, vote.score);
   }

   void EvaluateEngulfing(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
   {
      double o1 = CandleOpen(rates, shift), c1 = CandleClose(rates, shift);
      double o2 = CandleOpen(rates, shift + 1), c2 = CandleClose(rates, shift + 1);

      bool prevBearish = c2 < o2;
      bool prevBullish = c2 > o2;

      int dir = 0;
      double extreme = 0.0;
      double score = CFG.pattern.baseScore;

      if (prevBearish && c1 > o1 && c1 > o2 && o1 < c2)
      {
         dir = 1;
         extreme = MathMin(CandleLow(rates, shift), CandleLow(rates, shift + 1));
      }
      else if (prevBullish && c1 < o1 && c1 < o2 && o1 > c2)
      {
         dir = -1;
         extreme = MathMax(CandleHigh(rates, shift), CandleHigh(rates, shift + 1));
      }
      else
         return;

      double body1 = CandleBody(rates, shift);
      double body2 = CandleBody(rates, shift + 1);
      if (body2 > 0.0 && body1 >= body2 * CFG.pattern.engulfingBodyMult)
         score += CFG.pattern.bonusStrongBody;
      if (NormalizeATRFactor(CandleRange(rates, shift), _atrPoints) >= CFG.pattern.atrRangeThreshold)
         score += CFG.pattern.bonusStrongATR;

      vote.valid = true;
      vote.type = PATTERN_ENGULFING;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
      vote.label = (dir == 1) ? "Engulf Bull" : "Engulf Bear";
      AddStrengthFromFollowThrough(rates, shift, dir, vote.score);
   }

   void EvaluateBottom(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
   {
      double h1 = CandleHigh(rates, shift);
      double l1 = CandleLow(rates, shift);
      double h2 = CandleHigh(rates, shift + 1);
      double l2 = CandleLow(rates, shift + 1);
      double tol = MathMax(_atrPoints * CFG.pattern.sensitivityATR * _Point, 3 * _Point); // 3*_Point is a reasonable minimum
      int dir = 0;
      double extreme = 0.0;
      double score = CFG.pattern.baseScore;

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

      if (NormalizeATRFactor(CandleRange(rates, shift), _atrPoints) >= CFG.pattern.atrRangeThreshold)
         score += CFG.pattern.bonusStrongATR;
      if (CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= CFG.pattern.bodyRatioThreshold)
         score += CFG.pattern.bonusStrongBody;

      vote.valid = true;
      vote.type = PATTERN_BOTTOM;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
      vote.label = (dir == 1) ? "Tweezer Bottom" : "Tweezer Top";
   }

   void EvaluateFakey(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
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
      double score = CFG.pattern.baseScore;

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

      if (NormalizeATRFactor(CandleRange(rates, shift), _atrPoints) >= CFG.pattern.atrRangeThreshold)
         score += CFG.pattern.bonusStrongATR;
      if (CandleBody(rates, shift) / MathMax(CandleRange(rates, shift), _Point) >= CFG.pattern.bodyRatioThreshold)
         score += CFG.pattern.bonusStrongBody;

      vote.valid = true;
      vote.type = PATTERN_FAKEY;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
      vote.label = (dir == 1) ? "Fakey Bull" : "Fakey Bear";
   }

   void EvaluateInsideBar(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
   {
      if (!IsInsideBar(rates, shift))
         return;

      double motherHigh = CandleHigh(rates, shift + 1);
      double motherLow = CandleLow(rates, shift + 1);
      double motherMid = (motherHigh + motherLow) / 2.0;
      double childClose = CandleClose(rates, shift);
      int dir = 0;
      double extreme = 0.0;
      double score = CFG.pattern.baseScore;
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

      if (motherRange > 0.0 && childRange / motherRange <= CFG.pattern.insideBarRangeMax)
         score += CFG.pattern.bonusStrongBody;
      if (NormalizeATRFactor(motherRange, _atrPoints) >= CFG.pattern.atrRangeThreshold)
         score += CFG.pattern.bonusStrongATR;

      vote.valid = true;
      vote.type = PATTERN_INSIDE_BAR_BREAKOUT;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = CFG.pattern.insideBarSLMult;
      vote.label = (dir == 1) ? "Inside Bull" : "Inside Bear";
   }

   void EvaluateMorningStar(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
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
      double gapThreshold = CFG.pattern.sensitivityATR * _atrPoints * _Point;

      // Check middle bar is small (star)
      bool isSmallMiddle = (range1 > 0) && (body1 < body0 * CFG.pattern.starMiddleBodyMult) && (body1 < body2 * CFG.pattern.starMiddleBodyMult);
      if (!isSmallMiddle)
         return;

      int dir = 0;
      double extreme = 0.0;
      double score = CFG.pattern.baseScore;
      // Morning Star: c2 < o2 (bearish) -> c1 small -> c0 > o0 (bullish) with gaps
      bool morningGap1 = (c2 < o2) && (MathMax(o1, c1) < c2 - gapThreshold);
      bool morningGap2 = (c0 > o0) && (MathMin(o0, c0) > MathMax(o1, c1) + gapThreshold);
      bool morningClose = c0 > (o2 + c2) / 2.0;

      if (morningGap1 && morningGap2 && morningClose)
      {
         dir = 1;
         extreme = MathMin(CandleLow(rates, shift + 2), CandleLow(rates, shift + 1));
         score += CFG.pattern.bonusGapConfirm;
      }

      // Evening Star: c2 > o2 (bullish) -> c1 small -> c0 < o0 (bearish) with gaps
      bool eveningGap1 = (c2 > o2) && (MathMin(o1, c1) > c2 + gapThreshold);
      bool eveningGap2 = (c0 < o0) && (MathMax(o0, c0) < MathMin(o1, c1) - gapThreshold);
      bool eveningClose = c0 < (o2 + c2) / 2.0;

      if (eveningGap1 && eveningGap2 && eveningClose)
      {
         dir = -1;
         extreme = MathMax(CandleHigh(rates, shift + 2), CandleHigh(rates, shift + 1));
         score += CFG.pattern.bonusGapConfirm;
      }

      if (dir == 0)
         return;

      // Add strength from ATR
      if (NormalizeATRFactor(CandleRange(rates, shift), _atrPoints) >= CFG.pattern.atrRangeThreshold)
         score += CFG.pattern.bonusStrongATR;

      // Add strength from close position
      double closePosition = (dir == 1) ? (c0 - CandleLow(rates, shift)) / MathMax(CandleRange(rates, shift), _Point) : (CandleHigh(rates, shift) - c0) / MathMax(CandleRange(rates, shift), _Point);

      if (closePosition >= CFG.pattern.starCloseMin)
         score += CFG.pattern.bonusStrongBody;

      vote.valid = true;
      vote.type = PATTERN_MORNING_STAR;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
      vote.label = (dir == 1) ? "Morning Star" : "Evening Star";
   }

   void EvaluateThreeInside(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
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
      double score = CFG.pattern.baseScore;
      // Three Inside Up
      bool insideUp_1 = IsBearish(rates, shift + 2) && body0 > 0;
      bool insideUp_2 = IsInsideBar(rates, shift + 1) && c1 > o1; // Inside bar with bullish close
      bool insideUp_3 = c0 > h2;                                  // Breakout above mother bar high

      if (insideUp_1 && insideUp_2 && insideUp_3)
      {
         dir = 1;
         extreme = MathMin(l1, l2);
         score += CFG.pattern.bonusBreakoutConfirm;
      }

      // Three Inside Down
      bool insideDown_1 = IsBullish(rates, shift + 2) && body0 > 0;
      bool insideDown_2 = IsInsideBar(rates, shift + 1) && c1 < o1; // Inside bar with bearish close
      bool insideDown_3 = c0 < l2;                                  // Breakout below mother bar low

      if (insideDown_1 && insideDown_2 && insideDown_3)
      {
         dir = -1;
         extreme = MathMax(h1, h2);
         score += CFG.pattern.bonusBreakoutConfirm;
      }

      if (dir == 0)
         return;
      if (NormalizeATRFactor(CandleRange(rates, shift), _atrPoints) >= CFG.pattern.atrRangeThreshold)
         score += CFG.pattern.bonusStrongATR;
      if (body2 > 0 && body0 / body2 >= CFG.pattern.threeInsideBodyMin)
         score += CFG.pattern.bonusStrongBody;

      vote.valid = true;
      vote.type = PATTERN_THREE_INSIDE;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
      vote.label = (dir == 1) ? "Three Inside Up" : "Three Inside Down";
   }

   void EvaluateRailroadTracks(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
   {
      // Railroad Tracks Bullish: Long bearish candle followed by long bullish candle (similar body size, opposite direction)
      // Railroad Tracks Bearish: Long bullish candle followed by long bearish candle (similar body size, opposite direction)

      if (shift + 1 >= ArraySize(rates))
         return;

      double c0 = CandleClose(rates, shift), o0 = CandleOpen(rates, shift);
      double c1 = CandleClose(rates, shift + 1), o1 = CandleOpen(rates, shift + 1);

      double body0 = CandleBody(rates, shift);
      double body1 = CandleBody(rates, shift + 1);

      double minRatio = CFG.pattern.railroadMinBodyRatio;

      int dir = 0;
      double extreme = 0.0;
      double score = CFG.pattern.baseScore;

      // Both bodies must be significant
      if (body0 <= _Point || body1 <= _Point)
         return;

      // Check body size similarity (within reasonable ratio)
      double bodyRatio = MathMax(body0, body1) / MathMin(body0, body1);
      if (bodyRatio > minRatio)
         return; // Bodies too different in size

      // Railroad Tracks Bullish: Bar 2 bearish, Bar 1 bullish, similar bodies
      bool railBull = IsBearish(rates, shift + 1) && IsBullish(rates, shift);
      if (railBull)
      {
         dir = 1;
         extreme = MathMin(CandleLow(rates, shift + 1), CandleLow(rates, shift));
         score += CFG.pattern.bonusSmall; // Generic small bonus for pattern recognition
      }

      // Railroad Tracks Bearish: Bar 2 bullish, Bar 1 bearish, similar bodies
      bool railBear = IsBullish(rates, shift + 1) && IsBearish(rates, shift);
      if (railBear)
      {
         dir = -1;
         extreme = MathMax(CandleHigh(rates, shift + 1), CandleHigh(rates, shift));
         score += CFG.pattern.bonusSmall; // Generic small bonus for pattern recognition
      }

      if (dir == 0)
         return;

      // Add strength from ATR
      double avgBody = (body0 + body1) / 2.0;
      double atrPrice = _atrPoints * _Point;
      if (atrPrice > 0 && avgBody >= atrPrice * CFG.pattern.railroadAvgBodyMin)
         score += CFG.pattern.bonusStrongATR;

      // Add strength from wick rejection
      if (dir == 1 && LowerWick(rates, shift + 1) > body1 * CFG.pattern.railroadWickMult)
         score += CFG.pattern.bonusStrongWick;
      if (dir == -1 && UpperWick(rates, shift + 1) > body1 * CFG.pattern.railroadWickMult)
         score += CFG.pattern.bonusStrongWick;

      vote.valid = true;
      vote.type = PATTERN_RAILROAD_TRACKS;
      vote.dir = dir;
      vote.extreme = extreme;
      vote.score = score;
      vote.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
      vote.label = (dir == 1) ? "Railroad Bull" : "Railroad Bear";
   }

   void EvaluateDarkCloudPiercing(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
   {
      if (shift + 1 >= ArraySize(rates))
         return;

      double o0 = CandleOpen(rates, shift), c0 = CandleClose(rates, shift);
      double o1 = CandleOpen(rates, shift + 1), c1 = CandleClose(rates, shift + 1);
      double h1 = CandleHigh(rates, shift + 1), l1 = CandleLow(rates, shift + 1);

      double body1 = CandleBody(rates, shift + 1);
      double mid1 = (o1 + c1) / 2.0;

      int dir = 0;
      double score = CFG.pattern.baseScore;

      // Piercing Line (Bullish Reversal)
      if (IsBearish(rates, shift + 1) && IsBullish(rates, shift) && o0 < l1 && c0 > mid1 && c0 < o1)
      {
         dir = 1;
         vote.extreme = CandleLow(rates, shift);
         vote.label = "Piercing Line";
      }
      // Dark Cloud Cover (Bearish Reversal)
      else if (IsBullish(rates, shift + 1) && IsBearish(rates, shift) && o0 > h1 && c0 < mid1 && c0 > o1)
      {
         dir = -1;
         vote.extreme = CandleHigh(rates, shift);
         vote.label = "Dark Cloud Cover";
      }

      if (dir != 0)
      {
         vote.valid = true;
         vote.type = PATTERN_DARK_CLOUD_PIERCING;
         vote.dir = dir;
         vote.score = score;
         vote.slMult = CFG.pattern.defaultSLMult; // Default SL multiplier
         AddStrengthFromFollowThrough(rates, shift, dir, vote.score);
      }
   }

   void EvaluateMarubozu(const MqlRates &rates[], const int shift, const double _atrPoints, PatternVote &vote)
   {
      double range = CandleRange(rates, shift);
      double body = CandleBody(rates, shift);
      if (range <= 0)
         return;

      double bodyRatio = body / range;
      if (bodyRatio < CFG.pattern.marubozuMinBodyPct)
         return;

      double atrFactor = NormalizeATRFactor(range, _atrPoints);
      if (atrFactor < CFG.pattern.momentumThresholdATR * CFG.pattern.marubozuMinATRMult)
         return;

      int dir = IsBullish(rates, shift) ? 1 : -1;
      vote.valid = true;
      vote.type = PATTERN_MARUBOZU;
      vote.dir = dir;
      vote.extreme = (dir == 1) ? CandleLow(rates, shift) : CandleHigh(rates, shift);
      vote.slMult = CFG.pattern.defaultSLMult;                     // Default SL multiplier
      vote.score = CFG.pattern.baseScore + CFG.pattern.bonusSmall; // Marubozu has a slightly higher base score
      vote.label = (dir == 1) ? "Marubozu Bull" : "Marubozu Bear";

      if (atrFactor > CFG.pattern.marubozuStrongATRMin)
         vote.score += CFG.pattern.bonusStrongATR;
   }
};

#endif