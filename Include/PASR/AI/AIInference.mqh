//+------------------------------------------------------------------+
//| AI/AIInference.mqh                                               |
//| Expert routing + MLP forward pass for PASR AI subsystem          |
//| Sprint 10: Path fix ../Core/ -> ../../Core/                      |
//|            Path fix ../Data/ -> ../../Data/                      |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_INFERENCE_MQH__
#define __AI_INFERENCE_MQH__

#include "AITypes.mqh"
#include "../../Core/IManager.mqh"
#include "../../Data/RegimeTypes.mqh"

//--- Minimal MLP layer descriptor
struct SMLPLayer
{
   double weights[][];  // [in x out]
   double biases[];     // [out]
   bool   relu;         // use ReLU activation?
   int    in_size;
   int    out_size;
};

//+------------------------------------------------------------------+
//| CAIInference                                                     |
//| Lightweight MLP inference engine                                 |
//| Architecture: 26 -> 64 -> 32 -> 1 (tanh output)                 |
//+------------------------------------------------------------------+
class CAIInference : public IManager
{
private:
   bool     m_loaded;
   string   m_model_id;
   int      m_n_layers;
   
   // Simple 3-layer MLP weights (randomised at init if no model file)
   double   m_w1[][64];    // 26 x 64
   double   m_b1[64];
   double   m_w2[64][32];  // 64 x 32
   double   m_b2[32];
   double   m_w3[32];      // 32 x 1
   double   m_b3;
   
   double ReLU(double x)    { return MathMax(0.0, x); }
   double Tanh(double x)    { return (MathExp(2.0*x)-1.0)/(MathExp(2.0*x)+1.0); }
   double Sigmoid(double x) { return 1.0/(1.0+MathExp(-x)); }
   
   void InitRandomWeights()
   {
      MathSrand(42);
      // Xavier init: scale = sqrt(2/(fan_in + fan_out))
      double scale1 = MathSqrt(2.0 / (AI_FEATURE_DIM + 64));
      double scale2 = MathSqrt(2.0 / (64 + 32));
      double scale3 = MathSqrt(2.0 / (32 + 1));
      
      ArrayResize(m_w1, AI_FEATURE_DIM);
      for(int i=0; i<AI_FEATURE_DIM; i++)
         for(int j=0; j<64; j++)
            m_w1[i][j] = ((double)MathRand()/32767.0 - 0.5) * 2.0 * scale1;
      for(int j=0; j<64; j++) m_b1[j] = 0.0;
      for(int i=0; i<64;  i++)
         for(int j=0; j<32; j++)
            m_w2[i][j] = ((double)MathRand()/32767.0 - 0.5) * 2.0 * scale2;
      for(int j=0; j<32; j++) m_b2[j] = 0.0;
      for(int i=0; i<32; i++)
         m_w3[i] = ((double)MathRand()/32767.0 - 0.5) * 2.0 * scale3;
      m_b3 = 0.0;
   }
   
public:
   CAIInference() : m_loaded(false), m_model_id("mlp_v2_26dim"), m_n_layers(3), m_b3(0.0)
   {
      ArrayInitialize(m_b1, 0.0);
      ArrayInitialize(m_b2, 0.0);
      ArrayInitialize(m_w3, 0.0);
   }
   
   virtual bool Initialize(CEventBus *bus) override
   {
      if(!IManager::Initialize(bus)) return false;
      InitRandomWeights();
      m_loaded = true;
      Print("CAIInference: MLP 26->64->32->1 ready (random weights, load model to override)");
      return true;
   }
   
   virtual void Shutdown() override { m_loaded = false; IManager::Shutdown(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}
   
   //--- Forward pass: 26-dim input -> scalar score [-1..1]
   bool Forward(const double &features[], double &out_score)
   {
      out_score = 0.0;
      if(!m_loaded) return false;
      if(ArraySize(features) < AI_FEATURE_DIM) return false;
      
      // Layer 1: 26 -> 64 (ReLU)
      double h1[64];
      for(int j=0; j<64; j++)
      {
         double s = m_b1[j];
         for(int i=0; i<AI_FEATURE_DIM; i++) s += features[i] * m_w1[i][j];
         h1[j] = ReLU(s);
      }
      
      // Layer 2: 64 -> 32 (ReLU)
      double h2[32];
      for(int j=0; j<32; j++)
      {
         double s = m_b2[j];
         for(int i=0; i<64; i++) s += h1[i] * m_w2[i][j];
         h2[j] = ReLU(s);
      }
      
      // Layer 3: 32 -> 1 (Tanh)
      double s = m_b3;
      for(int i=0; i<32; i++) s += h2[i] * m_w3[i];
      out_score = Tanh(s);  // [-1..1]
      return true;
   }
   
   //--- Struct-based forward pass (used by CAIEnsemble)
   bool ForwardFV(const SAIFeatureVector &fv, double &out_score)
   {
      return Forward(fv.features, out_score);
   }
   
   bool     IsLoaded()    const { return m_loaded;   }
   string   GetModelId()  const { return m_model_id; }
   void     SetModelId(string id) { m_model_id = id; }
};

#endif // __AI_INFERENCE_MQH__
