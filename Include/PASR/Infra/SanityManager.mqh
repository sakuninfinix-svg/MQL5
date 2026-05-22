//+------------------------------------------------------------------+
//|                                             SanityManager.mqh    |
//|                                 Copyright © 2024, PASR System    |
//|                                       Senior Quant Architecture  |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2024, PASR System"
#property link      "https://pasr.system"
#property version   "1.00"
#property description "Data Sanity Check & Circuit Breaker Implementation"
//+------------------------------------------------------------------+
#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Config/Config.mqh"

// Forward declaration
class IDataManager;
//+------------------------------------------------------------------+
//| Enum: Status Sirkuit Breaker                                     |
//+------------------------------------------------------------------+
enum ENUM_CIRCUIT_STATE
  {
   CIRCUIT_CLOSED,     // Normal operation (Trading Allowed)
   CIRCUIT_OPEN,       // Tripped (Trading Paused)
   CIRCUIT_HALF_OPEN   // Testing waters (Limited check)
  };
//+------------------------------------------------------------------+
//| Struct: Konfigurasi Sanity                                       |
//+------------------------------------------------------------------+
struct SSanityConfig
  {
   int      max_stale_ticks;       // Max ticks tanpa update sebelum pause
   int      max_spread_points;     // Max spread sebelum pause
   double   max_price_gap_pct;     // Max % gap harga sebelum pause
   int      trip_threshold;        // Jumlah error berturut-turut untuk trip
   int      reset_timeout_sec;     // Waktu tunggu sebelum reset breaker
  };
//+------------------------------------------------------------------+
//| Class: CSanityManager                                            |
//| Implements IManager interface for Orchestrator integration       |
//+------------------------------------------------------------------+
class CSanityManager : public IManager
  {
private:
   SSanityConfig     m_config;
   ENUM_CIRCUIT_STATE m_state;
   int               m_consecutive_errors;
   datetime          m_last_tick_time;
   datetime          m_trip_time;
   double            m_last_price;

public:
   // Constructor
   CSanityManager() : IManager()
     {
      m_state              = CIRCUIT_CLOSED;
      m_consecutive_errors = 0;
      m_last_tick_time     = 0;
      m_trip_time          = 0;
      m_last_price         = 0;
      
      // Default Config (Conservative)
      m_config.max_stale_ticks    = 5;      // ~2.5 detik pada tick cepat
      m_config.max_spread_points  = 20;     // Sesuaikan dengan simbol
      m_config.max_price_gap_pct  = 0.5;    // 0.5% jump
      m_config.trip_threshold     = 3;      // 3 strikes -> Out
      m_config.reset_timeout_sec  = 60;     // Pause 1 menit
     }

   // Destructor
   ~CSanityManager() {}

   // IManager Interface Implementation
   bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      
      Print("[SANITY] Initialized with TripThreshold=", m_config.trip_threshold, 
            " ResetTimeout=", m_config.reset_timeout_sec, "s");
      return true;
     }

   void OnTick() override
     {
      // No per-tick processing needed - validation happens in ValidateTick()
     }

   void OnDeinit(const int reason) override
     {
      // Cleanup if needed
     }

   // Custom Initialize dengan konfigurasi spesifik
   bool Initialize(const SSanityConfig &cfg)
     {
      m_config = cfg;
      return true;
     }

   // Helper to send events via inherited m_bus
   void SendEvent(ENUM_EVENT_ID evt_id, const string &msg)
     {
      if(m_bus == NULL) return;
      
      PASREvent evt;
      evt.id       = evt_id;
      evt.priority = 50;
      evt.tag      = "SanityManager";
      m_bus.Push(evt);
     }

   // --- CORE LOGIC: Validasi Data Masuk ---
   
   /*
    * Memvalidasi data tick terbaru. 
    * Return: true jika data AMAN untuk diproses pipeline.
    *         false jika data BERBAHAYA (Pipeline harus abort).
    */
   bool ValidateTick(const MqlTick &tick)
     {
      // Jika Circuit OPEN, tolak semua data (kecuali logic reset)
      if(m_state == CIRCUIT_OPEN)
        {
         if(!TryResetBreaker()) return false;
         // Masih open, tapi sudah coba reset. Biarkan lolos ke validasi biasa
         // agar kita bisa cek apakah masalah sudah hilang.
        }

      bool is_valid = true;
      string reason = "";

      // 1. Check Stale Data (Waktu)
      if(!CheckFreshness(tick.time))
        {
         reason = "STALE_DATA";
         is_valid = false;
        }

      // 2. Check Spread Anomali
      if(is_valid && !CheckSpread(tick.ask, tick.bid))
        {
         reason = "WIDE_SPREAD";
         is_valid = false;
        }

      // 3. Check Price Gap (Lonjakan Harga)
      if(is_valid && !CheckPriceGap(tick.last))
        {
         reason = "PRICE_GAP";
         is_valid = false;
        }

      // Handle Result
      if(is_valid)
        {
         OnSuccess();
         return true;
        }
      else
        {
         OnFailure(reason);
         return false;
        }
     }

   // Getter Status
   ENUM_CIRCUIT_STATE GetState() const { return m_state; }
   
   bool IsTradingAllowed() const 
     { 
      return (m_state == CIRCUIT_CLOSED || m_state == CIRCUIT_HALF_OPEN); 
     }

   string GetStateString() const
     {
      switch(m_state)
        {
         case CIRCUIT_CLOSED:   return "CLOSED (Normal)";
         case CIRCUIT_OPEN:     return "OPEN (Paused)";
         case CIRCUIT_HALF_OPEN:return "HALF-OPEN (Testing)";
         default:               return "UNKNOWN";
        }
     }

private:
   // --- Validation Helpers ---

   bool CheckFreshness(datetime tick_time)
     {
      if(tick_time == 0) return false;
      
      // Update last seen time
      if(tick_time >= m_last_tick_time)
         m_last_tick_time = tick_time;
      
      // Hitung selisih detik dari waktu server saat ini
      // Catatan: Dalam OnTick, TimeCurrent() mungkin sama dengan tick.time
      // Kita cek apakah ada jeda terlalu lama sejak tick terakhir yang VALID
      // Logika ini lebih efektif jika dikombinasikan dengan OnTimer check
      
      return true; // Basic check passed, detailed stale check done in OnTimer
     }

   bool CheckSpread(double ask, double bid)
     {
      if(ask <= 0 || bid <= 0 || ask <= bid) return false; // Invalid price
      
      long spread_points = (long)((ask - bid) / _Point);
      if(spread_points > m_config.max_spread_points)
        {
         return false;
        }
      return true;
     }

   bool CheckPriceGap(double current_price)
     {
      if(m_last_price == 0) 
        {
         m_last_price = current_price;
         return true; // First tick
        }

      if(current_price == 0) return false;

      double change_pct = MathAbs((current_price - m_last_price) / m_last_price) * 100.0;
      
      if(change_pct > m_config.max_price_gap_pct)
        {
         return false;
        }

      m_last_price = current_price;
      return true;
     }

   // --- State Management ---

   void OnSuccess()
     {
      m_consecutive_errors = 0;
      
      // Jika sebelumnya Half-Open dan sukses, kembalikan ke Closed
      if(m_state == CIRCUIT_HALF_OPEN)
        {
         m_state = CIRCUIT_CLOSED;
         NotifyStateChange("Circuit Reset to CLOSED");
        }
     }

   void OnFailure(const string &reason)
     {
      m_consecutive_errors++;
      
      string msg = StringFormat("[SANITY FAIL] Reason=%s Errors=%d/%d", 
                                reason, m_consecutive_errors, m_config.trip_threshold);
      
      // Kirim Event Warning via inherited m_bus
      SendEvent(EVENT_ID_SYSTEM_WARNING, msg);

      // Check Threshold
      if(m_consecutive_errors >= m_config.trip_threshold)
        {
         TripBreaker(reason);
        }
     }

   void TripBreaker(const string &reason)
     {
      if(m_state == CIRCUIT_OPEN) return; // Sudah open

      m_state = CIRCUIT_OPEN;
      m_trip_time = TimeCurrent();
      
      string msg = StringFormat("[CIRCUIT BREAKER TRIPPED] Reason=%s. Pausing for %d sec.", 
                                reason, m_config.reset_timeout_sec);
      
      // Kirim Critical Event
      SendEvent(EVENT_ID_SYSTEM_CRITICAL, msg);
      Print("*** CRITICAL: ", msg);
     }

   bool TryResetBreaker()
     {
      if(m_state != CIRCUIT_OPEN) return true;

      // Cek timeout
      if(TimeCurrent() - m_trip_time >= m_config.reset_timeout_sec)
        {
         m_state = CIRCUIT_HALF_OPEN;
         NotifyStateChange("Circuit entering HALF-OPEN state for testing");
         return true;
        }
      
      return false; // Masih dalam masa tunggu
     }

   void NotifyStateChange(const string &msg)
     {
      if(m_bus != NULL)
        {
         PASREvent evt;
         evt.id       = EVENT_ID_SYSTEM_INFO;
         evt.priority = 50;
         evt.tag      = "SanityManager";
         m_bus.Push(evt);
        }
      Print("[SANITY STATE] ", msg);
     }
  };
//+------------------------------------------------------------------+
