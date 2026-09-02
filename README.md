# 8051 Smart Egg Boiler System

A sensor-driven automated egg cooker powered by the AT89S52 microcontroller, featuring real-time boiling detection, safety abort mechanisms, and dual-display telemetry.

---

### Hardware Configuration Matrix

| Category | Component | Qty | Functional Purpose |
| :--- | :--- | :---: | :--- |
| **Input** | DHT11 Sensor | 1 | Detects water vapor saturation and chamber temperature |
| **Input** | Grove Vibration Sensor | 1 | Detects dynamic boiling motion inside the container |
| **Input** | Rotary Potentiometer | 1 | Analog tuning dial for cooking mode selection |
| **Input** | Tactile Push Buttons | 2 | Mode confirmation & Emergency halt trigger |
| **Output** | 16x2 LCD (I2C) | 1 | Primary user interface for system prompts and status |
| **Output** | TM1637 Display | 1 | Dedicated 4-digit countdown timer |
| **Output** | Status LEDs (Red / Green) | 2 | Operational indicators (`Red` = Running, `Green` = Ready) |
| **Output** | Active Buzzer | 1 | Plays completion melody upon boiling termination |
| **Output** | 5V Relay Module | 1 | Solid-state / mechanical power switch for the heater |
| **Control** | AT89S52 MCU | 1 | Central 8051-core processing microcontroller |
| **Control** | ADC0804 | 1 | 8-bit A/D converter for potentiometer analog signal |
| **Tool** | Arduino Nano | 1 | In-System Programmer (ISP) used to burn firmware |

---

### Module Compatibility

> **Notice on 7-Segment Architecture:**  
> - **With I2C / TM1637 module:** Disregard `7_SEGMENT TEST.zip` and `COUNTDOWN SYSTEM.zip`.  
> - **Discrete 7-Segment displays:** Use a **74HC595 shift register** for parallel-to-serial digit multiplexing.

---

### Operating Cycle

```text
[ Idle ] ──> Select Mode (Potentiometer + ADC0804)
             │
             └──> Confirm (Btn 1) ──> [ Heating ] ──> Relay ON, Red LED ON
                                           │
             ┌─────────────────────────────┴─────────────────────────────┐
             ▼                                                           ▼
     Vibration + Vapor Detected                                Emergency Stop (Btn 2)
             │                                                           │
             ▼                                                           ▼
      [ Countdown ] (TM1637)                                      [ Abort / OFF ]
             │
             ▼
      [ Complete ] ──> Relay OFF, Green LED ON, Melody Alert
