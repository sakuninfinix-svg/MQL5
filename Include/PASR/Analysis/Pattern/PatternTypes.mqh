//+------------------------------------------------------------------+
//|                                              Include/PASR/Analysis/Pattern/PatternTypes.mqh |
//|                                  Copyright 2024, PASR Quant Team |
//|                                             https://pasr.quant.id |
//+------------------------------------------------------------------+
#property copyright "2024, PASR Quant Team"
#property link      "https://pasr.quant.id"
#property version   "2.01"
#property description "Definisi tipe data, enum, dan struktur untuk sistem Pattern Recognition PASR v2.01"
//+------------------------------------------------------------------+
#ifndef PATTERN_TYPES_MQH
#define PATTERN_TYPES_MQH
//+------------------------------------------------------------------+
#include "../../Data/RegimeTypes.mqh" // Untuk EMarketRegime
//+------------------------------------------------------------------+
// Enum Jenis Pola Candlestick Utama
enum EPatternType
  {
   PATTERN_NONE          = 0,  // Tidak ada pola
   PATTERN_PINBAR_BULL   = 1,  // Pinbar Bullish (Hammer)
   PATTERN_PINBAR_BEAR   = 2,  // Pinbar Bearish (Shooting Star)
   PATTERN_ENGULF_BULL   = 3,  // Bullish Engulfing
   PATTERN_ENGULF_BEAR   = 4,  // Bearish Engulfing
   PATTERN_INSIDE_BAR    = 5,  // Inside Bar
   PATTERN_OUTSIDE_BAR   = 6,  // Outside Bar
   PATTERN_DOJI          = 7,  // Doji
   PATTERN_HARAMI_BULL   = 8,  // Bullish Harami
   PATTERN_HARAMI_BEAR   = 9,  // Bearish Harami
   PATTERN_MORNING_STAR  = 10, // Morning Star (3 candle)
   PATTERN_EVENING_STAR  = 11  // Evening Star (3 candle)
  };
//+------------------------------------------------------------------+
// Struktur Data Sinyal Pola
struct SPatternSignal
  {
   EPatternType     type;           // Jenis pola
   int              barIndex;       // Index bar terbentuknya pola
   datetime         time;           // Waktu terbentuk
   double           open;           // Harga Open
   double           high;           // Harga High
   double           low;            // Harga Low
   double           close;          // Harga Close
   double           bodySize;       // Ukuran body candle
   double           upperWick;      // Panjang sumbu atas
   double           lowerWick;      // Panjang sumbu bawah
   double           totalRange;     // Range total (High-Low)
   double           strength;       // Skor kekuatan pola (0.0 - 1.0)
   double           confidence;     // Skor keyakinan berdasarkan Regime & Konteks
   EMarketRegime    detectedRegime; // Kondisi pasar saat deteksi
   
   // Method Helper
   bool IsValid() const { return type != PATTERN_NONE && strength > 0.0; }
   
   string TypeName() const
     {
      switch(type)
        {
         case PATTERN_PINBAR_BULL:  return "Pinbar Bull";
         case PATTERN_PINBAR_BEAR:  return "Pinbar Bear";
         case PATTERN_ENGULF_BULL:  return "Engulf Bull";
         case PATTERN_ENGULF_BEAR:  return "Engulf Bear";
         case PATTERN_INSIDE_BAR:   return "Inside Bar";
         case PATTERN_OUTSIDE_BAR:  return "Outside Bar";
         case PATTERN_DOJI:         return "Doji";
         case PATTERN_HARAMI_BULL:  return "Harami Bull";
         case PATTERN_HARAMI_BEAR:  return "Harami Bear";
         case PATTERN_MORNING_STAR: return "Morning Star";
         case PATTERN_EVENING_STAR: return "Evening Star";
         default:                   return "None";
        }
     }
     
   string Direction() const
     {
      if(type == PATTERN_PINBAR_BULL || type == PATTERN_ENGULF_BULL || 
         type == PATTERN_HARAMI_BULL || type == PATTERN_MORNING_STAR) return "BULLISH";
      if(type == PATTERN_PINBAR_BEAR || type == PATTERN_ENGULF_BEAR || 
         type == PATTERN_HARAMI_BEAR || type == PATTERN_EVENING_STAR) return "BEARISH";
      return "NEUTRAL";
     }
  };
//+------------------------------------------------------------------+
// Kelas Array untuk Menyimpan Sinyal Pola
class CPatternSignalArray : public CArrayObj
  {
public:
   CPatternSignalArray() { }
   
   // Tambahkan sinyal baru
   bool Add(const SPatternSignal &signal)
     {
      SPatternSignal *ptr = new SPatternSignal(signal);
      if(ptr == NULL) return false;
      return CArrayObj::Add(ptr);
     }
     
   // Ambil sinyal pada index tertentu
   SPatternSignal *At(int index) const
     {
      return (SPatternSignal*)CArrayObj::At(index);
     }
     
   // Filter sinyal berdasarkan jenis pola
   CPatternSignalArray *FilterByType(EPatternType type) const
     {
      CPatternSignalArray *result = new CPatternSignalArray();
      if(result == NULL) return NULL;
      
      for(int i = 0; i < Total(); i++)
        {
         SPatternSignal *sig = At(i);
         if(sig != NULL && sig.type == type)
           result.Add(*sig);
        }
      return result;
     }
     
   // Filter sinyal berdasarkan kekuatan minimum
   CPatternSignalArray *FilterByStrength(double minStrength) const
     {
      CPatternSignalArray *result = new CPatternSignalArray();
      if(result == NULL) return NULL;
      
      for(int i = 0; i < Total(); i++)
        {
         SPatternSignal *sig = At(i);
         if(sig != NULL && sig.strength >= minStrength)
           result.Add(*sig);
        }
      return result;
     }
  };
//+------------------------------------------------------------------+
#endif // PATTERN_TYPES_MQH
//+------------------------------------------------------------------+
