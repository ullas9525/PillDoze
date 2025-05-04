#include <Wire.h>
#include "RTClib.h"

RTC_DS3231 rtc;

const int irPins[6] = {2, 3, 4, 5, 6, 7};
const int ledPins[6] = {8, 9, 10, 11, 12, 13};
const int buzzerPin = A0;

// Initialize scheduleHour and scheduleMinute to -1 to indicate no schedule is set
int scheduleHour[6] = {-1, -1, -1, -1, -1, -1};
int scheduleMinute[6] = {-1, -1, -1, -1, -1, -1};

// Flags to track if the scheduled time has passed for each compartment
bool schedulePassed[6] = {false, false, false, false, false, false};
// Flags to track if a pill was taken at the scheduled time for each compartment
bool takenAtSchedule[6] = {false, false, false, false, false, false};
// Flags to track if a pill was taken before the scheduled time
bool takenBeforeSchedule[6] = {false, false, false, false, false, false};
// Flags to track if the buzzer is currently active for a compartment
bool buzzerActive[6] = {false, false, false, false, false, false};


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
    // This line sets the RTC time if power was lost.
    // You might want to set a default time here or handle it differently.
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  }
}

void loop() {
  checkBluetoothScheduleUpdate();
  monitorIRAndSchedule(); // New function to handle IR monitoring and schedule checks
  // The delay is now inside monitorIRAndSchedule to allow faster IR checks
}

void monitorIRAndSchedule() {
  DateTime now = rtc.now();

  for (int i = 0; i < 6; i++) {
    int irValue = digitalRead(irPins[i]);

    // Check if a schedule is set for this compartment
    bool scheduleIsSet = scheduleHour[i] != -1;

    // Check if the current time matches the scheduled time
    bool isScheduledTime = scheduleIsSet &&
                           now.hour() == scheduleHour[i] &&
                           now.minute() == scheduleMinute[i];

    // Check if the scheduled time has just passed (within the last minute)
    // This helps ensure the scheduled event triggers only once
    bool justPassedScheduledTime = scheduleIsSet &&
                                   !schedulePassed[i] &&
                                   (now.hour() > scheduleHour[i] || (now.hour() == scheduleHour[i] && now.minute() >= scheduleMinute[i]));


    // --- START: IR Sensor Monitoring and Logic ---
    if (irValue == LOW) { // IR sensor detected something (pill taken)
      // Add a small debounce delay to avoid multiple triggers from one event
      delay(50);
      irValue = digitalRead(irPins[i]); // Read again after delay
      if (irValue == LOW) { // Confirm detection

        if (scheduleIsSet) { // Only process if a schedule is set for this compartment
          // Create a DateTime object for the scheduled time on the current day
          DateTime scheduledTime = DateTime(now.year(), now.month(), now.day(), scheduleHour[i], scheduleMinute[i], 0);

          // --- START: Fixed comparison using unixtime() ---
          if (now.unixtime() < scheduledTime.unixtime()) {
          // --- END: Fixed comparison using unixtime() ---
            // Pill taken BEFORE scheduled time
            if (!takenBeforeSchedule[i]) { // Prevent sending message repeatedly
              Serial.print("Warning! - Pill taken before schedule for compartment ");
              Serial.println(i + 1);
              takenBeforeSchedule[i] = true;
              // Reset takenAtSchedule if it was true (in case of taking early after a missed dose)
              takenAtSchedule[i] = false;
            }
             // Turn off LED and buzzer if active for this compartment
             digitalWrite(ledPins[i], LOW);
             if (buzzerActive[i]) {
                digitalWrite(buzzerPin, LOW);
                buzzerActive[i] = false;
             }
          } else if (isScheduledTime || justPassedScheduledTime) {
            // Pill taken AT or JUST AFTER scheduled time (within the trigger window)
             if (buzzerActive[i] && !takenAtSchedule[i]) { // Only process if buzzer was active and pill not yet taken at schedule
                Serial.println("Pill taken"); // This message is sent to the app for scheduled take
                digitalWrite(buzzerPin, LOW);
                buzzerActive[i] = false;
                digitalWrite(ledPins[i], LOW);
                takenAtSchedule[i] = true; // Mark as taken at schedule
                takenBeforeSchedule[i] = false; // Reset before schedule flag
             } else if (!buzzerActive[i] && !takenAtSchedule[i]) {
                 // Case: Pill taken after scheduled time but not at the exact minute trigger
                 // This might happen if the user is slightly late.
                 // We can optionally send a "late take" message or just acknowledge it.
                 // For now, let's just acknowledge it as taken.
                 Serial.print("Pill taken late for compartment ");
                 Serial.println(i + 1);
                 takenAtSchedule[i] = true; // Mark as taken (even if late)
                 takenBeforeSchedule[i] = false; // Reset before schedule flag
             } else if (takenAtSchedule[i]) {
                 // Case: Pill already taken at schedule, but IR triggered again (e.g., putting pill back?)
                 // Can ignore or send a message like "Compartment accessed after take".
             }

          } else {
             // Case: IR triggered, schedule is set, but it's not scheduled time yet or already passed the window
             // This could be accessing a compartment at a random time.
             // We can send a "wrong time" or "unauthorized access" message.
             Serial.print("Warning! - Compartment accessed outside of scheduled time for compartment ");
             Serial.println(i + 1);
             // Optionally reset taken flags if accessing after a take
             takenAtSchedule[i] = false;
             takenBeforeSchedule[i] = false;
          }
        } else {
          // Case: IR triggered, but no schedule is set for this compartment
          Serial.print("Compartment accessed, but no schedule set for compartment ");
          Serial.println(i + 1);
        }
      }
    }
    // --- END: IR Sensor Monitoring and Logic ---

    // --- START: Scheduled Time Trigger Logic ---
    // Check if it's the scheduled minute and the schedule hasn't been triggered yet for today
    if (isScheduledTime && !schedulePassed[i]) {
      if (!takenAtSchedule[i]) { // Only trigger if pill hasn't been taken at schedule yet
         Serial.print("Time for ");
         Serial.println(compartmentNames[i]);

         // Activate LED and Buzzer for the scheduled compartment
         for (int j = 0; j < 6; j++) {
           digitalWrite(ledPins[j], j == i ? HIGH : LOW);
         }
         digitalWrite(buzzerPin, HIGH);
         buzzerActive[i] = true; // Mark buzzer as active

         schedulePassed[i] = true; // Mark schedule as passed for today
      } else {
          // If it's the scheduled time but the pill was already taken (either before or at schedule)
          // We can optionally send a message like "Scheduled time reached, pill already taken".
          // For now, we'll just mark the schedule as passed.
          schedulePassed[i] = true;
      }
    }

    // Reset schedulePassed and takenAtSchedule flags at the start of a new day
    // or when the time is significantly past the scheduled time.
    // A simple way is to reset them when the hour changes, or specifically after the scheduled hour.
    if (scheduleIsSet && now.hour() > scheduleHour[i] && schedulePassed[i]) {
        schedulePassed[i] = false;
        takenAtSchedule[i] = false; // Reset taken flag for the next day
        takenBeforeSchedule[i] = false; // Reset before schedule flag for the next day
        // Optionally send a "Missed dose" message if takenAtSchedule was false before resetting
        // if (!takenAtSchedule[i]) {
        //   Serial.print("Missed dose for compartment ");
        //   Serial.println(i + 1);
        // }
    } else if (scheduleIsSet && now.hour() < scheduleHour[i] && schedulePassed[i]) {
        // Handle case where schedule passed flag might still be true from a previous day
        // if the hour hasn't passed the scheduled hour yet.
        // This is less likely with the above check, but good for robustness.
         schedulePassed[i] = false;
         takenAtSchedule[i] = false;
         takenBeforeSchedule[i] = false;
    }
    // --- END: Scheduled Time Trigger Logic ---
  }

  delay(50); // Small delay in the main loop to prevent watchdog timer issues and allow serial communication
}


void checkBluetoothScheduleUpdate() {
  // Checks if there is data available on the serial port (from Bluetooth)
  if (Serial.available()) {
    // Reads the incoming data until a newline character is found
    String data = Serial.readStringUntil('\n');
    data.trim(); // Remove leading/trailing whitespace

    // Expected data format from the app: C1|Paracetamol|08:00
    if (data.startsWith("C")) {
      // Extract compartment index (e.g., '1' from 'C1')
      int cIndex = data.substring(1, 2).toInt() - 1;

      // Validate the compartment index
      if (cIndex >= 0 && cIndex < 6) {
        // Find the positions of the separator characters '|'
        int firstSep = data.indexOf('|');
        int secondSep = data.indexOf('|', firstSep + 1);

        // Check if both separators were found
        if (firstSep != -1 && secondSep != -1) {
          // Extract the medication name
          compartmentNames[cIndex] = data.substring(firstSep + 1, secondSep);

          // Extract the time part (e.g., '08:00')
          String timePart = data.substring(secondSep + 1);
          int colonIndex = timePart.indexOf(':');

          // Check if the colon was found in the time part
          if (colonIndex != -1) {
            // Extract hour and minute and convert to integers
            int h = timePart.substring(0, colonIndex).toInt();
            int m = timePart.substring(colonIndex + 1).toInt();

            // --- START: Update the schedule arrays with received values ---
            scheduleHour[cIndex] = h;
            scheduleMinute[cIndex] = m;
            // --- END: Update the schedule arrays with received values ---

            // Reset flags when a new schedule is set
            schedulePassed[cIndex] = false;
            takenAtSchedule[cIndex] = false;
            takenBeforeSchedule[cIndex] = false;
            digitalWrite(ledPins[cIndex], LOW); // Turn off LED if on
            if (buzzerActive[cIndex]) { // Turn off buzzer if active
               digitalWrite(buzzerPin, LOW);
               buzzerActive[cIndex] = false;
            }


            // Print confirmation to the serial monitor (and thus to the app's message display)
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
