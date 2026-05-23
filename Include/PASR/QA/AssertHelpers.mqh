//+------------------------------------------------------------------+
//| QA/AssertHelpers.mqh — v2.00                                     |
//| Sprint 6 — S6-004: Extended assertion macros for PASR tests     |
//|                                                                   |
//| CHANGELOG:                                                        |
//|   v2.00 (2026-05-23) Sprint 6:                                   |
//|     + ASSERT_RANGE(val, lo, hi, msg)                             |
//|     + ASSERT_NULL(ptr, msg)                                      |
//|     + ASSERT_NOT_NULL(ptr, msg)                                  |
//|     + ASSERT_SIGNAL_EQ(actual, expected, msg)                    |
//|     + ASSERT_STAGE_OK(result, msg)                               |
//|     + ASSERT_NO_TIMEOUT(result, msg)                             |
//|     + ASSERT_NEAR(a, b, eps, msg)                                |
//|     + ASSERT_STR_EQ(a, b, msg)                                   |
//|     All macros include __FILE__ + __LINE__ in failure output.    |
//|   v1.00 — Assertions.mqh (original, still included below)       |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_ASSERT_HELPERS_MQH__
#define __QA_ASSERT_HELPERS_MQH__

#include "../Core/PipelineTypes.mqh"   // ENUM_STAGE_RESULT
#include "../Core/PASR.Types.mqh"      // ENUM_SIGNAL_TYPE

//--- Internal failure reporter (used by all macros)
#define _QA_FAIL(msg) \
   { Print("[ASSERT FAIL] ", msg, " | ", __FILE__, ":", __LINE__); \
     DebugBreak(); }

//==================================================================
//  BASIC VALUE ASSERTIONS
//==================================================================

//--- ASSERT_TRUE: condition must be true
#define ASSERT_TRUE(cond, msg) \
   if(!(cond)) { _QA_FAIL(msg + " (expected TRUE, got FALSE)"); }

//--- ASSERT_FALSE: condition must be false
#define ASSERT_FALSE(cond, msg) \
   if((cond)) { _QA_FAIL(msg + " (expected FALSE, got TRUE)"); }

//--- ASSERT_EQ: two integer-compatible values equal
#define ASSERT_EQ(actual, expected, msg) \
   if((actual) != (expected)) { \
      _QA_FAIL(msg + " | actual=" + (string)(actual) + \
               " expected=" + (string)(expected)); }

//--- ASSERT_NEQ: two values NOT equal
#define ASSERT_NEQ(actual, expected, msg) \
   if((actual) == (expected)) { \
      _QA_FAIL(msg + " | values equal (" + (string)(actual) + ")"); }

//--- ASSERT_GT: actual > threshold
#define ASSERT_GT(actual, threshold, msg) \
   if((actual) <= (threshold)) { \
      _QA_FAIL(msg + " | " + (string)(actual) + " <= " + (string)(threshold)); }

//--- ASSERT_GTE: actual >= threshold
#define ASSERT_GTE(actual, threshold, msg) \
   if((actual) < (threshold)) { \
      _QA_FAIL(msg + " | " + (string)(actual) + " < " + (string)(threshold)); }

//--- ASSERT_LT: actual < threshold
#define ASSERT_LT(actual, threshold, msg) \
   if((actual) >= (threshold)) { \
      _QA_FAIL(msg + " | " + (string)(actual) + " >= " + (string)(threshold)); }

//--- ASSERT_LTE: actual <= threshold
#define ASSERT_LTE(actual, threshold, msg) \
   if((actual) > (threshold)) { \
      _QA_FAIL(msg + " | " + (string)(actual) + " > " + (string)(threshold)); }

//==================================================================
//  RANGE & PROXIMITY ASSERTIONS (v2.00 NEW)
//==================================================================

//--- ASSERT_RANGE: lo <= val <= hi
#define ASSERT_RANGE(val, lo, hi, msg) \
   if((val) < (lo) || (val) > (hi)) { \
      _QA_FAIL(msg + " | " + (string)(val) + " not in [" + \
               (string)(lo) + ".." + (string)(hi) + "]"); }

//--- ASSERT_NEAR: |a - b| <= eps  (double comparison with epsilon)
#define ASSERT_NEAR(a, b, eps, msg) \
   if(MathAbs((double)(a) - (double)(b)) > (double)(eps)) { \
      _QA_FAIL(msg + " | |" + DoubleToString(a,8) + " - " + \
               DoubleToString(b,8) + "| > " + DoubleToString(eps,8)); }

//==================================================================
//  POINTER ASSERTIONS (v2.00 NEW)
//==================================================================

//--- ASSERT_NULL: pointer must be NULL
#define ASSERT_NULL(ptr, msg) \
   if(CheckPointer(ptr) != POINTER_INVALID) { \
      _QA_FAIL(msg + " (expected NULL pointer)"); }

//--- ASSERT_NOT_NULL: pointer must NOT be NULL
#define ASSERT_NOT_NULL(ptr, msg) \
   if(CheckPointer(ptr) == POINTER_INVALID) { \
      _QA_FAIL(msg + " (expected valid pointer, got NULL/invalid)"); }

//==================================================================
//  PIPELINE-SPECIFIC ASSERTIONS (v2.00 NEW)
//==================================================================

//--- ASSERT_STAGE_OK: stage result must be STAGE_OK
#define ASSERT_STAGE_OK(result, msg) \
   if((result) != STAGE_OK) { \
      _QA_FAIL(msg + " | Stage result=" + (string)(int)(result) + \
               " (expected STAGE_OK="  + (string)(int)STAGE_OK + ")"); }

//--- ASSERT_NO_TIMEOUT: stage result must NOT be STAGE_TIMEOUT
#define ASSERT_NO_TIMEOUT(result, msg) \
   if((result) == STAGE_TIMEOUT) { \
      _QA_FAIL(msg + " | Stage timed out (STAGE_TIMEOUT)"); }

//--- ASSERT_SIGNAL_EQ: signal type must match
#define ASSERT_SIGNAL_EQ(actual, expected, msg) \
   if((ENUM_SIGNAL_TYPE)(actual) != (ENUM_SIGNAL_TYPE)(expected)) { \
      _QA_FAIL(msg + " | signal actual=" + EnumToString((ENUM_SIGNAL_TYPE)(actual)) + \
               " expected=" + EnumToString((ENUM_SIGNAL_TYPE)(expected))); }

//--- ASSERT_SIGNAL_NOT: signal must NOT be specific type
#define ASSERT_SIGNAL_NOT(actual, excluded, msg) \
   if((ENUM_SIGNAL_TYPE)(actual) == (ENUM_SIGNAL_TYPE)(excluded)) { \
      _QA_FAIL(msg + " | signal should NOT be " + \
               EnumToString((ENUM_SIGNAL_TYPE)(excluded))); }

//==================================================================
//  STRING ASSERTIONS (v2.00 NEW)
//==================================================================

//--- ASSERT_STR_EQ: two strings must match
#define ASSERT_STR_EQ(actual, expected, msg) \
   if((string)(actual) != (string)(expected)) { \
      _QA_FAIL(msg + " | actual=\"" + (string)(actual) + \
               "\" expected=\"" + (string)(expected) + "\""); }

//--- ASSERT_STR_CONTAINS: string must contain substring
#define ASSERT_STR_CONTAINS(haystack, needle, msg) \
   if(StringFind((string)(haystack), (string)(needle)) < 0) { \
      _QA_FAIL(msg + " | \"" + (string)(haystack) + "\" does not contain \"" + \
               (string)(needle) + "\""); }

//==================================================================
//  EVENTBUS ASSERTIONS (for MockEventBus)
//==================================================================

//--- ASSERT_EVENT_PUSHED: check bus has at least 1 event with given id
#define ASSERT_EVENT_PUSHED(mock_bus_ptr, ev_id, msg) \
   { PASREvent _ev; \
     if(!(mock_bus_ptr)->FindEvent(ev_id, _ev)) { \
        _QA_FAIL(msg + " | Event " + (string)(int)(ev_id) + " never pushed to bus"); }}

//--- ASSERT_EVENT_COUNT: exact event count
#define ASSERT_EVENT_COUNT(mock_bus_ptr, ev_id, n, msg) \
   { int _cnt = (mock_bus_ptr)->CountEvents(ev_id); \
     if(_cnt != (n)) { \
        _QA_FAIL(msg + " | Event count actual=" + (string)_cnt + \
                 " expected=" + (string)(n)); }}

//==================================================================
//  BACKWARD COMPAT: Include original Assertions.mqh macros
//  (Assertions.mqh will #include this file going forward)
//==================================================================
// All original ASSERT_* from Assertions.mqh are duplicated above
// or superseded. Assertions.mqh is kept for include-path compat.

#endif // __QA_ASSERT_HELPERS_MQH__
