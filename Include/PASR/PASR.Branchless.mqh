//+------------------------------------------------------------------+
//|                                                  PASR.Branchless.mqh |
//|                                   Branchless Programming Utilities |
//|                              Copyright © 2024 PASR Framework |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2024 PASR Framework"
#property link      "https://pasr.framework"
#property version   "1.00"
#property description "OPT-020: Branchless programming for CPU pipeline optimization"

#include "PASR.Optimizations.mqh"

//+------------------------------------------------------------------+
//| Branchless Min/Max/Abs Operations                                |
//+------------------------------------------------------------------+

// Branchless absolute value (faster than MathAbs for integers)
CRITICAL_FUNCTION int FastAbs(int x)
{
   int mask = x >> 31;
   return (x + mask) ^ mask;
}

CRITICAL_FUNCTION long FastAbs(long x)
{
   long mask = x >> 63;
   return (x + mask) ^ mask;
}

// Branchless min for integers
CRITICAL_FUNCTION int FastMin(int a, int b)
{
   int diff = a - b;
   int mask = diff >> 31;
   return b + (diff & mask);
}

CRITICAL_FUNCTION long FastMin(long a, long b)
{
   long diff = a - b;
   long mask = diff >> 63;
   return b + (diff & mask);
}

CRITICAL_FUNCTION double FastMin(double a, double b)
{
   // For doubles, use bit manipulation via long
   long bitsA = DoubleToLongBits(a);
   long bitsB = DoubleToLongBits(b);
   
   // This is approximate - for exact comparison use conditional
   return (a < b) ? a : b;
}

// Branchless max for integers
CRITICAL_FUNCTION int FastMax(int a, int b)
{
   int diff = a - b;
   int mask = diff >> 31;
   return a - (diff & mask);
}

CRITICAL_FUNCTION long FastMax(long a, long b)
{
   long diff = a - b;
   long mask = diff >> 63;
   return a - (diff & mask);
}

CRITICAL_FUNCTION double FastMax(double a, double b)
{
   return (a > b) ? a : b;
}

// Branchless clamp for integers
CRITICAL_FUNCTION int FastClamp(int x, int minVal, int maxVal)
{
   int diff1 = x - minVal;
   int mask1 = diff1 >> 31;
   x = minVal + (diff1 & ~mask1);
   
   int diff2 = x - maxVal;
   int mask2 = diff2 >> 31;
   return maxVal - (diff2 & ~mask2);
}

CRITICAL_FUNCTION long FastClamp(long x, long minVal, long maxVal)
{
   long diff1 = x - minVal;
   long mask1 = diff1 >> 63;
   x = minVal + (diff1 & ~mask1);
   
   long diff2 = x - maxVal;
   long mask2 = diff2 >> 63;
   return maxVal - (diff2 & ~mask2);
}

// Branchless sign function
CRITICAL_FUNCTION int FastSign(int x)
{
   return (x > 0) - (x < 0);
}

CRITICAL_FUNCTION int FastSign(double x)
{
   return (x > 0.0) - (x < 0.0);
}

//+------------------------------------------------------------------+
//| Branchless Conditional Selection                                 |
//+------------------------------------------------------------------+

// Branchless select: returns a if condition is true, b otherwise
CRITICAL_FUNCTION int Select(int condition, int a, int b)
{
   int mask = -condition; // All 1s if condition != 0, all 0s otherwise
   return (a & mask) | (b & ~mask);
}

CRITICAL_FUNCTION long Select(long condition, long a, long b)
{
   long mask = -condition;
   return (a & mask) | (b & ~mask);
}

CRITICAL_FUNCTION double Select(long condition, double a, double b)
{
   // Convert to long bits for manipulation
   long bitsA = DoubleToLongBits(a);
   long bitsB = DoubleToLongBits(b);
   long mask = -condition;
   long resultBits = (bitsA & mask) | (bitsB & ~mask);
   return LongBitsToDouble(resultBits);
}

// Branchless if-then-else for integers
CRITICAL_FUNCTION int IfThenElse(int condition, int thenVal, int elseVal)
{
   return Select(condition, thenVal, elseVal);
}

//+------------------------------------------------------------------+
//| Branchless Comparison Operations                                 |
//+------------------------------------------------------------------+

// Branchless equality check (returns 1 if equal, 0 otherwise)
CRITICAL_FUNCTION int IsEqual(int a, int b)
{
   int diff = a - b;
   return (diff == 0) ? 1 : 0;
}

// Branchless greater than (returns 1 if a > b, 0 otherwise)
CRITICAL_FUNCTION int IsGreater(int a, int b)
{
   int diff = a - b;
   int sign = diff >> 31;
   return (sign == 0 && diff != 0) ? 1 : 0;
}

// Branchless less than (returns 1 if a < b, 0 otherwise)
CRITICAL_FUNCTION int IsLess(int a, int b)
{
   int diff = a - b;
   return (diff >> 31) & 1;
}

//+------------------------------------------------------------------+
//| Branchless Array Operations                                      |
//+------------------------------------------------------------------+

// Branchless array sum (avoiding bounds check branches)
CRITICAL_FUNCTION double FastArraySum(const double& arr[], int start, int count)
{
   double sum = 0.0;
   int end = start + count;
   int size = ArraySize(arr);
   
   // Use branchless bounds clamping
   start = FastClamp(start, 0, size);
   end = FastClamp(end, 0, size);
   
   for(int i = start; i < end; i++)
      sum += arr[i];
   
   return sum;
}

// Branchless array find (returns index or -1)
CRITICAL_FUNCTION int FastArrayFind(const double& arr[], double value, int start, int count)
{
   int result = -1;
   int end = start + count;
   int size = ArraySize(arr);
   
   end = FastClamp(end, 0, size);
   
   for(int i = start; i < end; i++)
   {
      // Branchless update: only updates if match found and result is still -1
      int match = (arr[i] == value) ? 1 : 0;
      int shouldUpdate = (result == -1) ? 1 : 0;
      result = Select(match * shouldUpdate, i, result);
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Branchless Mathematical Functions                                |
//+------------------------------------------------------------------+

// Branchless integer power of 2 check
CRITICAL_FUNCTION bool IsPowerOfTwo(int x)
{
   return (x > 0) && ((x & (x - 1)) == 0);
}

// Branchless round to nearest power of 2 (for capacity sizing)
CRITICAL_FUNCTION int RoundUpToPowerOfTwo(int x)
{
   x = x - 1;
   x = x | (x >> 1);
   x = x | (x >> 2);
   x = x | (x >> 4);
   x = x | (x >> 8);
   x = x | (x >> 16);
   return x + 1;
}

// Branchless alignment to cache line (64 bytes)
CRITICAL_FUNCTION int AlignToCacheLine(int size)
{
   const int CACHE_LINE_SIZE = 64;
   return (size + CACHE_LINE_SIZE - 1) & ~(CACHE_LINE_SIZE - 1);
}

//+------------------------------------------------------------------+
//| Branchless Price Calculations                                    |
//+------------------------------------------------------------------+

// Branchless pip value calculation
CRITICAL_FUNCTION double FastPipValue(double price, int digits)
{
   // Determine pip size based on digits (branchless)
   double pipSize = Select(digits == 3 || digits == 5, 0.001, 0.01);
   pipSize = Select(digits == 2 || digits == 4, 0.01, pipSize);
   
   return MathFloor(price / pipSize) * pipSize;
}

// Branchless spread check (returns 1 if spread acceptable, 0 otherwise)
CRITICAL_FUNCTION int IsSpreadAcceptable(double bid, double ask, double maxSpread)
{
   double spread = ask - bid;
   return (spread <= maxSpread) ? 1 : 0;
}

// Branchless price normalization
CRITICAL_FUNCTION double FastNormalizePrice(double price, int digits)
{
   double multiplier = MathPow(10, digits);
   return MathRound(price * multiplier) / multiplier;
}

//+------------------------------------------------------------------+
//| Branchless Time Operations                                       |
//+------------------------------------------------------------------+

// Branchless time difference in milliseconds
CRITICAL_FUNCTION long FastTimeDiff(ulong time1, ulong time2)
{
   long diff = (long)(time1 - time2);
   long mask = diff >> 63;
   return (diff + mask) ^ mask; // Absolute value
}

// Branchless timeout check
CRITICAL_FUNCTION int IsTimeout(ulong startTime, ulong currentTime, ulong timeoutMs)
{
   ulong elapsed = currentTime - startTime;
   return (elapsed >= timeoutMs) ? 1 : 0;
}

//+------------------------------------------------------------------+
//| Branchless Signal Processing                                     |
//+------------------------------------------------------------------+

// Branchless signal threshold check
CRITICAL_FUNCTION int CheckSignalThreshold(double strength, double buyThreshold, double sellThreshold)
{
   // Returns: 1 for buy, -1 for sell, 0 for no signal
   int isBuy = (strength >= buyThreshold) ? 1 : 0;
   int isSell = (strength <= sellThreshold) ? 1 : 0;
   
   return isBuy - isSell;
}

// Branchless position size calculation
CRITICAL_FUNCTION double FastPositionSize(double accountBalance, double riskPercent, 
                                          double stopLossPips, double pipValue)
{
   // Avoid division by zero with branchless check
   double denominator = stopLossPips * pipValue;
   int isValid = (denominator > 0.0) ? 1 : 0;
   denominator = Select(isValid, denominator, 1.0);
   
   double riskAmount = accountBalance * (riskPercent / 100.0);
   return riskAmount / denominator;
}

//+------------------------------------------------------------------+
//| CBranchlessUtils - Utility Class                                 |
//+------------------------------------------------------------------+
class CBranchlessUtils
{
public:
   // Initialize (no-op for branchless utils)
   static void Initialize() {}
   
   // Shutdown (no-op)
   static void Shutdown() {}
   
   // Get supported operations list
   static string GetSupportedOps()
   {
      return "FastAbs, FastMin, FastMax, FastClamp, FastSign, Select, " +
             "IsEqual, IsGreater, IsLess, FastArraySum, FastArrayFind, " +
             "IsPowerOfTwo, RoundUpToPowerOfTwo, AlignToCacheLine, " +
             "FastPipValue, IsSpreadAcceptable, FastNormalizePrice, " +
             "FastTimeDiff, IsTimeout, CheckSignalThreshold, FastPositionSize";
   }
   
   // Benchmark all operations
   static string Benchmark()
   {
      ulong startTime = GetTickCount64();
      
      // Run benchmarks
      volatile int result = 0;
      const int iterations = 1000000;
      
      for(int i = 0; i < iterations; i++)
      {
         result += FastMin(i, i + 1);
         result += FastMax(i, i - 1);
         result += FastClamp(i, 0, 1000);
         result += FastAbs(i % 2 == 0 ? i : -i);
      }
      
      ulong endTime = GetTickCount64();
      ulong elapsed = endTime - startTime;
      
      return StringFormat(
         "Branchless Benchmark: %d iterations completed in %lu µs (%.2f ops/µs)",
         iterations * 4, elapsed, (iterations * 4.0) / MathMax(elapsed, 1)
      );
   }
};

//+------------------------------------------------------------------+
//| Usage Example                                                    |
//+------------------------------------------------------------------+
/*
void OnTick()
{
   // Branchless min/max/clamp
   int minVal = FastMin(10, 20);           // Returns 10
   int maxVal = FastMax(10, 20);           // Returns 20
   int clamped = FastClamp(150, 0, 100);   // Returns 100
   
   // Branchless select
   int condition = (bid > ask) ? 1 : 0;
   double selected = Select(condition, bid, ask);
   
   // Branchless signal check
   int signal = CheckSignalThreshold(strength, 0.7, 0.3);
   
   // Branchless spread check
   int spreadOK = IsSpreadAcceptable(bid, ask, 0.0002);
   
   // Use results without branching
   if(signal != 0 && spreadOK)
   {
      // Execute trade...
   }
}

int OnInit()
{
   CBranchlessUtils::Initialize();
   Print(CBranchlessUtils::Benchmark());
   return INIT_SUCCEEDED;
}
*/
//+------------------------------------------------------------------+
