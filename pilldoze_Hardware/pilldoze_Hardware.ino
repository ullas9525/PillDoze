#include <Wire.h>
#include "RTClib.h"

RTC_DS3231 rtc;

const int irPins[6] = {2, 3, 4, 5, 6, 7};
const int ledPins[6] = {8, 9, 10, 11, 12, 13};
const int buzzerPin = A0;

int scheduleHour[6] = {16, 16, 16, 16, 16, 16};
int scheduleMinute[6] = {6, 6, 6, 6, 6, 6};

bool triggered[6] = {false, false, false, false, false, false};
String compartmentNames[6] = {"C1", "C2", "C3", "C4", "C5", "C6"};

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
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  }
}

void loop() {
  checkBluetoothScheduleUpdate();

  DateTime now = rtc.now();

  for (int i = 0; i < 6; i++) {
    if (now.hour() == scheduleHour[i] && now.minute() == scheduleMinute[i]) {
      if (!triggered[i]) {
        handleCompartment(i);
        triggered[i] = true;
      }
    } else {
      triggered[i] = false;
    }
  }

  delay(1000);
}

void checkBluetoothScheduleUpdate() {
  if (Serial.available()) {
    String data = Serial.readStringUntil('\n');
    data.trim();

    // Expected: C1|Paracetamol|08:00
    if (data.startsWith("C")) {
      int cIndex = data.substring(1, 2).toInt() - 1;

      if (cIndex >= 0 && cIndex < 6) {
        int firstSep = data.indexOf('|');
        int secondSep = data.indexOf('|', firstSep + 1);

        if (firstSep != -1 && secondSep != -1) {
          compartmentNames[cIndex] = data.substring(firstSep + 1, secondSep);

          String timePart = data.substring(secondSep + 1);
          int colonIndex = timePart.indexOf(':');

          if (colonIndex != -1) {
            int h = timePart.substring(0, colonIndex).toInt();
            int m = timePart.substring(colonIndex + 1).toInt();

            scheduleHour[cIndex] = h;
            scheduleMinute[cIndex] = m;

            Serial.print("Updated C");
            Serial.print(cIndex + 1);
            Serial.print(" - ");
            Serial.print(compartmentNames[cIndex]);
            Serial.print(" @ ");
            Serial.print(h);
            Serial.print(":");
            Serial.println(m);
          }
        }
      }
    }
  }
}

void handleCompartment(int activeIndex) {
  Serial.print("Time for ");
  Serial.println(compartmentNames[activeIndex]);

  for (int i = 0; i < 6; i++) {
    digitalWrite(ledPins[i], i == activeIndex ? HIGH : LOW);
  }

  digitalWrite(buzzerPin, HIGH);

  bool detected = false;

  while (!detected) {
    for (int i = 0; i < 6; i++) {
      int irValue = digitalRead(irPins[i]);

      if (i == activeIndex && irValue == LOW) {
        Serial.println("Pill taken"); // This message triggers the success notification
        digitalWrite(buzzerPin, LOW);
        digitalWrite(ledPins[i], LOW);
        detected = true;
        break;
      } else if (i != activeIndex && irValue == LOW) {
        Serial.print("Error! - Wrong compartment accessed: "); // This message triggers the error notification
        Serial.println(i + 1);
        delay(1000);
      }
    }
  }
}
