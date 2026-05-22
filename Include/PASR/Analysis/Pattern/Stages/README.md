//+------------------------------------------------------------------+
//|                                 Pattern Pipeline Implementation  |
//|                                  Copyright 2024, PASR Team       |
//|                                     https://pasr-trading.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Team"
#property link      "https://pasr-trading.com"
#property version   "1.00"
//+------------------------------------------------------------------+
/**
 * @file Stages/README.md
 * @brief Dokumentasi untuk Pipeline Stages
 * 
 * ## Struktur Pipeline Stages
 * 
 * Pipeline pattern detection terdiri dari 4 stages utama yang dijalankan secara berurutan:
 * 
 * ### 1. PreprocessingStage
 * - **File**: `PreprocessingStage.mqh`
 * - **Tanggung Jawab**: Validasi data, normalisasi, filter noise
 * - **Output**: Context dengan normalized metrics (ATR, ratios)
 * - **Flag**: CONTEXT_FLAG_PREPROCESSED
 * 
 * ### 2. DetectionStage
 * - **File**: `DetectionStage.mqh`
 * - **Tanggung Jawab**: Menjalankan strategies, deteksi pattern
 * - **Output**: Detected pattern type, direction, confidence
 * - **Flag**: CONTEXT_FLAG_DETECTED
 * 
 * ### 3. ValidationStage
 * - **File**: `ValidationStage.mqh`
 * - **Tanggung Jawab**: Validasi regime, S/R, price location
 * - **Output**: Validation score, regime alignment
 * - **Flag**: CONTEXT_FLAG_VALIDATED
 * 
 * ### 4. ScoringStage
 * - **File**: `ScoringStage.mqh`
 * - **Tanggung Jawab**: Final scoring, grading, action determination
 * - **Output**: Final score, grade (A+-F), action signal
 * - **Flag**: CONTEXT_FLAG_SCORED
 * 
 * ## Flow Diagram
 * 
 * ```
 * [Input Candle] 
 *      ↓
 * [PreprocessingStage] → Validate → Normalize → Filter
 *      ↓
 * [DetectionStage] → Run Strategies → Aggregate → Set Pattern
 *      ↓
 * [ValidationStage] → Regime Check → S/R Check → Location Check
 *      ↓
 * [ScoringStage] → Weighted Score → Grading → Action
 *      ↓
 * [Output Signal]
 * ```
 * 
 * ## Stage Result Codes
 * 
 * - `STAGE_RESULT_SUCCESS`: Stage completed successfully
 * - `STAGE_RESULT_SKIP`: Pattern tidak valid/tidak terdeteksi (bukan error)
 * - `STAGE_RESULT_ERROR`: Error fatal, pipeline harus stop
 * 
 * ## Best Practices
 * 
 * 1. **Isolation**: Setiap stage tidak boleh bergantung pada state internal stage lain
 * 2. **Context-Only Communication**: Semua data sharing melalui CPatternContext
 * 3. **Fail-Fast**: Return SKIP/ERROR secepat mungkin jika kondisi tidak terpenuhi
 * 4. **No Side Effects**: Stage tidak boleh mengubah global state
 * 5. **Idempotent**: Stage harus bisa dipanggil berkali-kali dengan hasil sama
 * 
 * ## Adding New Stages
 * 
 * Untuk menambah stage baru:
 * 
 * 1. Buat class yang inherit dari `IPatternStage`
 * 2. Implementasi semua method interface:
 *    - `Init()`: Inisialisasi
 *    - `Name()`: Return nama stage
 *    - `Execute(ctx)`: Logic utama
 *    - `Reset()`: Reset state
 * 3. Daftarkan ke pipeline di `PatternPipeline.mqh`
 * 4. Update flag di `PatternContext.mqh` jika perlu
 * 
 * ## Performance Considerations
 * 
 * - Preprocessing: O(1) per candle
 * - Detection: O(n) dimana n = jumlah strategies
 * - Validation: O(1) dengan cached regime data
 * - Scoring: O(1)
 * 
 * Total complexity: O(n) per candle
 * 
 * @see IPatternStage.mqh untuk interface definition
 * @see PatternContext.mqh untuk context object
 * @see PatternPipeline.mqh untuk orchestrator
 */
//+------------------------------------------------------------------+
