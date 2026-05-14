//+------------------------------------------------------------------+
//|                                                   DataUtils.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Utility Functions for Data Processing                 |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __DATA_UTILS_MQH__
#define __DATA_UTILS_MQH__

//+------------------------------------------------------------------+
//| Static utility class for data parsing and formatting             |
//+------------------------------------------------------------------+
class DataUtils
{
private:
   DataUtils() {} // Prevent instantiation

public:
   // Parse HH:MM format to minutes from midnight
   static int ParseHM(const string hhmm)
   {
      string parts[];
      if (StringSplit(hhmm, ':', parts) != 2)
         return -1;
      
      int h = (int)StringToInteger(parts[0]);
      int m = (int)StringToInteger(parts[1]);
      
      return (h >= 0 && h <= 23 && m >= 0 && m <= 59) ? (h * 60 + m) : -1;
   }

   // Build standardized trade comment
   static string BuildComment(const string type, const int bias, const ENUM_ENTRY_MODE mode)
   {
      string b = (bias > 0) ? "+" : (bias < 0 ? "-" : "0");
      string t = (type == "BUY") ? "B" : (type == "SELL" ? "S" : type);
      string m = (mode == MODE_SAFE) ? "S" : "A";
      return "P_" + t + b + m;
   }

   // Strip HTML/XML tags from string
   static string StripTags(const string html)
   {
      string res = "";
      bool inside = false;
      int len = StringLen(html);
      
      for (int i = 0; i < len; i++)
      {
         ushort c = StringGetCharacter(html, i);
         if (c == '<')
            inside = true;
         else if (c == '>')
            inside = false;
         else if (!inside)
            StringAdd(res, ShortToString(c));
      }
      return res;
   }

   // Validate time string format
   static bool IsValidTimeFormat(const string timeStr, const string format = "HH:MM")
   {
      if (format == "HH:MM")
         return ParseHM(timeStr) >= 0;
      return false;
   }

   // Format number with fixed decimals
   static string FormatDouble(double value, int digits)
   {
      return DoubleToString(value, digits);
   }

   // Calculate percentage change
   static double CalcPercentChange(double oldValue, double newValue)
   {
      if (MathAbs(oldValue) < _Point) return 0.0;
      return ((newValue - oldValue) / oldValue) * 100.0;
   }
};

#endif
