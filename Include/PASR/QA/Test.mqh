//+------------------------------------------------------------------+
//| QA/Test.mqh — v1.00                                              |
//| Lightweight synchronous test runner for PASR unit tests.         |
//| PASR_QA_BUILD define required to include this file.              |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_TEST_MQH__
#define __QA_TEST_MQH__

#define PASR_ASSERT(expr, msg) CPASRTest::_Assert((expr), (msg), __FILE__, __LINE__)
#define PASR_TEST(name)        void Test_##name(CPASRTest &T)
#define PASR_RUN(runner, name) runner.Run(Test_##name, #name)

//+------------------------------------------------------------------+
//| CPASRTest — minimal test runner                                  |
//+------------------------------------------------------------------+
class CPASRTest
  {
private:
   int m_pass, m_fail, m_total;
   string m_suiteName;

public:
   CPASRTest(string suite="") : m_pass(0), m_fail(0), m_total(0), m_suiteName(suite) {}

   typedef void (*TestFn)(CPASRTest &);

   void Run(TestFn fn, const string testName)
     {
      PrintFormat("[Test] RUN: %s", testName);
      fn(this);
     }

   static void _Assert(bool expr, const string msg, const string file, int line)
     { /* Instance-free — calls Print directly */
       if(!expr) PrintFormat("[Test] FAIL %s:%d — %s", file, line, msg);
       else      PrintFormat("[Test] PASS — %s", msg);
     }

   void Expect(bool expr, const string msg)
     {
      m_total++;
      if(expr) { m_pass++; PrintFormat("[Test] PASS %s",  msg); }
      else     { m_fail++; PrintFormat("[Test] FAIL %s ← assertion false", msg); }
     }

   void ExpectEq(double a, double b, double tol, const string msg)
     {
      Expect(MathAbs(a-b) <= tol,
             StringFormat("%s (%.6f == %.6f ± %.6f)", msg, a, b, tol));
     }

   void ExpectNear(double a, double b, const string msg)
     { ExpectEq(a, b, 1e-6, msg); }

   void Summary()
     {
      PrintFormat("[Test] ═══ %s: %d/%d passed, %d failed ═══",
                  m_suiteName, m_pass, m_total, m_fail);
     }

   bool AllPassed() const { return m_fail == 0; }
   int  PassCount() const { return m_pass; }
   int  FailCount() const { return m_fail; }
   int  TotalCount()const { return m_total; }
  };

#endif
