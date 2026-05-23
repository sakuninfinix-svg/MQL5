//+------------------------------------------------------------------+
//| PatternManager.mqh                                               |
//| Copyright 2026, Agsicentre                                       |
//| Refactored for PASR v2.02 Architecture (Sprint 8 IManager fix)   |
//+------------------------------------------------------------------+
#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

#property strict

//--- Include dependencies
#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "PatternTypes.mqh"  // ENUM_PATTERN_TYPE definition
#include <Arrays/ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Pattern Vote Structure                                           |
//+------------------------------------------------------------------+
struct SPatternVote
{
   bool              valid;
   ENUM_PATTERN_TYPE type;
   int               dir;          // 1 = buy, -1 = sell
   double            extreme;
   double            score;
   double            regimeWeight; // Bobot tambahan berdasarkan regime
   string            label;

   void Reset()
   {
      valid        = false;
      type         = PATTERN_NONE;
      dir          = 0;
      extreme      = 0.0;
      score        = 0.0;
      regimeWeight = 1.0;
      label        = "";
   }

   double TotalScore() const { return score * regimeWeight; }
};

//+------------------------------------------------------------------+
//| Pattern Detection Result                                         |
//+------------------------------------------------------------------+
struct SPatternResult
{
   bool              found;
   ENUM_PATTERN_TYPE type;
   int               direction;
   double            extreme;
   double            confluenceScore;
   string            reason;
   ulong             barTime;

   void Clear()
   {
      found           = false;
      type            = PATTERN_NONE;
      direction       = 0;
      extreme         = 0.0;
      confluenceScore = 0.0;
      reason          = "";
      barTime         = 0;
   }
};

//+------------------------------------------------------------------+
//| CPatternManager Class — v2.02                                    |
//| Responsible for detecting candlestick patterns with regime filter|
//| v2.02 SPRINT 8 FIXES:                                            |
//|   BUG-014: Was plain class — not IManager, not on EventBus       |
//|            Now inherits IManager with full contract impl          |
//|   BUG-016: Detect() signature mismatch vs SignalManager           |
//|            Added 7-param adapter overload                        |
//+------------------------------------------------------------------+
class CPatternManager : public IManager
{
private:
   CArrayObj         m_patternHistory;     // History pola terdeteksi
   SPatternResult    m_lastResult;         // Cache hasil terakhir
   ulong             m_lastScanBarTime;    // Timestamp scan terakhir
   int               m_totalPatternsDetected;
   int               m_totalValidSignals;
   
   //--- Configuration
   double            m_minConfluenceScore;
   double            m_minDominanceGap;
   double            m_regimeBoostFactor;

public:
                     CPatternManager();
                    ~CPatternManager();

   //--- IManager contract (BUG-014 fix — Sprint 8)
   virtual bool      Initialize(CEventBus *bus, IDataManager *data) override;
   virtual void      DeclareEvents() override;
   virtual void      OnEvent(const PASREvent &ev) override;
   virtual string    HandlerName() const override { return "PatternManager"; }

   //--- Legacy plain init (backward compat — delegates to IManager version)
   bool              Initialize();
   void              Shutdown();

   //--- Main Detection Method (canonical — called by PipelineEngine Stage_PatternRec)
   bool              Detect(const MqlRates &rates[],
                            const int shift,
                            const double atrPoints,
                            const EMarketRegime currentRegime,
                            SPatternResult &outResult);

   //--- BUG-016 FIX: Adapter overload — bridges SignalManager.DetectSignalCore() call
   //    SignalManager calls: Detect(rates, shift, atr, pType, dir, price, reason)
   //    Maps to canonical 5-param version; regime defaults to REGIME_SIDEWAYS
   bool              Detect(const MqlRates &rates[],
                            const int shift,
                            const double atrPoints,
                            ENUM_PATTERN_TYPE &outType,
                            int &outDir,
                            double &outPrice,
                            string &outReason);

   //--- Statistics
   int               GetTotalDetected()     const { return m_totalPatternsDetected; }
   int               GetTotalValidSignals() const { return m_totalValidSignals; }
   double            GetSuccessRate()       const;
   
   //--- Cache Access
   const SPatternResult& GetLastResult() const { return m_lastResult; }

private:
   //--- Vote Management
   void              ResetVote(SPatternVote &v);
   int               FindBestVote(const SPatternVote &votes[], int dir);
   string            BuildConfluenceLabel(const SPatternVote &votes[], int dir);

   //--- Pattern Evaluators
   void              EvaluatePinbar(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateEngulfing(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateTweezer(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateFakey(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateInsideBar(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);

   //--- Helpers
   double            CandleOpen(const MqlRates &rates[], int shift) const;
   double            CandleHigh(const MqlRates &rates[], int shift) const;
   double            CandleLow(const MqlRates &rates[], int shift) const;
   double            CandleClose(const MqlRates &rates[], int shift) const;
   double            CandleRange(const MqlRates &rates[], int shift) const;
   double            CandleBody(const MqlRates &rates[], int shift) const;
   double            UpperWick(const MqlRates &rates[], int shift) const;
   double            LowerWick(const MqlRates &rates[], int shift) const;
   bool              IsBullish(const MqlRates &rates[], int shift) const;
   bool              IsBearish(const MqlRates &rates[], int shift) const;
   bool              IsInsideBar(const MqlRates &rates[], int shift) const;
   double            NormalizeATRFactor(const double value, const double atrPoints) const;
   
   //--- Scoring Enhancements
   void              AddStrengthFromRejection(const MqlRates &rates[], const int shift, const double atrPoints, const int dir, double &score);
   void              AddStrengthFromFollowThrough(const MqlRates &rates[], const int shift, const int dir, double &score);
   double            CalculateRegimeWeight(const EMarketRegime regime, ENUM_PATTERN_TYPE patternType, int direction) const;
   
   //--- Internal Utilities
   void              StorePatternHistory(const SPatternResult &result);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPatternManager::CPatternManager() : IManager(),
                                     m_lastScanBarTime(0),
                                     m_totalPatternsDetected(0),
                                     m_totalValidSignals(0),
                                     m_minConfluenceScore(1.60),
                                     m_minDominanceGap(0.35),
                                     m_regimeBoostFactor(0.20)
{
   m_patternHistory.Create();
   m_lastResult.Clear();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPatternManager::~CPatternManager()
{
   Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize — IManager contract (BUG-014 fix)                     |
//+------------------------------------------------------------------+
bool CPatternManager::Initialize(CEventBus *bus, IDataManager *data)
{
   m_bus  = bus;
   m_data = data;
   if(CheckPointer(m_bus) == POINTER_INVALID)
   {
      Print("[PatternManager] ERROR: EventBus is NULL — cannot subscribe");
      return false;
   }
   if(!m_bus.Subscribe(this))
   {
      Print("[PatternManager] ERROR: EventBus.Subscribe() failed");
      return false;
   }
   DeclareEvents();
   return Initialize();
}

//+------------------------------------------------------------------+
//| DeclareEvents — subscribe EVENT_ID_NEW_BAR (BUG-014 fix)        |
//+------------------------------------------------------------------+
void CPatternManager::DeclareEvents()
{
   AddEvent(EVENT_ID_NEW_BAR);        // Trigger cache invalidation on each new bar
   AddEvent(EVENT_ID_CONFIG_RELOAD);  // Refresh confluence thresholds
}

//+------------------------------------------------------------------+
//| OnEvent — EventBus dispatcher callback (BUG-014 fix)            |
//| Previously MISSING — pattern scan never triggered from pipeline  |
//+------------------------------------------------------------------+
void CPatternManager::OnEvent(const PASREvent &ev)
{
   switch(ev.id)
   {
      case EVENT_ID_NEW_BAR:
      {
         // Invalidate bar-scan cache so next Detect() call runs fresh
         // Actual Detect() is called by PipelineEngine.Stage_PatternRec()
         // which passes the rates[] array — we just reset the guard here
         m_lastScanBarTime = 0;
         if(m_cfgDirty && m_data != NULL) RefreshConfig();
         break;
      }
      case EVENT_ID_CONFIG_RELOAD:
      {
         m_cfgDirty = true;
         // Real threshold values would be read from m_cfg after RefreshConfig()
         break;
      }
      default: break;
   }
}

//+------------------------------------------------------------------+
//| Initialize — legacy plain init (no bus injection)                |
//+------------------------------------------------------------------+
bool CPatternManager::Initialize()
{
   m_patternHistory.Clear();
   m_lastResult.Clear();
   m_lastScanBarTime        = 0;
   m_totalPatternsDetected  = 0;
   m_totalValidSignals      = 0;
   Print("[PatternManager] v2.02 Initialized (IManager-aware)");
   return true;
}

//+------------------------------------------------------------------+
//| Shutdown Manager                                                 |
//+------------------------------------------------------------------+
void CPatternManager::Shutdown()
{
   m_patternHistory.Clear();
   Print("[PatternManager] Shutdown complete");
}

//+------------------------------------------------------------------+
//| Main Detection Method with Regime Filter (canonical 5-param)    |
//+------------------------------------------------------------------+
bool CPatternManager::Detect(const MqlRates &rates[],
                             const int shift,
                             const double atrPoints,
                             const EMarketRegime currentRegime,
                             SPatternResult &outResult)
{
   outResult.Clear();
   
   if(shift < 1 || atrPoints <= 0.0)
   {
      outResult.reason = "Invalid shift/ATR";
      return false;
   }

   if(shift + 2 >= ArraySize(rates))
   {
      outResult.reason = "Insufficient bar history";
      return false;
   }

   ulong currentBarTime = rates[shift].time;
   if(currentBarTime == m_lastScanBarTime && m_lastResult.found)
   {
      outResult = m_lastResult;
      return outResult.found;
   }

   SPatternVote votes[5];
   for(int i = 0; i < 5; i++)
      votes[i].Reset();

   EvaluatePinbar(rates, shift, atrPoints, votes[0]);
   EvaluateEngulfing(rates, shift, atrPoints, votes[1]);
   EvaluateTweezer(rates, shift, atrPoints, votes[2]);
   EvaluateFakey(rates, shift, atrPoints, votes[3]);
   EvaluateInsideBar(rates, shift, atrPoints, votes[4]);

   for(int i = 0; i < 5; i++)
   {
      if(votes[i].valid)
         votes[i].regimeWeight = CalculateRegimeWeight(currentRegime, votes[i].type, votes[i].dir);
   }

   double buyScore = 0.0, sellScore = 0.0;
   for(int i = 0; i < 5; i++)
   {
      if(!votes[i].valid) continue;
      double ts = votes[i].TotalScore();
      if(votes[i].dir == 1)       buyScore  += ts;
      else if(votes[i].dir == -1) sellScore += ts;
   }

   double totalScore   = MathMax(buyScore, sellScore);
   double conflictScore = MathMin(buyScore, sellScore);
   double dominanceGap  = totalScore - conflictScore;

   if(totalScore < m_minConfluenceScore)
   {
      outResult.reason = StringFormat("Confluence weak | buy=%.2f sell=%.2f", buyScore, sellScore);
      m_lastScanBarTime = currentBarTime;
      m_lastResult = outResult;
      m_totalPatternsDetected++;
      return false;
   }

   if(dominanceGap < m_minDominanceGap)
   {
      outResult.reason = StringFormat("Confluence conflict | buy=%.2f sell=%.2f", buyScore, sellScore);
      m_lastScanBarTime = currentBarTime;
      m_lastResult = outResult;
      m_totalPatternsDetected++;
      return false;
   }

   int direction = (buyScore > sellScore) ? 1 : -1;
   int bestIdx   = FindBestVote(votes, direction);
   if(bestIdx < 0)
   {
      outResult.reason = "No dominant directional pattern";
      m_lastScanBarTime = currentBarTime;
      m_lastResult = outResult;
      m_totalPatternsDetected++;
      return false;
   }

   outResult.found           = true;
   outResult.type            = votes[bestIdx].type;
   outResult.direction       = direction;
   outResult.extreme         = votes[bestIdx].extreme;
   outResult.confluenceScore = totalScore;
   outResult.barTime         = currentBarTime;
   outResult.reason          = votes[bestIdx].label +
                               StringFormat(" | Confluence %.2f | %s",
                                            totalScore,
                                            BuildConfluenceLabel(votes, direction));

   m_lastScanBarTime = currentBarTime;
   m_lastResult      = outResult;
   m_totalPatternsDetected++;
   m_totalValidSignals++;
   StorePatternHistory(outResult);
   return true;
}

//+------------------------------------------------------------------+
//| BUG-016 FIX: Adapter overload (7-param → 5-param canonical)     |
//| SignalManager.DetectSignalCore() calls:                          |
//|   m_pattern.Detect(rates, shift, atr, pType, dir, price, reason) |
//| This bridges the call to the canonical Detect() signature.       |
//| Regime defaults to REGIME_SIDEWAYS (safe neutral weight).        |
//+------------------------------------------------------------------+
bool CPatternManager::Detect(const MqlRates &rates[],
                             const int shift,
                             const double atrPoints,
                             ENUM_PATTERN_TYPE &outType,
                             int &outDir,
                             double &outPrice,
                             string &outReason)
{
   // Use REGIME_SIDEWAYS as safe default — no regime context available here
   // PipelineEngine.Stage_PatternRec() uses the full 5-param version with real regime
   EMarketRegime regime = REGIME_SIDEWAYS;

   SPatternResult result;
   bool found = Detect(rates, shift, atrPoints, regime, result);

   outType   = result.type;
   outDir    = result.direction;
   outPrice  = result.extreme;
   outReason = result.reason;
   return found;
}

//+------------------------------------------------------------------+
//| Get Success Rate                                                 |
//+------------------------------------------------------------------+
double CPatternManager::GetSuccessRate() const
{
   if(m_totalPatternsDetected == 0) return 0.0;
   return (double)m_totalValidSignals / (double)m_totalPatternsDetected * 100.0;
}

void CPatternManager::ResetVote(SPatternVote &v) { v.valid=false; v.type=PATTERN_NONE; v.dir=0; v.extreme=0.0; v.score=0.0; v.regimeWeight=1.0; v.label=""; }

int CPatternManager::FindBestVote(const SPatternVote &votes[], int dir)
{
   int best=-1; double bestScore=0.0;
   for(int i=0;i<ArraySize(votes);i++)
   {
      if(!votes[i].valid || votes[i].dir!=dir) continue;
      double ts=votes[i].TotalScore();
      if(ts>bestScore){bestScore=ts;best=i;}
   }
   return best;
}

string CPatternManager::BuildConfluenceLabel(const SPatternVote &votes[], int dir)
{
   string txt="";
   for(int i=0;i<ArraySize(votes);i++)
   {
      if(!votes[i].valid||votes[i].dir!=dir) continue;
      if(txt!="") txt+=" + ";
      txt+=votes[i].label;
   }
   return txt;
}

double CPatternManager::CandleOpen(const MqlRates &rates[], int shift)  const { return rates[shift].open;  }
double CPatternManager::CandleHigh(const MqlRates &rates[], int shift)  const { return rates[shift].high;  }
double CPatternManager::CandleLow(const MqlRates &rates[], int shift)   const { return rates[shift].low;   }
double CPatternManager::CandleClose(const MqlRates &rates[], int shift) const { return rates[shift].close; }
double CPatternManager::CandleRange(const MqlRates &rates[], int shift) const { return CandleHigh(rates,shift)-CandleLow(rates,shift); }
double CPatternManager::CandleBody(const MqlRates &rates[], int shift)  const { return MathAbs(CandleClose(rates,shift)-CandleOpen(rates,shift)); }
double CPatternManager::UpperWick(const MqlRates &rates[], int shift)   const { return CandleHigh(rates,shift)-MathMax(CandleOpen(rates,shift),CandleClose(rates,shift)); }
double CPatternManager::LowerWick(const MqlRates &rates[], int shift)   const { return MathMin(CandleOpen(rates,shift),CandleClose(rates,shift))-CandleLow(rates,shift); }
bool   CPatternManager::IsBullish(const MqlRates &rates[], int shift)   const { return CandleClose(rates,shift)>CandleOpen(rates,shift); }
bool   CPatternManager::IsBearish(const MqlRates &rates[], int shift)   const { return CandleClose(rates,shift)<CandleOpen(rates,shift); }
bool   CPatternManager::IsInsideBar(const MqlRates &rates[], int shift) const
{
   return CandleHigh(rates,shift)<CandleHigh(rates,shift+1) &&
          CandleLow(rates,shift)>CandleLow(rates,shift+1);
}
double CPatternManager::NormalizeATRFactor(const double value, const double atrPoints) const
{
   double atrPrice=atrPoints*_Point;
   if(atrPrice<=0.0) return 0.0;
   return value/atrPrice;
}

void CPatternManager::AddStrengthFromRejection(const MqlRates &rates[], const int shift, const double atrPoints, const int dir, double &score)
{
   double range=CandleRange(rates,shift);
   if(range<=0.0) return;
   double majorWick=(dir==1)?LowerWick(rates,shift):UpperWick(rates,shift);
   double wickPct=majorWick/range;
   double bodyPct=CandleBody(rates,shift)/range;
   double atrFactor=NormalizeATRFactor(range,atrPoints);
   if(wickPct>=0.50) score+=0.20;
   if(wickPct>=0.60) score+=0.10;
   if(bodyPct<=0.35) score+=0.10;
   if(atrFactor>=0.60) score+=0.10;
}

void CPatternManager::AddStrengthFromFollowThrough(const MqlRates &rates[], const int shift, const int dir, double &score)
{
   double prevClose=CandleClose(rates,shift+1);
   double curClose=CandleClose(rates,shift);
   if(dir==1 && curClose>prevClose) score+=0.10;
   if(dir==-1 && curClose<prevClose) score+=0.10;
}

double CPatternManager::CalculateRegimeWeight(const EMarketRegime regime, ENUM_PATTERN_TYPE patternType, int direction) const
{
   double weight=1.0;
   if(regime==REGIME_SIDEWAYS||regime==REGIME_CONSOLIDATION)
   {
      if(patternType==PATTERN_PINBAR||patternType==PATTERN_ENGULFING||patternType==PATTERN_FAKEY)
         weight+=m_regimeBoostFactor;
   }
   if(regime==REGIME_TREND_UP||regime==REGIME_TREND_DOWN)
   {
      if(patternType==PATTERN_INSIDE_BAR_BREAKOUT) weight+=m_regimeBoostFactor;
      if((regime==REGIME_TREND_UP&&direction==1)||(regime==REGIME_TREND_DOWN&&direction==-1))
         weight+=m_regimeBoostFactor*0.5;
   }
   if(regime==REGIME_HIGH_VOLATILITY||regime==REGIME_CRASH) weight-=0.15;
   return MathMax(0.5,weight);
}

void CPatternManager::EvaluatePinbar(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote)
{
   double range=CandleRange(rates,shift);
   if(range<=0.0) return;
   double bodyMid=(CandleOpen(rates,shift)+CandleClose(rates,shift))/2.0;
   double upper=UpperWick(rates,shift);
   double lower=LowerWick(rates,shift);
   int dir=0; double extreme=0.0;
   if(CandleClose(rates,shift)>bodyMid && lower>(upper>0?upper*2.0:_Point))
      { dir=1; extreme=CandleLow(rates,shift); }
   else if(CandleClose(rates,shift)<bodyMid && upper>(lower>0?lower*2.0:_Point))
      { dir=-1; extreme=CandleHigh(rates,shift); }
   else return;
   vote.valid=true; vote.type=PATTERN_PINBAR; vote.dir=dir; vote.extreme=extreme;
   vote.score=1.00; vote.label=(dir==1)?"Pinbar Bull":"Pinbar Bear";
   AddStrengthFromRejection(rates,shift,atrPoints,dir,vote.score);
   AddStrengthFromFollowThrough(rates,shift,dir,vote.score);
}

void CPatternManager::EvaluateEngulfing(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote)
{
   double o1=CandleOpen(rates,shift),c1=CandleClose(rates,shift);
   double o2=CandleOpen(rates,shift+1),c2=CandleClose(rates,shift+1);
   bool prevBearish=c2<o2; bool prevBullish=c2>o2;
   int dir=0; double extreme=0.0; double score=1.00;
   if(prevBearish&&c1>o1&&c1>o2&&o1<c2)      { dir=1;  extreme=CandleLow(rates,shift); }
   else if(prevBullish&&c1<o1&&c1<o2&&o1>c2) { dir=-1; extreme=CandleHigh(rates,shift); }
   else return;
   double body1=CandleBody(rates,shift),body2=CandleBody(rates,shift+1);
   if(body2>0.0&&body1>=body2*1.20) score+=0.20;
   if(NormalizeATRFactor(CandleRange(rates,shift),atrPoints)>=0.70) score+=0.15;
   vote.valid=true; vote.type=PATTERN_ENGULFING; vote.dir=dir; vote.extreme=extreme;
   vote.score=score; vote.label=(dir==1)?"Engulf Bull":"Engulf Bear";
   AddStrengthFromFollowThrough(rates,shift,dir,vote.score);
}

void CPatternManager::EvaluateTweezer(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote)
{
   double h1=CandleHigh(rates,shift),l1=CandleLow(rates,shift);
   double h2=CandleHigh(rates,shift+1),l2=CandleLow(rates,shift+1);
   double tol=MathMax(atrPoints*0.10*_Point,3*_Point);
   int dir=0; double extreme=0.0; double score=1.00;
   if(MathAbs(l1-l2)<=tol&&IsBullish(rates,shift))      { dir=1;  extreme=MathMin(l1,l2); }
   else if(MathAbs(h1-h2)<=tol&&IsBearish(rates,shift)) { dir=-1; extreme=MathMax(h1,h2); }
   else return;
   if(NormalizeATRFactor(CandleRange(rates,shift),atrPoints)>=0.50) score+=0.10;
   if(CandleBody(rates,shift)/MathMax(CandleRange(rates,shift),_Point)>=0.35) score+=0.10;
   vote.valid=true; vote.type=PATTERN_BOTTOM; vote.dir=dir; vote.extreme=extreme;
   vote.score=score; vote.label=(dir==1)?"Tweezer Bottom":"Tweezer Top";
}

void CPatternManager::EvaluateFakey(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote)
{
   double h0=CandleHigh(rates,shift),l0=CandleLow(rates,shift);
   double c0=CandleClose(rates,shift),o0=CandleOpen(rates,shift);
   double h1=CandleHigh(rates,shift+1),l1=CandleLow(rates,shift+1);
   double h2=CandleHigh(rates,shift+2),l2=CandleLow(rates,shift+2);
   bool insideStructure=(h1<h2&&l1>l2);
   if(!insideStructure) return;
   int dir=0; double extreme=0.0; double score=1.00;
   if(l0<l1&&c0>l1&&c0>o0)      { dir=1;  extreme=l0; }
   else if(h0>h1&&c0<h1&&c0<o0) { dir=-1; extreme=h0; }
   else return;
   if(NormalizeATRFactor(CandleRange(rates,shift),atrPoints)>=0.60) score+=0.15;
   if(CandleBody(rates,shift)/MathMax(CandleRange(rates,shift),_Point)>=0.40) score+=0.10;
   vote.valid=true; vote.type=PATTERN_FAKEY; vote.dir=dir; vote.extreme=extreme;
   vote.score=score; vote.label=(dir==1)?"Fakey Bull":"Fakey Bear";
}

void CPatternManager::EvaluateInsideBar(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote)
{
   if(!IsInsideBar(rates,shift)) return;
   double motherHigh=CandleHigh(rates,shift+1),motherLow=CandleLow(rates,shift+1);
   double motherMid=(motherHigh+motherLow)/2.0;
   double childClose=CandleClose(rates,shift);
   int dir=0; double extreme=0.0; double score=1.00;
   if(childClose>motherMid)      { dir=1;  extreme=CandleLow(rates,shift); }
   else if(childClose<motherMid) { dir=-1; extreme=CandleHigh(rates,shift); }
   else return;
   double motherRange=CandleRange(rates,shift+1);
   double childRange=CandleRange(rates,shift);
   if(motherRange>0.0&&childRange/motherRange<=0.65) score+=0.15;
   if(NormalizeATRFactor(motherRange,atrPoints)>=0.70) score+=0.10;
   vote.valid=true; vote.type=PATTERN_INSIDE_BAR_BREAKOUT; vote.dir=dir; vote.extreme=extreme;
   vote.score=score; vote.label=(dir==1)?"Inside Bull":"Inside Bear";
}

void CPatternManager::StorePatternHistory(const SPatternResult &result)
{
   if(m_patternHistory.Total()>=100)
      m_patternHistory.Delete(0);
   // History tracking by count; full SPatternResult objects
   // would require a wrapper CObject — kept lightweight for now
}

#endif // __PATTERN_MANAGER_MQH__
