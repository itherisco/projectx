"""
ITHERIS SPEECH INTERFACE
========================
Connects to the Julia multi-agent system via ZMQ
Provides natural language interaction with cognitive awareness
"""

import json
import zmq
import time
from datetime import datetime
from typing import Dict, Any, Optional
import uuid
import threading
import queue


class ItherisSpeechInterface:
    """
    Speech interface for ITHERIS multi-agent system.
    
    Features:
    - ZMQ connection to Julia backend
    - Memory-grounded responses (no hallucination)
    - Situational awareness from sensor data
    - Reasoning trace visibility
    - Law-based output filtering
    """
    
    def __init__(
        self,
        central_hub: str = "tcp://127.0.0.1:5555",
        memory_file: str = "itheris_speech_memory.json",
        law_file: str = "itheris_laws.json"
    ):
        self.central_hub = central_hub
        self.memory_file = memory_file
        self.law_file = law_file
        
        # Internal state
        self.identity = "SPEECH_INTERFACE"
        self.current_environment = {}
        self.recent_decisions = []
        self.reasoning_traces = []
        self.system_status = {}
        
        # Message queue for async handling
        self.message_queue = queue.Queue()
        
        # Load persistent data
        self.memory = self._load_json(memory_file, {
            "conversations": [],
            "learned_facts": {},
            "user_preferences": {}
        })
        self.laws = self._load_json(law_file, {
            "forbidden_phrases": [
                "I think", "I believe", "probably", "maybe",
                "I'm not sure", "it seems"
            ],
            "required_prefixes": {
                "speculation": "[UNVERIFIED]",
                "memory_gap": "[NO DATA]",
                "inference": "[INFERRED]"
            }
        })
        
        # ZMQ setup
        self.context = zmq.Context()
        self.socket = None
        self.listener_thread = None
        self.running = False
        
    # ============================================================
    # FILE I/O
    # ============================================================
    
    def _load_json(self, path: str, default: Dict) -> Dict:
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return default
    
    def _save_json(self, path: str, data: Dict):
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4, ensure_ascii=False)
        except Exception as e:
            print(f"Warning: Failed to save {path}: {e}")
    
    # ============================================================
    # ZMQ COMMUNICATION
    # ============================================================
    
    def connect(self):
        """Establish connection to ITHERIS central hub"""
        self.socket = self.context.socket(zmq.DEALER)
        self.socket.setsockopt_string(zmq.IDENTITY, self.identity)
        self.socket.connect(self.central_hub)
        
        # Start listener thread
        self.running = True
        self.listener_thread = threading.Thread(target=self._listen_loop, daemon=True)
        self.listener_thread.start()
        
        print(f"✓ Connected to ITHERIS at {self.central_hub}")
        
        # Request initial status
        self._send_message("CENTRAL_HUB", "STATUS_REQUEST", {})
        time.sleep(0.5)  # Allow time for response
    
    def disconnect(self):
        """Gracefully disconnect"""
        self.running = False
        if self.listener_thread:
            self.listener_thread.join(timeout=2)
        if self.socket:
            self.socket.close()
        self.context.term()
        self._save_json(self.memory_file, self.memory)
    
    def _send_message(self, recipient: str, msg_type: str, payload: Any, priority: str = "normal"):
        """Send formatted message to ITHERIS"""
        message = {
            "id": str(uuid.uuid4()),
            "timestamp": datetime.now().isoformat(),
            "sender": self.identity,
            "recipient": recipient,
            "type": msg_type,
            "priority": priority,
            "payload": payload
        }
        self.socket.send_json(message)
    
    def _listen_loop(self):
        """Background thread for receiving messages"""
        poller = zmq.Poller()
        poller.register(self.socket, zmq.POLLIN)
        
        while self.running:
            try:
                socks = dict(poller.poll(timeout=100))
                if self.socket in socks:
                    msg = self.socket.recv_json()
                    self._handle_message(msg)
            except Exception as e:
                if self.running:  # Only log if not shutting down
                    print(f"Listener error: {e}")
    
    def _handle_message(self, msg: Dict):
        """Process incoming messages from ITHERIS"""
        msg_type = msg.get("type", "")
        payload = msg.get("payload", {})
        
        if msg_type == "STATUS_RESPONSE":
            self.system_status = payload
            
        elif msg_type == "SENSOR_DATA":
            self.current_environment = payload
            
        elif msg_type == "DECISION":
            self.recent_decisions.append(payload)
            if "reasoning_trace" in payload:
                self.reasoning_traces.append(payload["reasoning_trace"])
            # Keep only last 10
            if len(self.recent_decisions) > 10:
                self.recent_decisions.pop(0)
                self.reasoning_traces.pop(0)
        
        # Queue for retrieval
        self.message_queue.put(msg)
    
    # ============================================================
    # SITUATIONAL AWARENESS
    # ============================================================
    
    def get_system_state(self) -> str:
        """Generate natural language system status"""
        if not self.current_environment:
            return "I have no sensor data available yet."
        
        severity = self.current_environment.get("overall_severity", 0)
        context = self.current_environment.get("context", "unknown")
        
        # Build awareness statement
        if severity > 0.8:
            state = "CRITICAL"
            emoji = "🚨"
        elif severity > 0.6:
            state = "ELEVATED"
            emoji = "⚠️"
        else:
            state = "STABLE"
            emoji = "✓"
        
        status_parts = [f"{emoji} System state: {state}"]
        
        # Add specifics
        cpu = self.current_environment.get("cpu_load", 0)
        mem = self.current_environment.get("memory_usage", 0)
        
        status_parts.append(f"CPU: {cpu*100:.1f}%, Memory: {mem*100:.1f}%")
        
        threats = self.current_environment.get("threats", [])
        if threats:
            status_parts.append(f"Active threats: {len(threats)}")
        
        return " | ".join(status_parts)
    
    def get_reasoning_context(self) -> str:
        """Explain current reasoning state"""
        if not self.recent_decisions:
            return "No recent decisions recorded."
        
        latest = self.recent_decisions[-1]
        trace = latest.get("reasoning_trace", [])
        
        context = f"Last decision: {latest.get('action_type', 'unknown')}\n"
        context += f"Confidence: {latest.get('confidence', 0)*100:.1f}%\n"
        
        if trace:
            context += "Reasoning:\n"
            for step in trace:
                context += f"  • {step}\n"
        
        return context
    
    # ============================================================
    # MEMORY-GROUNDED RESPONSE
    # ============================================================
    
    def query_knowledge(self, question: str) -> Optional[str]:
        """Query learned facts (no fabrication)"""
        q_lower = question.strip().lower()
        
        # Check exact matches first
        for fact_key, fact_value in self.memory["learned_facts"].items():
            if fact_key.lower() == q_lower:
                return fact_value
        
        # Check partial matches
        for fact_key, fact_value in self.memory["learned_facts"].items():
            if q_lower in fact_key.lower() or fact_key.lower() in q_lower:
                return f"[PARTIAL MATCH] {fact_value}"
        
        return None
    
    def interpret_query(self, user_input: str) -> str:
        """Route query to appropriate handler"""
        input_lower = user_input.lower()
        
        # System state queries
        if any(kw in input_lower for kw in ["status", "state", "how are you", "system"]):
            return self.get_system_state()
        
        # Reasoning queries
        if any(kw in input_lower for kw in ["thinking", "reasoning", "why", "decision"]):
            return self.get_reasoning_context()
        
        # Memory queries
        if any(kw in input_lower for kw in ["what is", "tell me about", "explain"]):
            result = self.query_knowledge(user_input)
            if result:
                return result
            else:
                return "[NO DATA] I have no verified information on that topic."
        
        # Mission queries
        if "mission" in input_lower:
            active = len([d for d in self.recent_decisions if d.get("mission_id")])
            return f"I have processed {active} missions recently."
        
        return "[UNKNOWN QUERY TYPE] Please rephrase or ask about: status, reasoning, missions, or specific facts."
    
    # ============================================================
    # LAW ENFORCEMENT (ANTI-HALLUCINATION)
    # ============================================================
    
    def enforce_laws(self, response: str) -> str:
        """Filter output to prevent speculation/lies"""
        # Check forbidden phrases
        for phrase in self.laws["forbidden_phrases"]:
            if phrase.lower() in response.lower():
                response = response.replace(phrase, "[REDACTED]")
        
        # Ensure proper prefixes for uncertain content
        if "infer" in response.lower() and not response.startswith("[INFERRED]"):
            response = "[INFERRED] " + response
        
        return response
    
    # ============================================================
    # PUBLIC INTERFACE
    # ============================================================
    
    def speak(self, user_input: str) -> str:
        """
        Main interface: process input and generate grounded response
        """
        # Log conversation
        self.memory["conversations"].append({
            "timestamp": datetime.now().isoformat(),
            "input": user_input,
            "system_state": self.get_system_state()
        })
        
        # Interpret and respond
        raw_response = self.interpret_query(user_input)
        
        # Apply laws
        lawful_response = self.enforce_laws(raw_response)
        
        # Add conversation to memory
        self.memory["conversations"][-1]["response"] = lawful_response
        
        # Periodic save
        if len(self.memory["conversations"]) % 10 == 0:
            self._save_json(self.memory_file, self.memory)
        
        return lawful_response
    
    def teach(self, fact_key: str, fact_value: str, confidence: float = 1.0):
        """Add verified knowledge to memory"""
        self.memory["learned_facts"][fact_key] = {
            "value": fact_value,
            "confidence": confidence,
            "learned_at": datetime.now().isoformat(),
            "source": "operator"
        }
        self._save_json(self.memory_file, self.memory)
        print(f"✓ Learned: {fact_key}")
    
    # ============================================================
    # UTILITY
    # ============================================================
    
    def show_stats(self):
        """Display interface statistics"""
        print("\n" + "="*60)
        print("ITHERIS SPEECH INTERFACE STATISTICS")
        print("="*60)
        print(f"Conversations: {len(self.memory['conversations'])}")
        print(f"Learned facts: {len(self.memory['learned_facts'])}")
        print(f"Recent decisions: {len(self.recent_decisions)}")
        print(f"System status: {self.system_status}")
        print("="*60 + "\n")


# ============================================================
# INTERACTIVE SESSION
# ============================================================

def run_interactive_session():
    """Run an interactive chat session with ITHERIS"""
    
    print("\n" + "="*60)
    print("  ITHERIS SPEECH INTERFACE v1.0")
    print("  Connecting to multi-agent cognitive system...")
    print("="*60 + "\n")
    
    interface = ItherisSpeechInterface()
    
    try:
        interface.connect()
        time.sleep(1)  # Allow initial handshake
        
        print("\nType 'help' for commands, 'exit' to quit\n")
        
        while True:
            user_input = input("You: ").strip()
            
            if not user_input:
                continue
            
            if user_input.lower() in ["exit", "quit", "bye"]:
                print("Disconnecting from ITHERIS...")
                break
            
            if user_input.lower() == "help":
                print("\nCommands:")
                print("  status - Get system state")
                print("  reasoning - See latest reasoning trace")
                print("  stats - Show interface statistics")
                print("  teach <fact> = <value> - Add knowledge")
                print("  exit - Quit")
                continue
            
            if user_input.lower() == "stats":
                interface.show_stats()
                continue
            
            if user_input.startswith("teach "):
                parts = user_input[6:].split("=")
                if len(parts) == 2:
                    interface.teach(parts[0].strip(), parts[1].strip())
                else:
                    print("Format: teach <fact> = <value>")
                continue
            
            # Generate response
            response = interface.speak(user_input)
            print(f"\nItheris: {response}\n")
    
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
    except Exception as e:
        print(f"\nError: {e}")
    finally:
        interface.disconnect()
        print("✓ Disconnected\n")


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    run_interactive_session()
