import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart'; // Required for date/time formatting
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'dart:convert'; // Import dart:convert for JSON encoding/decoding
import 'dart:async'; // Import async for StreamController

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BluetoothConnectScreen(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Changed the primary swatch color to light blue
        primarySwatch: Colors.lightBlue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Define error color for consistency using the new primary swatch
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.lightBlue).copyWith(error: Colors.redAccent),
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
  bool isConnecting = false;
  bool isConnected = false;
  String connectionStatus = '';

  // Buffer for incoming data
  String _incomingDataBuffer = "";

  // StreamController to send messages to other screens
  final StreamController<String> _messageController = StreamController<String>.broadcast();

  // Stream getter for other screens to listen to
  Stream<String> get messageStream => _messageController.stream;


  @override
  void initState() {
    super.initState();
    _checkBluetoothState(); // Check initial Bluetooth state
    // Listen to Bluetooth state changes
    FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      print("Bluetooth state changed: $state");
      if (state == BluetoothState.STATE_ON) {
        getBondedDevices(); // Refresh devices if Bluetooth is turned on
      } else {
        // If Bluetooth turns off, update connection status and state
        if (mounted) {
          setState(() {
            isConnected = false;
            isConnecting = false;
            connectionStatus = 'Bluetooth is off. Please turn it on.';
            connection?.dispose(); // Dispose existing connection if Bluetooth is off
            connection = null;
            devicesList = []; // Clear device list
            selectedDevice = null; // Clear selected device
          });
          // Also notify listeners that connection is lost
          _messageController.add('Bluetooth Disconnected.');
        }
      }
    });
  }

  // Check if Bluetooth is enabled, request if not
  Future<void> _checkBluetoothState() async {
    BluetoothState state = await FlutterBluetoothSerial.instance.state;
    print("Initial Bluetooth state: $state");
    if (state == BluetoothState.STATE_OFF) {
      if (mounted) {
        setState(() {
          connectionStatus = 'Bluetooth is off. Please turn it on.';
        });
      }
      // Optionally request user to enable Bluetooth
      // await FlutterBluetoothSerial.instance.requestEnable();
      // You might want to re-check state after requestEnable
    } else if (state == BluetoothState.STATE_ON) {
      getBondedDevices(); // Get devices if Bluetooth is on
    } else {
      if (mounted) {
        setState(() {
          connectionStatus = 'Bluetooth state: $state. Required: ON';
        });
      }
    }
  }


  @override
  void dispose() {
    // Avoid memory leaks by disconnecting and disposing the connection when the screen is disposed.
    print("BluetoothConnectScreen dispose called.");
    if (connection?.isConnected ?? false) { // Check isConnected before disposing
      print("Disconnecting Bluetooth connection on dispose.");
      connection?.dispose();
    }
    connection = null;
    _messageController.close(); // Close the stream controller
    super.dispose();
  }


  Future<void> getBondedDevices() async {
    print("Attempting to get bonded devices...");
    setState(() {
      connectionStatus = 'Getting bonded devices...';
      devicesList = []; // Clear previous list
      selectedDevice = null; // Reset selection
    });
    try {
      // Ensure Bluetooth is on before getting devices
      BluetoothState state = await FlutterBluetoothSerial.instance.state;
      if (state != BluetoothState.STATE_ON) {
         if (mounted) {
           setState(() {
             connectionStatus = 'Please turn on Bluetooth.';
           });
         }
         print("Bluetooth is not ON, cannot get bonded devices.");
         return;
      }

      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      // Check if the widget is still mounted before updating state
      if (mounted) {
        setState(() {
          devicesList = devices;
          connectionStatus = devices.isEmpty ? 'No bonded devices found. Please pair your dispenser.' : 'Select a device.';
        });
        print("Found ${devices.length} bonded devices.");
      }
    } catch (e) {
        if (mounted) {
          setState(() {
            connectionStatus = 'Error getting devices: $e';
          });
        }
        print("Error getting bonded devices: $e");
    }
  }

  void _connectToDevice() async {
    if (selectedDevice == null) {
        setState(() {
          connectionStatus = 'Please select a device first.';
        });
      return;
    }
    if (isConnecting || isConnected) {
      print("Connection attempt blocked: isConnecting=$isConnecting, isConnected=$isConnected");
      return; // Prevent multiple connection attempts or if already connected
    }

    setState(() {
      isConnecting = true;
      connectionStatus = 'Connecting to ${selectedDevice!.name ?? selectedDevice!.address}...';
    });
    print("Attempting to connect to ${selectedDevice!.address}");

    try {
      // Dispose any existing connection before creating a new one
      if (connection?.isConnected ?? false) {
        print("Disposing existing connection before new attempt.");
        connection?.dispose();
      }
      connection = null; // Ensure connection is null before assignment

      BluetoothConnection newConnection =
          await BluetoothConnection.toAddress(selectedDevice!.address);

      // Check if still mounted after await
      if (!mounted) {
          print("Widget unmounted after connection attempt, disposing new connection.");
          newConnection.dispose(); // Dispose if widget is gone
          return;
      }

      setState(() {
        connection = newConnection;
        isConnected = true;
        isConnecting = false;
        connectionStatus = 'Connected to ${selectedDevice!.name ?? selectedDevice!.address}!';
      });
      print("Successfully connected to ${selectedDevice!.address}");

      // --- START: Listening for incoming data from Arduino ---
      // This is the *only* listener for the Bluetooth input stream
      connection?.input?.listen(
        (Uint8List data) {
          // Convert incoming data to a string and add to buffer
          String incomingString = String.fromCharCodes(data);
          _incomingDataBuffer += incomingString;

          // Process complete messages (ending with newline)
          int newlineIndex;
          while ((newlineIndex = _incomingDataBuffer.indexOf('\n')) != -1) {
            String message = _incomingDataBuffer.substring(0, newlineIndex).trim();
            _incomingDataBuffer = _incomingDataBuffer.substring(newlineIndex + 1);

            _handleIncomingMessage(message); // Call method to handle the message
          }
        },
        onDone: () {
          // Connection closed
          print("Bluetooth connection closed (onDone triggered on ConnectScreen).");
          if (mounted) {
            setState(() {
              isConnected = false;
              isConnecting = false;
              connectionStatus = 'Device disconnected.';
              connection = null; // Clear the connection object
            });
            // Also notify listeners that connection is lost
            _messageController.add('Device disconnected.');
          }
        },
        onError: (error) {
            // Error on the connection stream
            print("Bluetooth connection error on ConnectScreen: $error");
            if (mounted) {
              setState(() {
                isConnected = false;
                isConnecting = false;
                connectionStatus = 'Connection Error: $error';
                connection = null; // Clear the connection object
              });
              // Also notify listeners about the error
              _messageController.add('Connection Error: $error');
            }
        },
        cancelOnError: true // Cancel subscription on error
      );
      // --- END: Listening for incoming data from Arduino ---

    } catch (e) {
        // Error during the connection attempt itself
        print("Connection failed: $e");
        if (mounted) {
         setState(() {
           isConnected = false;
           isConnecting = false;
           connectionStatus = "Connection Failed: ${e.toString()}"; // Show specific error
           connection = null; // Clear the connection object
         });
         // Notify listeners about the connection failure
         _messageController.add("Connection Failed: ${e.toString()}");
        }
    }
  }

   // Handle incoming messages from Arduino and add to the stream
  void _handleIncomingMessage(String message) {
    print("Received message from Arduino: '$message'"); // Print the exact received message

    // Add the message to the stream controller
    _messageController.add(message);

    // You can still add logging to confirm message content if needed
    if (message.contains("Pill taken")) { // Check for "Pill taken" or "Pill taken late"
      print("Message indicates pill was taken.");
    } else if (message.contains("Warning! - Pill taken before schedule")) {
      print("Message indicates pill taken before schedule.");
    } else if (message.contains("Warning! - Wrong compartment accessed")) {
      print("Message indicates wrong compartment accessed.");
    } else if (message.contains("Compartment accessed, but no schedule set")) {
      print("Message indicates compartment accessed without schedule.");
    } else if (message.contains("Disconnected")) {
      print("Message indicates disconnection.");
    } else if (message.contains("Connection Error")) {
       print("Message indicates connection error.");
    } else if (message.contains("Updated C")) {
       print("Message indicates schedule update confirmation.");
    }
  }


  @override
  Widget build(context) { // Added context parameter
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect Pill Dispenser'),
        centerTitle: true,
        actions: [ // Add a refresh button
           IconButton(
             icon: Icon(Icons.refresh),
             onPressed: isConnecting ? null : getBondedDevices, // Disable refresh while connecting
             tooltip: 'Refresh Devices',
           )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Display connection status
            if (connectionStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 15.0),
                child: Text(
                  connectionStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: isConnected ? Colors.green : Theme.of(context).colorScheme.error ),
                ),
              ),

            // --- Dropdown for selecting device ---
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 5.0),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<BluetoothDevice>(
                    isExpanded: true,
                    hint: Center(child: Text("Select Bluetooth Device")),
                    value: selectedDevice,
                    // Disable dropdown if connecting or connected to prevent changes during process
                    disabledHint: selectedDevice != null ? Center(child: Text(selectedDevice!.name ?? selectedDevice!.address)) : null,
                    items: devicesList.map((device) {
                      return DropdownMenuItem(
                        child: Text(device.name ?? device.address),
                        value: device,
                      );
                    }).toList(),
                    onChanged: (isConnecting || isConnected) ? null : (device) { // Disable onChanged when connecting/connected
                      setState(() {
                        selectedDevice = device;
                        connectionStatus = ''; // Clear status on new selection
                        // Don't reset connection state here, let connect button handle it
                      });
                    },
                    alignment: AlignmentDirectional.center,
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),

            // --- Connect Button ---
            ElevatedButton(
              onPressed: (selectedDevice == null || isConnecting || isConnected) ? null : _connectToDevice,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                // Background color is the primary color (light blue)
                backgroundColor: isConnected ? Colors.grey : Theme.of(context).primaryColor,
                disabledBackgroundColor: Colors.grey[400], // Style for disabled state
                // Set text color to black for visibility
                foregroundColor: Colors.black,
              ),
              child: isConnecting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isConnected ? 'Connected' : 'Connect', style: TextStyle(fontSize: 16)), // Text color is set by foregroundColor
            ),
            SizedBox(height: 15),

            // Removed the latest Arduino message display from here

            // --- Continue Button (only shown if connected) ---
            if (isConnected && connection != null) // Also check if connection object is not null
              ElevatedButton(
                onPressed: () {
                  // Ensure connection object exists and is connected before navigating
                  if (connection == null || !isConnected) {
                       if (mounted) {
                         setState(() {
                           connectionStatus = "Connection lost. Please reconnect.";
                           isConnected = false; // Update state
                         });
                       }
                       print("Attempted to navigate but connection is null or not connected.");
                       return;
                  }
                  print("Navigating to CompartmentScreen.");
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      // Pass the connection AND the message stream
                      builder: (_) => CompartmentScreen(
                        connection: connection!,
                        messageStream: messageStream,
                      ),
                    ),
                  ).then((_) {
                    // When returning from CompartmentScreen, check connection status again
                    // The listener in _connectToDevice should handle actual disconnection,
                    // but this ensures UI consistency if state somehow diverged.
                    print("Returned from CompartmentScreen.");
                    if (mounted && !(connection?.isConnected ?? false)) {
                       print("Connection found disconnected upon returning.");
                       setState(() {
                          isConnected = false;
                          isConnecting = false;
                          connectionStatus = 'Disconnected.';
                       });
                    } else {
                      print("Connection still active upon returning.");
                    }
                  });
                },
                  style: ElevatedButton.styleFrom(
                    // Keep background color green
                    backgroundColor: Colors.green,
                    // Set text color to black
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Set Up Compartments', style: TextStyle(fontSize: 16)), // Text color is set by foregroundColor
              ),
          ],
        ),
      ),
    );
  }
}


// --- Compartment Setup Screen (With Persistence) ---
class CompartmentScreen extends StatefulWidget {
  final BluetoothConnection connection;
  final Stream<String> messageStream; // Receive the message stream

  CompartmentScreen({required this.connection, required this.messageStream});

  @override
  _CompartmentScreenState createState() => _CompartmentScreenState();
}

class _CompartmentScreenState extends State<CompartmentScreen> {
  static const String _compartmentDataKey = 'compartment_data';
  static const String _messageHistoryKey = 'message_history'; // Key for message history

  List<Map<String, String?>> compartmentData = List.generate(6, (i) => {
    'name': 'Compartment ${i + 1}',
    'time': null
  });

  // List to store all incoming messages
  List<String> messageHistory = [];

  bool _isLoading = true;
  // Track connection state locally, initialized from the passed connection
  bool _isBluetoothConnected = false;

  // State variable to hold the latest message received on this screen (still useful for initial display or other purposes)
  String latestArduinoMessage = 'No messages yet.';

  // Subscription to the message stream
  StreamSubscription<String>? _messageSubscription;


  @override
  void initState() {
    super.initState();
    // Initialize local connection state from the passed connection object
    _isBluetoothConnected = widget.connection.isConnected;
    print("CompartmentScreen initState. Initial connection state: $_isBluetoothConnected");
    _loadCompartmentData(); // Load saved compartment data
    _loadMessageHistory(); // Load saved message history

    // --- START: Listening to the message stream from BluetoothConnectScreen ---
    _messageSubscription = widget.messageStream.listen((message) {
      _handleIncomingMessage(message); // Handle the message received from the stream
    },
    onError: (error) {
      print("CompartmentScreen: Error on message stream: $error");
      // Handle errors from the stream if necessary
    },
    onDone: () {
      print("CompartmentScreen: Message stream closed.");
      // Handle stream closure if necessary
       if (mounted) {
         setState(() {
           _isBluetoothConnected = false; // Update local connection state
           latestArduinoMessage = 'Disconnected.'; // Update message on disconnection
         });
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Bluetooth Disconnected! Cannot send data.'), backgroundColor: Colors.red),
         );
       }
    });
    // --- END: Listening to the message stream from BluetoothConnectScreen ---
  }

  @override
  void dispose() {
    // Cancel the message stream subscription
    _messageSubscription?.cancel();
    super.dispose();
  }


  // --- START: Handle incoming messages from Arduino and update the message display on THIS screen ---
  void _handleIncomingMessage(String message) {
    print("CompartmentScreen received message from stream: '$message'"); // Print the exact received message

    if (!mounted) {
      print("CompartmentScreen: Handle incoming message called, but widget is not mounted.");
      return;
    }

    // Add the new message to the history
    setState(() {
      messageHistory.add(message);
      latestArduinoMessage = message; // Keep latest message updated if needed elsewhere
    });

    // Save the updated message history
    _saveMessageHistory();

    // You can add specific UI responses here based on the message content if needed
    if (message.contains("Pill taken")) { // Covers "Pill taken" and "Pill taken late"
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Pill taken successfully!'), backgroundColor: Colors.green),
       );
    } else if (message.contains("Warning! - Pill taken before schedule")) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Warning: Pill taken before schedule!'), backgroundColor: Colors.orange),
       );
    } else if (message.contains("Warning! - Wrong compartment accessed")) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Warning: Wrong compartment accessed!'), backgroundColor: Colors.red),
       );
    } else if (message.contains("Compartment accessed, but no schedule set")) {
       // Optional: Show a less critical message for accessing unscheduled compartments
       // ScaffoldMessenger.of(context).showSnackBar(
       //   SnackBar(content: Text('Compartment accessed (no schedule set).')),
       // );
    } else if (message.contains("Disconnected")) {
      print("CompartmentScreen: Message indicates disconnection.");
      setState(() {
        _isBluetoothConnected = false;
      });
    } else if (message.contains("Connection Error")) {
       print("CompartmentScreen: Message indicates connection error.");
       setState(() {
         _isBluetoothConnected = false;
       });
    }
  }
  // --- END: Handle incoming messages from Arduino and update the message display on THIS screen ---

  // --- START: Message History Persistence ---
  Future<void> _loadMessageHistory() async {
    print("CompartmentScreen: Attempting to load message history...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? savedHistory = prefs.getStringList(_messageHistoryKey);
    if (mounted && savedHistory != null) {
      setState(() {
        messageHistory = savedHistory;
      });
      print("CompartmentScreen: Successfully loaded ${messageHistory.length} messages.");
    } else {
       print("CompartmentScreen: No saved message history found.");
    }
  }

  Future<void> _saveMessageHistory() async {
    print("CompartmentScreen: Attempting to save message history...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_messageHistoryKey, messageHistory);
    print("CompartmentScreen: Message history saved (${messageHistory.length} messages).");
  }

  void _clearMessageHistory() async {
    print("CompartmentScreen: Attempting to clear message history...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messageHistoryKey);
    if (mounted) {
      setState(() {
        messageHistory.clear();
        latestArduinoMessage = 'No messages yet.'; // Reset latest message display
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message history cleared.')),
      );
      print("CompartmentScreen: Message history cleared.");
    }
  }
  // --- END: Message History Persistence ---


  Future<void> _loadCompartmentData() async {
    print("CompartmentScreen: Attempting to load compartment data...");
    // Ensure mounted check if called late
    if (!mounted) return;
    setState(() { _isLoading = true; }); // Show loading indicator

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? savedDataJson = prefs.getString(_compartmentDataKey);

    if (savedDataJson != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(savedDataJson);
        final List<Map<String, String?>> loadedData = decodedList.map((item) {
          if (item is Map) {
            return Map<String, String?>.from(item.map((key, value) => MapEntry(key.toString(), value?.toString())));
          }
          return {'name': 'Error', 'time': null};
        }).toList();

        if (loadedData.length == 6) {
           // Check mounted again before setState
           if (mounted) {
             setState(() {
               compartmentData = loadedData;
             });
             print("CompartmentScreen: Successfully loaded compartment data.");
           }
        } else {
           print("CompartmentScreen: Warning: Loaded data length mismatch (${loadedData.length}). Using defaults.");
           // Optionally clear saved data if structure changed: prefs.remove(_compartmentDataKey);
        }

      } catch (e) {
         print("CompartmentScreen: Error loading compartment data: $e. Using defaults.");
         // prefs.remove(_compartmentDataKey); // Consider clearing corrupted data
      }
    } else {
      print("CompartmentScreen: No saved compartment data found. Using defaults.");
    }
     // Ensure mounted before final setState
     if (mounted) {
       setState(() {
         _isLoading = false;
       });
     }
  }

  Future<void> _saveCompartmentData() async {
    print("CompartmentScreen: Attempting to save compartment data...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String saveDataJson = jsonEncode(compartmentData);
    await prefs.setString(_compartmentDataKey, saveDataJson);
    print("CompartmentScreen: Compartment data saved.");
  }

  // --- Function to delete compartment data ---
  void _deleteCompartmentData(int index) async {
     // Send a message to Arduino to clear the schedule for this compartment
     // Using empty name and -1:-1 time as a signal for deletion
     _sendToArduino(index, "", "-1:-1");

     // Update local state
     if (mounted) {
       setState(() {
         compartmentData[index]['name'] = 'Compartment ${index + 1}'; // Reset name to default
         compartmentData[index]['time'] = null; // Clear time
       });
     }

     // Save updated data locally
     await _saveCompartmentData();

     // Provide user feedback
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('Compartment ${index + 1} schedule deleted.')),
     );
     print("Compartment ${index + 1} data deleted.");
  }


  void _openSetDialog(int index) {
    final TextEditingController nameController = TextEditingController(text: compartmentData[index]['name'] == 'Compartment ${index + 1}' ? '' : compartmentData[index]['name']);
    TimeOfDay? selectedTime = _parseTime(compartmentData[index]['time']);
    String displayTime = selectedTime != null ? selectedTime.format(context) : 'Tap to select time';

    showDialog(
      context: context,
      // Prevent closing dialog by tapping outside if needed
      // barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Set Up Compartment ${index + 1}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Medication Name',
                      hintText: 'e.g., Vitamin C',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  SizedBox(height: 15),
                  Text("Dispense Time:", style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  InkWell(
                    onTap: () async {
                      final TimeOfDay? pickedTime = await showTimePicker(
                        context: context,
                        initialTime: selectedTime ?? TimeOfDay.now(),
                      );
                      if (pickedTime != null && pickedTime != selectedTime) {
                         setDialogState(() {
                           selectedTime = pickedTime;
                           displayTime = selectedTime!.format(context);
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
            ),
            actions: [
              // --- Add Delete Button ---
              if (compartmentData[index]['time'] != null) // Only show delete if time is set
                TextButton(
                  onPressed: !_isBluetoothConnected ? null : () {
                     Navigator.pop(context); // Close dialog first
                     _deleteCompartmentData(index); // Call the delete function
                  },
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                // Disable save if bluetooth is not connected
                onPressed: !_isBluetoothConnected ? null : () {
                  String name = nameController.text.trim();
                  if (name.isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter a medication name.')),
                     );
                     return;
                  }
                  if (selectedTime == null) {
                     ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please select a dispense time.')),
                     );
                     return;
                  }

                  // Format time as HH:mm (24-hour format)
                  // Safely access hour and minute using the null assertion operator (!)
                  // We know selectedTime is not null here because of the check above.
                  String timeString = DateFormat('HH:mm').format(DateTime(2023, 1, 1, selectedTime!.hour, selectedTime!.minute));

                  // Send data to Arduino FIRST
                  _sendToArduino(index, name, timeString);

                  // Update the main screen state only AFTER successful sending (or based on desired logic)
                  // Consider if update should happen even if send fails? Current logic updates regardless.
                  if (mounted) {
                    setState(() {
                      compartmentData[index]['name'] = name;
                      compartmentData[index]['time'] = timeString;
                    });
                  }

                  // Save the updated data locally
                  _saveCompartmentData();

                  Navigator.pop(context); // Close dialog
                },
                child: Text('Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  TimeOfDay? _parseTime(String? timeString) {
    if (timeString == null || timeString.isEmpty || timeString == "-1:-1") return null; // Also check for "-1:-1"
    try {
      final format = DateFormat('HH:mm');
      final dt = format.parse(timeString);
      return TimeOfDay.fromDateTime(dt);
    } catch (e) {
      print("CompartmentScreen: Error parsing time '$timeString': $e");
      return null;
    }
  }


  void _sendToArduino(int index, String name, String time) {
    // Use the local state variable to check connection
    // We also check widget.connection.isConnected as a backup
    if (!_isBluetoothConnected || !widget.connection.isConnected) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Bluetooth disconnected! Cannot send data.'), backgroundColor: Colors.red),
         );
       }
       print("CompartmentScreen: Attempted to send data but Bluetooth is disconnected.");
       return;
    }

    String compartmentCode = 'C${index + 1}';
    // Send empty name and -1:-1 time for deletion
    String message = '$compartmentCode|$name|$time\n';
    print("CompartmentScreen: Attempting to send message: $message");
    try {
      widget.connection.output.add(Uint8List.fromList(message.codeUnits));
      widget.connection.output.allSent.then((_) {
         print('CompartmentScreen: Successfully sent to Arduino: $message');
         // Removed SnackBar here
      }).catchError((error) {
         print("CompartmentScreen: Error confirming send: $error");
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error confirming send: $error'), backgroundColor: Colors.red),
           );
            // Update connection state if error suggests disconnection
           setState(() { _isBluetoothConnected = false; });
         }
      });
    } catch (e) {
       print("CompartmentScreen: Error sending data: $e");
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error sending data: $e'), backgroundColor: Colors.red),
         );
          // Update connection state if error suggests disconnection
         setState(() { _isBluetoothConnected = false; });
       }
    }
  }

  // --- NEW: Function to show the message history dialog ---
  void _showMessageHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Dispenser Messages'),
          content: Container(
            width: double.maxFinite, // Allow the dialog to take more width
            child: messageHistory.isEmpty
                ? Center(child: Text('No messages yet.'))
                : ListView.builder(
                    shrinkWrap: true, // Important for ListView inside AlertDialog
                    itemCount: messageHistory.length,
                    itemBuilder: (context, index) {
                      // Display messages in reverse order (latest first)
                      final message = messageHistory[messageHistory.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(message),
                      );
                    },
                  ),
          ),
          actions: [
            // --- Add Delete All Messages Button ---
            if (messageHistory.isNotEmpty)
              TextButton(
                onPressed: () {
                  _clearMessageHistory();
                  Navigator.pop(context); // Close the dialog after clearing
                },
                child: Text('Clear All', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    // Update local connection state based on the widget's connection property
    // This helps ensure the UI reflects the current connection status
    _isBluetoothConnected = widget.connection.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text("Pill Compartment Setup"),
        centerTitle: true,
        actions: [
          // --- Add Message History Icon Button ---
          IconButton(
            icon: Icon(Icons.message), // Message icon
            onPressed: _showMessageHistoryDialog, // Call the dialog function on press
            tooltip: 'View Messages',
          ),
          // Removed the refresh button from here, assuming message history is more important
          // You can add it back if needed, perhaps in a different location or as part of a menu
          // IconButton(
          //   icon: Icon(Icons.refresh),
          //   onPressed: isConnecting ? null : getBondedDevices,
          //   tooltip: 'Refresh Devices',
          // )
        ],
      ),
      body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : Column( // Add column to show connection status message and message display
              children: [
                // Show connection status banner if not connected
                if (!_isBluetoothConnected)
                  Container(
                     width: double.infinity,
                     color: Theme.of(context).colorScheme.error,
                     padding: EdgeInsets.all(8),
                     child: Text(
                       'Bluetooth Disconnected. Cannot send updates.',
                       style: TextStyle(color: Colors.white),
                       textAlign: TextAlign.center,
                     ),
                   ),
                // List view takes remaining space
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(10),
                    itemCount: 6,
                    itemBuilder: (context, index) {
                      String name = compartmentData[index]['name'] ?? 'Compartment ${index + 1}';
                      String? timeStr = compartmentData[index]['time'];
                      TimeOfDay? time = _parseTime(timeStr);
                      String displayTime = time != null ? time.format(context) : 'Not set';

                      return Card(
                        elevation: 3,
                        margin: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                              child: Text('${index + 1}'),
                              backgroundColor: Theme.of(context).primaryColorLight,
                          ),
                          title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Time: $displayTime'),
                          trailing: Icon(Icons.edit, color: Theme.of(context).primaryColor),
                          // Disable onTap if bluetooth is not connected? Optional UX choice.
                          onTap: () => _openSetDialog(index),
                        ),
                      );
                    },
                  ),
                ),
                // Removed the latest Arduino message display card from here
              ],
            ),
    );
  }
}
