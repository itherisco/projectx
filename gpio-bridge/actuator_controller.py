#!/usr/bin/env python3
"""
Actuator Controller for GPIO Bridge

Controls all actuator pins with fail-closed defaults.
All actuators default to LOW (safe state = no power to actuators).

Motor/Actuator Pins (GPIO 10-27): Default to LOW
Network PHY Reset (GPIO 14): Default to LOW (network enabled)
External Power Gate (GPIO 15): Default to LOW (power enabled)
"""

import threading
import time
import logging
from typing import List, Optional, Dict
from datetime import datetime

try:
    import RPi.GPIO as GPIO
except ImportError:
    # Mock GPIO for testing on non-RPi systems
    import mock_gpio as GPIO

logger = logging.getLogger(__name__)


class ActuatorController:
    """
    Controls all actuators with fail-safe defaults.
    All outputs default to LOW (safe state).
    """
    
    # Safe state constants
    STATE_SAFE = GPIO.LOW  # 0 - No power to actuators
    STATE_ACTIVE = GPIO.HIGH  # 1 - Power to actuators
    
    def __init__(self, 
                 motor_pins: List[int],
                 network_reset_pin: int = 14,
                 power_gate_pin: int = 15):
        """
        Initialize actuator controller.
        
        Args:
            motor_pins: List of BCM GPIO pins for motors/actuators
            network_reset_pin: BCM GPIO pin for network PHY reset
            power_gate_pin: BCM GPIO pin for power gate relay
        """
        self.motor_pins = motor_pins
        self.network_reset_pin = network_reset_pin
        self.power_gate_pin = power_gate_pin
        
        # All GPIO pins we're controlling
        self._all_actuator_pins = motor_pins + [network_reset_pin, power_gate_pin]
        
        self._initialized = False
        self._lockdown_active = False
        self._lock = threading.Lock()
        
        logger.info(f"ActuatorController initialized with {len(motor_pins)} motor pins")
    
    def initialize(self) -> None:
        """Initialize GPIO pins for all actuators."""
        if self._initialized:
            logger.warning("ActuatorController already initialized")
            return
        
        with self._lock:
            # Setup motor pins as outputs, default to safe state
            for pin in self.motor_pins:
                try:
                    GPIO.setup(pin, GPIO.OUT, initial=self.STATE_SAFE)
                    logger.debug(f"Motor pin GPIO{pin} initialized to SAFE (LOW)")
                except Exception as e:
                    logger.error(f"Failed to initialize motor pin GPIO{pin}: {e}")
            
            # Setup network PHY reset pin (LOW = enabled, HIGH = reset)
            try:
                GPIO.setup(self.network_reset_pin, GPIO.OUT, initial=self.STATE_SAFE)
                logger.debug(f"Network reset pin GPIO{self.network_reset_pin} initialized to SAFE (LOW)")
            except Exception as e:
                logger.error(f"Failed to initialize network reset pin GPIO{self.network_reset_pin}: {e}")
            
            # Setup power gate relay pin (LOW = enabled, HIGH = cut)
            try:
                GPIO.setup(self.power_gate_pin, GPIO.OUT, initial=self.STATE_SAFE)
                logger.debug(f"Power gate pin GPIO{self.power_gate_pin} initialized to SAFE (LOW)")
            except Exception as e:
                logger.error(f"Failed to initialize power gate pin GPIO{self.power_gate_pin}: {e}")
            
            self._initialized = True
            logger.info("All actuator pins initialized to FAIL-SAFE state (LOW)")
    
    def set_motor(self, pin: int, state: bool) -> bool:
        """
        Set a specific motor pin to given state.
        
        Args:
            pin: BCM GPIO pin number
            state: True = active (HIGH), False = safe (LOW)
            
        Returns:
            True if successful, False otherwise
        """
        if not self._initialized:
            logger.error("ActuatorController not initialized")
            return False
        
        if pin not in self.motor_pins:
            logger.warning(f"Pin GPIO{pin} not in motor pins list")
            return False
        
        # Don't allow control if in lockdown (fail-closed)
        if self._lockdown_active:
            logger.warning(f"Cannot change motor GPIO{pin} - LOCKDOWN ACTIVE")
            return False
        
        try:
            GPIO.output(pin, self.STATE_ACTIVE if state else self.STATE_SAFE)
            state_str = "ACTIVE" if state else "SAFE"
            logger.debug(f"Motor GPIO{pin} set to {state_str}")
            return True
        except Exception as e:
            logger.error(f"Failed to set motor GPIO{pin}: {e}")
            return False
    
    def set_all_motors(self, state: bool) -> bool:
        """
        Set all motor pins to the given state.
        
        Args:
            state: True = active (HIGH), False = safe (LOW)
            
        Returns:
            True if successful
        """
        if self._lockdown_active:
            logger.warning("Cannot change motors - LOCKDOWN ACTIVE")
            return False
        
        success = True
        for pin in self.motor_pins:
            if not self.set_motor(pin, state):
                success = False
        
        return success
    
    def network_reset(self, hold_time_ms: int = 100) -> bool:
        """
        Trigger network PHY hardware reset.
        Holds PHY in reset for specified time, then releases.
        
        Args:
            hold_time_ms: Time to hold PHY in reset (milliseconds)
            
        Returns:
            True if successful
        """
        if self._lockdown_active:
            logger.warning("Cannot reset network - LOCKDOWN ACTIVE")
            return False
        
        try:
            # Hold PHY in reset (HIGH)
            GPIO.output(self.network_reset_pin, self.STATE_ACTIVE)
            logger.info(f"Network PHY held in RESET")
            
            # Hold for specified time
            time.sleep(hold_time_ms / 1000.0)
            
            # Release reset (LOW)
            GPIO.output(self.network_reset_pin, self.STATE_SAFE)
            logger.info("Network PHY released from RESET")
            
            return True
        except Exception as e:
            logger.error(f"Failed to reset network PHY: {e}")
            return False
    
    def set_power_gate(self, state: bool) -> bool:
        """
        Control external power gate relay.
        
        Args:
            state: True = CUT power (HIGH), False = ENABLE power (LOW)
            
        Returns:
            True if successful
        """
        try:
            GPIO.output(self.power_gate_pin, self.STATE_ACTIVE if state else self.STATE_SAFE)
            action = "CUT" if state else "ENABLED"
            logger.info(f"Power gate relay {action}")
            return True
        except Exception as e:
            logger.error(f"Failed to set power gate: {e}")
            return False
    
    def emergency_lockdown(self) -> bool:
        """
        Execute emergency lockdown - set ALL actuators to safe state immediately.
        
        This is the critical fail-closed function:
        - All motors to LOW (no power)
        - Network PHY to RESET (network cut)
        - Power gate to OFF (power cut)
        
        Returns:
            True if successful
        """
        logger.critical("!!! EMERGENCY LOCKDOWN INITIATED !!!")
        
        with self._lock:
            self._lockdown_active = True
        
        success = True
        
        # Set all motors to safe state
        logger.info("Setting all motors to SAFE (LOW) state...")
        for pin in self.motor_pins:
            try:
                GPIO.output(pin, self.STATE_SAFE)
                logger.debug(f"Motor GPIO{pin} set to SAFE")
            except Exception as e:
                logger.error(f"Failed to set motor GPIO{pin} to safe: {e}")
                success = False
        
        # Cut network (hold PHY in reset)
        logger.info("Cutting network connection...")
        try:
            GPIO.output(self.network_reset_pin, self.STATE_ACTIVE)
            logger.info("Network PHY in RESET (network cut)")
        except Exception as e:
            logger.error(f"Failed to cut network: {e}")
            success = False
        
        # Cut power
        logger.info("Cutting external power...")
        try:
            GPIO.output(self.power_gate_pin, self.STATE_ACTIVE)
            logger.info("Power gate OFF (power cut)")
        except Exception as e:
            logger.error(f"Failed to cut power: {e}")
            success = False
        
        # Log final state
        logger.critical("EMERGENCY LOCKDOWN COMPLETE")
        logger.critical("  - All actuators: SAFE (LOW)")
        logger.critical("  - Network: DISABLED")
        logger.critical("  - Power: CUT")
        
        return success
    
    def reset_lockdown(self) -> None:
        """
        Reset lockdown state to allow normal operation.
        This should only be called after verifying the system is safe.
        """
        with self._lock:
            self._lockdown_active = False
        
        # Set network back to normal (LOW = enabled)
        try:
            GPIO.output(self.network_reset_pin, self.STATE_SAFE)
        except Exception as e:
            logger.error(f"Failed to enable network: {e}")
        
        # Set power back to normal (LOW = enabled)
        try:
            GPIO.output(self.power_gate_pin, self.STATE_SAFE)
        except Exception as e:
            logger.error(f"Failed to enable power: {e}")
        
        logger.info("Lockdown state reset - normal operation resumed")
    
    def is_lockdown_active(self) -> bool:
        """Check if lockdown is currently active."""
        return self._lockdown_active
    
    def get_status(self) -> Dict:
        """Get current status of all actuators."""
        status = {
            'lockdown_active': self._lockdown_active,
            'motor_pins': {},
            'network_reset': None,
            'power_gate': None
        }
        
        # Read motor states
        for pin in self.motor_pins:
            try:
                state = GPIO.input(pin)
                status['motor_pins'][pin] = 'ACTIVE' if state == self.STATE_ACTIVE else 'SAFE'
            except:
                status['motor_pins'][pin] = 'UNKNOWN'
        
        # Read network reset state
        try:
            state = GPIO.input(self.network_reset_pin)
            status['network_reset'] = 'RESET' if state == self.STATE_ACTIVE else 'ENABLED'
        except:
            status['network_reset'] = 'UNKNOWN'
        
        # Read power gate state
        try:
            state = GPIO.input(self.power_gate_pin)
            status['power_gate'] = 'OFF' if state == self.STATE_ACTIVE else 'ON'
        except:
            status['power_gate'] = 'UNKNOWN'
        
        return status


def create_actuator_controller(config: dict) -> ActuatorController:
    """
    Factory function to create actuator controller from config.
    
    Args:
        config: Configuration dictionary with actuator settings
        
    Returns:
        Configured ActuatorController instance
    """
    actuator_config = config.get('actuators', {})
    
    return ActuatorController(
        motor_pins=actuator_config.get('motors', [17, 18, 22, 23, 24, 25, 26, 27]),
        network_reset_pin=actuator_config.get('network_reset', 14),
        power_gate_pin=actuator_config.get('power_gate', 15)
    )


# Standalone test mode
if __name__ == "__main__":
    import sys
    
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    print("Testing ActuatorController...")
    
    # Test with mock pins
    controller = ActuatorController(
        motor_pins=[17, 18, 22, 23],  # Using first 4 for testing
        network_reset_pin=14,
        power_gate_pin=15
    )
    
    controller.initialize()
    
    print("\n--- Testing motor control ---")
    controller.set_motor(17, True)
    time.sleep(0.5)
    controller.set_motor(17, False)
    
    print("\n--- Testing network reset ---")
    controller.network_reset(hold_time_ms=100)
    
    print("\n--- Testing power gate ---")
    controller.set_power_gate(True)  # Cut power
    time.sleep(0.5)
    controller.set_power_gate(False)  # Enable power
    
    print("\n--- Testing emergency lockdown ---")
    controller.emergency_lockdown()
    
    print("\n--- Current Status ---")
    status = controller.get_status()
    print(f"Lockdown Active: {status['lockdown_active']}")
    print(f"Motor States: {status['motor_pins']}")
    print(f"Network Reset: {status['network_reset']}")
    print(f"Power Gate: {status['power_gate']}")
    
    print("\nTest complete!")
