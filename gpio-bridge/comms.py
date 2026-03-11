#!/usr/bin/env python3
"""
Communication Interface for GPIO Bridge

Handles communication with Intel i9-13900K (Warden).
Supports both serial (RS-232) and TCP/IP communication.

Protocol: Simple ASCII commands over serial (115200 baud) or TCP
Commands: HEARTBEAT, LOCKDOWN, STATUS, RESET
"""

import socket
import threading
import time
import logging
import queue
from typing import Optional, Callable, Dict
from enum import Enum
from datetime import datetime

try:
    import serial
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False

logger = logging.getLogger(__name__)


class Command(Enum):
    """Supported commands from i9 host."""
    HEARTBEAT = "HEARTBEAT"
    LOCKDOWN = "LOCKDOWN"
    STATUS = "STATUS"
    RESET = "RESET"
    EMERGENCY = "EMERGENCY"
    ACK = "ACK"
    NACK = "NACK"


class CommsInterface:
    """
    Communication interface for i9 host.
    Supports serial and TCP connections.
    """
    
    def __init__(self,
                 comm_type: str = "serial",
                 port: str = "/dev/ttyS0",
                 baud: int = 115200,
                 tcp_port: int = 9000,
                 bind: str = "0.0.0.0",
                 on_command: Optional[Callable] = None):
        """
        Initialize communication interface.
        
        Args:
            comm_type: "serial" or "tcp"
            port: Serial port path (e.g., /dev/ttyS0)
            baud: Serial baud rate
            tcp_port: TCP listen port
            bind: TCP bind address
            on_command: Callback for received commands
        """
        self.comm_type = comm_type
        self.port = port
        self.baud = baud
        self.tcp_port = tcp_port
        self.bind = bind
        self.on_command = on_command
        
        self._running = False
        self._serial_port = None
        self._tcp_socket = None
        self._client_socket = None
        self._command_queue = queue.Queue()
        self._threads = []
        self._connected = False
        
        logger.info(f"CommsInterface initialized: type={comm_type}, "
                   f"port={port}, baud={baud}, tcp_port={tcp_port}")
    
    def start(self) -> None:
        """Start communication interface."""
        if self._running:
            logger.warning("CommsInterface already running")
            return
        
        self._running = True
        
        if self.comm_type == "serial":
            self._start_serial()
        elif self.comm_type == "tcp":
            self._start_tcp()
        else:
            logger.error(f"Unknown communication type: {self.comm_type}")
            return
        
        # Start command processor thread
        processor_thread = threading.Thread(target=self._process_commands, daemon=True)
        processor_thread.start()
        
        logger.info(f"CommsInterface started ({self.comm_type})")
    
    def stop(self) -> None:
        """Stop communication interface."""
        self._running = False
        self._connected = False
        
        # Close connections
        if self._client_socket:
            try:
                self._client_socket.close()
            except:
                pass
            self._client_socket = None
        
        if self._tcp_socket:
            try:
                self._tcp_socket.close()
            except:
                pass
            self._tcp_socket = None
        
        if self._serial_port and SERIAL_AVAILABLE:
            try:
                self._serial_port.close()
            except:
                pass
            self._serial_port = None
        
        logger.info("CommsInterface stopped")
    
    def _start_serial(self) -> None:
        """Start serial communication."""
        if not SERIAL_AVAILABLE:
            logger.error("PySerial not available")
            return
        
        try:
            self._serial_port = serial.Serial(
                port=self.port,
                baudrate=self.baud,
                timeout=1.0,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE
            )
            
            # Start read thread
            thread = threading.Thread(target=self._read_serial, daemon=True)
            thread.start()
            self._threads.append(thread)
            
            self._connected = True
            logger.info(f"Serial port opened: {self.port} @ {self.baud} baud")
            
        except Exception as e:
            logger.error(f"Failed to open serial port: {e}")
    
    def _read_serial(self) -> None:
        """Read from serial port."""
        while self._running and self._serial_port:
            try:
                if self._serial_port.in_waiting > 0:
                    line = self._serial_port.readline().decode('ascii', errors='ignore').strip()
                    if line:
                        logger.debug(f"Serial received: {line}")
                        self._command_queue.put(line)
                else:
                    time.sleep(0.01)
            except Exception as e:
                logger.error(f"Serial read error: {e}")
                time.sleep(0.1)
    
    def _start_tcp(self) -> None:
        """Start TCP server."""
        try:
            self._tcp_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self._tcp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self._tcp_socket.bind((self.bind, self.tcp_port))
            self._tcp_socket.listen(1)
            self._tcp_socket.settimeout(1.0)
            
            # Start accept thread
            thread = threading.Thread(target=self._accept_connections, daemon=True)
            thread.start()
            self._threads.append(thread)
            
            logger.info(f"TCP server listening on {self.bind}:{self.tcp_port}")
            
        except Exception as e:
            logger.error(f"Failed to start TCP server: {e}")
    
    def _accept_connections(self) -> None:
        """Accept TCP connections."""
        while self._running:
            try:
                client, addr = self._tcp_socket.accept()
                logger.info(f"TCP client connected: {addr}")
                
                if self._client_socket:
                    try:
                        self._client_socket.close()
                    except:
                        pass
                
                self._client_socket = client
                self._connected = True
                
                # Start read thread for this client
                thread = threading.Thread(
                    target=self._read_tcp, 
                    args=(client,), 
                    daemon=True
                )
                thread.start()
                
            except socket.timeout:
                continue
            except Exception as e:
                logger.error(f"TCP accept error: {e}")
                time.sleep(0.1)
    
    def _read_tcp(self, client: socket.socket) -> None:
        """Read from TCP client."""
        buffer = ""
        
        while self._running and self._connected:
            try:
                data = client.recv(1024)
                if not data:
                    break
                
                buffer += data.decode('ascii', errors='ignore')
                
                # Process complete lines
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.strip()
                    if line:
                        logger.debug(f"TCP received: {line}")
                        self._command_queue.put(line)
                
            except Exception as e:
                logger.error(f"TCP read error: {e}")
                break
        
        logger.info("TCP client disconnected")
        self._connected = False
    
    def _process_commands(self) -> None:
        """Process received commands."""
        while self._running:
            try:
                line = self._command_queue.get(timeout=0.1)
                command = self._parse_command(line)
                
                if command:
                    logger.info(f"Processing command: {command}")
                    
                    if self.on_command:
                        self.on_command(command)
                
            except queue.Empty:
                continue
            except Exception as e:
                logger.error(f"Command processing error: {e}")
    
    def _parse_command(self, line: str) -> Optional[Dict]:
        """
        Parse command from host.
        
        Args:
            line: Raw command string
            
        Returns:
            Parsed command dict or None
        """
        parts = line.upper().split()
        
        if not parts:
            return None
        
        cmd = parts[0]
        
        try:
            command_enum = Command(cmd)
        except ValueError:
            logger.warning(f"Unknown command: {cmd}")
            return None
        
        return {
            'command': command_enum,
            'raw': line,
            'timestamp': datetime.now()
        }
    
    def send_response(self, message: str) -> bool:
        """
        Send response to host.
        
        Args:
            message: Response message
            
        Returns:
            True if successful
        """
        try:
            if self.comm_type == "serial" and self._serial_port:
                self._serial_port.write(f"{message}\n".encode('ascii'))
                logger.debug(f"Serial sent: {message}")
                
            elif self.comm_type == "tcp" and self._client_socket:
                self._client_socket.sendall(f"{message}\n".encode('ascii'))
                logger.debug(f"TCP sent: {message}")
            
            return True
            
        except Exception as e:
            logger.error(f"Send error: {e}")
            return False
    
    def send_status(self, status: Dict) -> bool:
        """
        Send status report to host.
        
        Args:
            status: Status dictionary
            
        Returns:
            True if successful
        """
        status_str = f"STATUS: heartbeat={status.get('heartbeat_count', 0)}, " \
                    f"lockdown={status.get('lockdown_active', False)}, " \
                    f"emergency={status.get('emergency_active', False)}"
        
        return self.send_response(status_str)
    
    def is_connected(self) -> bool:
        """Check if communication is active."""
        return self._connected
    
    def send_heartbeat_ack(self) -> bool:
        """Send heartbeat acknowledgment."""
        return self.send_response("ACK HEARTBEAT")
    
    def send_lockdown_ack(self) -> bool:
        """Send lockdown acknowledgment."""
        return self.send_response("ACK LOCKDOWN")
    
    def send_reset_ack(self) -> bool:
        """Send reset acknowledgment."""
        return self.send_response("ACK RESET")


def create_comms_interface(config: dict, on_command: Callable) -> CommsInterface:
    """
    Factory function to create comms interface from config.
    
    Args:
        config: Configuration dictionary with comms settings
        on_command: Callback for received commands
        
    Returns:
        Configured CommsInterface instance
    """
    comms_config = config.get('comms', {})
    
    return CommsInterface(
        comm_type=comms_config.get('type', 'serial'),
        port=comms_config.get('port', '/dev/ttyS0'),
        baud=comms_config.get('baud', 115200),
        tcp_port=comms_config.get('tcp_port', 9000),
        bind=comms_config.get('bind', '0.0.0.0'),
        on_command=on_command
    )


# Standalone test mode
if __name__ == "__main__":
    import sys
    
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    def handle_command(cmd: dict):
        print(f"Received command: {cmd['command']}")
    
    # Test TCP mode
    print("Testing TCP CommsInterface on port 9000...")
    
    comms = CommsInterface(
        comm_type="tcp",
        tcp_port=9000,
        on_command=handle_command
    )
    
    comms.start()
    
    print("Waiting for commands...")
    print("Supported commands: HEARTBEAT, LOCKDOWN, STATUS, RESET")
    print("Press Ctrl+C to stop")
    
    try:
        while True:
            time.sleep(1)
            print(f"Connected: {comms.is_connected()}")
            
    except KeyboardInterrupt:
        print("\nStopping...")
        comms.stop()
        print("Stopped")
        sys.exit(0)
