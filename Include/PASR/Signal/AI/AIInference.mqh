//+------------------------------------------------------------------+
//|                                    Signal/AI/AIInference.mqh    |
//|                                    Copyright 2026, Agsicentre   |
//|                                                                  |
//|  PURPOSE: Forward pass only.                                     |
//|    - Called every tick via OnPriceUpdate()                       |
//|    - Must be O(layers * neurons), ZERO heap allocation           |
//|    - No training, no file I/O, no weight updates                 |
//|    - Latency target: < 0.5 ms per call                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_AI_INFERENCE_MQH__
#define __SIGNAL_AI_INFERENCE_MQH__

#include "../AITypes.mqh"

//--- Maximum network dimensions (compile-time, no heap)
#define AI_MAX_INPUTS   32
#define AI_MAX_NEURONS  64
#define AI_MAX_LAYERS    4
#define AI_MAX_OUTPUTS   3   // SIGNAL_NONE, SIGNAL_BUY, SIGNAL_SELL

//--- Result from a single forward pass
struct InferenceResult
  {
   double   scores[AI_MAX_OUTPUTS]; // raw softmax output
   int      bestClass;              // argmax index
   double   confidence;             // max score (0-1)
   ulong    durationUs;             // profiling

   InferenceResult() : bestClass(0), confidence(0.0), durationUs(0)
     { ArrayInitialize(scores, 0.0); }
  };

//--- Single dense layer (stack-allocated)
struct DenseLayer
  {
   double weights[AI_MAX_NEURONS][AI_MAX_NEURONS]; // [out][in]
   double biases[AI_MAX_NEURONS];
   int    inputSize;
   int    outputSize;
   bool   useReLU;    // true=ReLU, false=linear (output layer uses softmax separately)
  };

//+------------------------------------------------------------------+
//| CAIInference — pure forward-pass engine                          |
//+------------------------------------------------------------------+
class CAIInference
  {
private:
   DenseLayer m_layers[AI_MAX_LAYERS];
   int        m_layerCount;
   double     m_inputBuf[AI_MAX_INPUTS];   // reused each call, no alloc
   double     m_hiddenBuf[AI_MAX_NEURONS]; // intermediate activations
   double     m_outputBuf[AI_MAX_OUTPUTS];

   //--- Activation: ReLU (branchless-friendly)
   static double ReLU(double x) { return x > 0.0 ? x : 0.0; }

   //--- Stable softmax over first `n` elements of arr -> out
   void Softmax(const double &arr[], double &out[], int n)
     {
      double maxVal = arr[0];
      for(int i = 1; i < n; i++) if(arr[i] > maxVal) maxVal = arr[i];
      double sum = 0.0;
      for(int i = 0; i < n; i++) { out[i] = MathExp(arr[i] - maxVal); sum += out[i]; }
      if(sum > 0.0) for(int i = 0; i < n; i++) out[i] /= sum;
     }

   //--- Single layer forward pass: input(inSz) -> output(outSz)
   void LayerForward(const DenseLayer &layer,
                     const double &input[], double &output[])
     {
      for(int o = 0; o < layer.outputSize; o++)
        {
         double acc = layer.biases[o];
         for(int i = 0; i < layer.inputSize; i++)
            acc += layer.weights[o][i] * input[i];
         output[o] = layer.useReLU ? ReLU(acc) : acc;
        }
     }

public:
   CAIInference() : m_layerCount(0)
     {
      ArrayInitialize(m_inputBuf,  0.0);
      ArrayInitialize(m_hiddenBuf, 0.0);
      ArrayInitialize(m_outputBuf, 0.0);
     }

   //--- Load weights from AIWeightSet (set by AITrainer after backprop)
   bool LoadWeights(const AIWeightSet &ws)
     {
      if(ws.layerCount <= 0 || ws.layerCount > AI_MAX_LAYERS) return false;
      m_layerCount = ws.layerCount;
      for(int l = 0; l < m_layerCount; l++)
        {
         m_layers[l].inputSize  = ws.layers[l].inputSize;
         m_layers[l].outputSize = ws.layers[l].outputSize;
         m_layers[l].useReLU    = (l < m_layerCount - 1); // output layer: linear
         for(int o = 0; o < m_layers[l].outputSize; o++)
           {
            m_layers[l].biases[o] = ws.layers[l].biases[o];
            for(int i = 0; i < m_layers[l].inputSize; i++)
               m_layers[l].weights[o][i] = ws.layers[l].weights[o][i];
           }
        }
      return true;
     }

   //--- Run forward pass. features[] must be normalised [0,1] or z-scored.
   //--- ZERO allocation. Reuses stack buffers.
   InferenceResult Predict(const double &features[], int featureCount)
     {
      InferenceResult result;
      if(m_layerCount == 0 || featureCount <= 0) return result;

      ulong t0 = GetMicrosecondCount();

      // Copy input (clamp to buffer size)
      int n = MathMin(featureCount, AI_MAX_INPUTS);
      for(int i = 0; i < n; i++) m_inputBuf[i] = features[i];

      // Propagate through layers
      // Layer 0: input -> hidden
      LayerForward(m_layers[0], m_inputBuf, m_hiddenBuf);

      // Intermediate hidden layers
      double buf2[AI_MAX_NEURONS];
      double *prev = m_hiddenBuf;
      for(int l = 1; l < m_layerCount - 1; l++)
        {
         LayerForward(m_layers[l], m_hiddenBuf, buf2);
         ArrayCopy(m_hiddenBuf, buf2, 0, 0, m_layers[l].outputSize);
        }

      // Output layer -> softmax
      LayerForward(m_layers[m_layerCount-1], m_hiddenBuf, m_outputBuf);
      double softOut[AI_MAX_OUTPUTS];
      Softmax(m_outputBuf, softOut, AI_MAX_OUTPUTS);

      // Find best class
      int best = 0;
      for(int i = 1; i < AI_MAX_OUTPUTS; i++)
         if(softOut[i] > softOut[best]) best = i;

      for(int i = 0; i < AI_MAX_OUTPUTS; i++) result.scores[i] = softOut[i];
      result.bestClass  = best;
      result.confidence = softOut[best];
      result.durationUs = GetMicrosecondCount() - t0;

      return result;
     }

   bool IsReady()     const { return m_layerCount > 0; }
   int  LayerCount()  const { return m_layerCount; }
  };

#endif // __SIGNAL_AI_INFERENCE_MQH__
