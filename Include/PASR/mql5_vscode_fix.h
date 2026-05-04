#ifndef __MQL5_VSCODE_FIX_H__
#define __MQL5_VSCODE_FIX_H__

// File ini hanya untuk membantu IntelliSense VS Code (C++)
// MetaEditor akan mengabaikan ini karena MQL5 tidak mendefinisikan __c++
#ifdef __cplusplus
    #define input extern
    #define sinput extern
    #define group
    #define datetime unsigned long
    #define color unsigned int
    #define ushort unsigned short
    #define ulong unsigned long
    #define uint unsigned int
    #define uchar unsigned char

    // Simulasi fungsi internal MQL5 agar tidak error di VS Code
    #define GetPointer(ptr) ptr
    #define _Symbol "SYMBOL"
    #define _Period 1
    #define _Point 0.00001
    #define _Digits 5
    #define clrFireBrick 0xB22222

    // Casting dummy
    #define dynamic_cast
#endif

#endif