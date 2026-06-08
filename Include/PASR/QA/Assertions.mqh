//+------------------------------------------------------------------+
//|                                            QA/Assertions.mqh    |
//|                                     Copyright 2026, Agsicentre  |
//|  Assertion helpers for PASR unit tests.                         |
//|  All macros capture __FILE__ and __LINE__ automatically.        |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_ASSERTIONS_MQH__
#define __QA_ASSERTIONS_MQH__

//--- Internal result accumulator (filled by TestRunner context)
struct AssertionResult
  {
   bool   passed;
   string expression;
   string file;
   int    line;
   string detail;

   AssertionResult() : passed(false), line(0) {}
  };

//+------------------------------------------------------------------+
//| Low-level assertion recorder — called by macros below            |
//+------------------------------------------------------------------+
namespace QA
  {

   int g_assertPass = 0;
   int g_assertFail = 0;

   void _Record(bool cond, const string expr, const string file, int line, const string detail="")
     {
      if(cond)
        {
         g_assertPass++;
        }
      else
        {
         g_assertFail++;
         string msg = StringFormat("  ✗ FAIL  [%s:%d]  %s", file, line, expr);
         if(detail != "") msg += "  →  " + detail;
         Print(msg);
        }
     }

   void Reset() { g_assertPass = 0; g_assertFail = 0; }
   int  PassCount() { return g_assertPass; }
   int  FailCount() { return g_assertFail; }
  }

//+------------------------------------------------------------------+
//| Public assertion macros                                          |
//+------------------------------------------------------------------+

/// IsTrue — fails when condition is false
#define ASSERT_TRUE(expr) \
   QA::_Record((bool)(expr), "IsTrue: " #expr, __FILE__, __LINE__)

/// IsFalse — fails when condition is true
#define ASSERT_FALSE(expr) \
   QA::_Record(!(bool)(expr), "IsFalse: " #expr, __FILE__, __LINE__)

/// AreEqual — exact equality, works for int/bool/string/enum
#define ASSERT_EQ(a, b) \
   QA::_Record((a)==(b), "AreEqual: " #a " == " #b, __FILE__, __LINE__, \
               StringFormat("got %s, expected %s", (string)(a), (string)(b)))

/// AreNotEqual
#define ASSERT_NEQ(a, b) \
   QA::_Record((a)!=(b), "AreNotEqual: " #a " != " #b, __FILE__, __LINE__)

/// ApproxEqual — floating point with epsilon
#define ASSERT_APPROX(a, b, eps) \
   QA::_Record(MathAbs((double)(a)-(double)(b))<=(double)(eps), \
               "ApproxEq: " #a " ≈ " #b, __FILE__, __LINE__, \
               StringFormat("|%.8f - %.8f| = %.2e (eps=%.2e)", (double)(a),(double)(b), \
                            MathAbs((double)(a)-(double)(b)),(double)(eps)))

/// IsNull — pointer is NULL
#define ASSERT_NULL(ptr) \
   QA::_Record((ptr)==NULL, "IsNull: " #ptr, __FILE__, __LINE__)

/// IsNotNull — pointer is not NULL
#define ASSERT_NOT_NULL(ptr) \
   QA::_Record((ptr)!=NULL, "IsNotNull: " #ptr, __FILE__, __LINE__)

/// InRange — value within [lo, hi] inclusive
#define ASSERT_RANGE(val, lo, hi) \
   QA::_Record((val)>=(lo) && (val)<=(hi), \
               "InRange: " #lo " <= " #val " <= " #hi, __FILE__, __LINE__, \
               StringFormat("value = %s", (string)(val)))

/// Positive — value > 0
#define ASSERT_POSITIVE(val) \
   QA::_Record((val)>0, "Positive: " #val, __FILE__, __LINE__, \
               StringFormat("value = %s", (string)(val)))

/// Fail — unconditional failure with message
#define ASSERT_FAIL(msg) \
   QA::_Record(false, "Fail: " msg, __FILE__, __LINE__)

class CAssertions
  {
private:
   string m_section;

public:
   void BeginSection(const string name)
     {
      m_section = name;
      Print("[QA] BEGIN ", name);
     }

   void EndSection()
     {
      if(m_section != "")
         Print("[QA] END ", m_section);
      m_section = "";
     }

   void AreEqual(const string name, const int expected, const int actual)
     {
      QA::_Record(expected == actual, name, __FILE__, __LINE__,
                  StringFormat("expected=%d actual=%d", expected, actual));
     }

   void IsTrue(const string name, const bool value)
     {
      QA::_Record(value, name, __FILE__, __LINE__);
     }

   void IsFalse(const string name, const bool value)
     {
      QA::_Record(!value, name, __FILE__, __LINE__);
     }

   void IsNotNull(const string name, const void *ptr)
     {
      QA::_Record(ptr != NULL, name, __FILE__, __LINE__);
     }

   void IsNear(const string name, const double expected, const double actual, const double epsilon)
     {
      double delta = MathAbs(expected - actual);
      QA::_Record(delta <= epsilon, name, __FILE__, __LINE__,
                  StringFormat("expected=%.8f actual=%.8f delta=%.8f eps=%.8f",
                               expected, actual, delta, epsilon));
     }

   void PrintReport()
     {
      PrintFormat("[QA] Assertions pass=%d fail=%d", QA::PassCount(), QA::FailCount());
     }
  };

#endif // __QA_ASSERTIONS_MQH__
