#ifndef __MQL5_VSCODE_FIX_H__
#define __MQL5_VSCODE_FIX_H__

// File ini hanya untuk membantu IntelliSense VS Code (C++)
// MetaEditor akan mengabaikan ini karena MQL5 tidak mendefinisikan __c++
#ifdef __cplusplus
#define input extern
#define sinput extern
#define group
#define interface class
#define datetime unsigned long
#define color unsigned int
#define ushort unsigned short
#define ulong unsigned long
#define uint unsigned int
#define uchar unsigned char

// Simulasi fungsi internal MQL5 agar tidak error di VS Code
#define GetPointer(ptr) ptr
#define GetTickCount64() 0ULL
#define GetMicrosecondCount() 0ULL
#define _Symbol "SYMBOL"
#define _Period 1
#define _Point 0.00001
#define _Digits 5
#define clrFireBrick 0xB22222

// History Deal Properties
#define DEAL_MAGIC 0
#define DEAL_SYMBOL 0
#define DEAL_TYPE 0
#define DEAL_PROFIT 0
#define DEAL_SWAP 0
#define DEAL_COMMISSION 0
#define DEAL_ENTRY 0
#define DEAL_ENTRY_OUT 0

// MQL5 Functions for IntelliSense
#define HistorySelect(f, t) true
#define HistoryDealsTotal() 0
#define HistoryDealGetTicket(i) 0ULL
#define HistoryDealGetInteger(t, p) 0LL
#define HistoryDealGetDouble(t, p) 0.0
#define HistoryDealGetString(t, p) _Symbol
#define PositionGetString(p) _Symbol
#define OrdersTotal() 0
#define OrderGetTicket(i) 0ULL
#define OrderGetInteger(p) 0LL
#define OrderGetString(p) _Symbol
#define PositionGetInteger(p) 0LL
#define PositionGetDouble(p) 0.0

// Position & Order Properties
#define POSITION_MAGIC 0
#define POSITION_SYMBOL 0
#define POSITION_TYPE 0
#define POSITION_PROFIT 0
#define POSITION_SWAP 0
#define POSITION_COMMISSION 0

#define ORDER_MAGIC 0
#define ORDER_SYMBOL 0
#define ORDER_STATE 0
#define ORDER_STATE_STARTED 0
#define ORDER_STATE_PLACED 0

// Casting dummy
#define dynamic_cast static_cast
#endif

#endif