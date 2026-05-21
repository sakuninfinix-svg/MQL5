//+------------------------------------------------------------------+
//|                                                     QA/Test.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|                     Unit Testing Framework for PASR              |
//|                   VERSION 1.01 - Relocated to QA/               |
//+------------------------------------------------------------------+
// NOTE: File relocated from PASR.Test.mqh (root) to QA/Test.mqh
// Update includes: #include <PASR/QA/Test.mqh>
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.01"
#property strict

#ifndef __PASR_QA_TEST_MQH__
#define __PASR_QA_TEST_MQH__

enum ENUM_TEST_RESULT { TEST_PASS, TEST_FAIL, TEST_SKIP, TEST_ERROR };

struct TestResult
{
   string           testName;
   string           className;
   ENUM_TEST_RESULT result;
   string           message;
   ulong            durationUs;
   int              lineNumber;

   TestResult() : result(TEST_SKIP), durationUs(0), lineNumber(0) {}

   string ToString() const
   {
      string r = "";
      switch(result)
      {
         case TEST_PASS:  r = "PASS";  break;
         case TEST_FAIL:  r = "FAIL";  break;
         case TEST_SKIP:  r = "SKIP";  break;
         case TEST_ERROR: r = "ERROR"; break;
      }
      return StringFormat("[%s] %s::%s (%d us) - %s", r, className, testName, durationUs, message);
   }
};

struct TestSuiteReport
{
   TestResult results[];
   int        totalTests;
   int        passCount;
   int        failCount;
   int        skipCount;
   int        errorCount;
   ulong      totalDuration;
   double     passRate;

   TestSuiteReport() : totalTests(0), passCount(0), failCount(0),
                       skipCount(0), errorCount(0), totalDuration(0), passRate(0.0) {}

   void AddResult(const TestResult &r)
   {
      int idx = ArraySize(results);
      ArrayResize(results, idx + 1);
      results[idx] = r;
      totalTests++;
      totalDuration += r.durationUs;
      switch(r.result)
      {
         case TEST_PASS:  passCount++;  break;
         case TEST_FAIL:  failCount++;  break;
         case TEST_SKIP:  skipCount++;  break;
         case TEST_ERROR: errorCount++; break;
      }
      passRate = totalTests > 0 ? (double)passCount / (double)totalTests * 100.0 : 0.0;
   }

   void LogReport() const
   {
      Print("=== TEST SUITE REPORT ===");
      Print("Total: ", totalTests, "  Pass: ", passCount,
            " (", DoubleToString(passRate, 1), "%)  Fail: ", failCount,
            "  Error: ", errorCount, "  Skip: ", skipCount);
      Print("Duration: ", totalDuration / 1000.0, " ms");
      if(failCount > 0 || errorCount > 0)
      {
         Print("=== FAILED TESTS ===");
         for(int i = 0; i < totalTests; i++)
            if(results[i].result == TEST_FAIL || results[i].result == TEST_ERROR)
               Print(results[i].ToString());
      }
      Print("=========================");
   }

   bool AllPassed() const { return failCount == 0 && errorCount == 0; }
};

class Assert
{
private:
   static int s_assertions;
   static int s_failures;
public:
   static void Reset() { s_assertions = 0; s_failures = 0; }
   static int  Count()   { return s_assertions; }
   static int  Failures(){ return s_failures;   }

   static bool IsTrue(bool c, const string msg = "")
   { s_assertions++; if(!c){ s_failures++; Print("FAIL IsTrue: ", msg); return false; } return true; }

   static bool IsFalse(bool c, const string msg = "")
   { s_assertions++; if(c){ s_failures++; Print("FAIL IsFalse: ", msg); return false; } return true; }

   static bool AreEqual(int exp, int act, const string msg = "")
   { s_assertions++; if(exp!=act){ s_failures++; Print(StringFormat("FAIL AreEqual: exp=%d act=%d - %s",exp,act,msg)); return false; } return true; }

   static bool AreEqual(double exp, double act, double tol=0.0001, const string msg="")
   { s_assertions++; if(MathAbs(exp-act)>tol){ s_failures++; Print(StringFormat("FAIL AreEqual: exp=%.8f act=%.8f - %s",exp,act,msg)); return false; } return true; }

   static bool AreEqual(string exp, string act, const string msg="")
   { s_assertions++; if(exp!=act){ s_failures++; Print(StringFormat("FAIL AreEqual: exp='%s' act='%s' - %s",exp,act,msg)); return false; } return true; }

   static bool IsNotNull(void *p, const string msg="")
   { s_assertions++; if(p==NULL){ s_failures++; Print("FAIL IsNotNull: ",msg); return false; } return true; }

   static bool IsNull(void *p, const string msg="")
   { s_assertions++; if(p!=NULL){ s_failures++; Print("FAIL IsNull: ",msg); return false; } return true; }

   static bool IsInRange(int v, int mn, int mx, const string msg="")
   { s_assertions++; if(v<mn||v>mx){ s_failures++; Print(StringFormat("FAIL InRange: %d not in [%d,%d] - %s",v,mn,mx,msg)); return false; } return true; }
};

int Assert::s_assertions = 0;
int Assert::s_failures   = 0;

class CTestBase
{
protected:
   TestSuiteReport m_report;
   string          m_currentTest;
   ulong           m_testStart;
public:
   CTestBase() {}
   virtual ~CTestBase() {}
   virtual void Setup()    {}
   virtual void Teardown() {}
   virtual void RunAllTests() = 0;
   TestSuiteReport GetReport() const { return m_report; }
protected:
   void StartTest(const string name)
   { m_currentTest = name; m_testStart = GetMicrosecondCount(); Assert::Reset(); }

   void EndTest(ENUM_TEST_RESULT result, const string msg = "")
   {
      TestResult r;
      r.testName   = m_currentTest;
      r.className  = TypeName(this);
      r.result     = result;
      r.message    = msg;
      r.durationUs = GetMicrosecondCount() - m_testStart;
      m_report.AddResult(r);
      if(result == TEST_FAIL || result == TEST_ERROR) Print(r.ToString());
   }

   bool ASSERT_TRUE(bool c,const string m="")        { return Assert::IsTrue(c,m); }
   bool ASSERT_FALSE(bool c,const string m="")       { return Assert::IsFalse(c,m); }
   bool ASSERT_EQ(int e,int a,const string m="")     { return Assert::AreEqual(e,a,m); }
   bool ASSERT_EQD(double e,double a,double t=0.0001,const string m="") { return Assert::AreEqual(e,a,t,m); }
   bool ASSERT_EQS(string e,string a,const string m="") { return Assert::AreEqual(e,a,m); }
   bool ASSERT_NULL(void *p,const string m="")       { return Assert::IsNull(p,m); }
   bool ASSERT_NOT_NULL(void *p,const string m="")   { return Assert::IsNotNull(p,m); }
   bool ASSERT_RANGE(int v,int mn,int mx,const string m="") { return Assert::IsInRange(v,mn,mx,m); }
};

class TestRunner
{
private:
   CTestBase *m_suites[];
   int        m_count;
public:
   TestRunner() : m_count(0) {}

   void Register(CTestBase *suite)
   {
      ArrayResize(m_suites, m_count + 1);
      m_suites[m_count++] = suite;
   }

   TestSuiteReport RunAll()
   {
      TestSuiteReport combined;
      Print("=== STARTING TEST RUN ===");
      ulong t0 = GetMicrosecondCount();
      for(int i = 0; i < m_count; i++)
      {
         if(!CheckPointer(m_suites[i])) continue;
         Print("Suite: ", TypeName(m_suites[i]));
         m_suites[i]->RunAllTests();
         TestSuiteReport s = m_suites[i]->GetReport();
         for(int j = 0; j < s.totalTests; j++) combined.AddResult(s.results[j]);
      }
      Print("=== DONE in ", (GetMicrosecondCount()-t0)/1000.0, " ms ===");
      combined.LogReport();
      return combined;
   }
};

#endif // __PASR_QA_TEST_MQH__
