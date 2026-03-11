#!/bin/bash
# GPIO Initialization Script for Raspberry Pi CM4
# Initializes all GPIO pins for fail-closed operation

set -e

# GPIO Base Path
GPIO_PATH="/sys/class/gpio"

# Heartbeat pins
HEARTBEAT_IN=5    # GPIO5 (BCM) - Pin 29
HEARTBEAT_OUT=6   # GPIO6 (BCM) - Pin 31

# Emergency shutdown pin
EMERGENCY_SHUTDOWN=4  # GPIO4 (BCM) - Pin 7

# Network and Power Control
NETWORK_RESET=14  # GPIO14 (BCM) - Pin 8
POWER_GATE=15     # GPIO15 (BCM) - Pin 10

# Status LED
STATUS_LED=26     # GPIO26 (BCM) - Pin 37

# Motor/Actuator pins (BCM numbering)
ACTUATOR_PINS=(17 18 22 23 24 25 26 27)

# All pins to export
ALL_PINS=($HEARTBEAT_IN $HEARTBEAT_OUT $EMERGENCY_SHUTDOWN $NETWORK_RESET $POWER_GATE $STATUS_LED "${ACTUATOR_PINS[@]}")

echo "=========================================="
echo "GPIO Bridge Initialization Script"
echo "=========================================="
echo "Date: $(date)"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "WARNING: Not running as root. Some operations may fail."
    echo "Run with sudo for proper GPIO access."
    echo ""
fi

# Function to export GPIO pin if not already exported
export_pin() {
    local pin=$1
    if [ ! -d "$GPIO_PATH/gpio$pin" ]; then
        echo "$pin" > "$GPIO_PATH/export"
        echo "Exported GPIO$pin"
    else
        echo "GPIO$pin already exported"
    fi
}

# Function to set GPIO direction
set_direction() {
    local pin=$1
    local direction=$2
    echo "$direction" > "$GPIO_PATH/gpio$pin/direction"
    echo "GPIO$pin set to $direction"
}

# Function to set GPIO value
set_value() {
    local pin=$1
    local value=$2
    echo "$value" > "$GPIO_PATH/gpio$pin/value"
    echo "GPIO$pin set to $value"
}

# Export all required pins
echo "Step 1: Exporting GPIO pins..."
echo "-------------------------------"
for pin in "${ALL_PINS[@]}"; do
    export_pin $pin
done
echo ""

# Configure Input pins (heartbeat in, emergency shutdown)
echo "Step 2: Configuring input pins..."
echo "---------------------------------"
set_direction $HEARTBEAT_IN "in"
set_direction $EMERGENCY_SHUTDOWN "in"
echo ""

# Configure Output pins
echo "Step 3: Configuring output pins..."
echo "---------------------------------"

# Heartbeat out (starts LOW)
set_direction $HEARTBEAT_OUT "out"
set_value $HEARTBEAT_OUT 0

# Network PHY reset (starts LOW = enabled)
set_direction $NETWORK_RESET "out"
set_value $NETWORK_RESET 0

# Power gate relay (starts LOW = enabled)
set_direction $POWER_GATE "out"
set_value $POWER_GATE 0

# Status LED (starts LOW = off)
set_direction $STATUS_LED "out"
set_value $STATUS_LED 0

# Actuator pins (all start LOW = safe state)
echo "Step 4: Configuring actuator pins..."
echo "-------------------------------------"
for pin in "${ACTUATOR_PINS[@]}"; do
    set_direction $pin "out"
    set_value $pin 0
done
echo ""

# Verify configuration
echo "Step 5: Verification..."
echo "----------------------"
echo "Input pins:"
echo "  GPIO$HEARTBEAT_IN (HEARTBEAT_IN): $(cat $GPIO_PATH/gpio$HEARTBEAT_IN/direction)"
echo "  GPIO$EMERGENCY_SHUTDOWN (EMERGENCY_SHUTDOWN): $(cat $GPIO_PATH/gpio$EMERGENCY_SHUTDOWN/direction)"

echo ""
echo "Output pins (all should be 'out' and value '0'):"
echo "  GPIO$HEARTBEAT_OUT (HEARTBEAT_OUT): $(cat $GPIO_PATH/gpio$HEARTBEAT_OUT/direction) = $(cat $GPIO_PATH/gpio$HEARTBEAT_OUT/value)"
echo "  GPIO$NETWORK_RESET (NETWORK_RESET): $(cat $GPIO_PATH/gpio$NETWORK_RESET/direction) = $(cat $GPIO_PATH/gpio$NETWORK_RESET/value)"
echo "  GPIO$POWER_GATE (POWER_GATE): $(cat $GPIO_PATH/gpio$POWER_GATE/direction) = $(cat $GPIO_PATH/gpio$POWER_GATE/value)"
echo "  GPIO$STATUS_LED (STATUS_LED): $(cat $GPIO_PATH/gpio$STATUS_LED/direction) = $(cat $GPIO_PATH/gpio$STATUS_LED/value)"

echo ""
echo "Actuator pins:"
for pin in "${ACTUATOR_PINS[@]}"; do
    echo "  GPIO$pin: $(cat $GPIO_PATH/gpio$pin/direction) = $(cat $GPIO_PATH/gpio$pin/value)"
done

echo ""
echo "=========================================="
echo "GPIO Initialization Complete"
echo "=========================================="
echo ""
echo "Default State (FAIL-SAFE):"
echo "  - All actuators: LOW (no power)"
echo "  - Network PHY: ENABLED (LOW)"
echo "  - Power Gate: ENABLED (LOW)"
echo "  - Status LED: OFF"
echo ""
echo "Ready for GPIO Bridge application."
