;; Action Agent - WebAssembly Text Format
;; This module implements the Action agent for execution and task handling
;;
;; Interface:
;;   - init() -> initializes the agent
;;   - process(input_ptr: i32, input_len: i32) -> i32
;;   - execute(action_ptr: i32, action_len: i32) -> i32

(module
  ;; Import host functions
  (import "host" "log" (func $host_log (param i32 i32 i32)))
  (import "host" "allocate" (func $host_allocate (param i32) (result i32)))
  (import "host" "deallocate" (func $host_deallocate (param i32 i32)))
  (import "host" "get_agent_id" (func $get_agent_id (result i32)))

  ;; Memory
  (memory 1)
  (export "memory" (memory 0))

  ;; Agent state
  (global $actions_executed (mut i32) (i32.const 0))
  (global $initialized (mut i32) (i32.const 0))

  ;; Helper: string length
  (func $strlen (param $ptr i32) (result i32)
    (local $curr i32)
    (local $byte i32)
    (block $break
      (loop $loop
        (local.set $curr (local.get $ptr))
        (local.set $byte (i32.load8_u (local.get $curr)))
        (br_if $break (i32.eqz (local.get $byte)))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $ptr)
  )

  ;; Helper: log message
  (func $log (param $msg_ptr i32)
    (local $msg_len i32)
    (local.set $msg_len (call $strlen (local.get $msg_ptr)))
    (call $host_log (i32.const 1) (local.get $msg_ptr) (local.get $msg_len))
  )

  ;; Initialize function
  (func $init (export "init")
    (global.set $initialized (i32.const 1))
    (global.set $actions_executed (i32.const 0))
    ;; Log initialization
    (call $log (i32.const 0))
  )

  ;; Main processing function
  (func $process (export "process") (param $input_ptr i32) (param $input_len i32) (result i32)
    ;; Check if initialized
    (if (i32.eqz (global.get $initialized))
      (then
        (call $init)
      )
    )
    
    ;; Simple processing: return actions executed
    (global.get $actions_executed)
  )

  ;; Execute function
  (func $execute (export "execute") (param $action_ptr i32) (param $action_len i32) (result i32)
    ;; Increment actions counter
    (global.set $actions_executed (i32.add (global.get $actions_executed) (i32.const 1)))
    
    ;; Return success
    (i32.const 1)
  )

  ;; Get actions executed count
  (func $get_actions_executed (export "get_actions_executed") (result i32)
    (global.get $actions_executed)
  )

  ;; Reset actions counter
  (func $reset (export "reset")
    (global.set $actions_executed (i32.const 0))
  )

  ;; Data section
  (data (i32.const 0) "Action agent initialized\00")
)
