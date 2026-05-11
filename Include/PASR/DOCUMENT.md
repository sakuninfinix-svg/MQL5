//+------------------------------------------------------------------+
//|              COMPREHENSIVE AUDIT & REPAIR REPORT                 |
//|                    PASR EA MODULE - FINAL                        |
//|                   Copyright 2026, Agsicentre                     |
//+------------------------------------------------------------------+

/*
┌─────────────────────────────────────────────────────────────────────┐
│                  PASR EA - FULL SYSTEM AUDIT COMPLETE               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

══════════════════════════════════════════════════════════════════════
SUMMARY
══════════════════════════════════════════════════════════════════════

The PASR (Price Action & Support Resistance) adalah sebuah ekosistem trading modular yang menggabungkan presisi Price Action klasik dengan kecerdasan buatan (Machine Learning) untuk menghadapi dinamika pasar modern. Dibangun di atas infrastruktur Event-Driven yang efisien, PASR menawarkan kecepatan eksekusi dan akurasi analisis setingkat institusi.

 Fitur Unggulan PASR:
🧠 Adaptive AI Filtering (Logistic Regression) Sistem kami dilengkapi dengan AIManager yang menggunakan algoritma Logistic Regression. EA tidak hanya mengikuti aturan statis, tetapi memberikan skor probabilitas pada setiap sinyal. Hebatnya lagi, AI ini memiliki fitur Online Learning—ia belajar dari setiap hasil trade (Profit/Loss) untuk mengadaptasi bobot strategi secara real-time.

🛡️ Smart Recovery & Fakeout Protection Bosan dengan Stop Loss yang sering terkena fakeout? RecoveryManager kami memiliki deteksi wick penetration 3 level. Jika harga menembus zona hanya untuk menipu (fakeout), sistem akan menyesuaikan SL secara dinamis. Jika SL benar-benar terkena, mode Recovery Re-entry akan aktif mencari peluang terbaik untuk memulihkan kerugian secara terukur.

📊 Modern Real-Time Dashboard Pantau kesehatan akun Anda melalui Interactive Dashboard dengan tema Modern Dark. Dashboard ini menyajikan statistik performa, Win Rate harian, status Market Gate, hingga hitung mundur berita ekonomi (News Alert) secara visual dan intuitif.

🌐 Multi-Layer Market Filters Keamanan adalah prioritas. PASR menggunakan filter berlapis:

News Filter Dual-Source: Integrasi kalender ekonomi otomatis untuk menghindari volatilitas tinggi.
Volatility Gate (ATR): Memastikan EA hanya trading saat volatilitas ideal.
MTF Confluence: Sinyal hanya dieksekusi jika selaras dengan tren di Higher Timeframe.
⚡ Event-Driven Infrastructure Berbeda dengan EA tradisional yang lambat, PASR Pro menggunakan EventBus Architecture. Setiap perubahan harga, pembentukan bar baru, atau perubahan margin diproses sebagai "Event" instan, memastikan tidak ada peluang yang terlewatkan akibat lag pemrosesan kode.

🎯 Strategi Trading:
Primary Logic: Support & Resistance Reversal/Breakout.
Patterns: Pinbar, Engulfing, Morning/Evening Star, Three Inside Up/Down, Railroad Tracks, dan Marubozu.
Risk Management: Auto-Lot berdasarkan % Risk, Daily Loss Limit, Trailing Stop berbasis ATR, dan Partial Close.

══════════════════════════════════════════════════════════════════════
DETAILED 
══════════════════════════════════════════════════════════════════════

1. FILE STRUCTURE
─────────────────
Total Files: 12 .mqh header files

Core Layer (No external dependencies):
  • 0.EventBus.mqh      (254 lines) - Event bus, Event base class
  • 2.Config.mqh        (754 lines) - Enums, structs, input parameters, RecoveryEngine
  
Event Layer:
  • 1.Events.mqh        (345 lines) - All event type definitions
  
Base Manager Layer:
  • IManager.mqh        (241 lines) - Base class for all managers
  
Data Layer:
  • 10.DataManager.mqh  (443 lines) - ATR, Fractals, Account state
  
Domain Managers:
  • 3.MarketManager.mqh   (569 lines) - Sessions, News, Market gate
  • 4.SRManager.mqh       (368 lines) - Support/Resistance detection
  • 5.SignalManager.mqh   (869 lines) - Signal generation & filtering
  • 6.ExecutionManager.mqh (525 lines) - Order execution, Trailing, Partial close
  • 8.RecoveryManager.mqh  (729 lines) - Position lifecycle, Fakeout detection
  • 9.PatternManager.mqh   (779 lines) - Pattern detection (stateless utility)
  • 11.DashboardManager.mqh (1012 lines) - UI Dashboard

2. DEPENDENCY GRAPH
────────────────────────────────

Dependency Flow (Unidirectional):
┌─────────────────────────────────────────────────────────────────┐
│ CORE LAYER                                                      │
│  0.EventBus ←→ 2.Config                                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ EVENT LAYER                                                     │
│  1.Events → 0.EventBus + 2.Config                               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ BASE MANAGER                                                    │
│  IManager → 2.Config + 0.EventBus + 1.Events                    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ DATA LAYER                                                      │
│  10.DataManager → IManager                                      │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ DOMAIN MANAGERS                                                 │
│  3.MarketManager    → IManager + 10.DataManager                 │
│  4.SRManager        → IManager + 10.DataManager                 │
│  6.ExecutionManager → IManager + 10.DataManager                 │
│  8.RecoveryManager  → IManager + 10.DataManager + 9.PatternMgr  │
│  11.DashboardMgr    → IManager + 10.DataManager + MQL5 GUI libs │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ SPECIALIZED MANAGERS                                            │
│  9.PatternManager   → 2.Config only (stateless)                 │
│  5.SignalManager    → IManager + 9.PatternManager               │
└─────────────────────────────────────────────────────────────────┘

4. CLASS/STRUCT DEFINITIONS
───────────────────────────

Classes Defined:
• Event (abstract base)
• EventRecorder
• EventBus
• IEventHandler (interface)
• PriceUpdateEvent, NewBarEvent, SessionChangeEvent, NewsAlertEvent
• ZoneUpdateEvent, SignalGeneratedEvent, RecoveryOpportunityEvent
• RecoverySignalEvent, ConfigReloadEvent, OrderExecutionEvent
• PositionUpdateEvent, PauseToggleEvent, HeartbeatEvent
• EmergencyStopEvent, MarketGateEvent
• IManager (abstract base)
• DataManager
• MarketManager
• SRManager
• SignalManager
• ExecutionManager
• RecoveryManager
• PatternManager
• DashboardManager
• DashboardUI
• RecoveryEngine (in Config.mqh - business logic in config file ⚠️)

Structs Defined:
• RecordedEvent (EventRecorder internal)
• HandlerRegistration (EventBus internal)
• SignalDecision
• OrderPlan
• PositionScanResult
• PerformanceStats
• StrategyConfig (CFG global instance)
• DataConfigCache (DataManager internal)
• CachedData (DataManager internal)
• MarketConfigCache (MarketManager internal)
• SRConfigCache (SRManager internal)
• SignalConfigCache (SignalManager internal)
• SignalCooldown, FailedZone (SignalManager internal)
• CachedMarketData (SignalManager internal)
• ExecConfigCache (ExecutionManager internal)
• RecoveryConfigCache (RecoveryManager internal)
• PatternVote (PatternManager internal)
• FakeoutResult, FakeoutContext (PatternManager)
• DataCacheUI (DashboardManager)

══════════════════════════════════════════════════════════════════════
FLOW CHART (MERMAID EDITOR)
══════════════════════════════════════════════════════════════════════

1. Modul Inti: Alur Inisialisasi (EA Main Entry)
graph TD
    A[Start: OnInit] --> B[Init EventBus Singleton]
    B --> C[Set Default Config & Cache]
    C --> D[Init DataManager]
    D --> E[Set Global Data Cache Reference]
    E --> F[Init All Managers: Market, SR, Signal, AI, Exec, Recovery]
    F --> G[Init Dashboard UI & Factory]
    G --> H[Sync Existing Positions to RecoveryEngines]
    H --> I[Start Timer & Dispatch Heartbeat]
    I --> J[System Ready: Waiting for Ticks]

2. Modul Data & Market Filter (Data & Market Manager)
graph TD
    Tick[OnTick Received] --> DM[DataManager: Update ATR & Indicator Cache]
    DM --> Bus1{Dispatch PriceUpdateEvent}
    Bus1 --> MM[MarketManager: Check Session & Spread]
    MM --> News[Check News Calendar & Web Fetch]
    News --> Gate{PassesGate?}
    Gate -- No --> Block[Dispatch MarketGateEvent: gateOpen=false]
    Gate -- Yes --> Allow[Dispatch MarketGateEvent: gateOpen=true]

3. Modul Strategi: Deteksi Sinyal (SR & Signal Manager)
graph TD
    NB[Event: NewBarEvent] --> SR[SRManager: Update Main & HTF Zones]
    SR --> Bus2{Dispatch ZoneUpdateEvent}
    Bus2 --> SM[SignalManager: Receive Zones & ATR]
    SM --> PM[PatternManager: Scan PA Patterns]
    PM --> Filter[Apply Context & MTF Filters]
    Filter -- Valid --> Sig[Dispatch SignalGeneratedEvent]
    Filter -- Invalid --> SM

4. Modul AI: Filter Kualitas (AIManager)
graph TD
    SGE[Event: SignalGeneratedEvent] --> AI[AIManager: Evaluate Feature Weights]
    AI --> Calc[Calculate Logistic Regression Score]
    Calc --> Thres{Score > Confidence Threshold?}
    Thres -- No --> Reject[Modify Signal: valid=false, reason=AI_REJECT]
    Thres -- Yes --> Accept[Modify Signal: reason=AI_ACCEPT]
    Accept --> Bus3{Re-Dispatch Updated Event}

5. Modul Eksekusi (ExecutionManager)
graph TD
    ValidSig[Event: Validated Signal] --> Risk[DataManager: Calculate Lot by Risk %]
    Risk --> Plan[Build OrderPlan: Entry, SL, TP with Buffers]
    Plan --> Check[Validate Trade Levels & Margin]
    Check -- Pass --> Async[OrderSendAsync to Broker]
    Async --> GV[Save Pending State to GlobalVariable]
    GV --> Done[Wait for Trade Transaction Confirmation]

6. Modul Pengelolaan: Lifecycle & Recovery (RecoveryManager)
graph TD
    Update[Event: PriceUpdate / Heartbeat] --> Trail[Process Trailing Stop & Partial Close]
    Trail --> SLCheck{Is StopLoss Hit?}
    SLCheck -- No --> Keep[Update Engine State]
    SLCheck -- Yes --> Fakeout[PatternManager: Detect Fakeout/Reversal]
    Fakeout -- Fakeout Detected --> Adjust[Modify SL: Give more room]
    Fakeout -- Real SL --> Recov[Change State to TRADE_STATE_RECOVERY]
    Recov --> Opp[Dispatch RecoveryOpportunityEvent]
    Opp --> SM2[SignalManager: Look for Re-entry Pattern]
