#include <Wire.h>
#include "RTClib.h"

RTC_DS3231 rtc;

const int irPins[6] = {2, 3, 4, 5, 6, 7};       // IR sensor pins
const int ledPins[6] = {8, 9, 10, 11, 12, 13};  // LED pins
const int buzzerPin = A0;                      // Buzzer pin

// Set schedule time for each compartment (HH, MM)
int scheduleHour[6] = {16, 16, 16, 16, 16, 16};  
int scheduleMinute[6] = {6, 6, 6, 6, 6, 6};

bool triggered[6] = {false, false, false, false, false, false};

void setup() {
  Serial.begin(9600);
  rtc.begin();

  pinMode(buzzerPin, OUTPUT);
  digitalWrite(buzzerPin, LOW);

  for (int i = 0; i < 6; i++) {
    pinMode(irPins[i], INPUT);
    pinMode(ledPins[i], OUTPUT);
    digitalWrite(ledPins[i], LOW);
  }

  if (rtc.lostPower()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__))); // Set RTC time from compile time
  }
}

void loop() {
  DateTime now = rtc.now();

  for (int i = 0; i < 6; i++) {
    if (now.hour() == scheduleHour[i] && now.minute() == scheduleMinute[i]) {
      if (!triggered[i]) {
        handleCompartment(i);
        triggered[i] = true;
      }
    } else {
      triggered[i] = false; // Reset trigger after the time passes
    }
  }

  delay(1000); // Check every second
}

void handleCompartment(int activeIndex) {
  Serial.print("Time for compartment ");
  Serial.println(activeIndex + 1);

  // Turn on only the correct LED
  for (int i = 0; i < 6; i++) {
    digitalWrite(ledPins[i], i == activeIndex ? HIGH : LOW);
  }

  // Buzz alert
  digitalWrite(buzzerPin, HIGH);


  bool detected = false;

  while (!detected) {
    for (int i = 0; i < 6; i++) {
      int irValue = digitalRead(irPins[i]);

      if (i == activeIndex && irValue == LOW) {
        Serial.println("Pill taken ✅");
        digitalWrite(buzzerPin, LOW);
        digitalWrite(ledPins[i], LOW); // Turn off LED
        detected = true;
        break;
      } else if (i != activeIndex && irValue == LOW) {
        Serial.print("Error ❌ - Wrong compartment accessed: ");
        Serial.println(i + 1);
        // Optional: add error buzzer sound
        delay(1000);
      }
    }
  }
}
