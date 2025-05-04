import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart'; // Required for date/time formatting

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BluetoothConnectScreen(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData( // Optional: Add a theme for better visuals
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
    );
  }
}

// --- Bluetooth Connection Screen ---
class BluetoothConnectScreen extends StatefulWidget {
  @override
  _BluetoothConnectScreenState createState() => _BluetoothConnectScreenState();
}

class _BluetoothConnectScreenState extends State<BluetoothConnectScreen> {
  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? selectedDevice;
  BluetoothConnection? connection;
  bool isConnecting = false; // To show a loading indicator
  bool isConnected = false;
  String connectionStatus = ''; // To show connection status/errors

  @override
  void initState() {
    super.initState();
    getBondedDevices();
  }

  @override
  void dispose() {
    // Avoid memory leaks by disconnecting and disposing the connection when the screen is disposed.
    if (isConnected) {
      connection?.dispose();
      connection = null;
    }
    super.dispose();
  }


  Future<void> getBondedDevices() async {
    setState(() {
      connectionStatus = 'Getting bonded devices...';
    });
    try {
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        devicesList = devices;
        connectionStatus = devices.isEmpty ? 'No bonded devices found.' : 'Select a device.';
      });
    } catch (e) {
       setState(() {
         connectionStatus = 'Error getting devices: $e';
       });
    }
  }

  void _connectToDevice() async {
    if (selectedDevice == null) {
       setState(() {
         connectionStatus = 'Please select a device first.';
       });
      return;
    }
    if (isConnecting) return; // Prevent multiple connection attempts

    setState(() {
      isConnecting = true;
      isConnected = false; // Reset connection status
      connectionStatus = 'Connecting to ${selectedDevice!.name ?? selectedDevice!.address}...';
    });

    try {
      BluetoothConnection newConnection =
          await BluetoothConnection.toAddress(selectedDevice!.address);
      setState(() {
        connection = newConnection;
        isConnected = true;
        isConnecting = false;
        connectionStatus = 'Connected to ${selectedDevice!.name ?? selectedDevice!.address}!';
      });

      // Optional: Listen for disconnection
      connection?.input?.listen((Uint8List data) {
        // Handle data received from Arduino if needed
      }).onDone(() {
        setState(() {
          isConnected = false;
          isConnecting = false;
          connectionStatus = 'Disconnected.';
        });
      });

    } catch (e) {
      setState(() {
        isConnected = false;
        isConnecting = false;
        connectionStatus = "Connection failed: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect Pill Dispenser'),
        centerTitle: true, // Center the AppBar title
      ),
      body: Padding( // Add padding around the content
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center vertically
          crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
          children: [
            // Display connection status
            if (connectionStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 15.0),
                child: Text(
                  connectionStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: isConnected ? Colors.green : Colors.redAccent),
                ),
              ),

            // --- Dropdown for selecting device ---
            // Wrap Dropdown in a Card for better visual separation and centering
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 5.0),
                child: DropdownButtonHideUnderline( // Hide default underline
                  child: DropdownButton<BluetoothDevice>(
                    isExpanded: true, // Make dropdown take available width
                    hint: Center(child: Text("Select Bluetooth Device")), // Center hint text
                    value: selectedDevice,
                    items: devicesList.map((device) {
                      return DropdownMenuItem(
                        child: Text(device.name ?? device.address), // Show address if name is null
                        value: device,
                      );
                    }).toList(),
                    onChanged: (device) {
                      setState(() {
                        selectedDevice = device;
                        connectionStatus = ''; // Clear status on new selection
                      });
                    },
                    alignment: AlignmentDirectional.center, // Center selected item text
                  ),
                ),
              ),
            ),
            SizedBox(height: 20), // Spacing

            // --- Connect Button ---
            ElevatedButton(
              // Disable button while connecting or if no device is selected
              onPressed: (selectedDevice == null || isConnecting || isConnected) ? null : _connectToDevice,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isConnecting
                  ? SizedBox( // Show loading indicator
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isConnected ? 'Connected' : 'Connect', style: TextStyle(fontSize: 16)),
            ),
            SizedBox(height: 15), // Spacing

            // --- Continue Button (only shown if connected) ---
            if (isConnected)
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      // Pass the connection to the next screen
                      builder: (_) => CompartmentScreen(connection: connection!),
                    ),
                  );
                },
                 style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Use a different color for continue
                  padding: EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('Set Up Compartments', style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}


// --- Compartment Setup Screen ---
class CompartmentScreen extends StatefulWidget {
  final BluetoothConnection connection;

  CompartmentScreen({required this.connection});

  @override
  _CompartmentScreenState createState() => _CompartmentScreenState();
}

class _CompartmentScreenState extends State<CompartmentScreen> {
  // Store name and time for each compartment
  List<Map<String, String?>> compartmentData = List.generate(6, (i) => {
    'name': 'Compartment ${i + 1}', // Default name
    'time': null // Default time (null)
  });

  // --- Function to show the setup dialog ---
  void _openSetDialog(int index) {
    // Controllers to manage text fields state within the dialog
    final TextEditingController nameController = TextEditingController(text: compartmentData[index]['name'] == 'Compartment ${index + 1}' ? '' : compartmentData[index]['name']);
    // Use a state variable for the time within the dialog
    TimeOfDay? selectedTime = _parseTime(compartmentData[index]['time']);
    // Use StatefulBuilder to update the time display within the dialog
    String displayTime = selectedTime != null ? selectedTime.format(context) : 'Tap to select time';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // Use StatefulBuilder for dialog state updates
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Set Up Compartment ${index + 1}'),
            content: Column(
              mainAxisSize: MainAxisSize.min, // Make column height fit content
              children: [
                // Medication Name Input
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Medication Name',
                    hintText: 'e.g., Vitamin C',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                SizedBox(height: 15), // Spacing

                // Time Selection
                Text("Dispense Time:", style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                InkWell( // Make the time display tappable
                  onTap: () async {
                    // Show Time Picker
                    final TimeOfDay? pickedTime = await showTimePicker(
                      context: context,
                      initialTime: selectedTime ?? TimeOfDay.now(), // Start with selected or current time
                    );
                    // Update time if user picked one
                    if (pickedTime != null) {
                       setDialogState(() { // Update the dialog's state
                         selectedTime = pickedTime;
                         displayTime = selectedTime!.format(context); // Format for display (e.g., 10:30 AM)
                       });
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 15),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(displayTime),
                        Icon(Icons.access_time, color: Theme.of(context).primaryColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), // Close dialog
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  String name = nameController.text.trim();
                  // Check if both name and time are set
                  if (name.isNotEmpty && selectedTime != null) {
                    // Format time as HH:mm (24-hour format) for Arduino
                    String timeString = DateFormat('HH:mm').format(DateTime(2023, 1, 1, selectedTime!.hour, selectedTime!.minute));

                    // Send data to Arduino
                    _sendToArduino(index, name, timeString);

                    // Update the main screen state
                    setState(() {
                      compartmentData[index]['name'] = name;
                      compartmentData[index]['time'] = timeString;
                    });
                    Navigator.pop(context); // Close dialog
                  } else {
                    // Show error if fields are missing
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter name and select time.')),
                    );
                  }
                },
                child: Text('Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  // --- Helper to parse HH:mm string to TimeOfDay ---
  TimeOfDay? _parseTime(String? timeString) {
    if (timeString == null) return null;
    try {
      final format = DateFormat('HH:mm');
      final dt = format.parse(timeString);
      return TimeOfDay.fromDateTime(dt);
    } catch (e) {
      print("Error parsing time: $e");
      return null;
    }
  }


  // --- Function to send data to Arduino ---
  void _sendToArduino(int index, String name, String time) {
    if (!widget.connection.isConnected) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Bluetooth disconnected!')),
       );
       return;
    }
    // Format: C<index+1>|Medication Name|HH:mm\n
    // Example: C1|Aspirin|08:30\n
    String compartmentCode = 'C${index + 1}';
    String message = '$compartmentCode|$name|$time\n'; // Add newline as terminator
    try {
      widget.connection.output.add(Uint8List.fromList(message.codeUnits));
      widget.connection.output.allSent.then((_) {
         print('Sent to Arduino: $message');
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Compartment ${index + 1} updated.')),
         );
      });
    } catch (e) {
       print("Error sending data: $e");
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Error sending data: $e')),
       );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Pill Compartment Setup"),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(10), // Add padding around the list
        itemCount: 6, // Number of compartments
        itemBuilder: (context, index) {
          String name = compartmentData[index]['name'] ?? 'Compartment ${index + 1}';
          String? timeStr = compartmentData[index]['time'];
          TimeOfDay? time = _parseTime(timeStr);
          String displayTime = time != null ? time.format(context) : 'Not set'; // Format for display

          return Card(
            elevation: 3,
            margin: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              leading: CircleAvatar( // Add a leading icon/number
                 child: Text('${index + 1}'),
                 backgroundColor: Theme.of(context).primaryColorLight,
              ),
              title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Time: $displayTime'), // Display the set time
              trailing: Icon(Icons.edit, color: Theme.of(context).primaryColor), // Edit icon
              onTap: () => _openSetDialog(index), // Open dialog on tap
            ),
          );
        },
      ),
    );
  }
}