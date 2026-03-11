#!/usr/bin/env python3
"""
Heartbeat Monitor for GPIO Bridge

Monitors GPIO pin 6 (BCM) for heartbeat signal from Intel i9-13900K (Warden).
On heartbeat timeout, triggers immediate actuator lockdown.

Specifications:
- Heartbeat frequency: 100Hz (10ms period)
- Timeout: 30ms (3 missed heartbeats)
- Voltage: 3.3V, 50% duty cycle
"""

import threading
import time
import logging
import sys
from typing import Callable, Optional
from datetime import datetime

try:
    import RPi.GPIO as GPIO
except ImportError:
    # Mock GPIO for testing on non-RPi systems
    import mock_gpio as GPIO

logger = logging.getLogger(__name__)


class HeartbeatMonitor:
    """
    Monitors heartbeat signal from i9 host and triggers lockdown on timeout.
    """
    
    def __init__(self, 
                 gpio_pin: int = 6, 
                 timeout_ms: int = 30,
                 frequency_hz: int = 100,
                 on_timeout: Optional[Callable] = None):
        """
        Initialize heartbeat monitor.
        
        Args:
            gpio_pin: BCM GPIO pin number for heartbeat input
            timeout_ms: Timeout in milliseconds before triggering lockdown
            frequency_hz: Expected heartbeat frequency in Hz
            on_timeout: Callback function to execute on timeout
        """
        self.gpio_pin = gpio_pin
        self.timeout_ms = timeout_ms
        self.timeout_seconds = timeout_ms / 1000.0
        self.frequency_hz = frequency_hz
        self.period_seconds = 1.0 / frequency_hz
        self.on_timeout = on_timeout
        
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._last_heartbeat_time: Optional[float] = None
        self._lockdown_triggered = False
        self._heartbeat_count = 0
        self._timeout_count = 0
        
        logger.info(f"HeartbeatMonitor initialized: pin={gpio_pin}, "
                   f"timeout={timeout_ms}ms, freq={frequency_hz}Hz")
    
    def start(self) -> None:
        """Start monitoring heartbeat signal."""
        if self._running:
            logger.warning("HeartbeatMonitor already running")
            return
        
        # Setup GPIO
        GPIO.setup(self.gpio_pin, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
        
        self._running = True
        self._lockdown_triggered = False
        self._last_heartbeat_time = time.time()
        
        self._thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self._thread.start()
        
        logger.info(f"HeartbeatMonitor started on GPIO{self.gpio_pin}")
    
    def stop(self) -> None:
        """Stop monitoring heartbeat signal."""
        self._running = False
        
        if self._thread:
            self._thread.join(timeout=2.0)
            self._thread = None
        
        logger.info("HeartbeatMonitor stopped")
    
    def reset(self) -> None:
        """Reset the monitor after a lockdown (for recovery)."""
        self._lockdown_triggered = False
        self._last_heartbeat_time = time.time()
        logger.info("HeartbeatMonitor reset")
    
    def is_lockdown_active(self) -> bool:
        """Check if lockdown is currently active."""
        return self._lockdown_triggered
    
    def get_stats(self) -> dict:
        """Get heartbeat statistics."""
        return {
            'heartbeat_count': self._heartbeat_count,
            'timeout_count': self._timeout_count,
            'lockdown_active': self._lockdown_triggered,
            'last_heartbeat': self._last_heartbeat_time
        }
    
    def _monitor_loop(self) -> None:
        """
        Main monitoring loop.
        Polls GPIO pin and checks for heartbeat timeout.
        """
        logger.debug("Heartbeat monitoring loop started")
        
        while self._running:
            try:
                # Read GPIO state
                heartbeat_state = GPIO.input(self.gpio_pin)
                
                current_time = time.time()
                
                if heartbeat_state == GPIO.HIGH:
                    # Heartbeat detected (rising edge)
                    self._last_heartbeat_time = current_time
                    self._heartbeat_count += 1
                    
                    logger.debug(f"Heartbeat #{self._heartbeat_count} received at "
                               f"{datetime.now().isoformat()}")
                else:
                    # Check for timeout
                    if self._last_heartbeat_time is not None:
                        elapsed = current_time - self._last_heartbeat_time
                        
                        if elapsed > self.timeout_seconds and not self._lockdown_triggered:
                            self._trigger_lockdown()
                
                # Poll at 1kHz (1ms interval) for responsive detection
                time.sleep(0.001)
                
            except Exception as e:
                logger.error(f"Error in heartbeat monitor loop: {e}")
                time.sleep(0.001)
    
    def _trigger_lockdown(self) -> None:
        """Trigger lockdown due to heartbeat timeout."""
        if self._lockdown_triggered:
            return
        
        self._lockdown_triggered = True
        self._timeout_count += 1
        
        logger.critical(f"HEARTBEAT TIMEOUT #{self._timeout_count} - "
                       f"No heartbeat received for {self.timeout_ms}ms! "
                       f"Triggering ACTUATOR LOCKDOWN!")
        
        # Log the event with timestamp
        logger.critical(f"Lockdown triggered at {datetime.now().isoformat()}")
        
        # Execute callback if configured
        if self.on_timeout:
            try:
                logger.info("Executing lockdown callback...")
                self.on_timeout()
            except Exception as e:
                logger.error(f"Error executing lockdown callback: {e}")
        
        # Log final statistics
        logger.critical(f"Total heartbeats received: {self._heartbeat_count}")
        logger.critical(f"Total timeouts: {self._timeout_count}")


def create_heartbeat_monitor(config: dict, on_timeout: Callable) -> HeartbeatMonitor:
    """
    Factory function to create heartbeat monitor from config.
    
    Args:
        config: Configuration dictionary with heartbeat settings
        on_timeout: Callback to execute on heartbeat timeout
        
    Returns:
        Configured HeartbeatMonitor instance
    """
    heartbeat_config = config.get('heartbeat', {})
    
    return HeartbeatMonitor(
        gpio_pin=heartbeat_config.get('pin', 6),
        timeout_ms=heartbeat_config.get('timeout_ms', 30),
        frequency_hz=heartbeat_config.get('frequency_hz', 100),
        on_timeout=on_timeout
    )


# Standalone test/monitor mode
if __name__ == "__main__":
    import sys
    
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    def lockdown_callback():
        print("!!! LOCKDOWN TRIGGERED !!!")
        print("All actuators should now be in safe (LOW) state")
    
    print("Starting Heartbeat Monitor in test mode...")
    print(f"Monitoring GPIO6, timeout=30ms")
    print("Press Ctrl+C to stop")
    
    monitor = HeartbeatMonitor(
        gpio_pin=6,
        timeout_ms=30,
        frequency_hz=100,
        on_timeout=lockdown_callback
    )
    
    try:
        monitor.start()
        
        while True:
            time.sleep(1)
            stats = monitor.get_stats()
            print(f"Stats: heartbeats={stats['heartbeat_count']}, "
                  f"timeouts={stats['timeout_count']}, "
                  f"lockdown={'ACTIVE' if stats['lockdown_active'] else 'inactive'}")
            
    except KeyboardInterrupt:
        print("\nStopping monitor...")
        monitor.stop()
        print("Monitor stopped")
        sys.exit(0)
