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
// Enum Jenis Pola Candlestick Utama (Unified untuk PatternManager)
// Compatible dengan SPatternVote di PatternManager.mqh
enum ENUM_PATTERN_TYPE
  {
   PATTERN_NONE                = 0,  // Tidak ada pola
   PATTERN_PINBAR              = 1,  // Pinbar (reversal - direction determined by context)
   PATTERN_ENGULFING           = 2,  // Engulfing (reversal)
   PATTERN_INSIDE_BAR          = 3,  // Inside Bar (continuation/breakout)
   PATTERN_INSIDE_BAR_BREAKOUT = 4,  // Inside Bar Breakout
   PATTERN_FAKEY               = 5,  // Fakey (false breakout trap)
   PATTERN_BOTTOM              = 6,  // Tweezer Bottom/Top
   PATTERN_DOJI                = 7,  // Doji (indecision)
   PATTERN_HARAMI              = 8,  // Harami (reversal)
   PATTERN_OUTSIDE_BAR         = 9,  // Outside Bar (volatility expansion)
   PATTERN_MORNING_STAR        = 10, // Morning Star (3-candle reversal)
   PATTERN_EVENING_STAR        = 11  // Evening Star (3-candle reversal)
  };

// Alias untuk backward compatibility dengan EPatternType
typedef ENUM_PATTERN_TYPE EPatternType;

// Alias konstanta untuk backward compatibility
#define PATTERN_PINBAR_BULL   PATTERN_PINBAR
#define PATTERN_PINBAR_BEAR   PATTERN_PINBAR
#define PATTERN_ENGULF_BULL   PATTERN_ENGULFING
#define PATTERN_ENGULF_BEAR   PATTERN_ENGULFING
#define PATTERN_HARAMI_BULL   PATTERN_HARAMI
#define PATTERN_HARAMI_BEAR   PATTERN_HARAMI
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
         case PATTERN_PINBAR:              return "Pinbar";
         case PATTERN_ENGULFING:           return "Engulfing";
         case PATTERN_INSIDE_BAR:          return "Inside Bar";
         case PATTERN_INSIDE_BAR_BREAKOUT: return "Inside Bar Breakout";
         case PATTERN_FAKEY:               return "Fakey";
         case PATTERN_BOTTOM:              return "Tweezer";
         case PATTERN_DOJI:                return "Doji";
         case PATTERN_HARAMI:              return "Harami";
         case PATTERN_OUTSIDE_BAR:         return "Outside Bar";
         case PATTERN_MORNING_STAR:        return "Morning Star";
         case PATTERN_EVENING_STAR:        return "Evening Star";
         default:                          return "None";
        }
     }
     
   // Note: Direction sekarang ditentukan oleh context (dir parameter di PatternManager)
   // Method ini tetap ada untuk backward compatibility
   string Direction() const
     {
      // Untuk pola reversal tradisional
      if(type == PATTERN_MORNING_STAR) return "BULLISH";
      if(type == PATTERN_EVENING_STAR) return "BEARISH";
      // Pola lain memerlukan konteks direction dari hasil deteksi
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
