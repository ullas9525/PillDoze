# 💊 Smart Pill Reminder System for Elderly People

This project is a **smart pill reminder and monitoring system** designed to assist elderly individuals with accurate and timely medication intake. It uses IR sensors, LEDs, and buzzer alerts — all controlled by an Arduino — to ensure pills are taken correctly, and warns if the wrong compartment is accessed.

---

## 🚀 Project Overview

Taking the right medicine at the right time is critical, especially for the elderly. Our system ensures:
- Accurate pill reminders via buzzer alerts at scheduled times (set using a mobile app).
- LED guidance to indicate the correct compartment.
- Real-time pill verification using IR sensors.
- Alerts if a wrong compartment is opened.

No LCD is used. Instead, the system is optimized with LEDs and sensors, keeping it simple and effective.

---

## 🧠 Features

- 🕒 **App-Scheduled Alerts** for pill times
- 🔦 **LED Indicators** show the correct pill compartment
- 👀 **6 IR Sensors** track compartment access
- 🔊 **Buzzer** alerts on schedule or wrong pill attempt
- 🧠 **Smart Detection Logic** to reduce human error
- 🧩 Fully Arduino-based, no external display required

---

## 🔧 Hardware Components

| Component         | Quantity |
|------------------|----------|
| Arduino Uno       | 1        |
| IR Sensors        | 6        |
| LEDs              | 6        |
| Buzzer            | 1        |
| Pill Box Compartments | 6 (manually divided) |
| Power Supply / USB | 1        |

---

## 🖥️ Software Tools

- **Arduino IDE** – Code development and upload
- **Flutter** – For custom scheduling app *(update with actual platform used)*
- **GitHub** – Version control and collaboration

---

## 🧾 How It Works

1. **User schedules pill times via the app(Pilldoze)**.
2. At the scheduled time, the **buzzer sounds**, and the system activates the **LED for the correct compartment**.
3. **IR sensors detect** if the correct pill compartment is accessed.
4. If the **correct pill is taken**, system goes silent.
5. If the **wrong compartment** is accessed, buzzer sounds again as a warning.
6. System resets and waits for the next dose.

---

## 🔁 Circuit Overview

- 💡 The system uses 6 IR sensors aligned with 6 compartments.  
- On scheduled time (via app), Arduino powers the correct LED.  
- IR checks which compartment is opened and triggers alerts accordingly.

---
## 🔮 Future Improvements

🛰️ Add IoT support with ESP32 for remote monitoring
📱 Add SMS or app-based alert for missed doses
📊 Pill intake history logging
🔋 Battery backup system

---

## 📦 Use Cases

🧓 Elderly individuals with regular medication
🧠 Alzheimer’s or dementia patients
🏥 Clinics and care centers
📚 Academic embedded system projects

---

👥 Team & Credits

Developers:
Ullas B R,
Nagapooja G S,
Thrishool M S,
Yashas Kumar R 
