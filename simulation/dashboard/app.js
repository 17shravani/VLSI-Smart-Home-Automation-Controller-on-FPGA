// file: simulation/dashboard/app.js
// Smart Home Automation FPGA Controller Simulator & Visualizer

// --------------------------------------------------
// 1. Simulation State Variables
// --------------------------------------------------
const STATES = {
    S_IDLE: 0,
    S_MANUAL: 1,
    S_AUTO: 2,
    S_ALARM: 3
};

const STATE_NAMES = ["IDLE (00)", "MANUAL (01)", "AUTO (10)", "ALARM (11)"];

// FPGA State Registers
let state = STATES.S_IDLE;
let pir = false;
let dark = false;
let overcur = false;
let door = false;
let security_mode = false;
let temp_high = false;

let duty_L0 = 0;
let duty_L1 = 0;
let duty_L2 = 0;
let duty_L3 = 0;
let duty_F0 = 0;
let duty_F1 = 0;
let relays = 0; // 4-bit mask (R3..R0)
let alarm_active = false;
let energy_saving = false;

// Manual Registers
let man_L0 = 0;
let man_L1 = 0;
let man_L2 = 0;
let man_L3 = 0;
let man_F0 = 0;
let man_F1 = 0;
let man_R = 0;

// Scheduled Registers
let sched_L0 = 0;
let sched_L1 = 0;
let sched_L2 = 0;
let sched_L3 = 0;
let sched_F0 = 0;
let sched_F1 = 0;
let sched_R = 0;

// Night Mode cap flag
let night_mode = false;

// Clock Timers
let simulated_minute = 1078; // Start at 17:58 (to quickly see 18:00 Evening trigger)
let ticks_10hz_counter = 0;
let manual_idle_cnt = 0;
let auto_idle_cnt = 0;

// UI elements and Waveform History
let waveHistory = [];
const maxWavePoints = 150;
let simulatedClockEdge = 0;

// --------------------------------------------------
// 2. Preset Scenes Lookup (ROM)
// --------------------------------------------------
const scenes = [
    { name: "ALL OFF",  L: [0, 0, 0, 0],       F: [0, 0],     R: 0b0000 },
    { name: "EVENING",  L: [40, 20, 10, 0],    F: [0, 0],     R: 0b0001 },
    { name: "WORK",     L: [200, 180, 0, 0],   F: [80, 0],    R: 0b0010 },
    { name: "NIGHT",    L: [10, 0, 0, 10],     F: [0, 0],     R: 0b0000 },
    { name: "READING",  L: [120, 120, 0, 0],   F: [40, 0],    R: 0b0011 },
    { name: "PARTY",    L: [255, 50, 255, 50], F: [180, 180], R: 0b1100 },
    { name: "ECO",      L: [25, 25, 25, 25],   F: [50, 50],   R: 0b0000 },
    { name: "EMERGENCY",L: [255, 255, 255, 255],F: [0, 0],    R: 0b1111 }
];

// --------------------------------------------------
// 3. Helper Functions & Loggers
// --------------------------------------------------
function logTerminal(message, type = "info") {
    const log = document.getElementById("terminalLog");
    if (!log) return;
    
    const timeStr = new Date().toLocaleTimeString();
    let classname = "log-info";
    if (type === "rx") classname = "log-rx";
    if (type === "tx") classname = "log-tx";
    if (type === "err") classname = "log-err";

    log.innerHTML += `<div class="${classname}">[${timeStr}] ${message}</div>`;
    log.scrollTop = log.scrollHeight; // Auto-scroll
}

function byteToHex(b) {
    return b.toString(16).toUpperCase().padStart(2, '0');
}

// Helper to assemble Tx package: 0x55 <evt> <len> <payload...> <xor>
function sendTxPacket(evt, payload) {
    let len = payload.length;
    let computedXor = evt ^ len;
    for (let i = 0; i < len; i++) {
        computedXor ^= payload[i];
    }
    
    let hexStream = `0x55 ${byteToHex(evt)} ${byteToHex(len)} `;
    for (let i = 0; i < len; i++) {
        hexStream += `${byteToHex(payload[i])} `;
    }
    hexStream += `${byteToHex(computedXor)}`;
    
    logTerminal(`TX EVENT: ${hexStream}`, "tx");
}

// --------------------------------------------------
// 4. FPGA Logic Simulation Tick
// --------------------------------------------------
function simulateFPGATick() {
    // 1. Alternate simulated clock line for waveform drawer
    simulatedClockEdge = simulatedClockEdge === 0 ? 1 : 0;

    // 2. Increment simulated minute timer
    ticks_10hz_counter++;
    if (ticks_10hz_counter >= 100) { // 10 seconds of sim tick = 1 min in dashboard speed
        ticks_10hz_counter = 0;
        simulated_minute = (simulated_minute + 1) % 1440;
        
        // Trigger scheduler check
        checkScheduler();
        
        // Periodic telemetry STATUS event (every 1 simulated minute or 10s of tick)
        sendTelemetryStatus();
    }

    // 3. Manage FSM Timeout Counters
    if (state === STATES.S_MANUAL) {
        manual_idle_cnt++;
    } else {
        manual_idle_cnt = 0;
    }

    if (state === STATES.S_AUTO) {
        if (pir) {
            auto_idle_cnt = 0;
        } else {
            auto_idle_cnt++;
        }
    } else {
        auto_idle_cnt = 0;
    }

    // 4. FSM State Transition Logic
    let next_state = state;
    
    // Priority 1: ALARM
    if (overcur || (security_mode && door)) {
        next_state = STATES.S_ALARM;
    } else {
        switch (state) {
            case STATES.S_IDLE:
                if (pir && dark) {
                    next_state = STATES.S_AUTO;
                }
                break;
            case STATES.S_MANUAL:
                if (manual_idle_cnt >= 150) { // 15s timeout
                    next_state = (pir && dark) ? STATES.S_AUTO : STATES.S_IDLE;
                }
                break;
            case STATES.S_AUTO:
                if (auto_idle_cnt >= 200) { // 20s no motion
                    next_state = STATES.S_IDLE;
                }
                break;
            case STATES.S_ALARM:
                if (!overcur && !security_mode) {
                    next_state = STATES.S_IDLE;
                }
                break;
        }
    }

    // Report state transitions
    if (next_state !== state) {
        logTerminal(`FSM Transition: ${STATE_NAMES[state]} -> ${STATE_NAMES[next_state]}`);
        state = next_state;
    }

    // 5. Output Driver Resolution based on active state
    switch (state) {
        case STATES.S_IDLE:
            alarm_active = false;
            energy_saving = false;
            duty_L0 = sched_L0;
            duty_L1 = sched_L1;
            duty_L2 = sched_L2;
            duty_L3 = sched_L3;
            duty_F0 = sched_F0;
            duty_F1 = sched_F1;
            relays = sched_R;
            break;

        case STATES.S_MANUAL:
            alarm_active = false;
            energy_saving = false;
            // Night mode cap
            duty_L0 = (night_mode && man_L0 > 50) ? 50 : man_L0;
            duty_L1 = (night_mode && man_L1 > 50) ? 50 : man_L1;
            duty_L2 = (night_mode && man_L2 > 50) ? 50 : man_L2;
            duty_L3 = (night_mode && man_L3 > 50) ? 50 : man_L3;
            duty_F0 = man_F0;
            duty_F1 = man_F1;
            relays = man_R;
            break;

        case STATES.S_AUTO:
            alarm_active = false;
            if (auto_idle_cnt >= 100) { // Eco Mode (10s idle)
                energy_saving = true;
                duty_L0 = 15;
                duty_L1 = 15;
                duty_L2 = 15;
                duty_L3 = 15;
                duty_F0 = 40;
                duty_F1 = 40;
                relays = 0;
            } else {
                energy_saving = false;
                if (dark) {
                    duty_L0 = night_mode ? 50 : 150;
                    duty_L1 = night_mode ? 30 : 100;
                    duty_L2 = 0;
                    duty_L3 = 0;
                } else {
                    duty_L0 = 0; duty_L1 = 0; duty_L2 = 0; duty_L3 = 0;
                }
                
                if (temp_high) {
                    duty_F0 = 200; duty_F1 = 0;
                } else {
                    duty_F0 = 0; duty_F1 = 0;
                }
                relays = 0b0011; // Standard relay configuration for auto
            }
            break;

        case STATES.S_ALARM:
            alarm_active = true;
            energy_saving = false;
            // Force lights 100% on, turn off relays/fans
            duty_L0 = 255; duty_L1 = 255; duty_L2 = 255; duty_L3 = 255;
            duty_F0 = 0; duty_F1 = 0;
            relays = 0;
            break;
    }

    // 6. Update Web UI
    updateUIElements();

    // 7. Store Waveform History
    storeWaveformPoint();
    drawWaveforms();
}

// Check Time Scheduler
function checkScheduler() {
    let load_idx = -1;
    if (simulated_minute === 0) load_idx = 0;     // 00:00 -> ALL OFF
    if (simulated_minute === 420) load_idx = 2;   // 07:00 -> WORK
    if (simulated_minute === 1080) load_idx = 1;  // 18:00 -> EVENING
    if (simulated_minute === 1380) load_idx = 3;  // 23:00 -> NIGHT

    if (load_idx !== -1) {
        logTerminal(`[Scheduler] Alarm tick triggered for time ${formatTime(simulated_minute)}. Loading Scene Index: ${load_idx}`);
        const sc = scenes[load_idx];
        sched_L0 = sc.L[0]; sched_L1 = sc.L[1]; sched_L2 = sc.L[2]; sched_L3 = sc.L[3];
        sched_F0 = sc.F[0]; sched_F1 = sc.F[1];
        sched_R = sc.R;
        
        // Pulse state trigger
        if (state === STATES.S_IDLE) {
            duty_L0 = sched_L0; duty_L1 = sched_L1; duty_L2 = sched_L2; duty_L3 = sched_L3;
            duty_F0 = sched_F0; duty_F1 = sched_F1;
            relays = sched_R;
        }
    }
}

// --------------------------------------------------
// 5. UART Packet Parser
// --------------------------------------------------
// Parses 0xAA <cmd> <len> <payload...> <xor>
function parseIncomingUARTBytes(bytes) {
    if (bytes.length < 5) {
        logTerminal("RX Command Error: Packet too short", "err");
        return;
    }
    
    let sof = bytes[0];
    let cmd = bytes[1];
    let len = bytes[2];
    let xorIndex = 3 + len;
    
    if (sof !== 0xAA) {
        logTerminal(`RX Frame Error: Invalid SOF (0x${byteToHex(sof)})`, "err");
        return;
    }

    let calculatedXor = cmd ^ len;
    for (let i = 0; i < len; i++) {
        calculatedXor ^= bytes[3 + i];
    }

    let rxXor = bytes[xorIndex];
    if (calculatedXor !== rxXor) {
        logTerminal(`RX Checksum Error: Calculated 0x${byteToHex(calculatedXor)}, Received 0x${byteToHex(rxXor)}`, "err");
        return;
    }

    logTerminal(`RX CMD SUCCESS: SOF=0xAA CMD=0x${byteToHex(cmd)} LEN=${len} XOR=0x${byteToHex(rxXor)}`, "rx");

    // Execute Command
    let p = bytes.slice(3, 3 + len);
    state = STATES.S_MANUAL; // Force Manual Override on UART write
    manual_idle_cnt = 0;      // Reset inactivity counter

    switch (cmd) {
        case 0x01: // SET_DUTY ch val
            let ch = p[0];
            let val = p[1];
            if (ch === 0) man_L0 = val;
            if (ch === 1) man_L1 = val;
            if (ch === 2) man_L2 = val;
            if (ch === 3) man_L3 = val;
            if (ch === 4) man_F0 = val;
            if (ch === 5) man_F1 = val;
            logTerminal(`Remote command: Set Channel ${ch} to Duty ${val}`);
            break;
        case 0x02: // SET_RELAY mask
            man_R = p[0] & 0x0F;
            logTerminal(`Remote command: Set Relays mask to 4'b${man_R.toString(2).padStart(4, '0')}`);
            break;
        case 0x03: // LOAD_SCENE idx
            let idx = p[0] & 0x07;
            let sc = scenes[idx];
            man_L0 = sc.L[0]; man_L1 = sc.L[1]; man_L2 = sc.L[2]; man_L3 = sc.L[3];
            man_F0 = sc.F[0]; man_F1 = sc.F[1];
            man_R = sc.R;
            logTerminal(`Remote command: Loaded Preset Scene "${sc.name}"`);
            break;
        case 0x04: // SET_NIGHT_MODE value
            night_mode = p[0] === 1;
            logTerminal(`Remote command: Night Mode cap set to ${night_mode}`);
            break;
        default:
            logTerminal(`RX Command Warning: Unknown command 0x${byteToHex(cmd)}`, "err");
    }
}

function sendTelemetryStatus() {
    let payload = [
        duty_L0, duty_L1, duty_L2, duty_L3,
        duty_F0, duty_F1,
        relays,
        (alarm_active ? 1 : 0) | (energy_saving ? 2 : 0) | (night_mode ? 4 : 0)
    ];
    sendTxPacket(0x81, payload);
}

function sendSensorTelemetryEvent() {
    let mask = (pir ? 1 : 0) | (dark ? 2 : 0) | (overcur ? 4 : 0) | (door ? 8 : 0);
    sendTxPacket(0x82, [mask]);
}

// --------------------------------------------------
// 6. UI Update Controllers
// --------------------------------------------------
function formatTime(totalMinutes) {
    let hrs = Math.floor(totalMinutes / 60);
    let mins = totalMinutes % 60;
    return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}`;
}

function updateUIElements() {
    // Current Time
    document.getElementById("clockDisplay").innerText = formatTime(simulated_minute);
    
    // Status text
    document.getElementById("fsmStateText").innerText = STATE_NAMES[state];
    
    // Night mode indicator
    document.getElementById("nightModeBadge").innerText = night_mode ? "ON" : "OFF";
    document.getElementById("nightModeBadge").className = night_mode ? "relay-status relay-on" : "relay-status relay-off";

    // FSM Active Nodes
    document.querySelectorAll(".fsm-node").forEach(node => node.classList.remove("active", "alarm-active"));
    if (state === STATES.S_ALARM) {
        const node = document.getElementById("node-alarm");
        node.classList.add("active", "alarm-active");
    } else {
        if (state === STATES.S_IDLE) document.getElementById("node-idle").classList.add("active");
        if (state === STATES.S_MANUAL) document.getElementById("node-manual").classList.add("active");
        if (state === STATES.S_AUTO) document.getElementById("node-auto").classList.add("active");
    }

    // Actuator Bulbs glowing
    updateBulb("bulb-L0", duty_L0, "L0_val");
    updateBulb("bulb-L1", duty_L1, "L1_val");
    updateBulb("bulb-L2", duty_L2, "L2_val");
    updateBulb("bulb-L3", duty_L3, "L3_val");

    // Actuator Fans rotating
    updateFan("fan-F0", duty_F0, "F0_val");
    updateFan("fan-F1", duty_F1, "F1_val");

    // Relays Clickers
    updateRelayRow("relay-R0", relays & 0b0001);
    updateRelayRow("relay-R1", relays & 0b0010);
    updateRelayRow("relay-R2", relays & 0b0100);
    updateRelayRow("relay-R3", relays & 0b1000);

    // Indicators
    const alarmLed = document.getElementById("led-alarm");
    alarmLed.style.background = alarm_active ? "var(--neon-red)" : "#334155";
    alarmLed.style.boxShadow = alarm_active ? "0 0 12px var(--neon-red)" : "none";

    const ecoLed = document.getElementById("led-eco");
    ecoLed.style.background = energy_saving ? "var(--neon-green)" : "#334155";
    ecoLed.style.boxShadow = energy_saving ? "0 0 12px var(--neon-green)" : "none";
}

function updateBulb(id, duty, valId) {
    const bulb = document.getElementById(id);
    const valueDisp = document.getElementById(valId);
    let pct = Math.round((duty / 255) * 100);
    valueDisp.innerText = `${pct}%`;

    if (duty === 0) {
        bulb.style.backgroundColor = "#334155";
        bulb.style.boxShadow = "none";
    } else {
        let opacity = 0.2 + (duty / 255) * 0.8;
        bulb.style.backgroundColor = `rgba(0, 240, 255, ${opacity})`;
        bulb.style.boxShadow = `0 0 ${10 + (duty/255)*25}px rgba(0, 240, 255, ${opacity * 0.6})`;
    }
}

let fanRotations = { "fan-F0": 0, "fan-F1": 0 };
function updateFan(id, duty, valId) {
    const fan = document.getElementById(id);
    const valueDisp = document.getElementById(valId);
    let pct = Math.round((duty / 255) * 100);
    valueDisp.innerText = `${pct}%`;

    if (duty === 0) {
        fan.style.color = "#64748b";
        fan.style.animation = "none";
    } else {
        fan.style.color = "var(--neon-purple)";
        // Emulate rotation via keyframes or manually incrementing transform angle
        let speed = 4 - (duty / 255) * 3.6; // Speed duration in seconds (0.4s to 4s)
        fan.style.animation = `spin ${speed}s linear infinite`;
    }
}

function updateRelayRow(id, active) {
    const row = document.getElementById(id);
    const badge = row.querySelector(".relay-status");
    if (active) {
        badge.innerText = "CLOSED (ON)";
        badge.className = "relay-status relay-on";
    } else {
        badge.innerText = "OPEN (OFF)";
        badge.className = "relay-status relay-off";
    }
}

// --------------------------------------------------
// 7. Live Logic Analyzer Canvas Plotter
// --------------------------------------------------
function storeWaveformPoint() {
    waveHistory.push({
        clk: simulatedClockEdge,
        state: state,
        L0_duty: duty_L0,
        alarm: alarm_active ? 1 : 0,
        eco: energy_saving ? 1 : 0
    });

    if (waveHistory.length > maxWavePoints) {
        waveHistory.shift();
    }
}

function drawWaveforms() {
    const canvas = document.getElementById("waveCanvas");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    
    // Clear
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    if (waveHistory.length < 2) return;

    let signals = [
        { label: "CLK (50M)", key: "clk", max: 1, color: "#64748b" },
        { label: "STATE", key: "state", max: 3, color: "#bd00ff" },
        { label: "L0 PWM", key: "L0_duty", max: 255, color: "#00f0ff" },
        { label: "ALARM", key: "alarm", max: 1, color: "#ff3131" },
        { label: "ECO", key: "eco", max: 1, color: "#39ff14" }
    ];

    let rowHeight = canvas.height / signals.length;
    
    signals.forEach((sig, idx) => {
        let yOffset = idx * rowHeight;
        
        // Draw Label
        ctx.fillStyle = "#9ca3af";
        ctx.font = "10px monospace";
        ctx.fillText(sig.label, 10, yOffset + 14);

        // Draw dotted separating line
        ctx.strokeStyle = "rgba(255, 255, 255, 0.05)";
        ctx.beginPath();
        ctx.moveTo(0, yOffset + rowHeight);
        ctx.lineTo(canvas.width, yOffset + rowHeight);
        ctx.stroke();

        // Draw signal wave
        ctx.strokeStyle = sig.color;
        ctx.lineWidth = 1.5;
        ctx.beginPath();

        let stepX = canvas.width / maxWavePoints;

        for (let i = 0; i < waveHistory.length; i++) {
            let x = i * stepX;
            let val = waveHistory[i][sig.key];
            
            // Normalize Y
            let pct = val / sig.max;
            let y = yOffset + rowHeight - 6 - (pct * (rowHeight - 16));

            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                let prevVal = waveHistory[i-1][sig.key];
                if (prevVal !== val && sig.key !== "L0_duty") {
                    // Draw digital vertical edge
                    let prevPct = prevVal / sig.max;
                    let prevY = yOffset + rowHeight - 6 - (prevPct * (rowHeight - 16));
                    ctx.lineTo(x, prevY);
                }
                ctx.lineTo(x, y);
            }
        }
        ctx.stroke();
    });
}

// Initialize Canvas Size
function initCanvas() {
    const canvas = document.getElementById("waveCanvas");
    if (!canvas) return;
    canvas.width = canvas.parentElement.clientWidth;
    canvas.height = canvas.parentElement.clientHeight;
}

// --------------------------------------------------
// 8. Event Listeners & Bootstrapping
// --------------------------------------------------
window.addEventListener("resize", initCanvas);

document.addEventListener("DOMContentLoaded", () => {
    initCanvas();
    logTerminal("FPGA Automation Simulator Booted.");
    logTerminal("Standard Time Base: 10 Hz Clock Active.");

    // Input Element Hookups
    document.getElementById("sw-pir").addEventListener("change", (e) => {
        pir = e.target.checked;
        sendSensorTelemetryEvent();
        logTerminal(`Sensor event: PIR Motion changed to ${pir}`);
    });

    document.getElementById("sw-dark").addEventListener("change", (e) => {
        dark = e.target.checked;
        sendSensorTelemetryEvent();
        logTerminal(`Sensor event: LDR light level set to ${dark ? "DARK" : "BRIGHT"}`);
    });

    document.getElementById("sw-overcur").addEventListener("change", (e) => {
        overcur = e.target.checked;
        sendSensorTelemetryEvent();
        logTerminal(`Safety event: Over-current fault set to ${overcur}`);
    });

    document.getElementById("sw-door").addEventListener("change", (e) => {
        door = e.target.checked;
        sendSensorTelemetryEvent();
        logTerminal(`Sensor event: Door magnetic sensor set to ${door ? "OPEN" : "CLOSED"}`);
    });

    document.getElementById("sw-security").addEventListener("change", (e) => {
        security_mode = e.target.checked;
        logTerminal(`Security armed status set to ${security_mode}`);
    });

    document.getElementById("sw-temp").addEventListener("change", (e) => {
        temp_high = e.target.checked;
        logTerminal(`Environment event: Temperature threshold high = ${temp_high}`);
    });

    // Preset Buttons Toggles
    document.querySelectorAll(".btn-preset").forEach((btn, idx) => {
        btn.addEventListener("click", () => {
            logTerminal(`Push button press: Loaded Scene Index ${idx} (${scenes[idx].name})`);
            // Format UART CMD 0x03 packet: 0xAA 0x03 1 idx xor
            let bytes = [0xAA, 0x03, 1, idx, 0x03 ^ 1 ^ idx];
            parseIncomingUARTBytes(bytes);
        });
    });

    // Manual Local Push buttons (Toggles lights in manual mode)
    document.getElementById("btn-toggle-L0").addEventListener("click", () => {
        state = STATES.S_MANUAL;
        man_L0 = man_L0 > 0 ? 0 : 255;
        manual_idle_cnt = 0;
        logTerminal("Physical button push: Toggle Light L0");
    });
    
    document.getElementById("btn-toggle-L1").addEventListener("click", () => {
        state = STATES.S_MANUAL;
        man_L1 = man_L1 > 0 ? 0 : 255;
        manual_idle_cnt = 0;
        logTerminal("Physical button push: Toggle Light L1");
    });

    // Custom UART Packet Sender Hookup
    document.getElementById("btnSendHex").addEventListener("click", () => {
        const input = document.getElementById("hexInput").value.trim();
        if (!input) return;
        
        let hexArr = input.split(/\s+/);
        let byteArr = [];
        
        for (let i = 0; i < hexArr.length; i++) {
            let val = parseInt(hexArr[i], 16);
            if (isNaN(val)) {
                logTerminal(`Hex Send Error: Invalid byte "${hexArr[i]}"`, "err");
                return;
            }
            byteArr.push(val);
        }
        
        parseIncomingUARTBytes(byteArr);
    });

    // Command Selector helper
    document.getElementById("cmdSelect").addEventListener("change", (e) => {
        const cmd = e.target.value;
        const hexInput = document.getElementById("hexInput");
        
        if (cmd === "set_duty_50") {
            // SET_DUTY ch=0 val=128 (50%): 0xAA 0x01 0x02 0x00 0x80 (XOR = 01 ^ 02 ^ 00 ^ 80 = 83)
            hexInput.value = "AA 01 02 00 80 83";
        } else if (cmd === "set_relay_all") {
            // SET_RELAY mask=0x0F (15): 0xAA 0x02 0x01 0x0F (XOR = 02 ^ 01 ^ 0F = 0C)
            hexInput.value = "AA 02 01 0F 0C";
        } else if (cmd === "load_scene_night") {
            // LOAD_SCENE idx=3 (Night): 0xAA 0x03 0x01 0x03 (XOR = 03 ^ 01 ^ 03 = 01)
            hexInput.value = "AA 03 01 03 01";
        } else if (cmd === "night_mode_on") {
            // SET_NIGHT_MODE on=1: 0xAA 0x04 0x01 0x01 (XOR = 04 ^ 01 ^ 01 = 04)
            hexInput.value = "AA 04 01 01 04";
        }
    });

    // Start Simulation Interval (100 ms = 10 Hz Clock Enable Ticks)
    setInterval(simulateFPGATick, 100);
});
