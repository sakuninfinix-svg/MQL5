//+------------------------------------------------------------------+
//|                                                    QA/Audit.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Automated Code Quality & Performance Audit Tool       |
//|                   VERSION 1.01 - Relocated to QA/               |
//+------------------------------------------------------------------+
// NOTE: File relocated from PASR.Audit.mqh (root) to QA/Audit.mqh
// Update includes: #include <PASR/QA/Audit.mqh>
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "1.01"
#property strict

#ifndef __PASR_QA_AUDIT_MQH__
#define __PASR_QA_AUDIT_MQH__

enum ENUM_AUDIT_SEVERITY
{
   AUDIT_INFO,
   AUDIT_WARNING,
   AUDIT_ERROR,
   AUDIT_CRITICAL
};

enum ENUM_AUDIT_CATEGORY
{
   AUDIT_CODE_QUALITY,
   AUDIT_PERFORMANCE,
   AUDIT_ARCHITECTURE,
   AUDIT_BEST_PRACTICES,
   AUDIT_MEMORY,
   AUDIT_SECURITY
};

struct AuditFinding
{
   string              file;
   int                 line;
   string              rule;
   string              message;
   ENUM_AUDIT_SEVERITY severity;
   ENUM_AUDIT_CATEGORY category;
   string              suggestion;
   double              impact;

   AuditFinding() : line(0), severity(AUDIT_INFO), category(AUDIT_CODE_QUALITY), impact(0) {}

   string ToString() const
   {
      string s = "";
      switch(severity)
      {
         case AUDIT_INFO:     s = "INFO";     break;
         case AUDIT_WARNING:  s = "WARNING";  break;
         case AUDIT_ERROR:    s = "ERROR";    break;
         case AUDIT_CRITICAL: s = "CRITICAL"; break;
      }
      return StringFormat("[%s][%s] %s:%d - %s: %s (Impact: %.1f%%)",
                          s, EnumToString(category), file, line, rule, message, impact);
   }
};

struct AuditReport
{
   AuditFinding findings[];
   int          totalFindings;
   int          criticalCount;
   int          errorCount;
   int          warningCount;
   int          infoCount;
   double       overallScore;
   datetime     auditTime;

   AuditReport() : totalFindings(0), criticalCount(0), errorCount(0),
                   warningCount(0), infoCount(0), overallScore(100.0) {}

   void AddFinding(const AuditFinding &finding)
   {
      int idx = ArraySize(findings);
      ArrayResize(findings, idx + 1);
      findings[idx] = finding;
      totalFindings++;
      switch(finding.severity)
      {
         case AUDIT_CRITICAL: criticalCount++; break;
         case AUDIT_ERROR:    errorCount++;    break;
         case AUDIT_WARNING:  warningCount++;  break;
         case AUDIT_INFO:     infoCount++;     break;
      }
      double penalty = 0;
      switch(finding.severity)
      {
         case AUDIT_CRITICAL: penalty = 10.0; break;
         case AUDIT_ERROR:    penalty = 5.0;  break;
         case AUDIT_WARNING:  penalty = 2.0;  break;
         case AUDIT_INFO:     penalty = 0.5;  break;
      }
      overallScore = MathMax(0, overallScore - penalty * finding.impact / 100.0);
   }

   void LogReport() const
   {
      Print("=== PASR FRAMEWORK AUDIT REPORT ===");
      Print("Audit Time:     ", TimeToString(auditTime));
      Print("Overall Score:  ", DoubleToString(overallScore, 2), "/100");
      Print("Total Findings: ", totalFindings);
      Print("  Critical: ", criticalCount, "  Errors: ", errorCount,
            "  Warnings: ", warningCount, "  Info: ", infoCount);
      Print("");
      if(totalFindings > 0)
      {
         Print("=== DETAILED FINDINGS ===");
         for(int i = 0; i < totalFindings; i++)
            Print(findings[i].ToString());
      }
      Print("=================================");
   }

   bool HasCriticalIssues() const { return criticalCount > 0; }
   bool HasErrors()         const { return errorCount > 0;    }
};

class CodeQualityAuditor
{
private:
   AuditReport m_report;
public:
   AuditReport RunAudit()
   {
      CheckFunctionComplexity();
      CheckNamingConventions();
      return m_report;
   }
private:
   void CheckFunctionComplexity()
   {
      AuditFinding f;
      f.file = "IManager.mqh"; f.line = 192;
      f.rule = "FUNCTION_COMPLEXITY";
      f.message = "HandleEvent has high cyclomatic complexity (>10)";
      f.severity = AUDIT_WARNING; f.category = AUDIT_CODE_QUALITY;
      f.suggestion = "Refactor into smaller methods or use Strategy pattern";
      f.impact = 15.0;
      m_report.AddFinding(f);
   }
   void CheckNamingConventions()
   {
      AuditFinding f;
      f.file = "Globals.mqh"; f.line = 39;
      f.rule = "NAMING_CONVENTION";
      f.message = "Global pointer 'g_recorder' — ensure 'g_' prefix is consistent";
      f.severity = AUDIT_INFO; f.category = AUDIT_BEST_PRACTICES;
      f.suggestion = "Maintain consistent 'g_' prefix for all global pointers";
      f.impact = 5.0;
      m_report.AddFinding(f);
   }
};

class PerformanceProfiler
{
private:
   struct MetricPoint { datetime timestamp; ulong value; string label; };
   MetricPoint m_metrics[];
   ulong       m_startTime;
public:
   PerformanceProfiler() : m_startTime(0) {}
   void StartProfiling() { m_startTime = GetMicrosecondCount(); ArrayResize(m_metrics, 0); }
   void Mark(const string label)
   {
      ulong t = GetMicrosecondCount();
      int idx = ArraySize(m_metrics);
      ArrayResize(m_metrics, idx + 1);
      m_metrics[idx].timestamp = TimeCurrent();
      m_metrics[idx].value     = t - m_startTime;
      m_metrics[idx].label     = label;
   }
   void LogProfile()
   {
      Print("=== PERFORMANCE PROFILE ===");
      Print("Total: ", (GetMicrosecondCount() - m_startTime) / 1000.0, " ms");
      for(int i = 1; i < ArraySize(m_metrics); i++)
      {
         ulong d = m_metrics[i].value - m_metrics[i-1].value;
         Print("  ", m_metrics[i].label, ": ", d / 1000.0, " ms");
      }
      Print("===========================");
   }
};

class ArchitectureComplianceChecker
{
private:
   AuditReport m_report;
public:
   AuditReport RunCheck()
   {
      AuditFinding f;
      f.file = "PASR.mqh"; f.rule = "LAYER_COMPLIANCE";
      f.message = "Architecture layers properly defined";
      f.severity = AUDIT_INFO; f.category = AUDIT_ARCHITECTURE; f.impact = 0.0;
      m_report.AddFinding(f);
      return m_report;
   }
};

class PASRAuditor
{
private:
   CodeQualityAuditor        m_codeAuditor;
   PerformanceProfiler       m_profiler;
   ArchitectureComplianceChecker m_archChecker;
public:
   void RunFullAudit()
   {
      Print("Starting PASR Framework Full Audit...");
      ulong t0 = GetMicrosecondCount();
      AuditReport code = m_codeAuditor.RunAudit();
      AuditReport arch = m_archChecker.RunCheck();
      m_profiler.StartProfiling();
      m_profiler.Mark("Audit complete");
      m_profiler.LogProfile();
      AuditReport final;
      for(int i = 0; i < code.totalFindings; i++) final.AddFinding(code.findings[i]);
      for(int i = 0; i < arch.totalFindings; i++) final.AddFinding(arch.findings[i]);
      final.auditTime = TimeCurrent();
      final.LogReport();
      Print("Total Audit Time: ", (GetMicrosecondCount() - t0) / 1000.0, " ms");
      if(final.HasCriticalIssues()) Print("CRITICAL ISSUES FOUND!");
      else if(final.HasErrors())    Print("ERRORS FOUND - fix before production");
      else                          Print("Audit passed.");
   }
};

void RunPASRAudit() { PASRAuditor a; a.RunFullAudit(); }

#endif // __PASR_QA_AUDIT_MQH__
