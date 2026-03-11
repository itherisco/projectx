// CognitionStatusPanel - Dual-Process Cognitive Status Display
// Shows System 1 (Reflex) and System 2 (Reasoning) status in real-time

import React from 'react';
import { Brain, Zap, ZapOff, Activity, Heart } from 'lucide-react';

// Types (should match Rust System1Status)
interface System1Status {
  isActive: boolean;
  state: 'idle' | 'classifying' | 'executing' | 'waiting';
  lastConfidence: number;
  lastClassification: string | null;
  reflexCount: number;
  wakeupCount: number;
  avgClassifyLatencyMs: number;
  mlAvailable: boolean;
}

interface EmotionalContext {
  sentiment: number;    // -1 to 1 (frustrated to happy)
  arousal: number;      // 0 to 1 (calm to excited)
  dominance: number;    // 0 to 1 (submissive to dominant)
  source: 'voice_mfcc' | 'text' | 'default';
}

interface System2Status {
  isReasoning: boolean;
  currentThought: string | null;
  confidence: number;
  emotionalAlignment: number;
}

interface Props {
  system1Status: System1Status;
  system2Status: System2Status;
  emotionalContext: EmotionalContext | null;
}

// Helper functions
const getConfidenceColor = (confidence: number): string => {
  if (confidence >= 0.9) return '#22c55e'; // green
  if (confidence >= 0.7) return '#eab308'; // yellow
  return '#ef4444'; // red
};

const getSentimentEmoji = (sentiment: number): string => {
  if (sentiment > 0.3) return '😊';
  if (sentiment < -0.3) return '😠';
  return '😐';
};

const getSystem1StateColor = (state: string): string => {
  switch (state) {
    case 'idle': return '#6b7280';
    case 'classifying': return '#3b82f6';
    case 'executing': return '#22c55e';
    case 'waiting': return '#f59e0b';
    default: return '#6b7280';
  }
};

export const CognitionStatusPanel: React.FC<Props> = ({
  system1Status,
  system2Status,
  emotionalContext
}) => {
  return (
    <div className="bg-[#111111] rounded-lg border border-[#222222] p-4">
      <div className="flex items-center gap-2 mb-4">
        <Brain className="w-5 h-5 text-violet-400" />
        <span className="text-sm font-mono font-bold text-gray-300">
          DUAL-PROCESS COGNITION
        </span>
      </div>
      
      {/* System 1 Status */}
      <div className="mb-4 p-3 bg-[#0a0a0a] rounded-lg border border-[#222222]">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <Zap className={`w-4 h-4 ${system1Status.isActive ? 'text-yellow-400' : 'text-gray-500'}`} />
            <span className="text-xs font-mono text-yellow-400">SYSTEM 1 (REFLEX)</span>
          </div>
          <div 
            className="px-2 py-1 rounded text-xs font-mono"
            style={{ 
              backgroundColor: getSystem1StateColor(system1Status.state),
              color: '#000'
            }}
          >
            {system1Status.state.toUpperCase()}
          </div>
        </div>
        
        {/* Confidence Gauge */}
        <div className="mb-2">
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>Confidence</span>
            <span>{(system1Status.lastConfidence * 100).toFixed(0)}%</span>
          </div>
          <div className="relative h-2 bg-[#222222] rounded-full overflow-hidden">
            <div 
              className="absolute h-full rounded-full transition-all duration-300"
              style={{ 
                width: `${system1Status.lastConfidence * 100}%`,
                backgroundColor: getConfidenceColor(system1Status.lastConfidence)
              }}
            />
          </div>
        </div>
        
        {/* Stats Grid */}
        <div className="grid grid-cols-3 gap-2 text-xs">
          <div className="text-center">
            <div className="text-gray-500">Reflex</div>
            <div className="text-green-400 font-mono">{system1Status.reflexCount}</div>
          </div>
          <div className="text-center">
            <div className="text-gray-500">Wakeups</div>
            <div className="text-orange-400 font-mono">{system1Status.wakeupCount}</div>
          </div>
          <div className="text-center">
            <div className="text-gray-500">Latency</div>
            <div className="text-blue-400 font-mono">{(system1Status.avgClassifyLatencyMs ?? 0).toFixed(0)}ms</div>
          </div>
        </div>
        
        {/* ML Available Indicator */}
        <div className="mt-2 flex items-center gap-1 text-xs">
          {system1Status.mlAvailable ? (
            <><Zap className="w-3 h-3 text-green-400" /><span className="text-green-400">ML Enabled</span></>
          ) : (
            <><ZapOff className="w-3 h-3 text-gray-500" /><span className="text-gray-500">Rule-based</span></>
          )}
        </div>
      </div>
      
      {/* System 2 Status */}
      <div className="mb-4 p-3 bg-[#0a0a0a] rounded-lg border border-[#222222]">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <Activity className={`w-4 h-4 ${system2Status.isReasoning ? 'text-purple-400' : 'text-gray-500'}`} />
            <span className="text-xs font-mono text-purple-400">SYSTEM 2 (REASONING)</span>
          </div>
          <div className={`px-2 py-1 rounded text-xs font-mono ${system2Status.isReasoning ? 'bg-purple-500 text-white' : 'bg-gray-700 text-gray-400'}`}>
            {system2Status.isReasoning ? 'REASONING' : 'IDLE'}
          </div>
        </div>
        
        {/* Confidence */}
        <div className="mb-2">
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>Reasoning Confidence</span>
            <span>{(system2Status.confidence * 100).toFixed(0)}%</span>
          </div>
          <div className="relative h-2 bg-[#222222] rounded-full overflow-hidden">
            <div 
              className="absolute h-full bg-purple-500 rounded-full transition-all duration-300"
              style={{ width: `${system2Status.confidence * 100}%` }}
            />
          </div>
        </div>
        
        {/* Emotional Alignment */}
        <div>
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>Emotional Alignment</span>
            <span>{(system2Status.emotionalAlignment * 100).toFixed(0)}%</span>
          </div>
          <div className="relative h-2 bg-[#222222] rounded-full overflow-hidden">
            <div 
              className="absolute h-full bg-pink-500 rounded-full transition-all duration-300"
              style={{ width: `${system2Status.emotionalAlignment * 100}%` }}
            />
          </div>
        </div>
      </div>
      
      {/* Emotional Context */}
      {emotionalContext && (
        <div className="p-3 bg-[#0a0a0a] rounded-lg border border-[#222222]">
          <div className="flex items-center gap-2 mb-2">
            <Heart className="w-4 h-4 text-pink-400" />
            <span className="text-xs font-mono text-pink-400">EMOTIONAL CONTEXT</span>
          </div>
          
          <div className="flex items-center justify-around">
            {/* Sentiment */}
            <div className="text-center">
              <div className="text-2xl mb-1">{getSentimentEmoji(emotionalContext.sentiment)}</div>
              <div className="text-xs text-gray-500">Sentiment</div>
              <div className="text-xs font-mono" style={{ color: emotionalContext.sentiment > 0 ? '#22c55e' : '#ef4444' }}>
                {emotionalContext.sentiment >= 0 ? '+' : ''}{emotionalContext.sentiment.toFixed(2)}
              </div>
            </div>
            
            {/* Arousal */}
            <div className="text-center">
              <div className="text-2xl mb-1">{emotionalContext.arousal > 0.5 ? '⚡' : '💤'}</div>
              <div className="text-xs text-gray-500">Arousal</div>
              <div className="text-xs font-mono text-blue-400">{emotionalContext.arousal.toFixed(2)}</div>
            </div>
            
            {/* Dominance */}
            <div className="text-center">
              <div className="text-2xl mb-1">{emotionalContext.dominance > 0.5 ? '👑' : '🙋'}</div>
              <div className="text-xs text-gray-500">Dominance</div>
              <div className="text-xs font-mono text-yellow-400">{emotionalContext.dominance.toFixed(2)}</div>
            </div>
          </div>
          
          <div className="mt-2 text-center text-xs text-gray-500">
            Source: {emotionalContext.source}
          </div>
        </div>
      )}
    </div>
  );
};

export default CognitionStatusPanel;
