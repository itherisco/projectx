#!/usr/bin/env python3
"""
GPIO Bridge Main Application

Unified application for Raspberry Pi CM4 GPIO Bridge.
Combines heartbeat monitoring, actuator control, emergency handling,
and communication with Intel i9-13900K (Warden).

Features:
- Heartbeat monitoring (100Hz, 30ms timeout)
- Emergency shutdown signal handling
- Actuator fail-closed control
- Serial/TCP communication with i9 host
- Status reporting and graceful shutdown
"""

import os
import sys
import signal
import time
import logging
import threading
import argparse
from typing import Optional, Dict
from datetime import datetime
from pathlib import Path

import yaml

# Import GPIO bridge components
try:
    import RPi.GPIO as GPIO
except ImportError:
    # Mock GPIO for testing
    import mock_gpio as GPIO

from heartbeat_monitor import HeartbeatMonitor, create_heartbeat_monitor
from actuator_controller import ActuatorController, create_actuator_controller
from emergency_handler import EmergencyHandler, create_emergency_handler
from comms import CommsInterface, create_comms_interface, Command


# Configure logging
def setup_logging(config: dict) -> None:
    """Setup logging configuration."""
    log_config = config.get('logging', {})
    level = getattr(logging, log_config.get('level', 'INFO'))
    
    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # Setup root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)
    
    # File handler (optional)
    if 'file' in log_config:
        file_handler = logging.FileHandler(log_config['file'])
        file_handler.setLevel(level)
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)
    
    # Syslog handler (optional)
    if log_config.get('syslog', False):
        try:
            syslog_handler = logging.handlers.SysLogHandler(address='/dev/log')
            syslog_handler.setLevel(level)
            syslog_handler.setFormatter(formatter)
            root_logger.addHandler(syslog_handler)
        except Exception as e:
            print(f"Warning: Could not setup syslog: {e}")


class GpioBridge:
    """
    Main GPIO Bridge application.
    Coordinates all components and handles commands from i9 host.
    """
    
    def __init__(self, config_path: str = "config.yaml"):
        """
        Initialize GPIO Bridge.
        
        Args:
            config_path: Path to configuration file
        """
        self.config_path = config_path
        self.config = self._load_config()
        
        # Setup logging
        setup_logging(self.config)
        self.logger = logging.getLogger(__name__)
        
        # Components
        self.heartbeat_monitor: Optional[HeartbeatMonitor] = None
        self.actuator_controller: Optional[ActuatorController] = None
        self.emergency_handler: Optional[EmergencyHandler] = None
        self.comms: Optional[CommsInterface] = None
        
        # Status
        self._running = False
        self._start_time = None
        
        self.logger.info("GPIO Bridge initialized")
    
    def _load_config(self) -> dict:
        """Load configuration from YAML file."""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            self.logger.warning(f"Config file not found: {self.config_path}, using defaults")
            return self._get_default_config()
        except Exception as e:
            self.logger.error(f"Error loading config: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> dict:
        """Get default configuration."""
        return {
            'heartbeat': {
                'pin': 6,
                'timeout_ms': 30,
                'frequency_hz': 100
            },
            'emergency': {
                'pin': 4
            },
            'actuators': {
                'motors': [17, 18, 22, 23, 24, 25, 26, 27],
                'network_reset': 14,
                'power_gate': 15
            },
            'comms': {
                'type': 'serial',
                'port': '/dev/ttyS0',
                'baud': 115200,
                'tcp_port': 9000,
                'bind': '0.0.0.0'
            },
            'logging': {
                'level': 'INFO'
            }
        }
    
    def start(self) -> None:
        """Start the GPIO Bridge application."""
        if self._running:
            self.logger.warning("GPIO Bridge already running")
            return
        
        self.logger.info("=" * 60)
        self.logger.info("GPIO BRIDGE STARTING")
        self.logger.info("=" * 60)
        
        # Initialize GPIO
        self._init_gpio()
        
        # Create components
        self._create_components()
        
        # Start components
        self._start_components()
        
        self._running = True
        self._start_time = datetime.now()
        
        self.logger.info("=" * 60)
        self.logger.info("GPIO BRIDGE RUNNING")
        self.logger.info("=" * 60)
        
        # Main loop - just keep alive and handle commands
        self._main_loop()
    
    def _init_gpio(self) -> None:
        """Initialize GPIO subsystem."""
        try:
            GPIO.setmode(GPIO.BCM)
            GPIO.setwarnings(False)
            self.logger.info("GPIO subsystem initialized (BCM mode)")
        except Exception as e:
            self.logger.error(f"Failed to initialize GPIO: {e}")
            raise
    
    def _create_components(self) -> None:
        """Create all components."""
        self.logger.info("Creating components...")
        
        # Create actuator controller first (needed for callbacks)
        self.actuator_controller = create_actuator_controller(self.config)
        self.actuator_controller.initialize()
        
        # Create heartbeat monitor with lockdown callback
        def heartbeat_timeout_callback():
            self.logger.critical("HEARTBEAT TIMEOUT - Triggering lockdown!")
            if self.actuator_controller:
                self.actuator_controller.emergency_lockdown()
            if self.comms:
                self.comms.send_response("EVENT: HEARTBEAT_TIMEOUT")
        
        self.heartbeat_monitor = create_heartbeat_monitor(
            self.config, 
            heartbeat_timeout_callback
        )
        
        # Create emergency handler with lockdown callback
        def emergency_callback():
            self.logger.critical("EMERGENCY SIGNAL - Triggering lockdown!")
            if self.actuator_controller:
                self.actuator_controller.emergency_lockdown()
            if self.comms:
                self.comms.send_response("EVENT: EMERGENCY_SHUTDOWN")
        
        self.emergency_handler = create_emergency_handler(
            self.config,
            emergency_callback
        )
        
        # Create comms interface with command handler
        def command_callback(cmd: Dict):
            self._handle_command(cmd)
        
        self.comms = create_comms_interface(
            self.config,
            command_callback
        )
        
        self.logger.info("All components created")
    
    def _start_components(self) -> None:
        """Start all components."""
        self.logger.info("Starting components...")
        
        # Start heartbeat monitor
        self.heartbeat_monitor.start()
        
        # Start emergency handler
        self.emergency_handler.start()
        
        # Start communication interface
        self.comms.start()
        
        self.logger.info("All components started")
    
    def _handle_command(self, cmd: Dict) -> bool:
        """
        Handle command from i9 host.
        
        Args:
            cmd: Parsed command dictionary
            
        Returns:
            True if command was handled successfully
        """
        command = cmd['command']
        
        try:
            if command == Command.HEARTBEAT:
                # Host is sending heartbeat
                self.logger.debug("Received HEARTBEAT from host")
                if self.heartbeat_monitor:
                    self.heartbeat_monitor.reset()
                return self.comms.send_heartbeat_ack() if self.comms else True
            
            elif command == Command.LOCKDOWN:
                # Host requesting lockdown
                self.logger.warning("Received LOCKDOWN command from host")
                if self.actuator_controller:
                    self.actuator_controller.emergency_lockdown()
                return self.comms.send_lockdown_ack() if self.comms else True
            
            elif command == Command.STATUS:
                # Host requesting status
                self.logger.debug("Received STATUS request")
                status = self._get_status()
                return self.comms.send_status(status) if self.comms else True
            
            elif command == Command.RESET:
                # Host requesting reset (after lockdown)
                self.logger.info("Received RESET command")
                self._reset_system()
                return self.comms.send_reset_ack() if self.comms else True
            
            elif command == Command.EMERGENCY:
                # Host sending emergency signal
                self.logger.critical("Received EMERGENCY command")
                if self.emergency_handler:
                    self.emergency_handler.force_emergency()
                return True
            
            else:
                self.logger.warning(f"Unknown command: {command}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error handling command: {e}")
            return False
    
    def _get_status(self) -> Dict:
        """Get current system status."""
        status = {
            'uptime': (datetime.now() - self._start_time).total_seconds() if self._start_time else 0,
            'lockdown_active': False,
            'emergency_active': False,
            'heartbeat_count': 0,
            'connected': self.comms.is_connected() if self.comms else False
        }
        
        if self.heartbeat_monitor:
            hb_stats = self.heartbeat_monitor.get_stats()
            status['heartbeat_count'] = hb_stats['heartbeat_count']
            status['lockdown_active'] = hb_stats['lockdown_active']
        
        if self.emergency_handler:
            status['emergency_active'] = self.emergency_handler.is_emergency_active()
        
        if self.actuator_controller:
            actuator_status = self.actuator_controller.get_status()
            status['lockdown_active'] = status['lockdown_active'] or actuator_status['lockdown_active']
        
        return status
    
    def _reset_system(self) -> None:
        """Reset system after lockdown."""
        self.logger.info("Resetting system...")
        
        # Reset heartbeat monitor
        if self.heartbeat_monitor:
            self.heartbeat_monitor.reset()
        
        # Reset emergency handler
        if self.emergency_handler:
            self.emergency_handler.reset()
        
        # Reset actuator controller
        if self.actuator_controller:
            self.actuator_controller.reset_lockdown()
        
        self.logger.info("System reset complete")
    
    def _main_loop(self) -> None:
        """Main application loop."""
        self.logger.info("Entering main loop...")
        
        while self._running:
            try:
                # Periodic status logging
                status = self._get_status()
                self.logger.debug(f"Status: uptime={status['uptime']:.0f}s, "
                                f"lockdown={status['lockdown_active']}, "
                                f"connected={status['connected']}")
                
                # Sleep for 1 second
                time.sleep(1)
                
            except KeyboardInterrupt:
                self.logger.info("Keyboard interrupt received")
                break
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}")
                time.sleep(1)
        
        self._running = False
    
    def stop(self) -> None:
        """Stop the GPIO Bridge application."""
        self.logger.info("Stopping GPIO Bridge...")
        
        self._running = False
        
        # Stop components
        if self.heartbeat_monitor:
            self.heartbeat_monitor.stop()
        
        if self.emergency_handler:
            self.emergency_handler.stop()
        
        if self.comms:
            self.comms.stop()
        
        # Cleanup GPIO
        try:
            GPIO.cleanup()
        except:
            pass
        
        self.logger.info("GPIO Bridge stopped")
    
    def signal_handler(self, signum, frame) -> None:
        """Handle termination signals."""
        self.logger.warning(f"Received signal {signum}")
        self.stop()
        sys.exit(0)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='GPIO Bridge for Raspberry Pi CM4')
    parser.add_argument('-c', '--config', default='config.yaml',
                       help='Path to configuration file')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Enable verbose logging')
    args = parser.parse_args()
    
    # Create and start bridge
    bridge = GpioBridge(args.config)
    
    # Setup signal handlers
    signal.signal(signal.SIGINT, bridge.signal_handler)
    signal.signal(signal.SIGTERM, bridge.signal_handler)
    
    try:
        bridge.start()
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
