//+------------------------------------------------------------------+
//| Trade/ExecutionLedger.mqh - request/fill lifecycle tracker       |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_TRADE_EXECUTION_LEDGER_MQH__
#define __PASR_TRADE_EXECUTION_LEDGER_MQH__

#include "../Core/PipelineTypes.mqh"
#include "TradePlan.mqh"

enum ENUM_EXEC_LEDGER_STATE
  {
   EXEC_LEDGER_IDLE       = 0,
   EXEC_LEDGER_REQUESTED  = 1,
   EXEC_LEDGER_SENT       = 2,
   EXEC_LEDGER_RETRYING   = 3,
   EXEC_LEDGER_FILLED     = 4,
   EXEC_LEDGER_REJECTED   = 5,
   EXEC_LEDGER_TIMEOUT    = 6
  };

struct ExecutionLedgerSnapshot
  {
   ulong                  requestId;
   ENUM_EXEC_LEDGER_STATE state;
   ENUM_SIGNAL_DIR        direction;
   double                 lot;
   double                 entryPrice;
   double                 sl;
   double                 tp;
   ulong                  orderTicket;
   ulong                  positionTicket;
   ulong                  dealTicket;
   int                    retcode;
   int                    retryCount;
   datetime               requestedAt;
   datetime               updatedAt;
   string                 reason;

   void Clear()
     {
      requestId = 0;
      state = EXEC_LEDGER_IDLE;
      direction = SIGNAL_NONE;
      lot = 0.0;
      entryPrice = 0.0;
      sl = 0.0;
      tp = 0.0;
      orderTicket = 0;
      positionTicket = 0;
      dealTicket = 0;
      retcode = 0;
      retryCount = 0;
      requestedAt = 0;
      updatedAt = 0;
      reason = "";
     }
  };

class CExecutionLedger
  {
private:
   ulong                   m_nextRequestId;
   ExecutionLedgerSnapshot m_snapshot;

   void Touch(const string reason)
     {
      m_snapshot.updatedAt = TimeCurrent();
      if(reason != "") m_snapshot.reason = reason;
     }

public:
   CExecutionLedger() : m_nextRequestId(1)
     {
      m_snapshot.Clear();
     }

   ulong StartRequest(const TradePlan &plan)
     {
      m_snapshot.Clear();
      m_snapshot.requestId = m_nextRequestId++;
      m_snapshot.state = EXEC_LEDGER_REQUESTED;
      m_snapshot.direction = plan.direction;
      m_snapshot.lot = plan.lot;
      m_snapshot.entryPrice = plan.entryPrice;
      m_snapshot.sl = plan.sl;
      m_snapshot.tp = plan.tp;
      m_snapshot.requestedAt = TimeCurrent();
      Touch("Requested");
      return m_snapshot.requestId;
     }

   void MarkSent(const ulong orderTicket, const int retcode, const string reason)
     {
      if(m_snapshot.requestId == 0) return;
      m_snapshot.state = EXEC_LEDGER_SENT;
      m_snapshot.orderTicket = orderTicket;
      m_snapshot.retcode = retcode;
      Touch(reason);
     }

   void MarkRetrying(const int retcode, const int retryCount, const string reason)
     {
      if(m_snapshot.requestId == 0) return;
      m_snapshot.state = EXEC_LEDGER_RETRYING;
      m_snapshot.retcode = retcode;
      m_snapshot.retryCount = retryCount;
      Touch(reason);
     }

   void MarkRejected(const int retcode, const string reason)
     {
      if(m_snapshot.requestId == 0) return;
      m_snapshot.state = EXEC_LEDGER_REJECTED;
      m_snapshot.retcode = retcode;
      Touch(reason);
     }

   void MarkFilled(const ulong positionTicket, const ulong dealTicket, const string reason)
     {
      if(m_snapshot.requestId == 0) return;
      m_snapshot.state = EXEC_LEDGER_FILLED;
      m_snapshot.positionTicket = positionTicket;
      m_snapshot.dealTicket = dealTicket;
      Touch(reason);
     }

   void MarkTimeout(const string reason)
     {
      if(m_snapshot.requestId == 0) return;
      m_snapshot.state = EXEC_LEDGER_TIMEOUT;
      Touch(reason);
     }

   bool HasPending() const
     {
      return (m_snapshot.state == EXEC_LEDGER_REQUESTED ||
              m_snapshot.state == EXEC_LEDGER_SENT ||
              m_snapshot.state == EXEC_LEDGER_RETRYING);
     }

   bool IsStale(const int maxAgeSec) const
     {
      if(!HasPending() || maxAgeSec <= 0 || m_snapshot.updatedAt <= 0) return false;
      return (TimeCurrent() - m_snapshot.updatedAt) > maxAgeSec;
     }

   ExecutionLedgerSnapshot GetSnapshot() const
     {
      return m_snapshot;
     }
  };

#endif // __PASR_TRADE_EXECUTION_LEDGER_MQH__
