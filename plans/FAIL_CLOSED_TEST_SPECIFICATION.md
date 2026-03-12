# Hardware Fail-Closed Architecture Test Specification

## ITHERIS + JARVIS System

> **Version**: 1.0  
> **Classification**: Test Specification  
> **Status**: Specification for Test Suite Implementation  
> **Target**: Intel i9-13900K (Sovereign Controller) + Raspberry Pi CM4 (GPIO Bridge) + Infineon SLB9670 TPM 2.0  

---

## Executive Summary

This test specification defines comprehensive tests for the fail-closed hardware architecture implemented in the ITHERIS + JARVIS cognitive system. The specification covers hardware watchdog mechanisms, heartbeat signaling, kill chain execution, GPIO bridge control, TPM 2.0 memory sealing, and integration scenarios.

### Verification Targets

| Requirement | Target | Test Category |
|-------------|--------|---------------|
| Zero actuation within 500ms | ≤500ms | Integration Tests |
| Memory seal by TPM on fail-closed | Success | TPM Tests |
| All actuators go LOW on lockdown | 100% | GPIO Bridge Tests |
| Network isolation achieved | PHY reset | GPIO Bridge Tests |
| Recovery requires human intervention | Physical HSM | Recovery Tests |

---

## 1. Hardware Watchdog Tests

### Test Category: FC-HW (Fail-Closed Hardware Watchdog)

#### FC-HW-001: Watchdog Device Open

| Property | Value |
|----------|-------|
| **Test ID** | FC-HW-001 |
| **Test Description** | Verify watchdog device `/dev/watchdog` opens correctly |
| **Test Setup** | Linux environment with watchdog driver loaded |
| **Dependencies** | `/dev/watchdog` device file exists |
| **Procedure** | 1. Initialize Watchdog module<br>2. Attempt to open `/dev/watchdog`<br>3. Verify file handle is valid |
| **Expected Result** | Watchdog device opens without error, returns valid file handle |
| **Pass Criteria** | File handle is valid, no error returned |
| **Failure Handling** | Fall back to software simulation mode |

#### FC-HW-002: Watchdog Configuration

| Property | Value |
|----------|-------|
| **Test ID** | FC-HW-002 |
| **Test Description** | Verify watchdog is configured with 500ms timeout |
| **Test Setup** | Watchdog device opened successfully |
| **Dependencies** | FC-HW-001 |
| **Procedure** | 1. Set watchdog timeout to 1 second (500ms rounded up in Linux)<br>2. Read back timeout value<br>3. Verify configuration |
| **Expected Result** | Timeout is set to 1 second (Linux watchdog uses seconds) |
| **Pass Criteria** | Timeout value matches configuration (±100ms) |

#### FC-HW-003: Watchdog Kick Mechanism

| Property | Value |
|----------|-------|
| **Test ID** | FC-HW-003 |
| **Test Description** | Verify kick mechanism resets watchdog timer at 400ms intervals |
| **Test Setup** | Watchdog configured with 1s timeout |
| **Dependencies** | FC-HW-002 |
| **Procedure** | 1. Start watchdog timer<br>2. Kick watchdog every 400ms for 5 iterations<br>3. Monitor for timeout events |
| **Expected Result** | No timeout occurs during regular kicks |
| **Pass Criteria** | All 5 kicks successful, no timeout triggered |
| **Edge Case** | Verify kick at 600ms causes timeout (missed kick) |

#### FC-HW-004: Watchdog Timeout Triggers NMI

| Property | Value |
|----------|-------|
| **Test ID** | FC-HW-004 |
| **Test Description** | Verify watchdog timeout triggers NMI handler |
| **Test Setup** | Watchdog configured, NMI handler registered |
| **Dependencies** | FC-HW-003 |
| **Procedure** | 1. Configure watchdog with 1s timeout<br>2. Do NOT kick for 2 seconds<br>3. Verify NMI handler is invoked |
| **Expected Result** | NMI handler receives timeout signal |
| **Pass Criteria** | NMI handler called within 1.5s of last kick |
| **Safety Note** | Test only in controlled environment |

#### FC-HW-005: Watchdog Disable on Graceful Shutdown

| Property | Value |
|----------|-------|
| **Test ID** | FC-HW-005 |
| **Test Description** | Verify watchdog is properly disabled on graceful shutdown |
| **Test Setup** | System in normal operation |
| **Dependencies** | FC-HW-001 |
| **Procedure** | 1. Initialize watchdog<br>2. Initiate graceful shutdown<br>3. Write watchdog "V" magic character to disable |
| **Expected Result** | Watchdog disabled, system can shutdown cleanly |
| **Pass Criteria** | Disable command succeeds, no timeout during shutdown |

#### FC-HW-006: Watchdog Status Reporting

| Property | Value |
|----------|-------|
| **Test ID** | FC-HW-006 |
| **Test Description** | Verify watchdog status is correctly reported |
| **Test Setup** | Watchdog module initialized |
| **Dependencies** | FC-HW-001 |
| **Procedure** | 1. Query watchdog status<br>2. Verify fields: enabled, timeout_occurred, timeout_secs |
| **Expected Result** | Status fields accurately reflect watchdog state |
| **Pass Criteria** | All status fields match actual state |

---

## 2. Heartbeat Signal Tests

### Test Category: FC-HB (Fail-Closed Heartbeat)

#### FC-HB-001: Heartbeat Generation Frequency

| Property | Value |
|----------|-------|
| **Test ID** | FC-HB-001 |
| **Test Description** | Verify heartbeat is generated at 100Hz (10ms period) |
| **Test Setup** | Heartbeat module initialized |
| **Dependencies** | GPIO sysfs available |
| **Procedure** | 1. Start heartbeat generator on GPIO6<br>2. Measure 10 consecutive transitions<br>3. Calculate frequency |
| **Expected Result** | Frequency is 100Hz ±5Hz |
| **Pass Criteria** | Average period = 10ms ±0.5ms |

#### FC-HB-002: Heartbeat Voltage Level

| Property | Value |
|----------|-------|
| **Test ID** | FC-HB-002 |
| **Test Description** | Verify heartbeat outputs 3.3V logic level |
| **Test Setup** | Heartbeat running on GPIO6 |
| **Dependencies** | FC-HB-001 |
| **Procedure** | 1. Measure voltage on GPIO6 during HIGH state<br>2. Measure voltage during LOW state |
| **Expected Result** | HIGH = 3.3V, LOW = 0V |
| **Pass Criteria** | HIGH voltage ≥3.0V, LOW voltage ≤0.3V |

#### FC-HB-003: Heartbeat Duty Cycle

| Property | Value |
|----------|-------|
| **Test ID** | FC-HB-003 |
| **Test Description** | Verify heartbeat has 50% duty cycle |
| **Test Setup** | Heartbeat running on GPIO6 |
| **Dependencies** | FC-HB-001 |
| **Procedure** | 1. Measure time in HIGH state over 10 cycles<br>2. Measure time in LOW state over 10 cycles<br>3. Calculate duty cycle |
| **Expected Result** | Duty cycle = 50% ±5% |
| **Pass Criteria** | HIGH time = 5ms ±0.5ms per cycle |

#### FC-HB-004: Heartbeat Stop on System Failure

| Property | Value |
|----------|-------|
| **Test ID** | FC-HB-004 |
| **Test Description** | Verify heartbeat stops immediately on system failure |
| **Test Setup** | Heartbeat running, kill chain can be triggered |
| **Dependencies** | FC-HB-001, FC-KC-001 |
| **Procedure** | 1. Start heartbeat<br>2. Trigger kill chain<br>3. Verify heartbeat stops within 10ms |
| **Expected Result** | Heartbeat stops immediately when kill chain executes |
| **Pass Criteria** | GPIO6 goes LOW and stays LOW |

#### FC-HB-005: Heartbeat GPIO Export

| Property | Value |
|----------|-------|
| **Test ID** | FC-HB-005 |
| **Test Description** | Verify GPIO6 is properly exported and configured |
| **Test Setup** | GPIO sysfs available |
| **Dependencies** | None |
| **Procedure** | 1. Export GPIO6 via sysfs<br>2. Set direction to OUT<br>3. Verify direction |
| **Expected Result** | GPIO6 exported, direction = out |
| **Pass Criteria** | `/sys/class/gpio/gpio6/direction` contains "out" |

---

## 3. Kill Chain Tests

### Test Category: FC-KC (Fail-Closed Kill Chain)

#### FC-KC-001: Kill Chain CLI Instruction Execution

| Property | Value |
|----------|-------|
| **Test ID** | FC-KC-001 |
| **Test Description** | Verify CLI (Clear Interrupts) instruction is executed |
| **Test Setup** | Kill chain module loaded |
| **Dependencies** | None |
| **Procedure** | 1. Call execute_kill_chain()<br>2. Verify CLI assembly is executed |
| **Expected Result** | CLI instruction executes, interrupts disabled |
| **Pass Criteria** | No interrupts can be serviced after CLI |
| **Safety Note** | This test should use a mock/simulation |

#### FC-KC-002: Kill Chain TLB Flush

| Property | Value |
|----------|-------|
| **Test ID** | FC-KC-002 |
| **Test Description** | Verify TLB is flushed via CR3 reload |
| **Test Setup** | Kill chain executing |
| **Dependencies** | FC-KC-001 |
| **Procedure** | 1. Execute TLB flush stage<br>2. Verify CR3 is reloaded |
| **Expected Result** | TLB entries are invalidated |
| **Pass Criteria** | CR3 read/write completes successfully |
| **Performance Target** | Cycles 3-10 (8 cycles) |

#### FC-KC-003: Kill Chain Memory Protection

| Property | Value |
|----------|-------|
| **Test ID** | FC-KC-003 |
| **Test Description** | Verify memory protection (mprotect PROT_NONE) is applied |
| **Test Setup** | Julia process memory accessible |
| **Dependencies** | None |
| **Procedure** | 1. Scan /proc/self/maps for writable regions<br>2. Call protect_current_process_memory()<br>3. Verify all regions have PROT_NONE |
| **Expected Result** | All memory regions protected |
| **Pass Criteria** | mprotect returns 0 for all regions |
| **Performance Target** | Cycles 11-50 (40 cycles) |

#### FC-KC-004: Kill Chain GPIO Emergency Shutdown Signal

| Property | Value |
|----------|-------|
| **Test ID** | FC-KC-004 |
| **Test Description** | Verify GPIO emergency shutdown signal is triggered |
| **Test Setup** | Emergency GPIO configured |
| **Dependencies** | None |
| **Procedure** | 1. Call trigger_emergency_shutdown()<br>2. Verify GPIO4 is set to LOW |
| **Expected Result** | Emergency shutdown signal sent to CM4 |
| **Pass Criteria** | GPIO4 value = 0 |
| **Performance Target** | Cycles 51-80 (30 cycles) |

#### FC-KC-005: Kill Chain HLT Instruction

| Property | Value |
|----------|-------|
| **Test ID** | FC-KC-005 |
| **Test Description** | Verify CPU is halted with HLT instruction |
| **Test Setup** | Kill chain in final stage |
| **Dependencies** | FC-KC-001 through FC-KC-004 |
| **Procedure** | 1. Execute HLT stage<br>2. Verify CPU halts |
| **Expected Result** | CPU enters halt state |
| **Pass Criteria** | CPU does not execute further instructions |
| **Safety Note** | Use simulation only - actual HLT halts CPU |

#### FC-KC-006: Kill Chain Cycle Count Measurement

| Property | Value |
|----------|-------|
| **Test ID** | FC-KC-006 |
| **Test Description** | Verify total kill chain completes within 120 cycles |
| **Test Setup** | Kill chain module with cycle counter |
| **Dependencies** | FC-KC-001 through FC-KC-005 |
| **Procedure** | 1. Execute full kill chain<br>2. Measure cycle count from CLI to HLT |
| **Expected Result** | Total cycles ≤ 120 |
| **Pass Criteria** | Cycle count ≤ 120 |

#### FC-KC-007: Kill Chain Actuator Lockdown

| Property | Value |
|----------|-------|
| **Test ID** | FC-KC-007 |
| **Test Description** | Verify all actuators are set to LOW via GPIO lockdown |
| **Test Setup** | Actuator controller initialized |
| **Dependencies** | FC-KC-004 |
| **Procedure** | 1. Set actuators to various states<br>2. Call lockdown_actuators()<br>3. Verify all actuators go LOW |
| **Expected Result** | All actuator pins set to LOW |
| **Pass Criteria** | All actuator GPIO values = 0 |

---

## 4. GPIO Bridge Tests

### Test Category: FC-GPIO (Fail-Closed GPIO Bridge)

#### FC-GPIO-001: Heartbeat Monitor Timeout Detection

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-001 |
| **Test Description** | Verify heartbeat monitor detects timeout at 30ms |
| **Test Setup** | HeartbeatMonitor initialized with 30ms timeout |
| **Dependencies** | None |
| **Procedure** | 1. Start heartbeat monitor<br>2. Do not send heartbeat for 50ms<br>3. Verify timeout callback is triggered |
| **Expected Result** | Timeout detected after 30ms of no heartbeat |
| **Pass Criteria** | on_timeout callback called within 35ms |

#### FC-GPIO-002: Actuator Pins Go LOW on Lockdown

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-002 |
| **Test Description** | Verify all actuator pins go LOW on lockdown |
| **Test Setup** | ActuatorController initialized with all motor pins |
| **Dependencies** | None |
| **Procedure** | 1. Set all actuators to HIGH (active)<br>2. Call lockdown_all()<br>3. Verify all pins read LOW |
| **Expected Result** | All actuator pins = LOW |
| **Pass Criteria** | 13 motor pins + 2 control pins = 15 pins LOW |

#### FC-GPIO-003: Network PHY Reset on Lockdown

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-003 |
| **Test Description** | Verify network PHY reset is triggered on lockdown |
| **Test Setup** | ActuatorController with network reset pin |
| **Dependencies** | FC-GPIO-002 |
| **Procedure** | 1. Verify network reset pin is LOW (enabled)<br>2. Trigger lockdown<br>3. Verify network reset pin goes HIGH |
| **Expected Result** | Network PHY held in reset |
| **Pass Criteria** | GPIO14 = HIGH after lockdown |

#### FC-GPIO-004: Power Gate Relay Activation

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-004 |
| **Test Description** | Verify power gate relay is activated on lockdown |
| **Test Setup** | ActuatorController with power gate pin |
| **Dependencies** | FC-GPIO-002 |
| **Procedure** | 1. Verify power gate pin is LOW (power enabled)<br>2. Trigger lockdown<br>3. Verify power gate pin goes HIGH |
| **Expected Result** | External power circuit cut |
| **Pass Criteria** | GPIO15 = HIGH after lockdown |

#### FC-GPIO-005: Emergency Signal Handling

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-005 |
| **Test Description** | Verify emergency shutdown signal is properly handled |
| **Test Setup** | EmergencyHandler monitoring GPIO4 |
| **Dependencies** | None |
| **Procedure** | 1. Start emergency handler<br>2. Pull GPIO4 LOW (simulate panic)<br>3. Verify on_emergency callback triggered |
| **Expected Result** | Emergency state activated |
| **Pass Criteria** | is_emergency_active() returns True within 15ms |

#### FC-GPIO-006: Serial Communication

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-006 |
| **Test Description** | Verify serial communication with i9 host |
| **Test Setup** | CommsInterface configured for serial |
| **Dependencies** | None |
| **Procedure** | 1. Open serial port<br>2. Send HEARTBEAT command<br>3. Verify response |
| **Expected Result** | Bidirectional communication works |
| **Pass Criteria** | Commands sent and acknowledged |

#### FC-GPIO-007: TCP Communication

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-007 |
| **Test Description** | Verify TCP communication with i9 host |
| **Test Setup** | CommsInterface configured for TCP |
| **Dependencies** | None |
| **Procedure** | 1. Start TCP server on port 9000<br>2. Connect from i9 host<br>3. Send/receive commands |
| **Expected Result** | TCP socket communication works |
| **Pass Criteria** | Commands sent and acknowledged over TCP |

#### FC-GPIO-008: GPIO Permission Handling

| Property | Value |
|----------|-------|
| **Test ID** | FC-GPIO-008 |
| **Test Description** | Verify graceful handling of GPIO permission denied |
| **Test Setup** | Running without root privileges |
| **Dependencies** | None |
| **Procedure** | 1. Attempt GPIO operations without permissions<br>2. Verify graceful fallback |
| **Expected Result** | Error handled, simulation mode used |
| **Pass Criteria** | No crash, warning logged |

---

## 5. TPM 2.0 Memory Sealing Tests

### Test Category: FC-TPM (Fail-Closed TPM)

#### FC-TPM-001: TPM Device Detection

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-001 |
| **Test Description** | Verify TPM device is detected (/dev/tpm0 or /dev/tpmrm0) |
| **Test Setup** | TPM hardware present |
| **Dependencies** | None |
| **Procedure** | 1. Query for TPM device files<br>2. Verify /dev/tpm0 or /dev/tpmrm0 exists |
| **Expected Result** | TPM device available |
| **Pass Criteria** | At least one TPM device file exists |

#### FC-TPM-002: TPM Context Initialization

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-002 |
| **Test Description** | Verify TPM context initializes correctly |
| **Test Setup** | TPM device detected |
| **Dependencies** | FC-TPM-001 |
| **Procedure** | 1. Create TpmContext<br>2. Initialize with device TCTI<br>3. Verify context is valid |
| **Expected Result** | Context initialized successfully |
| **Pass Criteria** | Esys_Initialize returns TSS2_RC_SUCCESS |

#### FC-TPM-003: PCR Read Operations

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-003 |
| **Test Description** | Verify PCR values can be read |
| **Test Setup** | TPM context initialized |
| **Dependencies** | FC-TPM-002 |
| **Procedure** | 1. Read PCR 17 (MemorySeal)<br>2. Read PCR 18 (MemorySeal_State)<br>3. Verify values returned |
| **Expected Result** | PCR values read successfully |
| **Pass Criteria** | Esys_PCR_Read returns success, 32 bytes returned |

#### FC-TPM-004: Memory Sealing Operation

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-004 |
| **Test Description** | Verify memory can be sealed with TPM |
| **Test Setup** | TPM context initialized, PCR policy configured |
| **Dependencies** | FC-TPM-002, FC-TPM-003 |
| **Procedure** | 1. Create PCR policy for PCRs 17, 18<br>2. Serialize memory state<br>3. Call TPM2_Create with sealed key |
| **Expected Result** | Sealed blob created |
| **Pass Criteria** | Esys_Create returns success, sealed blob produced |

#### FC-TPM-005: Memory Unsealing Operation

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-005 |
| **Test Description** | Verify sealed memory can be unsealed |
| **Test Setup** | Memory sealed from FC-TPM-004 |
| **Dependencies** | FC-TPM-004 |
| **Procedure** | 1. Load sealed blob<br>2. Call TPM2_Unseal<br>3. Verify deserialized memory matches original |
| **Expected Result** | Memory unsealed successfully |
| **Pass Criteria** | Unsealed data matches original sealed data |

#### FC-TPM-006: PCR Extend on Fail-Closed

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-006 |
| **Test Description** | Verify PCRs are extended when fail-closed occurs |
| **Test Setup** | TPM context initialized |
| **Dependencies** | FC-TPM-003 |
| **Procedure** | 1. Record initial PCR 17 value<br>2. Trigger fail-closed (seal memory)<br>3. Read PCR 17 again<br>4. Verify value changed |
| **Expected Result** | PCR 17 extended with fail-closed event |
| **Pass Criteria** | PCR 17 value ≠ initial value |

#### FC-TPM-007: Chain-of-Custody Verification

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-007 |
| **Test Description** | Verify chain-of-custody via TPM quote |
| **Test Setup** | TPM context initialized |
| **Dependencies** | FC-TPM-003 |
| **Procedure** | 1. Create TPM quote for PCRs 0,1,7,14,17,18<br>2. Verify quote signature<br>3. Extract PCR values |
| **Expected Result** | Quote produced and verified |
| **Pass Criteria** | TPM quote valid, signature verified |

#### FC-TPM-008: Recovery Ceremony Workflow

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-008 |
| **Test Description** | Verify recovery requires physical HSM intervention |
| **Test Setup** | System in fail-closed state |
| **Dependencies** | FC-TPM-005 |
| **Procedure** | 1. Attempt software-only recovery (should fail)<br>2. Provide HSM authorization<br>3. Verify recovery succeeds |
| **Expected Result** | Recovery blocked without HSM |
| **Pass Criteria** | Unseal fails without proper authorization |

#### FC-TPM-009: TPM Unavailable Fallback

| Property | Value |
|----------|-------|
| **Test ID** | FC-TPM-009 |
| **Test Description** | Verify graceful handling when TPM is unavailable |
| **Test Setup** | TPM device not present |
| **Dependencies** | None |
| **Procedure** | 1. Initialize TPM module without hardware<br>2. Verify graceful error handling |
| **Expected Result** | Error handled, system can continue |
| **Pass Criteria** | No crash, error logged |

---

## 6. Integration Tests

### Test Category: FC-INT (Fail-Closed Integration)

#### FC-INT-001: Full Fail-Closed Flow

| Property | Value |
|----------|-------|
| **Test ID** | FC-INT-001 |
| **Test Description** | Verify complete fail-closed flow: panic → seal → lockdown → halt |
| **Test Setup** | All components initialized |
| **Dependencies** | FC-HW-001, FC-HB-001, FC-KC-001, FC-TPM-004, FC-GPIO-002 |
| **Procedure** | 1. Start system in normal operation<br>2. Simulate kernel crash (forced panic)<br>3. Verify kill chain executes<br>4. Verify memory sealed<br>5. Verify actuators locked |
| **Expected Result** | Complete fail-closed sequence executes |
| **Pass Criteria** | All stages complete: panic→seal→lockdown→halt |

#### FC-INT-002: Zero Actuation Within 500ms

| Property | Value |
|----------|-------|
| **Test ID** | FC-INT-002 |
| **Test Description** | Verify zero actuation achieved within 500ms of kernel crash |
| **Test Setup** | System in normal operation |
| **Dependencies** | FC-INT-001 |
| **Procedure** | 1. Start system in normal operation<br>2. Trigger panic<br>3. Measure time until all actuators = LOW<br>4. Verify time ≤ 500ms |
| **Expected Result** | All actuators LOW within 500ms |
| **Pass Criteria** | Total time ≤ 500ms |

#### FC-INT-003: TPM Seal Success on Fail-Closed

| Property | Value |
|----------|-------|
| **Test ID** | FC-INT-003 |
| **Test Description** | Verify TPM sealing succeeds during fail-closed |
| **Test Setup** | System in normal operation |
| **Dependencies** | FC-TPM-004 |
| **Procedure** | 1. Trigger fail-closed<br>2. Capture memory state<br>3. Seal with TPM<br>4. Verify sealed blob exists |
| **Expected Result** | Memory sealed to TPM |
| **Pass Criteria** | Sealed blob persisted to disk |

#### FC-INT-004: Simulated Kernel Crash

| Property | Value |
|----------|-------|
| **Test ID** | FC-INT-004 |
| **Test Description** | Verify system responds to simulated kernel crash |
| **Test Setup** | System in normal operation |
| **Dependencies** | FC-INT-001 |
| **Procedure** | 1. Send SIGSEGV to simulate crash<br>2. Verify panic handler triggers<br>3. Verify fail-closed sequence |
| **Expected Result** | Kill chain activates on signal |
| **Pass Criteria** | All fail-closed actions execute |

#### FC-INT-005: Network Isolation Verification

| Property | Value |
|----------|-------|
| **Test ID** | FC-INT-005 |
| **Test Description** | Verify network is isolated on fail-closed |
| **Test Setup** | Network connection active |
| **Dependencies** | FC-GPIO-003 |
| **Procedure** | 1. Establish network connection<br>2. Trigger fail-closed<br>3. Verify network PHY reset<br>4. Attempt network access |
| **Expected Result** | Network disabled after fail-closed |
| **Pass Criteria** | GPIO14 HIGH, no network traffic |

---

## 7. Recovery Tests

### Test Category: FC-REC (Fail-Closed Recovery)

#### FC-REC-001: Resealing Requires Human Intervention

| Property | Value |
|----------|-------|
| **Test ID** | FC-REC-001 |
| **Test Description** | Verify resealing requires human intervention |
| **Test Setup** | System in fail-closed state |
| **Dependencies** | FC-TPM-008 |
| **Procedure** | 1. System in fail-closed state<br>2. Attempt automatic reseal (should fail)<br>3. Verify manual intervention required |
| **Expected Result** | Auto reseal blocked |
| **Pass Criteria** | Error returned, human action required |

#### FC-REC-002: Physical HSM Integration

| Property | Value |
|----------|-------|
| **Test ID** | FC-REC-002 |
| **Test Description** | Verify physical HSM integration for recovery |
| **Test Setup** | External HSM connected |
| **Dependencies** | FC-REC-001 |
| **Procedure** | 1. Connect physical HSM<br>2. Provide HSM authorization<br>3. Verify recovery succeeds |
| **Expected Result** | HSM-based recovery works |
| **Pass Criteria** | Recovery completes with HSM |

#### FC-REC-003: Multi-Party Authorization

| Property | Value |
|----------|-------|
| **Test ID** | FC-REC-003 |
| **Test Description** | Verify multi-party authorization for critical recovery |
| **Test Setup** | Multiple authorization keys configured |
| **Dependencies** | FC-REC-002 |
| **Procedure** | 1. Attempt recovery with single key (should fail)<br>2. Provide required threshold of keys<br>3. Verify recovery succeeds |
| **Expected Result** | Threshold of keys required |
| **Pass Criteria** | Recovery requires M-of-N keys |

---

## 8. Edge Cases

### Test Category: FC-EDGE (Fail-Closed Edge Cases)

#### FC-EDGE-001: Heartbeat Glitch Tolerance

| Property | Value |
|----------|-------|
| **Test ID** | FC-EDGE-001 |
| **Test Description** | Verify system handles heartbeat glitches gracefully |
| **Test Setup** | Heartbeat monitor running |
| **Dependencies** | FC-GPIO-001 |
| **Procedure** | 1. Send heartbeat<br>2. Introduce 5ms gap (normal)<br>3. Send heartbeat<br>4. Verify no false lockdown |
| **Expected Result** | False positives avoided |
| **Pass Criteria** | No timeout triggered for glitches < 30ms |

#### FC-EDGE-002: Watchdog Failure Handling

| Property | Value |
|----------|-------|
| **Test ID** | FC-EDGE-002 |
| **Test Description** | Verify graceful handling when watchdog fails |
| **Test Setup** | Watchdog device unavailable |
| **Dependencies** | FC-HW-001 |
| **Procedure** | 1. Detect watchdog unavailable<br>2. Fall back to software timer<br>3. Verify fail-closed still works |
| **Expected Result** | Software fallback works |
| **Pass Criteria** | System continues, fail-closed maintained |

#### FC-EDGE-003: GPIO Permission Denied

| Property | Value |
|----------|-------|
| **Test ID** | FC-EDGE-003 |
| **Test Description** | Verify graceful handling of GPIO permission errors |
| **Test Setup** | Running without GPIO permissions |
| **Dependencies** | FC-GPIO-008 |
| **Procedure** | 1. Attempt GPIO operations<br>2. Verify PermissionError handled<br>3. Verify system continues |
| **Expected Result** | Graceful error handling |
| **Pass Criteria** | Warning logged, no crash |

#### FC-EDGE-004: Memory Seal Too Large

| Property | Value |
|----------|-------|
| **Test ID** | FC-EDGE-004 |
| **Test Description** | Verify handling when memory to seal exceeds TPM limits |
| **Test Setup** | Large memory region to seal |
| **Dependencies** | FC-TPM-004 |
| **Procedure** | 1. Create memory larger than TPM NV size<br>2. Attempt to seal<br>3. Verify appropriate error |
| **Expected Result** | Error returned, partial seal or fallback |
| **Pass Criteria** | No crash, error handled |

#### FC-EDGE-005: Concurrent Kill Chain and Recovery

| Property | Value |
|----------|-------|
| **Test ID** | FC-EDGE-005 |
| **Test Description** | Verify handling of recovery attempt during fail-closed |
| **Test Setup** | Kill chain executing |
| **Dependencies** | FC-KC-001 |
| **Procedure** | 1. Trigger fail-closed<br>2. Immediately attempt recovery<br>3. Verify recovery blocked |
| **Expected Result** | Recovery blocked during active fail-closed |
| **Pass Criteria** | Recovery returns error |

#### FC-EDGE-006: Watchdog Timeout During Seal

| Property | Value |
|----------|-------|
| **Test ID** | FC-EDGE-006 |
| **Test Description** | Verify handling when watchdog fires during TPM seal |
| **Test Setup** | TPM seal in progress |
| **Dependencies** | FC-TPM-004 |
| **Procedure** | 1. Start TPM seal operation<br>2. Let watchdog timeout fire<br>3. Verify seal completes or state captured |
| **Expected Result** | Seal completes or emergency backup |
| **Pass Criteria** | No inconsistent state |

---

## Test Execution Matrix

### Priority Matrix

| Priority | Tests | Description |
|----------|-------|-------------|
| P0 - Critical | FC-INT-001, FC-INT-002, FC-TPM-004 | Must pass for production |
| P1 - High | FC-KC-006, FC-GPIO-002, FC-GPIO-003 | Core fail-closed behavior |
| P2 - Medium | FC-HW-001, FC-HB-001, FC-TPM-003 | Hardware integration |
| P3 - Low | FC-REC-*, FC-EDGE-* | Edge cases and recovery |

### Test Environment Requirements

| Requirement | Specification |
|-------------|---------------|
| Hardware | Intel i9-13900K + Raspberry Pi CM4 + Infineon SLB9670 |
| OS | Linux with PREEMPT_RT kernel |
| Software | Rust toolchain, Python 3.9+, TPM2-TSS |
| Test Tools | pytest, cargo test, hardware simulators |

### Test Dependencies Graph

```
FC-HW-001 ──┬── FC-HW-002 ──┬── FC-HW-003 ──┬── FC-HW-004
            │               │               │
            └── FC-HW-005   └── FC-HW-006   └── FC-KC-001 ──┬── FC-KC-002 ──┬── FC-KC-003
                                                               │               │
                                                               └── FC-KC-004 ──┼── FC-KC-005
                                                                              │
                                                                              └── FC-KC-006 ──┬── FC-KC-007
                                                                                              │
FC-GPIO-001 ── FC-GPIO-005 ──┬── FC-INT-001 ──┬── FC-INT-002
                              │                │
            FC-GPIO-002 ──────┤                └── FC-INT-003
                              │
            FC-GPIO-003 ──────┤
                              │
            FC-GPIO-004 ──────┤
                              │
FC-TPM-001 ── FC-TPM-002 ────┼── FC-TPM-003 ──┬── FC-TPM-004 ──┬── FC-TPM-005
                              │                │                │
                              │                └── FC-TPM-006   └── FC-TPM-007
                              │
                              └── FC-TPM-008 ── FC-TPM-009
```

---

## Appendices

### A. GPIO Pin Reference

| Pin | BCM | Signal | Direction | Default | Function |
|-----|-----|--------|-----------|---------|----------|
| 7 | GPIO4 | EMERGENCY_SHUTDOWN | IN | HIGH | i9→CM4 panic |
| 8 | GPIO14 | NETWORK_PHY_RESET | OUT | LOW | PHY reset |
| 10 | GPIO15 | POWER_GATE_RELAY | OUT | LOW | Power control |
| 29 | GPIO5 | HEARTBEAT_IN | IN | LOW | CM4→i9 heartbeat |
| 31 | GPIO6 | HEARTBEAT_OUT | OUT | LOW | i9→CM4 heartbeat |
| 11-13 | GPIO17-27 | ACTUATOR_01-13 | OUT | LOW | Motor control |

### B. PCR Assignments

| PCR | Name | Purpose |
|-----|------|---------|
| 0 | SRTM_Boot | BIOS measurements |
| 1 | SRTM_Config | Platform configuration |
| 7 | SecureBoot | Secure boot state |
| 14 | CommandLine | Kernel command line |
| 17 | MemorySeal | Memory sealing events |
| 18 | MemorySeal_State | Sealed state hash |

### C. Cycle Budget

| Stage | Cycles | Operation |
|-------|--------|-----------|
| 1-2 | 2 | CLI (clear interrupts) |
| 3-10 | 8 | TLB Flush |
| 11-50 | 40 | EPT Poisoning |
| 51-80 | 30 | GPIO Lockdown |
| 81-120 | 40 | HLT |
| **Total** | **120** | |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-10 | Initial test specification |

---

*This test specification is derived from HARDWARE_FAIL_CLOSED_SPECIFICATION.md and TPM2_MEMORY_SEALING_SPECIFICATION.md. All tests should be implemented using the hardware modules in itheris-daemon/src/hardware/ and gpio-bridge/.*
