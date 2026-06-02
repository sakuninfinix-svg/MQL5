//+------------------------------------------------------------------+
//| Trade/PositionRegistry.mqh - canonical per-cycle position scan   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_TRADE_POSITION_REGISTRY_MQH__
#define __PASR_TRADE_POSITION_REGISTRY_MQH__

#define PASR_POSITION_REGISTRY_CAPACITY 64

struct SPositionSnapshot
  {
   ulong              ticket;
   string             symbol;
   long               magic;
   ENUM_POSITION_TYPE type;
   double             volume;
   double             open_price;
   double             sl;
   double             tp;
   double             profit;
   double             swap;
   double             commission;
   datetime           open_time;

   void Clear()
     {
      ticket = 0;
      symbol = "";
      magic = 0;
      type = WRONG_VALUE;
      volume = 0.0;
      open_price = 0.0;
      sl = 0.0;
      tp = 0.0;
      profit = 0.0;
      swap = 0.0;
      commission = 0.0;
      open_time = 0;
     }

   bool IsValid() const
     {
      return ticket > 0 && symbol != "" && volume > 0.0;
     }
  };

class CPositionRegistry
  {
private:
   SPositionSnapshot m_positions[PASR_POSITION_REGISTRY_CAPACITY];
   int               m_count;
   datetime          m_captured_at;
   long              m_filter_magic;
   string            m_filter_symbol;
   bool              m_overflow;

public:
   CPositionRegistry()
      : m_count(0), m_captured_at(0), m_filter_magic(0), m_filter_symbol(""), m_overflow(false)
     {
      Clear();
     }

   void Clear()
     {
      for(int i = 0; i < PASR_POSITION_REGISTRY_CAPACITY; i++)
         m_positions[i].Clear();
      m_count = 0;
      m_captured_at = 0;
      m_overflow = false;
     }

   void SetFilter(const string symbol, const long magic)
     {
      m_filter_symbol = symbol;
      m_filter_magic = magic;
     }

   bool Scan(const string symbol = "", const long magic = 0)
     {
      Clear();
      SetFilter(symbol, magic);
      m_captured_at = TimeCurrent();

      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         string posSymbol = PositionGetString(POSITION_SYMBOL);
         long posMagic = PositionGetInteger(POSITION_MAGIC);
         if(m_filter_symbol != "" && posSymbol != m_filter_symbol) continue;
         if(m_filter_magic != 0 && posMagic != m_filter_magic) continue;

         if(m_count >= PASR_POSITION_REGISTRY_CAPACITY)
           {
            m_overflow = true;
            break;
           }

         m_positions[m_count].ticket = ticket;
         m_positions[m_count].symbol = posSymbol;
         m_positions[m_count].magic = posMagic;
         m_positions[m_count].type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         m_positions[m_count].volume = PositionGetDouble(POSITION_VOLUME);
         m_positions[m_count].open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         m_positions[m_count].sl = PositionGetDouble(POSITION_SL);
         m_positions[m_count].tp = PositionGetDouble(POSITION_TP);
         m_positions[m_count].profit = PositionGetDouble(POSITION_PROFIT);
         m_positions[m_count].swap = PositionGetDouble(POSITION_SWAP);
         m_positions[m_count].commission = 0.0;
         m_positions[m_count].open_time = (datetime)PositionGetInteger(POSITION_TIME);
         m_count++;
        }
      return !m_overflow;
     }

   int Count() const { return m_count; }
   datetime CapturedAt() const { return m_captured_at; }
   bool Overflow() const { return m_overflow; }
   bool HasPosition() const { return m_count > 0; }
   ulong FirstTicket() const { return (m_count > 0) ? m_positions[0].ticket : 0; }

   bool GetAt(const int index, SPositionSnapshot &out) const
     {
      if(index < 0 || index >= m_count) return false;
      out = m_positions[index];
      return out.IsValid();
     }

   bool FindByTicket(const ulong ticket, SPositionSnapshot &out) const
     {
      if(ticket == 0) return false;
      for(int i = 0; i < m_count; i++)
        {
         if(m_positions[i].ticket == ticket)
           {
            out = m_positions[i];
            return out.IsValid();
           }
        }
      return false;
     }

   double FloatingPnL() const
     {
      double pnl = 0.0;
      for(int i = 0; i < m_count; i++)
         pnl += m_positions[i].profit + m_positions[i].swap + m_positions[i].commission;
      return pnl;
     }
  };

#endif // __PASR_TRADE_POSITION_REGISTRY_MQH__
