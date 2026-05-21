//+------------------------------------------------------------------+
//|                                           QA/TestRunner.mqh     |
//|                                     Copyright 2026, Agsicentre  |
//|  Lightweight test runner for PASR Framework.                    |
//|                                                                  |
//|  USAGE:                                                          |
//|    CTestRunner runner;                                           |
//|    runner.Run("EventBus basic dispatch", TestEventBusDispatch);  |
//|    runner.Run("Config validate",         TestConfigValidate);    |
//|    runner.PrintSummary();                                        |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_TEST_RUNNER_MQH__
#define __QA_TEST_RUNNER_MQH__

#include "Assertions.mqh"

typedef void (*TestFn)();

enum ENUM_TEST_STATUS
  {
   TEST_PASS,
   TEST_FAIL,
   TEST_SKIP,
   TEST_ERROR
  };

struct TestRecord
  {
   string           name;
   ENUM_TEST_STATUS status;
   int              assertPass;
   int              assertFail;
   ulong            durationUs;
   string           errorMsg;
  };

//+------------------------------------------------------------------+
//| CTestRunner                                                      |
//+------------------------------------------------------------------+
class CTestRunner
  {
private:
   TestRecord m_records[256];
   int        m_count;
   bool       m_stopOnFail;     // abort suite on first failure
   bool       m_verbose;        // print pass lines too
   int        m_totalPass;
   int        m_totalFail;
   int        m_totalSkip;

public:
   CTestRunner(bool stopOnFail = false, bool verbose = false)
      : m_count(0), m_stopOnFail(stopOnFail), m_verbose(verbose),
        m_totalPass(0), m_totalFail(0), m_totalSkip(0) {}

   //--- Run a test function and capture results
   bool Run(const string name, TestFn fn)
     {
      if(m_count >= 256) { Print("TestRunner: record limit reached"); return false; }
      if(m_stopOnFail && m_totalFail > 0) return false;

      QA::Reset();

      TestRecord rec;
      rec.name   = name;
      rec.status = TEST_PASS;
      ulong t0   = GetMicrosecondCount();

      // Execute — catch logic errors via return value convention (void fn)
      fn();

      rec.durationUs  = GetMicrosecondCount() - t0;
      rec.assertPass  = QA::PassCount();
      rec.assertFail  = QA::FailCount();

      if(rec.assertFail > 0)
        {
         rec.status = TEST_FAIL;
         m_totalFail++;
        }
      else
        {
         m_totalPass++;
        }

      m_records[m_count++] = rec;

      // Per-test line
      string icon = (rec.status == TEST_PASS) ? "✓" : "✗";
      if(rec.status == TEST_PASS && !m_verbose) { /* skip verbose line */ }
      else
        {
         Print(StringFormat("  %s %-48s  %d/%d assertions  [%.2f ms]",
                            icon, name,
                            rec.assertPass, rec.assertPass + rec.assertFail,
                            rec.durationUs / 1000.0));
        }

      return (rec.status == TEST_PASS);
     }

   //--- Skip a test (dependency not met, feature not implemented)
   void Skip(const string name, const string reason = "")
     {
      if(m_count >= 256) return;
      TestRecord rec;
      rec.name   = name;
      rec.status = TEST_SKIP;
      m_records[m_count++] = rec;
      m_totalSkip++;
      Print(StringFormat("  ⊘ SKIP  %-48s  %s", name, reason));
     }

   //--- Print summary table
   void PrintSummary() const
     {
      int total = m_totalPass + m_totalFail + m_totalSkip;
      Print("\n╔══════════════════════════════════════════════════╗");
      Print(StringFormat("║  PASR TEST SUITE RESULTS   %s",
            (m_totalFail == 0) ? "✅  ALL PASSED" : "❌  FAILURES DETECTED"));
      Print("╠══════════════════════════════════════════════════╣");
      Print(StringFormat("║  Total: %-4d  Pass: %-4d  Fail: %-4d  Skip: %-4d ║",
                         total, m_totalPass, m_totalFail, m_totalSkip));
      Print("╚══════════════════════════════════════════════════╝\n");
     }

   //--- Accessors
   int PassCount() const { return m_totalPass; }
   int FailCount() const { return m_totalFail; }
   int SkipCount() const { return m_totalSkip; }
   bool AllPassed() const { return m_totalFail == 0; }
  };

#endif // __QA_TEST_RUNNER_MQH__
