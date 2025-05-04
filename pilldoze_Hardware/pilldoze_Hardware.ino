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

// Variable to store the index of the compartment whose scheduled alert is currently active
int activeScheduledCompartment = -1;


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
  monitorIRAndSchedule(); // Handle IR monitoring and schedule checks
  // The delay is now inside monitorIRAndSchedule to allow faster IR checks
}

void monitorIRAndSchedule() {
  DateTime now = rtc.now();

  // --- START: Scheduled Time Trigger Logic ---
  // Check if scheduled time is reached for any compartment and trigger alert if needed
  for (int i = 0; i < 6; i++) {
     bool scheduleIsSet = scheduleHour[i] != -1;
     bool isScheduledTime = scheduleIsSet && now.hour() == scheduleHour[i] && now.minute() == scheduleMinute[i];

     if (isScheduledTime && !schedulePassed[i]) {
        if (!takenAtSchedule[i] && activeScheduledCompartment == -1) { // Only trigger if not taken and no other scheduled alert is active
           Serial.print("Time for ");
           Serial.println(compartmentNames[i]);

           // Activate LED for the scheduled compartment
           digitalWrite(ledPins[i], HIGH);
           // Turn on the buzzer (will stay on until turned off by IR trigger)
           digitalWrite(buzzerPin, HIGH);

           activeScheduledCompartment = i; // Mark this compartment's alert as active
           schedulePassed[i] = true; // Mark schedule as passed for today

           // Removed the delay here, as restructuring should handle timing better
           // delay(150); // Small delay to allow state to update before checking IR

        } else if (takenAtSchedule[i]) {
             // If it's the scheduled time but the pill was already taken
             // Mark the schedule as passed for today without triggering alert
             schedulePassed[i] = true;
        }
     }
     // Reset schedulePassed and takenAtSchedule flags at the start of a new day
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
          schedulePassed[i] = false;
          takenAtSchedule[i] = false;
          takenBeforeSchedule[i] = false;
     }
  }
  // --- END: Scheduled Time Trigger Logic ---


  // --- START: IR Sensor Monitoring and Logic ---
  // Check all IR sensors constantly
  for (int i = 0; i < 6; i++) {
    int irValue = digitalRead(irPins[i]);

    if (irValue == LOW) { // IR sensor detected something (pill taken)
      // Add a small debounce delay to avoid multiple triggers from one event
      delay(50);
      irValue = digitalRead(irPins[i]); // Read again after delay
      if (irValue == LOW) { // Confirm detection

        // --- Determine if a scheduled alert is currently active ---
        bool isScheduledAlertActive = (activeScheduledCompartment != -1);

        if (isScheduledAlertActive) {
           // A scheduled alert is currently active

           // Turn off the continuous buzzer and all LEDs immediately for any IR trigger during alert
           digitalWrite(buzzerPin, LOW);
           for (int j = 0; j < 6; j++) {
             digitalWrite(ledPins[j], LOW);
           }

           if (i == activeScheduledCompartment) {
             // User accessed the CORRECT compartment during the scheduled alert
             Serial.println("Pill taken");
             delay(3000);// Message for scheduled take

             takenAtSchedule[activeScheduledCompartment] = true; // Mark as taken at schedule
             takenBeforeSchedule[activeScheduledCompartment] = false; // Reset before schedule flag

             // Reset the active scheduled compartment flag - alert is complete
             activeScheduledCompartment = -1;

           } else {
             // User accessed a WRONG compartment during the scheduled alert
             Serial.print("Warning! - Wrong compartment accessed during alert for compartment ");
             Serial.println(i + 1);

             // Pulse buzzer twice for wrong access
             delay(200); // Buzzer off for 200ms
             digitalWrite(buzzerPin, HIGH);
             delay(200); // Buzzer on for 200ms
             digitalWrite(buzzerPin, LOW);
             delay(200); // Buzzer off for 200ms
             digitalWrite(buzzerPin, HIGH);
             delay(200); // Buzzer on for 200ms
             digitalWrite(buzzerPin, LOW); // Turn off after pulse

             // Resume the scheduled alert after the pulse
             // Check if the scheduled compartment is still valid (schedule not updated/removed)
             if (activeScheduledCompartment != -1 && scheduleHour[activeScheduledCompartment] != -1) {
                 digitalWrite(ledPins[activeScheduledCompartment], HIGH); // Turn scheduled LED back on
                 digitalWrite(buzzerPin, HIGH); // Turn continuous buzzer back on
             } else {
                 // If the scheduled compartment became invalid during the pulse,
                 // ensure everything is off and reset active flag
                 digitalWrite(buzzerPin, LOW);
                 for (int j = 0; j < 6; j++) {
                   digitalWrite(ledPins[j], LOW);
                 }
                 activeScheduledCompartment = -1;
             }

             // Do NOT reset activeScheduledCompartment here if alert is resumed.

             // Optionally reset taken flags for the wrongly accessed compartment
             takenAtSchedule[i] = false;
             takenBeforeSchedule[i] = false;
           }

        }
        // --- If isScheduledAlertActive IS false (No Scheduled Alert Active) ---
        else {
           // Handle access outside of a scheduled alert (before schedule or random access)
           bool scheduleIsSet = scheduleHour[i] != -1;
           if (scheduleIsSet) {
              DateTime scheduledTime = DateTime(now.year(), now.month(), now.day(), scheduleHour[i], scheduleMinute[i], 0);
              if (now.unixtime() < scheduledTime.unixtime()) {
                 // Pill taken BEFORE scheduled time
                 if (!takenBeforeSchedule[i]) { // Prevent sending message repeatedly
                   Serial.print("Warning! - Pill taken before schedule for compartment ");
                   Serial.println(i + 1);
                   takenBeforeSchedule[i] = true;
                   takenAtSchedule[i] = false; // Reset takenAtSchedule if it was true
                 }
              } else {
                 // Accessing a compartment with a schedule, but after the scheduled time and not during an active alert
                 // This could be a late take or accessing after a missed dose.
                 // We can send a different message here.
                 Serial.print("Compartment accessed, but no schedule set for compartment ");
                 Serial.println(i + 1);
                 // Optionally reset taken flags here too depending on desired behavior
                 takenAtSchedule[i] = false;
                 takenBeforeSchedule[i] = false;
              }
           } else {
             // Case: IR triggered, but no schedule is set for this compartment
             Serial.print("Compartment accessed, but no schedule set for compartment ");
             Serial.println(i + 1);
           }
             // Optionally pulse buzzer once or twice here for any access without an active scheduled alert
             digitalWrite(buzzerPin, HIGH);
             delay(300);
             digitalWrite(buzzerPin, LOW);
        }
      }
    }
    // --- END: IR Sensor Monitoring and Logic ---
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

            // Reset flags for the updated compartment
            schedulePassed[cIndex] = false;
            takenAtSchedule[cIndex] = false;
            takenBeforeSchedule[cIndex] = false;

            // If this compartment's alert was active, turn off buzzer/LED and reset active state
            if (activeScheduledCompartment == cIndex) {
               digitalWrite(buzzerPin, LOW);
               digitalWrite(ledPins[cIndex], LOW);
               activeScheduledCompartment = -1;
            } else {
               // Just turn off the LED if it was on for some other reason
               digitalWrite(ledPins[cIndex], LOW);
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
