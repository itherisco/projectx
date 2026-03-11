#!/usr/bin/env python3
"""
Emergency Shutdown Handler for GPIO Bridge

Handles emergency shutdown signals from Intel i9-13900K (Warden).
On emergency signal, executes full lockdown sequence.

Monitors GPIO pin 4 (BCM) for emergency shutdown signal.
Active-low signal: LOW = PANIC (Julia brain has failed), HIGH = Normal operation
"""

import threading
import time
import logging
from typing import Callable, Optional
from datetime import datetime

try:
    import RPi.GPIO as GPIO
except ImportError:
    # Mock GPIO for testing on non-RPi systems
    import mock_gpio as GPIO

logger = logging.getLogger(__name__)


class EmergencyHandler:
    """
    Handles emergency shutdown signals from i9 host.
    Implements fail-closed behavior on emergency signal.
    """
    
    # Emergency signal is active-LOW (pulled up internally)
    # LOW = PANIC (emergency), HIGH = Normal
    SIGNAL_NORMAL = GPIO.HIGH  # 1
    SIGNAL_EMERGENCY = GPIO.LOW  # 0
    
    def __init__(self, 
                 emergency_pin: int = 4,
                 on_emergency: Optional[Callable] = None,
                 debounce_ms: int = 10):
        """
        Initialize emergency handler.
        
        Args:
            emergency_pin: BCM GPIO pin for emergency shutdown signal
            on_emergency: Callback function to execute on emergency signal
            debounce_ms: Debounce time in milliseconds
        """
        self.emergency_pin = emergency_pin
        self.on_emergency = on_emergency
        self.debounce_ms = debounce_ms / 1000.0
        
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._emergency_triggered = False
        self._trigger_count = 0
        self._last_state = self.SIGNAL_NORMAL
        
        logger.info(f"EmergencyHandler initialized: pin={emergency_pin}, "
                   f"debounce={debounce_ms}ms")
    
    def start(self) -> None:
        """Start monitoring emergency shutdown signal."""
        if self._running:
            logger.warning("EmergencyHandler already running")
            return
        
        # Setup GPIO with pull-up (default to normal)
        GPIO.setup(self.emergency_pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        
        self._running = True
        self._emergency_triggered = False
        self._last_state = GPIO.input(self.emergency_pin)
        
        self._thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self._thread.start()
        
        logger.info(f"EmergencyHandler started on GPIO{self.emergency_pin}")
        logger.info("Monitoring for emergency shutdown signal (ACTIVE-LOW)")
    
    def stop(self) -> None:
        """Stop monitoring emergency shutdown signal."""
        self._running = False
        
        if self._thread:
            self._thread.join(timeout=2.0)
            self._thread = None
        
        logger.info("EmergencyHandler stopped")
    
    def reset(self) -> None:
        """Reset the emergency handler (for recovery after manual reset)."""
        self._emergency_triggered = False
        logger.info("EmergencyHandler reset")
    
    def is_emergency_active(self) -> bool:
        """Check if emergency state is currently active."""
        return self._emergency_triggered
    
    def get_trigger_count(self) -> int:
        """Get number of times emergency was triggered."""
        return self._trigger_count
    
    def force_emergency(self) -> None:
        """Force emergency state (for testing)."""
        if not self._emergency_triggered:
            self._trigger_emergency()
    
    def _monitor_loop(self) -> None:
        """
        Main monitoring loop.
        Detects emergency shutdown signal (active-LOW).
        """
        logger.debug("Emergency monitoring loop started")
        
        while self._running:
            try:
                # Read GPIO state
                current_state = GPIO.input(self.emergency_pin)
                
                # Debounce check
                if current_state != self._last_state:
                    time.sleep(self.debounce_ms)
                    current_state = GPIO.input(self.emergency_pin)
                    
                    # Check again after debounce
                    if current_state != self._last_state:
                        self._last_state = current_state
                        
                        if current_state == self.SIGNAL_EMERGENCY:
                            self._trigger_emergency()
                
                # Poll at 100Hz (10ms interval)
                time.sleep(0.01)
                
            except Exception as e:
                logger.error(f"Error in emergency monitor loop: {e}")
                time.sleep(0.01)
    
    def _trigger_emergency(self) -> None:
        """Trigger emergency shutdown sequence."""
        if self._emergency_triggered:
            return
        
        self._emergency_triggered = True
        self._trigger_count += 1
        
        logger.critical(f"!!! EMERGENCY SHUTDOWN SIGNAL RECEIVED #{self._trigger_count} !!!")
        logger.critical(f"Emergency signal detected at {datetime.now().isoformat()}")
        logger.critical("Julia brain has failed - executing FAIL-CLOSED lockdown!")
        
        # Execute callback if configured
        if self.on_emergency:
            try:
                logger.info("Executing emergency shutdown callback...")
                self.on_emergency()
            except Exception as e:
                logger.error(f"Error executing emergency callback: {e}")
        
        logger.critical("Emergency shutdown sequence complete")


class PhysicalRelayController:
    """
    Controls physical relays for power gating and network isolation.
    Provides additional hardware-level control beyond GPIO.
    """
    
    def __init__(self, 
                 relay_pins: Optional[list] = None):
        """
        Initialize physical relay controller.
        
        Args:
            relay_pins: List of BCM GPIO pins for relay control
        """
        self.relay_pins = relay_pins or []
        self._initialized = False
        
        logger.info(f"PhysicalRelayController initialized with {len(self.relay_pins)} relays")
    
    def initialize(self) -> None:
        """Initialize relay control pins."""
        if self._initialized:
            return
        
        for pin in self.relay_pins:
            try:
                GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
                logger.debug(f"Relay pin GPIO{pin} initialized")
            except Exception as e:
                logger.error(f"Failed to initialize relay GPIO{pin}: {e}")
        
        self._initialized = True
    
    def energize_relay(self, pin: int) -> bool:
        """
        Energize a relay (close contacts).
        
        Args:
            pin: BCM GPIO pin for relay
            
        Returns:
            True if successful
        """
        try:
            GPIO.output(pin, GPIO.HIGH)
            logger.info(f"Relay GPIO{pin} energized (contacts closed)")
            return True
        except Exception as e:
            logger.error(f"Failed to energize relay GPIO{pin}: {e}")
            return False
    
    def deenergize_relay(self, pin: int) -> bool:
        """
        De-energize a relay (open contacts).
        
        Args:
            pin: BCM GPIO pin for relay
            
        Returns:
            True if successful
        """
        try:
            GPIO.output(pin, GPIO.LOW)
            logger.info(f"Relay GPIO{pin} de-energized (contacts open)")
            return True
        except Exception as e:
            logger.error(f"Failed to de-energize relay GPIO{pin}: {e}")
            return False
    
    def emergency_cut_all(self) -> bool:
        """
        Emergency cut - de-energize all relays (fail-safe).
        
        Returns:
            True if successful
        """
        logger.critical("EMERGENCY: Cutting all relay connections")
        
        success = True
        for pin in self.relay_pins:
            if not self.deenergize_relay(pin):
                success = False
        
        return success


def create_emergency_handler(config: dict, on_emergency: Callable) -> EmergencyHandler:
    """
    Factory function to create emergency handler from config.
    
    Args:
        config: Configuration dictionary with emergency settings
        on_emergency: Callback to execute on emergency signal
        
    Returns:
        Configured EmergencyHandler instance
    """
    emergency_config = config.get('emergency', {})
    
    return EmergencyHandler(
        emergency_pin=emergency_config.get('pin', 4),
        on_emergency=on_emergency,
        debounce_ms=10
    )


# Standalone test mode
if __name__ == "__main__":
    import sys
    
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    def emergency_callback():
        print("!!! EMERGENCY SHUTDOWN !!!")
        print("All systems should now be in fail-closed state")
    
    print("Testing EmergencyHandler...")
    print("Monitoring GPIO4 for emergency shutdown signal (ACTIVE-LOW)")
    print("Press Ctrl+C to stop")
    
    handler = EmergencyHandler(
        emergency_pin=4,
        on_emergency=emergency_callback
    )
    
    try:
        handler.start()
        
        while True:
            time.sleep(1)
            state = GPIO.input(4)
            print(f"GPIO4 state: {'NORMAL (HIGH)' if state else 'EMERGENCY (LOW)'}, "
                  f"emergency_active={handler.is_emergency_active()}, "
                  f"triggers={handler.get_trigger_count()}")
            
    except KeyboardInterrupt:
        print("\nStopping handler...")
        handler.stop()
        print("Handler stopped")
        sys.exit(0)
