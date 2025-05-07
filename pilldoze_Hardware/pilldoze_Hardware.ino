#include <Wire.h>
#include "RTClib.h"

RTC_DS3231 rtc;

const int irPins[6] = {2, 3, 4, 5, 6, 7};
const int ledPins[6] = {8, 9, 10, 11, 12, 13};
const int buzzerPin = A0;

int scheduleHour[6] = {-1, -1, -1, -1, -1, -1};
int scheduleMinute[6] = {-1, -1, -1, -1, -1, -1};
String scheduleDays[6] = {"", "", "", "", "", ""};  // New

bool schedulePassed[6] = {false, false, false, false, false, false};
bool takenAtSchedule[6] = {false, false, false, false, false, false};
bool takenBeforeSchedule[6] = {false, false, false, false, false, false};

int activeScheduledCompartment = -1;

String compartmentNames[6] = {"C1", "C2", "C3", "C4", "C5", "C6"};

String dayShortNames[7] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};

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
  monitorIRAndSchedule();
}

void monitorIRAndSchedule() {
  DateTime now = rtc.now();
  int currentDOW = now.dayOfTheWeek(); // 0 = Sun, 1 = Mon, ..., 6 = Sat
  String todayStr = dayShortNames[currentDOW];

  for (int i = 0; i < 6; i++) {
    bool scheduleIsSet = scheduleHour[i] != -1;
    bool todayIsScheduled = scheduleDays[i].indexOf(todayStr) != -1;
    bool isScheduledTime = scheduleIsSet && todayIsScheduled && now.hour() == scheduleHour[i] && now.minute() == scheduleMinute[i];

    if (isScheduledTime && !schedulePassed[i]) {
      if (!takenAtSchedule[i] && activeScheduledCompartment == -1) {
        Serial.print("Time for ");
        Serial.println(compartmentNames[i]);
        digitalWrite(ledPins[i], HIGH);
        digitalWrite(buzzerPin, HIGH);
        activeScheduledCompartment = i;
        schedulePassed[i] = true;
      } else if (takenAtSchedule[i]) {
        schedulePassed[i] = true;
      }
    }

    if (scheduleIsSet && now.hour() > scheduleHour[i] && schedulePassed[i]) {
      schedulePassed[i] = false;
      takenAtSchedule[i] = false;
      takenBeforeSchedule[i] = false;
    } else if (scheduleIsSet && now.hour() < scheduleHour[i] && schedulePassed[i]) {
      schedulePassed[i] = false;
      takenAtSchedule[i] = false;
      takenBeforeSchedule[i] = false;
    }
  }

  for (int i = 0; i < 6; i++) {
    int irValue = digitalRead(irPins[i]);

    if (irValue == LOW) {
      delay(50);
      irValue = digitalRead(irPins[i]);
      if (irValue == LOW) {
        if (activeScheduledCompartment != -1) {
          digitalWrite(buzzerPin, LOW);
          for (int j = 0; j < 6; j++) digitalWrite(ledPins[j], LOW);

          if (i == activeScheduledCompartment) {
            Serial.println("Pill taken");
            delay(3000);
            takenAtSchedule[activeScheduledCompartment] = true;
            takenBeforeSchedule[activeScheduledCompartment] = false;
            activeScheduledCompartment = -1;
          } else {
            Serial.print("Warning! - Wrong compartment accessed during alert for compartment ");
            Serial.println(i + 1);

            delay(200);
            digitalWrite(buzzerPin, HIGH);
            delay(200);
            digitalWrite(buzzerPin, LOW);
            delay(200);
            digitalWrite(buzzerPin, HIGH);
            delay(200);
            digitalWrite(buzzerPin, LOW);

            if (activeScheduledCompartment != -1 && scheduleHour[activeScheduledCompartment] != -1) {
              digitalWrite(ledPins[activeScheduledCompartment], HIGH);
              digitalWrite(buzzerPin, HIGH);
            } else {
              digitalWrite(buzzerPin, LOW);
              for (int j = 0; j < 6; j++) digitalWrite(ledPins[j], LOW);
              activeScheduledCompartment = -1;
            }

            takenAtSchedule[i] = false;
            takenBeforeSchedule[i] = false;
          }
        } else {
          bool scheduleIsSet = scheduleHour[i] != -1;
          if (scheduleIsSet) {
            DateTime now = rtc.now();
            DateTime scheduledTime = DateTime(now.year(), now.month(), now.day(), scheduleHour[i], scheduleMinute[i], 0);
            if (now.unixtime() < scheduledTime.unixtime()) {
              if (!takenBeforeSchedule[i]) {
                Serial.print("Accessed compartment before schedule time for compartment ");
                Serial.println(i + 1);
                takenBeforeSchedule[i] = true;
                takenAtSchedule[i] = false;
              }
            } else {
              Serial.print("Compartment accessed, but no schedule set for compartment ");
              Serial.println(i + 1);
              takenAtSchedule[i] = false;
              takenBeforeSchedule[i] = false;
            }
          } else {
            Serial.print("Compartment accessed, but no schedule set for compartment ");
            Serial.println(i + 1);
          }
          digitalWrite(buzzerPin, HIGH);
          delay(300);
          digitalWrite(buzzerPin, LOW);
        }
      }
    }
  }

  delay(50);
}

void checkBluetoothScheduleUpdate() {
  if (Serial.available()) {
    String data = Serial.readStringUntil('\n');
    data.trim();

    // Format: C1|Name|HH:MM|Mon,Wed,Fri
    if (data.startsWith("C")) {
      int cIndex = data.substring(1, 2).toInt() - 1;
      if (cIndex >= 0 && cIndex < 6) {
        int firstSep = data.indexOf('|');
        int secondSep = data.indexOf('|', firstSep + 1);
        int thirdSep = data.indexOf('|', secondSep + 1);

        if (firstSep != -1 && secondSep != -1 && thirdSep != -1) {
          compartmentNames[cIndex] = data.substring(firstSep + 1, secondSep);
          String timePart = data.substring(secondSep + 1, thirdSep);
          String daysPart = data.substring(thirdSep + 1);

          int colonIndex = timePart.indexOf(':');
          if (colonIndex != -1) {
            int h = timePart.substring(0, colonIndex).toInt();
            int m = timePart.substring(colonIndex + 1).toInt();

            scheduleHour[cIndex] = h;
            scheduleMinute[cIndex] = m;
            scheduleDays[cIndex] = daysPart;

            schedulePassed[cIndex] = false;
            takenAtSchedule[cIndex] = false;
            takenBeforeSchedule[cIndex] = false;

            if (activeScheduledCompartment == cIndex) {
              digitalWrite(buzzerPin, LOW);
              digitalWrite(ledPins[cIndex], LOW);
              activeScheduledCompartment = -1;
            } else {
              digitalWrite(ledPins[cIndex], LOW);
            }

            Serial.print("Updated C");
            Serial.print(cIndex + 1);
            Serial.print(" - ");
            Serial.print(compartmentNames[cIndex]);
            Serial.print(" @ ");
            Serial.print(h);
            Serial.print(":");
            Serial.print(m);
            Serial.print(" on ");
            Serial.println(daysPart);
          }
        }
      }
    }
  }
}
