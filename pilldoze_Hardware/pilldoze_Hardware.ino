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

String compartmentNames[6] = {"C1", "C2", "C3", "C4", "C5", "C6"}; // Corrected typo C3 duplicate

String dayShortNames[7] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};

// Removed variables for periodic time sending (previousMillis, interval)
// Removed the sendCurrentTimePeriodically() function

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

  // This line sets the RTC to the time the sketch was compiled if power was lost.
  // The new time sync feature from the app will override this if used.
  if (rtc.lostPower()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  }
}

void loop() {
  checkBluetoothScheduleUpdate();
  monitorIRAndSchedule();
  // Removed the call to sendCurrentTimePeriodically()
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

    // Original flag reset logic - kept as per user request not to change other logic
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
            delay(3000); // Note: This delay is blocking
            takenAtSchedule[activeScheduledCompartment] = true;
            takenBeforeSchedule[activeScheduledCompartment] = false;
            activeScheduledCompartment = -1;
          } else {
            Serial.print("Warning! - Wrong compartment accessed during alert for compartment ");
            Serial.println(i + 1);

            delay(200); // Note: These delays are blocking
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
              // This message is misleading if accessed after schedule time
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
          delay(300); // Note: This delay is blocking
          digitalWrite(buzzerPin, LOW);
        }
      }
    }
  }

  delay(50); // Note: This delay is blocking
}

void checkBluetoothScheduleUpdate() {
  if (Serial.available()) {
    String data = Serial.readStringUntil('\n');
    data.trim(); // This removes the newline character and any other whitespace from the end

    // Format for scheduling: C1|Name|HH:MM|Mon,Wed,Fri
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
    // Handle RTC Time Synchronization message from app
    // Expected format: T|YYYY-MM-DD|HH:MM:SS
    else if (data.startsWith("T|")) {
      Serial.println("Received time sync message.");
      int firstSep = data.indexOf('|'); // Finds the first separator after 'T'
      int secondSep = data.indexOf('|', firstSep + 1); // Finds the separator after the date part

      if (firstSep != -1 && secondSep != -1) {
        String datePart = data.substring(firstSep + 1, secondSep); // ExtractsYYYY-MM-DD
        String timePart = data.substring(secondSep + 1);          // Extracts HH:MM:SS

        // Parse date components
        int year = datePart.substring(0, 4).toInt();
        int month = datePart.substring(5, 7).toInt();
        int day = datePart.substring(8, 10).toInt();

        // Parse time components
        int hour24 = timePart.substring(0, 2).toInt();
        int minute = timePart.substring(3, 5).toInt();
        int second = timePart.substring(6, 8).toInt();

        // Adjust the RTC with the new time (RTC library uses 24-hour format internally)
        rtc.adjust(DateTime(year, month, day, hour24, minute, second));

        // --- Format the time for the confirmation message (12-hour format) ---
        int hour12 = hour24 % 12;
        if (hour12 == 0) hour12 = 12; // Convert 0 to 12 for 12 AM/PM
        String ampm = (hour24 < 12) ? "AM" : "PM";

        // Format month and day with leading zeros if needed
        String formattedMonth = (month < 10) ? "0" + String(month) : String(month);
        String formattedDay = (day < 10) ? "0" + String(day) : String(day);

        // Format minute and second with leading zeros
        String formattedMinute = (minute < 10) ? "0" + String(minute) : String(minute);
        String formattedSecond = (second < 10) ? "0" + String(second) : String(second);

        // Send a confirmation back to Flutter in the requested format
        Serial.print("RTC Updated: ");
        Serial.print(formattedDay); Serial.print("-");
        Serial.print(formattedMonth); Serial.print("-");
        Serial.print(year); Serial.print(" ");
        Serial.print(hour12); Serial.print(":");
        Serial.print(formattedMinute); Serial.print(":");
        Serial.print(formattedSecond); Serial.print(" ");
        Serial.println(ampm); // Use println to send the newline character

      } else {
        Serial.println("Error parsing time sync message. Format: T|YYYY-MM-DD|HH:MM:SS");
      }
    }
  }
}
