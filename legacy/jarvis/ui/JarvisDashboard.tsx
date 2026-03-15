import React, { useState, useEffect, useCallback } from 'react';
import { 
  Cpu, 
  MemoryStick, 
  Network, 
  Shield, 
  Target, 
  Zap,
  ChevronDown,
  ChevronRight,
  AlertTriangle,
  CheckCircle,
  XCircle,
  Bot,
  Activity,
  Brain,
  MessageSquare
} from 'lucide-react';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

// ============================================================================
// TYPES
// ============================================================================

interface SystemMetrics {
  cpuLoad: number[];
  memoryUse: number[];
  networkLatency: number[];
}

interface KernelExecution {
  id: string;
  action: string;
  timestamp: Date;
  success: boolean;
  vetoed: boolean;
  reason?: string;
}

interface Goal {
  id: string;
  description: string;
  progress: number;
  status: 'active' | 'completed' | 'failed';
}

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  internalMonologue?: string;
  kernelValidation?: {
    approved: boolean;
    reason?: string;
  };
  timestamp: Date;
}

interface JarvisState {
  isConnected: boolean;
  trustLevel: number; // 0-100
  isDreaming: boolean;
  systemMetrics: SystemMetrics;
  goals: Goal[];
  executions: KernelExecution[];
  messages: ChatMessage[];
  currentInput: string;
}

// ============================================================================
// MOCK DATA GENERATORS
// ============================================================================

const generateMetrics = (): SystemMetrics => {
  const generateArray = (base: number, variance: number) => 
    Array.from({ length: 20 }, () => base + (Math.random() - 0.5) * variance);
  
  return {
    cpuLoad: generateArray(35, 20),
    memoryUse: generateArray(45, 15),
    networkLatency: generateArray(25, 10),
  };
};

const mockGoals: Goal[] = [
  { id: '1', description: 'Process user request', progress: 75, status: 'active' },
  { id: '2', description: 'Maintain system coherence', progress: 100, status: 'completed' },
  { id: '3', description: 'Optimize decision pipeline', progress: 45, status: 'active' },
];

const mockExecutions: KernelExecution[] = [
  { id: '1', action: 'read_file', timestamp: new Date(Date.now() - 60000), success: true, vetoed: false },
  { id: '2', action: 'safe_http_request', timestamp: new Date(Date.now() - 45000), success: true, vetoed: false },
  { id: '3', action: 'write_file', timestamp: new Date(Date.now() - 30000), success: false, vetoed: true, reason: 'Risk threshold exceeded' },
  { id: '4', action: 'execute_shell', timestamp: new Date(Date.now() - 15000), success: true, vetoed: false },
  { id: '5', action: 'analyze_data', timestamp: new Date(Date.now() - 5000), success: true, vetoed: false },
];

const mockMessages: ChatMessage[] = [
  {
    id: '1',
    role: 'assistant',
    content: 'I have analyzed the system logs and identified three potential optimization opportunities.',
    internalMonologue: '[0.85, 0.72, 0.91, 0.68, 0.77, 0.83, 0.95, 0.61, 0.88, 0.74, 0.79, 0.86]',
    kernelValidation: { approved: true },
    timestamp: new Date(Date.now() - 120000),
  },
  {
    id: '2',
    role: 'user',
    content: 'What optimizations do you recommend?',
    timestamp: new Date(Date.now() - 60000),
  },
  {
    id: '3',
    role: 'assistant',
    content: 'Based on my analysis, I recommend: (1) caching frequently accessed data, (2) parallelizing independent tasks, and (3) reducing memory fragmentation.',
    internalMonologue: '[0.92, 0.81, 0.88, 0.75, 0.83, 0.90, 0.87, 0.79, 0.85, 0.91, 0.82, 0.89]',
    kernelValidation: { approved: true },
    timestamp: new Date(Date.now() - 30000),
  },
];

// ============================================================================
// CUSTOM HOOK: useJarvis
// ============================================================================

export const useJarvis = () => {
  const [state, setState] = useState<JarvisState>({
    isConnected: true,
    trustLevel: 87,
    isDreaming: false,
    systemMetrics: generateMetrics(),
    goals: mockGoals,
    executions: mockExecutions,
    messages: mockMessages,
    currentInput: '',
  });

  // Simulate WebSocket updates
  useEffect(() => {
    const interval = setInterval(() => {
      setState(prev => ({
        ...prev,
        systemMetrics: generateMetrics(),
        trustLevel: Math.max(50, Math.min(100, prev.trustLevel + (Math.random() - 0.5) * 5)),
      }));
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  const sendMessage = useCallback((content: string) => {
    const userMessage: ChatMessage = {
      id: Date.now().toString(),
      role: 'user',
      content,
      timestamp: new Date(),
    };

    setState(prev => ({
      ...prev,
      messages: [...prev.messages, userMessage],
      currentInput: '',
    }));

    // Simulate assistant response
    setTimeout(() => {
      const responses = [
        'Processing your request through the cognitive pipeline.',
        'Analyzing the input using 12D vector reasoning.',
        'Evaluating action against security policies.',
      ];
      
      const assistantMessage: ChatMessage = {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: responses[Math.floor(Math.random() * responses.length)],
        internalMonologue: Array.from({ length: 12 }, () => (0.5 + Math.random() * 0.5).toFixed(2)).join(', '),
        kernelValidation: { approved: Math.random() > 0.1 },
        timestamp: new Date(),
      };

      setState(prev => ({
        ...prev,
        messages: [...prev.messages, assistantMessage],
      }));
    }, 1500);
  }, []);

  const executeCommand = useCallback((command: string) => {
    const trimmed = command.trim().toLowerCase();
    
    if (trimmed.startsWith('/')) {
      const [cmd] = trimmed.split(' ');
      
      switch (cmd) {
        case '/status':
          return { type: 'info', message: `Connected: ${state.isConnected}, Trust: ${state.trustLevel}%` };
        case '/dream':
          setState(prev => ({ ...prev, isDreaming: !prev.isDreaming }));
          return { type: 'success', message: `Dream cycle ${state.isDreaming ? 'stopped' : 'started'}` };
        case '/clean-memory':
          setState(prev => ({ ...prev, executions: [] }));
          return { type: 'success', message: 'Memory cleaned' };
        default:
          return { type: 'error', message: `Unknown command: ${cmd}` };
      }
    }
    
    sendMessage(command);
    return null;
  }, [state.isConnected, state.trustLevel, state.isDreaming, sendMessage]);

  return {
    state,
    sendMessage,
    executeCommand,
    setInput: (input: string) => setState(prev => ({ ...prev, currentInput: input })),
  };
};

// ============================================================================
// COMPONENTS
// ============================================================================

// Vitality Sidebar
export const VitalitySidebar: React.FC<{ metrics: SystemMetrics; trustLevel: number }> = ({ 
  metrics, 
  trustLevel 
}) => {
  const getTrustColor = (level: number) => {
    if (level >= 80) return '#10b981';
    if (level >= 60) return '#f59e0b';
    return '#ef4444';
  };

  const MetricCard: React.FC<{ icon: React.ReactNode; label: string; data: number[]; color: string }> = ({
    icon, label, data, color
  }) => (
    <div className="bg-[#111111] rounded-lg p-3 border border-[#222222]">
      <div className="flex items-center gap-2 mb-2">
        <span style={{ color }}>{icon}</span>
        <span className="text-xs text-gray-400 uppercase tracking-wider">{label}</span>
      </div>
      <div className="h-16">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data.map((v, i) => ({ x: i, y: v }))}>
            <XAxis dataKey="x" hide />
            <YAxis domain={[0, 100]} hide />
            <Tooltip 
              contentStyle={{ background: '#1a1a1a', border: '1px solid #333' }}
              labelStyle={{ display: 'none' }}
            />
            <Line 
              type="monotone" 
              dataKey="y" 
              stroke={color} 
              strokeWidth={1.5} 
              dot={false} 
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );

  return (
    <div className="w-64 bg-[#0a0a0a] border-r border-[#222222] p-4 flex flex-col gap-4">
      <div className="flex items-center gap-2 text-violet-400 mb-2">
        <Activity size={20} />
        <span className="font-mono text-sm font-bold">VITALITY</span>
      </div>

      <MetricCard 
        icon={<Cpu size={14} />} 
        label="CPU Load" 
        data={metrics.cpuLoad} 
        color="#9558B2" 
      />
      <MetricCard 
        icon={<MemoryStick size={14} />} 
        label="Memory" 
        data={metrics.memoryUse} 
        color="#06b6d4" 
      />
      <MetricCard 
        icon={<Network size={14} />} 
        label="Latency" 
        data={metrics.networkLatency} 
        color="#10b981" 
      />

      <div className="mt-4 p-4 bg-[#111111] rounded-lg border border-[#222222]">
        <div className="flex items-center gap-2 mb-3">
          <Shield size={14} className="text-violet-400" />
          <span className="text-xs text-gray-400 uppercase tracking-wider">Trust</span>
        </div>
        <div className="relative h-3 bg-[#222222] rounded-full overflow-hidden">
          <div 
            className="absolute inset-y-0 left-0 rounded-full transition-all duration-500"
            style={{ 
              width: `${trustLevel}%`, 
              backgroundColor: getTrustColor(trustLevel) 
            }}
          />
        </div>
        <div className="mt-2 text-center">
          <span className="text-2xl font-mono font-bold" style={{ color: getTrustColor(trustLevel) }}>
            {Math.round(trustLevel)}%
          </span>
        </div>
      </div>
    </div>
  );
};

// Cognitive Spine (Right Sidebar)
export const CognitiveSpine: React.FC<{ goals: Goal[]; executions: KernelExecution[] }> = ({ 
  goals, 
  executions 
}) => {
  return (
    <div className="w-72 bg-[#0a0a0a] border-l border-[#222222] p-4 flex flex-col gap-4 overflow-y-auto">
      <div className="flex items-center gap-2 text-violet-400 mb-2">
        <Brain size={20} />
        <span className="font-mono text-sm font-bold">COGNITIVE SPINE</span>
      </div>

      {/* Active Goals */}
      <div className="space-y-3">
        <div className="flex items-center gap-2 text-gray-400 text-xs uppercase tracking-wider">
          <Target size={14} />
          <span>Active Goals</span>
        </div>
        
        {goals.map(goal => (
          <div key={goal.id} className="bg-[#111111] rounded-lg p-3 border border-[#222222]">
            <div className="flex justify-between items-start mb-2">
              <span className="text-sm text-gray-200">{goal.description}</span>
              {goal.status === 'completed' && <CheckCircle size={14} className="text-green-500" />}
              {goal.status === 'failed' && <XCircle size={14} className="text-red-500" />}
            </div>
            <div className="relative h-1.5 bg-[#222222] rounded-full">
              <div 
                className="absolute inset-y-0 left-0 bg-violet-500 rounded-full"
                style={{ width: `${goal.progress}%` }}
              />
            </div>
          </div>
        ))}
      </div>

      {/* Action History */}
      <div className="mt-4 space-y-2">
        <div className="flex items-center gap-2 text-gray-400 text-xs uppercase tracking-wider">
          <Zap size={14} />
          <span>Action History</span>
        </div>
        
        {executions.slice(0, 10).map(exec => (
          <div 
            key={exec.id} 
            className="flex items-center justify-between py-2 px-3 bg-[#111111] rounded border border-[#222222]"
          >
            <div className="flex items-center gap-2">
              {exec.vetoed ? (
                <XCircle size={14} className="text-red-500" />
              ) : exec.success ? (
                <CheckCircle size={14} className="text-green-500" />
              ) : (
                <XCircle size={14} className="text-yellow-500" />
              )}
              <span className="text-xs font-mono text-gray-300">{exec.action}</span>
            </div>
            <span className="text-xs text-gray-500">
              {new Date(exec.timestamp).toLocaleTimeString()}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
};

// Chat Message Component
export const ChatMessage: React.FC<{ message: ChatMessage }> = ({ message }) => {
  const [expanded, setExpanded] = useState(false);
  const isAssistant = message.role === 'assistant';

  return (
    <div className={`flex ${isAssistant ? 'justify-start' : 'justify-end'} mb-4`}>
      <div className={`max-w-[70%] ${isAssistant ? 'bg-[#111111]' : 'bg-[#1a1a2e]'} rounded-lg border border-[#222222]`}>
        {isAssistant && (
          <div className="flex items-center gap-2 px-3 pt-3 pb-1 border-b border-[#222222]">
            <Bot size={14} className="text-violet-400" />
            <span className="text-xs text-violet-400 font-mono">JARVIS</span>
            {message.kernelValidation && (
              message.kernelValidation.approved ? (
                <span className="ml-auto text-xs text-green-500 flex items-center gap-1">
                  <CheckCircle size={10} /> Approved
                </span>
              ) : (
                <span className="ml-auto text-xs text-red-500 flex items-center gap-1">
                  <XCircle size={10} /> Vetoed
                </span>
              )
            )}
          </div>
        )}
        
        <div className="p-3">
          <p className="text-gray-200 text-sm">{message.content}</p>
        </div>

        {isAssistant && message.internalMonologue && (
          <div className="border-t border-[#222222]">
            <button
              onClick={() => setExpanded(!expanded)}
              className="flex items-center gap-2 w-full px-3 py-2 text-xs text-gray-500 hover:text-violet-400 transition-colors"
            >
              {expanded ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
              <span className="font-mono">12D Vector Logic</span>
            </button>
            
            {expanded && (
              <div className="px-3 pb-3">
                <code className="text-xs text-violet-300 font-mono bg-[#0a0a0a] p-2 rounded block">
                  [{message.internalMonologue}]
                </code>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};

// Safety Override Toast
export const SafetyOverrideToast: React.FC<{ visible: boolean; reason?: string }> = ({ visible, reason }) => {
  if (!visible) return null;

  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 animate-pulse">
      <div className="bg-red-900/90 border border-red-500 text-red-100 px-6 py-3 rounded-lg flex items-center gap-3 shadow-lg backdrop-blur">
        <AlertTriangle size={20} />
        <div>
          <div className="font-bold text-sm">KERNEL VETO</div>
          <div className="text-xs opacity-80">Priority × (Reward − Risk) failure</div>
          {reason && <div className="text-xs mt-1 text-red-300">{reason}</div>}
        </div>
      </div>
    </div>
  );
};

// Command Input
export const CommandInput: React.FC<{ 
  value: string; 
  onChange: (value: string) => void; 
  onSubmit: (value: string) => void;
  isDreaming: boolean;
}> = ({ value, onChange, onSubmit, isDreaming }) => {
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      onSubmit(value);
    }
  };

  return (
    <div className={`border-t border-[#222222] p-4 ${isDreaming ? 'animate-pulse' : ''}`}>
      <div className="flex items-center gap-3 bg-[#111111] rounded-lg border border-[#333333] focus-within:border-violet-500 transition-colors">
        <MessageSquare size={18} className="text-gray-500 ml-3" />
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Type message or /command..."
          className="flex-1 bg-transparent py-3 text-gray-200 placeholder-gray-600 outline-none font-mono text-sm"
        />
        <button
          onClick={() => onSubmit(value)}
          className="px-4 py-2 bg-violet-600 hover:bg-violet-500 text-white rounded-md text-sm font-medium transition-colors"
        >
          Send
        </button>
      </div>
      <div className="mt-2 text-xs text-gray-600 font-mono">
        Commands: /status /dream /clean-memory
      </div>
    </div>
  );
};

// ============================================================================
// MAIN APP COMPONENT
// ============================================================================

export default function JarvisDashboard() {
  const { state, sendMessage, executeCommand, setInput } = useJarvis();
  const [showToast, setShowToast] = useState(false);

  // Check for vetos
  useEffect(() => {
    const lastExecution = state.executions[state.executions.length - 1];
    if (lastExecution?.vetoed) {
      setShowToast(true);
      const timer = setTimeout(() => setShowToast(false), 5000);
      return () => clearTimeout(timer);
    }
  }, [state.executions]);

  const handleSubmit = (input: string) => {
    if (!input.trim()) return;
    
    if (input.startsWith('/')) {
      const result = executeCommand(input);
      if (result) {
        // Handle command result (could show toast)
      }
    } else {
      sendMessage(input);
    }
  };

  return (
    <div className="flex h-screen bg-[#0a0a0a] text-gray-200 overflow-hidden">
      {/* Left Sidebar - Vitality */}
      <VitalitySidebar 
        metrics={state.systemMetrics} 
        trustLevel={state.trustLevel} 
      />

      {/* Main Content - Neural Stream */}
      <div className="flex-1 flex flex-col">
        {/* Header */}
        <header className="h-14 border-b border-[#222222] flex items-center justify-between px-4">
          <div className="flex items-center gap-3">
            <Bot size={24} className="text-violet-400" />
            <h1 className="text-lg font-mono font-bold text-violet-100">
              JARVIS <span className="text-violet-400">Command Center</span>
            </h1>
          </div>
          <div className="flex items-center gap-4">
            {state.isDreaming && (
              <div className="flex items-center gap-2 text-violet-400 animate-pulse">
                <Brain size={16} />
                <span className="text-xs font-mono">DREAM CYCLE</span>
              </div>
            )}
            <div className={`w-2 h-2 rounded-full ${state.isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
            <span className="text-xs text-gray-500 font-mono">
              {state.isConnected ? 'CONNECTED' : 'DISCONNECTED'}
            </span>
          </div>
        </header>

        {/* Chat Area */}
        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {state.messages.map(msg => (
            <ChatMessage key={msg.id} message={msg} />
          ))}
        </div>

        {/* Command Input */}
        <CommandInput
          value={state.currentInput}
          onChange={setInput}
          onSubmit={handleSubmit}
          isDreaming={state.isDreaming}
        />
      </div>

      {/* Right Sidebar - Cognitive Spine */}
      <CognitiveSpine 
        goals={state.goals} 
        executions={state.executions} 
      />

      {/* Safety Override Toast */}
      <SafetyOverrideToast 
        visible={showToast} 
        reason={state.executions[state.executions.length - 1]?.reason}
      />

      {/* Dream Cycle Background Effect */}
      {state.isDreaming && (
        <div className="fixed inset-0 pointer-events-none z-0">
          <div className="absolute inset-0 bg-violet-900/5 animate-pulse" />
        </div>
      )}
    </div>
  );
}
