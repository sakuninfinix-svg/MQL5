//+------------------------------------------------------------------+
//| PatternManager.mqh                                               |
//| Copyright 2026, Agsicentre                                       |
//| Refactored for PASR v2.02 Architecture (Sprint 9 History fix)   |
//+------------------------------------------------------------------+
//| CHANGELOG:                                                       |
//|  v2.03 (2026-05-23) — Sprint 9 fixes:                           |
//|    BUG-017: StorePatternHistory() was no-op (empty body).        |
//|             Added CPatternRecord CObject wrapper so history is   |
//|             actually stored in m_patternHistory CArrayObj.       |
//|    BUG-018: Adapter overload REGIME_SIDEWAYS cast documented;    |
//|             EMarketRegime cast is safe — enum cast to int is ok. |
//|    BUG-019: GetHistoryCount()/GetHistoryAt() accessor added so   |
//|             PipelineEngine can read pattern history for scoring.  |
//+------------------------------------------------------------------+
#ifndef __PATTERN_MANAGER_MQH__
#define __PATTERN_MANAGER_MQH__

#property strict

//--- Include dependencies
#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"
#include "../Analysis/MarketRegimeDetector.mqh"
#include "PatternTypes.mqh"
#include <Arrays/ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Pattern Vote Structure                                           |
//+------------------------------------------------------------------+
struct SPatternVote
{
   bool              valid;
   ENUM_PATTERN_TYPE type;
   int               dir;
   double            extreme;
   double            score;
   double            regimeWeight;
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
//| BUG-017 FIX: CObject wrapper for heap-storing SPatternResult     |
//| Previously StorePatternHistory() was a no-op — CArrayObj needs  |
//| CObject-derived items; plain structs cannot be stored directly.  |
//+------------------------------------------------------------------+
class CPatternRecord : public CObject
{
public:
   SPatternResult    data;
   explicit CPatternRecord(const SPatternResult &r) { data = r; }
};

//+------------------------------------------------------------------+
//| CPatternManager Class — v2.03                                    |
//+------------------------------------------------------------------+
class CPatternManager : public IManager
{
private:
   CArrayObj         m_patternHistory;
   SPatternResult    m_lastResult;
   ulong             m_lastScanBarTime;
   int               m_totalPatternsDetected;
   int               m_totalValidSignals;

   double            m_minConfluenceScore;
   double            m_minDominanceGap;
   double            m_regimeBoostFactor;

public:
                     CPatternManager();
                    ~CPatternManager();

   //--- IManager contract
   virtual bool      Initialize(CEventBus *bus, IDataManager *data) override;
   virtual void      DeclareEvents() override;
   virtual void      OnEvent(const PASREvent &ev) override;
   virtual string    HandlerName() const override { return "PatternManager"; }

   bool              Initialize();
   void              Shutdown();

   //--- Main Detection (canonical 5-param)
   bool              Detect(const MqlRates &rates[],
                            const int shift,
                            const double atrPoints,
                            const EMarketRegime currentRegime,
                            SPatternResult &outResult);

   //--- BUG-016 FIX: Adapter overload (7-param → 5-param)
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
   const SPatternResult& GetLastResult()   const { return m_lastResult; }

   //--- BUG-019 FIX: History accessors for PipelineEngine scoring
   int               GetHistoryCount()     const { return m_patternHistory.Total(); }
   bool              GetHistoryAt(int idx, SPatternResult &out) const;

private:
   void              ResetVote(SPatternVote &v);
   int               FindBestVote(const SPatternVote &votes[], int dir);
   string            BuildConfluenceLabel(const SPatternVote &votes[], int dir);

   void              EvaluatePinbar(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateEngulfing(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateTweezer(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateFakey(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);
   void              EvaluateInsideBar(const MqlRates &rates[], const int shift, const double atrPoints, SPatternVote &vote);

   double            CandleOpen(const MqlRates &r[], int s)   const { return r[s].open;  }
   double            CandleHigh(const MqlRates &r[], int s)   const { return r[s].high;  }
   double            CandleLow(const MqlRates &r[], int s)    const { return r[s].low;   }
   double            CandleClose(const MqlRates &r[], int s)  const { return r[s].close; }
   double            CandleRange(const MqlRates &r[], int s)  const { return CandleHigh(r,s)-CandleLow(r,s); }
   double            CandleBody(const MqlRates &r[], int s)   const { return MathAbs(CandleClose(r,s)-CandleOpen(r,s)); }
   double            UpperWick(const MqlRates &r[], int s)    const { return CandleHigh(r,s)-MathMax(CandleOpen(r,s),CandleClose(r,s)); }
   double            LowerWick(const MqlRates &r[], int s)    const { return MathMin(CandleOpen(r,s),CandleClose(r,s))-CandleLow(r,s); }
   bool              IsBullish(const MqlRates &r[], int s)    const { return CandleClose(r,s)>CandleOpen(r,s); }
   bool              IsBearish(const MqlRates &r[], int s)    const { return CandleClose(r,s)<CandleOpen(r,s); }
   bool              IsInsideBar(const MqlRates &r[], int s)  const
                        { return CandleHigh(r,s)<CandleHigh(r,s+1) && CandleLow(r,s)>CandleLow(r,s+1); }
   double            NormalizeATRFactor(const double v, const double atr) const
                        { double ap=atr*_Point; return(ap<=0.0)?0.0:v/ap; }

   void              AddStrengthFromRejection(const MqlRates &r[], int s, double atr, int dir, double &score);
   void              AddStrengthFromFollowThrough(const MqlRates &r[], int s, int dir, double &score);
   double            CalculateRegimeWeight(const EMarketRegime regime, ENUM_PATTERN_TYPE pt, int dir) const;

   //--- BUG-017 FIX: real heap-store implementation
   void              StorePatternHistory(const SPatternResult &result);
};

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

CPatternManager::~CPatternManager() { Shutdown(); }

bool CPatternManager::Initialize(CEventBus *bus, IDataManager *data)
{
   m_bus  = bus;
   m_data = data;
   if(CheckPointer(m_bus)==POINTER_INVALID)
      { Print("[PatternManager] ERROR: EventBus NULL"); return false; }
   if(!m_bus.Subscribe(this))
      { Print("[PatternManager] ERROR: Subscribe failed"); return false; }
   DeclareEvents();
   return Initialize();
}

void CPatternManager::DeclareEvents()
{
   AddEvent(EVENT_ID_NEW_BAR);
   AddEvent(EVENT_ID_CONFIG_RELOAD);
}

void CPatternManager::OnEvent(const PASREvent &ev)
{
   switch(ev.id)
   {
      case EVENT_ID_NEW_BAR:
         m_lastScanBarTime = 0;
         if(m_cfgDirty && m_data!=NULL) RefreshConfig();
         break;
      case EVENT_ID_CONFIG_RELOAD:
         m_cfgDirty = true;
         break;
      default: break;
   }
}

bool CPatternManager::Initialize()
{
   m_patternHistory.Clear();
   m_lastResult.Clear();
   m_lastScanBarTime       = 0;
   m_totalPatternsDetected = 0;
   m_totalValidSignals     = 0;
   Print("[PatternManager] v2.03 Initialized");
   return true;
}

void CPatternManager::Shutdown()
{
   m_patternHistory.Clear();
   Print("[PatternManager] Shutdown");
}

//+------------------------------------------------------------------+
//| BUG-019 FIX: GetHistoryAt accessor                              |
//+------------------------------------------------------------------+
bool CPatternManager::GetHistoryAt(int idx, SPatternResult &out) const
{
   if(idx<0 || idx>=m_patternHistory.Total()) return false;
   CPatternRecord *rec = (CPatternRecord*)m_patternHistory.At(idx);
   if(CheckPointer(rec)==POINTER_INVALID) return false;
   out = rec.data;
   return true;
}

bool CPatternManager::Detect(const MqlRates &rates[],
                              const int shift,
                              const double atrPoints,
                              const EMarketRegime currentRegime,
                              SPatternResult &outResult)
{
   outResult.Clear();
   if(shift<1 || atrPoints<=0.0)           { outResult.reason="Invalid shift/ATR"; return false; }
   if(shift+2>=ArraySize(rates))           { outResult.reason="Insufficient bars"; return false; }

   ulong curTime=rates[shift].time;
   if(curTime==m_lastScanBarTime && m_lastResult.found) { outResult=m_lastResult; return outResult.found; }

   SPatternVote votes[5];
   for(int i=0;i<5;i++) votes[i].Reset();
   EvaluatePinbar(rates,shift,atrPoints,votes[0]);
   EvaluateEngulfing(rates,shift,atrPoints,votes[1]);
   EvaluateTweezer(rates,shift,atrPoints,votes[2]);
   EvaluateFakey(rates,shift,atrPoints,votes[3]);
   EvaluateInsideBar(rates,shift,atrPoints,votes[4]);

   for(int i=0;i<5;i++)
      if(votes[i].valid)
         votes[i].regimeWeight=CalculateRegimeWeight(currentRegime,votes[i].type,votes[i].dir);

   double buyScore=0,sellScore=0;
   for(int i=0;i<5;i++)
   {
      if(!votes[i].valid) continue;
      double ts=votes[i].TotalScore();
      if(votes[i].dir==1) buyScore+=ts; else if(votes[i].dir==-1) sellScore+=ts;
   }

   double totalScore=MathMax(buyScore,sellScore);
   double conflictScore=MathMin(buyScore,sellScore);
   double dominanceGap=totalScore-conflictScore;

   m_totalPatternsDetected++;
   m_lastScanBarTime=curTime;

   if(totalScore<m_minConfluenceScore)
   {
      outResult.reason=StringFormat("Confluence weak | buy=%.2f sell=%.2f",buyScore,sellScore);
      m_lastResult=outResult; return false;
   }
   if(dominanceGap<m_minDominanceGap)
   {
      outResult.reason=StringFormat("Confluence conflict | buy=%.2f sell=%.2f",buyScore,sellScore);
      m_lastResult=outResult; return false;
   }

   int direction=(buyScore>sellScore)?1:-1;
   int bestIdx=FindBestVote(votes,direction);
   if(bestIdx<0)
   {
      outResult.reason="No dominant pattern"; m_lastResult=outResult; return false;
   }

   outResult.found=true;
   outResult.type=votes[bestIdx].type;
   outResult.direction=direction;
   outResult.extreme=votes[bestIdx].extreme;
   outResult.confluenceScore=totalScore;
   outResult.barTime=curTime;
   outResult.reason=votes[bestIdx].label+StringFormat(" | Confluence %.2f | %s",
                     totalScore,BuildConfluenceLabel(votes,direction));

   m_lastResult=outResult;
   m_totalValidSignals++;
   StorePatternHistory(outResult);
   return true;
}

//+------------------------------------------------------------------+
//| BUG-016 FIX: Adapter overload                                    |
//+------------------------------------------------------------------+
bool CPatternManager::Detect(const MqlRates &rates[], const int shift, const double atrPoints,
                              ENUM_PATTERN_TYPE &outType, int &outDir, double &outPrice, string &outReason)
{
   // Safe default: REGIME_SIDEWAYS = no directional regime bias applied
   // Cast is compile-safe — EMarketRegime is a plain enum (int-based)
   SPatternResult result;
   bool found=Detect(rates,shift,atrPoints,(EMarketRegime)REGIME_SIDEWAYS,result);
   outType=result.type; outDir=result.direction;
   outPrice=result.extreme; outReason=result.reason;
   return found;
}

double CPatternManager::GetSuccessRate() const
{
   if(m_totalPatternsDetected==0) return 0.0;
   return (double)m_totalValidSignals/(double)m_totalPatternsDetected*100.0;
}

void CPatternManager::ResetVote(SPatternVote &v){v.valid=false;v.type=PATTERN_NONE;v.dir=0;v.extreme=0;v.score=0;v.regimeWeight=1.0;v.label="";}

int CPatternManager::FindBestVote(const SPatternVote &votes[], int dir)
{
   int best=-1; double bs=0;
   for(int i=0;i<ArraySize(votes);i++)
   {
      if(!votes[i].valid||votes[i].dir!=dir) continue;
      double ts=votes[i].TotalScore();
      if(ts>bs){bs=ts;best=i;}
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

//+------------------------------------------------------------------+
//| BUG-017 FIX: StorePatternHistory — real heap-store implementation|
//| Previously was empty body (no-op). Now allocates CPatternRecord  |
//| on heap and appends to CArrayObj. Caps at 200 entries (FIFO).    |
//+------------------------------------------------------------------+
void CPatternManager::StorePatternHistory(const SPatternResult &result)
{
   //--- Enforce FIFO cap of 200 bars
   if(m_patternHistory.Total()>=200)
   {
      m_patternHistory.Delete(0); // remove oldest
   }
   CPatternRecord *rec = new CPatternRecord(result);
   if(CheckPointer(rec)!=POINTER_INVALID)
      m_patternHistory.Add(rec);
}

void CPatternManager::AddStrengthFromRejection(const MqlRates &r[], const int s, const double atr, const int dir, double &score)
{
   double range=CandleRange(r,s);
   if(range<=0.0) return;
   double mw=(dir==1)?LowerWick(r,s):UpperWick(r,s);
   double wp=mw/range; double bp=CandleBody(r,s)/range;
   double af=NormalizeATRFactor(range,atr);
   if(wp>=0.50) score+=0.20;
   if(wp>=0.60) score+=0.10;
   if(bp<=0.35) score+=0.10;
   if(af>=0.60) score+=0.10;
}

void CPatternManager::AddStrengthFromFollowThrough(const MqlRates &r[], const int s, const int dir, double &score)
{
   double pc=CandleClose(r,s+1),cc=CandleClose(r,s);
   if(dir==1&&cc>pc) score+=0.10;
   if(dir==-1&&cc<pc) score+=0.10;
}

double CPatternManager::CalculateRegimeWeight(const EMarketRegime regime, ENUM_PATTERN_TYPE pt, int dir) const
{
   double w=1.0;
   if(regime==REGIME_SIDEWAYS||regime==REGIME_CONSOLIDATION)
      if(pt==PATTERN_PINBAR||pt==PATTERN_ENGULFING||pt==PATTERN_FAKEY) w+=m_regimeBoostFactor;
   if(regime==REGIME_TREND_UP||regime==REGIME_TREND_DOWN)
   {
      if(pt==PATTERN_INSIDE_BAR_BREAKOUT) w+=m_regimeBoostFactor;
      if((regime==REGIME_TREND_UP&&dir==1)||(regime==REGIME_TREND_DOWN&&dir==-1)) w+=m_regimeBoostFactor*0.5;
   }
   if(regime==REGIME_HIGH_VOLATILITY||regime==REGIME_CRASH) w-=0.15;
   return MathMax(0.5,w);
}

void CPatternManager::EvaluatePinbar(const MqlRates &r[], const int s, const double atr, SPatternVote &vote)
{
   double range=CandleRange(r,s); if(range<=0.0) return;
   double bm=(CandleOpen(r,s)+CandleClose(r,s))/2.0;
   double up=UpperWick(r,s),lw=LowerWick(r,s);
   int dir=0; double extreme=0;
   if(CandleClose(r,s)>bm&&lw>(up>0?up*2.0:_Point)){dir=1;extreme=CandleLow(r,s);}
   else if(CandleClose(r,s)<bm&&up>(lw>0?lw*2.0:_Point)){dir=-1;extreme=CandleHigh(r,s);}
   else return;
   vote.valid=true;vote.type=PATTERN_PINBAR;vote.dir=dir;vote.extreme=extreme;
   vote.score=1.00;vote.label=(dir==1)?"Pinbar Bull":"Pinbar Bear";
   AddStrengthFromRejection(r,s,atr,dir,vote.score);
   AddStrengthFromFollowThrough(r,s,dir,vote.score);
}

void CPatternManager::EvaluateEngulfing(const MqlRates &r[], const int s, const double atr, SPatternVote &vote)
{
   double o1=CandleOpen(r,s),c1=CandleClose(r,s),o2=CandleOpen(r,s+1),c2=CandleClose(r,s+1);
   bool pb=(c2<o2),pub=(c2>o2); int dir=0; double extreme=0,score=1.0;
   if(pb&&c1>o1&&c1>o2&&o1<c2){dir=1;extreme=CandleLow(r,s);}
   else if(pub&&c1<o1&&c1<o2&&o1>c2){dir=-1;extreme=CandleHigh(r,s);}
   else return;
   double b1=CandleBody(r,s),b2=CandleBody(r,s+1);
   if(b2>0&&b1>=b2*1.20) score+=0.20;
   if(NormalizeATRFactor(CandleRange(r,s),atr)>=0.70) score+=0.15;
   vote.valid=true;vote.type=PATTERN_ENGULFING;vote.dir=dir;vote.extreme=extreme;
   vote.score=score;vote.label=(dir==1)?"Engulf Bull":"Engulf Bear";
   AddStrengthFromFollowThrough(r,s,dir,vote.score);
}

void CPatternManager::EvaluateTweezer(const MqlRates &r[], const int s, const double atr, SPatternVote &vote)
{
   double h1=CandleHigh(r,s),l1=CandleLow(r,s),h2=CandleHigh(r,s+1),l2=CandleLow(r,s+1);
   double tol=MathMax(atr*0.10*_Point,3*_Point);
   int dir=0; double extreme=0,score=1.0;
   if(MathAbs(l1-l2)<=tol&&IsBullish(r,s)){dir=1;extreme=MathMin(l1,l2);}
   else if(MathAbs(h1-h2)<=tol&&IsBearish(r,s)){dir=-1;extreme=MathMax(h1,h2);}
   else return;
   if(NormalizeATRFactor(CandleRange(r,s),atr)>=0.50) score+=0.10;
   if(CandleBody(r,s)/MathMax(CandleRange(r,s),_Point)>=0.35) score+=0.10;
   vote.valid=true;vote.type=PATTERN_BOTTOM;vote.dir=dir;vote.extreme=extreme;
   vote.score=score;vote.label=(dir==1)?"Tweezer Bottom":"Tweezer Top";
}

void CPatternManager::EvaluateFakey(const MqlRates &r[], const int s, const double atr, SPatternVote &vote)
{
   double h0=CandleHigh(r,s),l0=CandleLow(r,s),c0=CandleClose(r,s),o0=CandleOpen(r,s);
   double h1=CandleHigh(r,s+1),l1=CandleLow(r,s+1),h2=CandleHigh(r,s+2),l2=CandleLow(r,s+2);
   if(!(h1<h2&&l1>l2)) return;
   int dir=0; double extreme=0,score=1.0;
   if(l0<l1&&c0>l1&&c0>o0){dir=1;extreme=l0;}
   else if(h0>h1&&c0<h1&&c0<o0){dir=-1;extreme=h0;}
   else return;
   if(NormalizeATRFactor(CandleRange(r,s),atr)>=0.60) score+=0.15;
   if(CandleBody(r,s)/MathMax(CandleRange(r,s),_Point)>=0.40) score+=0.10;
   vote.valid=true;vote.type=PATTERN_FAKEY;vote.dir=dir;vote.extreme=extreme;
   vote.score=score;vote.label=(dir==1)?"Fakey Bull":"Fakey Bear";
}

void CPatternManager::EvaluateInsideBar(const MqlRates &r[], const int s, const double atr, SPatternVote &vote)
{
   if(!IsInsideBar(r,s)) return;
   double mh=CandleHigh(r,s+1),ml=CandleLow(r,s+1),mm=(mh+ml)/2.0;
   double cc=CandleClose(r,s);
   int dir=0; double extreme=0,score=1.0;
   if(cc>mm){dir=1;extreme=CandleLow(r,s);}
   else if(cc<mm){dir=-1;extreme=CandleHigh(r,s);}
   else return;
   double mr=CandleRange(r,s+1),cr=CandleRange(r,s);
   if(mr>0&&cr/mr<=0.65) score+=0.15;
   if(NormalizeATRFactor(mr,atr)>=0.70) score+=0.10;
   vote.valid=true;vote.type=PATTERN_INSIDE_BAR_BREAKOUT;vote.dir=dir;vote.extreme=extreme;
   vote.score=score;vote.label=(dir==1)?"Inside Bull":"Inside Bear";
}

#endif // __PATTERN_MANAGER_MQH__
