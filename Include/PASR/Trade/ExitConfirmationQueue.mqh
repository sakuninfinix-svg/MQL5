//+------------------------------------------------------------------+
//| Trade/ExitConfirmationQueue.mqh - close confirmation tracker     |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_TRADE_EXIT_CONFIRMATION_QUEUE_MQH__
#define __PASR_TRADE_EXIT_CONFIRMATION_QUEUE_MQH__

#define PASR_EXIT_QUEUE_CAPACITY 16
#define PASR_EXIT_QUEUE_MAX_RETRIES 2

enum ENUM_EXIT_CONFIRM_STATE
  {
   EXIT_CONFIRM_IDLE      = 0,
   EXIT_CONFIRM_REQUESTED = 1,
   EXIT_CONFIRM_SENT      = 2,
   EXIT_CONFIRM_CONFIRMED = 3,
   EXIT_CONFIRM_REJECTED  = 4,
   EXIT_CONFIRM_TIMEOUT   = 5
  };

enum ENUM_EXIT_REQUEST_ACTION
  {
   EXIT_ACTION_NONE    = 0,
   EXIT_ACTION_CLOSE   = 1,
   EXIT_ACTION_PARTIAL = 2
  };

struct ExitConfirmationRecord
  {
   ulong                   requestId;
   ulong                   positionTicket;
   ulong                   dealTicket;
   int                     exitReason;
   ENUM_EXIT_REQUEST_ACTION action;
   double                  requestedVolume;
   ENUM_EXIT_CONFIRM_STATE state;
   int                     retcode;
   int                     retryCount;
   datetime                requestedAt;
   datetime                updatedAt;
   string                  reason;

   void Clear()
     {
      requestId = 0;
      positionTicket = 0;
      dealTicket = 0;
      exitReason = 0;
      action = EXIT_ACTION_NONE;
      requestedVolume = 0.0;
      state = EXIT_CONFIRM_IDLE;
      retcode = 0;
      retryCount = 0;
      requestedAt = 0;
      updatedAt = 0;
      reason = "";
     }

   bool IsPending() const
     {
      return state == EXIT_CONFIRM_REQUESTED || state == EXIT_CONFIRM_SENT;
     }
  };

struct ExitConfirmationSnapshot
  {
   int      pendingCount;
   int      confirmedCount;
   int      rejectedCount;
   int      timeoutCount;
   int      lastAction;
   double   lastRequestedVolume;
   int      lastRetryCount;
   ulong    lastRequestId;
   ulong    lastPositionTicket;
   int      lastState;
   string   lastReason;

   void Clear()
     {
      pendingCount = 0;
      confirmedCount = 0;
      rejectedCount = 0;
      timeoutCount = 0;
      lastAction = EXIT_ACTION_NONE;
      lastRequestedVolume = 0.0;
      lastRetryCount = 0;
      lastRequestId = 0;
      lastPositionTicket = 0;
      lastState = EXIT_CONFIRM_IDLE;
      lastReason = "";
     }
  };

class CExitConfirmationQueue
  {
private:
   ExitConfirmationRecord m_records[PASR_EXIT_QUEUE_CAPACITY];
   ulong                  m_nextRequestId;
   ExitConfirmationSnapshot m_snapshot;

   void Touch(ExitConfirmationRecord &rec, const string reason)
     {
      rec.updatedAt = TimeCurrent();
      if(reason != "") rec.reason = reason;
      RefreshSnapshot(rec);
     }

   int FindByPosition(const ulong positionTicket) const
     {
      if(positionTicket == 0) return -1;
      for(int i = 0; i < PASR_EXIT_QUEUE_CAPACITY; i++)
         if(m_records[i].positionTicket == positionTicket && m_records[i].IsPending())
            return i;
      return -1;
     }

   int FindFreeSlot() const
     {
      for(int i = 0; i < PASR_EXIT_QUEUE_CAPACITY; i++)
         if(!m_records[i].IsPending())
            return i;
      return -1;
     }

   int FindRetryableByPosition(const ulong positionTicket) const
     {
      if(positionTicket == 0) return -1;
      for(int i = 0; i < PASR_EXIT_QUEUE_CAPACITY; i++)
        {
         if(m_records[i].positionTicket != positionTicket) continue;
         bool terminalRetryable = (m_records[i].state == EXIT_CONFIRM_REJECTED ||
                                   m_records[i].state == EXIT_CONFIRM_TIMEOUT);
         if(terminalRetryable && m_records[i].retryCount < PASR_EXIT_QUEUE_MAX_RETRIES)
            return i;
        }
      return -1;
     }

   void RefreshSnapshot(const ExitConfirmationRecord &last)
     {
      m_snapshot.Clear();
      for(int i = 0; i < PASR_EXIT_QUEUE_CAPACITY; i++)
        {
         if(m_records[i].IsPending()) m_snapshot.pendingCount++;
         else if(m_records[i].state == EXIT_CONFIRM_CONFIRMED) m_snapshot.confirmedCount++;
         else if(m_records[i].state == EXIT_CONFIRM_REJECTED) m_snapshot.rejectedCount++;
         else if(m_records[i].state == EXIT_CONFIRM_TIMEOUT) m_snapshot.timeoutCount++;
        }
      m_snapshot.lastRequestId = last.requestId;
      m_snapshot.lastPositionTicket = last.positionTicket;
      m_snapshot.lastState = (int)last.state;
      m_snapshot.lastAction = (int)last.action;
      m_snapshot.lastRequestedVolume = last.requestedVolume;
      m_snapshot.lastRetryCount = last.retryCount;
      m_snapshot.lastReason = last.reason;
     }

public:
   CExitConfirmationQueue() : m_nextRequestId(1)
     {
      Clear();
     }

   void Clear()
     {
      for(int i = 0; i < PASR_EXIT_QUEUE_CAPACITY; i++)
         m_records[i].Clear();
      m_snapshot.Clear();
   }

   bool HasPendingClose(const ulong positionTicket) const
     {
      return FindByPosition(positionTicket) >= 0;
     }

   bool HasConfirmedAction(const ulong positionTicket, const ENUM_EXIT_REQUEST_ACTION action) const
     {
      if(positionTicket == 0 || action == EXIT_ACTION_NONE) return false;
      for(int i = 0; i < PASR_EXIT_QUEUE_CAPACITY; i++)
         if(m_records[i].positionTicket == positionTicket &&
            m_records[i].action == action &&
            m_records[i].state == EXIT_CONFIRM_CONFIRMED)
            return true;
      return false;
     }

   bool HasRetryableExit(const ulong positionTicket) const
     {
      return FindRetryableByPosition(positionTicket) >= 0;
     }

   bool PrepareRetry(const ulong positionTicket, ENUM_EXIT_REQUEST_ACTION &action, double &requestedVolume, int &exitReason, string &reason)
     {
      int idx = FindRetryableByPosition(positionTicket);
      if(idx < 0) return false;
      m_records[idx].retryCount++;
      m_records[idx].state = EXIT_CONFIRM_REQUESTED;
      action = m_records[idx].action;
      requestedVolume = m_records[idx].requestedVolume;
      exitReason = m_records[idx].exitReason;
      reason = "RetryExit";
      Touch(m_records[idx], reason);
      return true;
     }

   ulong RequestExit(const ulong positionTicket, const int exitReason, const ENUM_EXIT_REQUEST_ACTION action, const double requestedVolume, const string reason)
     {
      if(positionTicket == 0) return 0;
      int idx = FindByPosition(positionTicket);
      if(idx < 0) idx = FindFreeSlot();
      if(idx < 0) return 0;

      m_records[idx].Clear();
      m_records[idx].requestId = m_nextRequestId++;
      m_records[idx].positionTicket = positionTicket;
      m_records[idx].exitReason = exitReason;
      m_records[idx].action = action;
      m_records[idx].requestedVolume = requestedVolume;
      m_records[idx].state = EXIT_CONFIRM_REQUESTED;
      m_records[idx].requestedAt = TimeCurrent();
      Touch(m_records[idx], reason);
      return m_records[idx].requestId;
   }

   ulong RequestClose(const ulong positionTicket, const int exitReason, const string reason)
     {
      return RequestExit(positionTicket, exitReason, EXIT_ACTION_CLOSE, 0.0, reason);
     }

   ulong RequestPartial(const ulong positionTicket, const int exitReason, const double requestedVolume, const string reason)
     {
      return RequestExit(positionTicket, exitReason, EXIT_ACTION_PARTIAL, requestedVolume, reason);
     }

   void MarkSent(const ulong positionTicket, const int retcode, const string reason)
     {
      int idx = FindByPosition(positionTicket);
      if(idx < 0) return;
      m_records[idx].state = EXIT_CONFIRM_SENT;
      m_records[idx].retcode = retcode;
      Touch(m_records[idx], reason);
   }

   void MarkRejected(const ulong positionTicket, const int retcode, const string reason)
     {
      int idx = FindByPosition(positionTicket);
      if(idx < 0) return;
      m_records[idx].state = EXIT_CONFIRM_REJECTED;
      m_records[idx].retcode = retcode;
      Touch(m_records[idx], reason);
   }

   void MarkConfirmed(const ulong positionTicket, const ulong dealTicket, const string reason)
     {
      int idx = FindByPosition(positionTicket);
      if(idx < 0) return;
      m_records[idx].state = EXIT_CONFIRM_CONFIRMED;
      m_records[idx].dealTicket = dealTicket;
      Touch(m_records[idx], reason);
   }

   void MarkTimeouts(const int maxAgeSec)
     {
      if(maxAgeSec <= 0) return;
      datetime now = TimeCurrent();
      for(int i = 0; i < PASR_EXIT_QUEUE_CAPACITY; i++)
        {
         if(!m_records[i].IsPending() || m_records[i].updatedAt <= 0) continue;
         if(now - m_records[i].updatedAt > maxAgeSec)
           {
            m_records[i].state = EXIT_CONFIRM_TIMEOUT;
            Touch(m_records[i], "CloseConfirmationTimeout");
           }
        }
   }

   ExitConfirmationSnapshot GetSnapshot() const
     {
      return m_snapshot;
     }
  };

#endif // __PASR_TRADE_EXIT_CONFIRMATION_QUEUE_MQH__
