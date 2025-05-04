import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart'; // Required for date/time formatting
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'dart:convert'; // Import dart:convert for JSON encoding/decoding

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
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Define error color for consistency
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue).copyWith(error: Colors.redAccent),
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

      // Listen for disconnection AFTER connection is established and state is set
      connection?.input?.listen(
        (Uint8List data) {
          // Handle data received from Arduino if needed on this screen
          // print('Data received on ConnectScreen: ${String.fromCharCodes(data)}');
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
            }
        },
        cancelOnError: true // Cancel subscription on error
      );

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
        }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                backgroundColor: isConnected ? Colors.grey : Theme.of(context).primaryColor,
                disabledBackgroundColor: Colors.grey[400], // Style for disabled state
              ),
              child: isConnecting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isConnected ? 'Connected' : 'Connect', style: TextStyle(fontSize: 16)),
            ),
            SizedBox(height: 15),

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
                      builder: (_) => CompartmentScreen(connection: connection!),
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
                    backgroundColor: Colors.green,
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


// --- Compartment Setup Screen (With Persistence) ---
class CompartmentScreen extends StatefulWidget {
  final BluetoothConnection connection;

  CompartmentScreen({required this.connection});

  @override
  _CompartmentScreenState createState() => _CompartmentScreenState();
}

class _CompartmentScreenState extends State<CompartmentScreen> {
  static const String _compartmentDataKey = 'compartment_data';

  List<Map<String, String?>> compartmentData = List.generate(6, (i) => {
    'name': 'Compartment ${i + 1}',
    'time': null
  });

  bool _isLoading = true;
  // Track connection state locally, initialized from the passed connection
  bool _isBluetoothConnected = false;

  @override
  void initState() {
    super.initState();
    // Initialize local connection state from the passed connection object
    _isBluetoothConnected = widget.connection.isConnected;
    print("CompartmentScreen initState. Initial connection state: $_isBluetoothConnected");
    _loadCompartmentData(); // Load saved data

    // Removed the duplicate listener on widget.connection.input
    // The BluetoothConnectScreen is responsible for managing the primary listener.

    // If you need to react to incoming data on this screen, you would need
    // a different mechanism, perhaps a shared state management solution
    // or callbacks passed from the BluetoothConnectScreen.
  }

  Future<void> _loadCompartmentData() async {
    print("Attempting to load compartment data...");
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
             print("Successfully loaded compartment data.");
           }
        } else {
           print("Warning: Loaded data length mismatch (${loadedData.length}). Using defaults.");
           // Optionally clear saved data if structure changed: prefs.remove(_compartmentDataKey);
        }

      } catch (e) {
         print("Error loading compartment data: $e. Using defaults.");
         // prefs.remove(_compartmentDataKey); // Consider clearing corrupted data
      }
    } else {
      print("No saved compartment data found. Using defaults.");
    }
     // Ensure mounted before final setState
     if (mounted) {
       setState(() {
         _isLoading = false;
       });
     }
  }

  Future<void> _saveCompartmentData() async {
    print("Attempting to save compartment data...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String saveDataJson = jsonEncode(compartmentData);
    await prefs.setString(_compartmentDataKey, saveDataJson);
    print("Compartment data saved.");
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
    if (timeString == null || timeString.isEmpty) return null;
    try {
      final format = DateFormat('HH:mm');
      final dt = format.parse(timeString);
      return TimeOfDay.fromDateTime(dt);
    } catch (e) {
      print("Error parsing time '$timeString': $e");
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
       print("Attempted to send data but Bluetooth is disconnected.");
       return;
    }

    String compartmentCode = 'C${index + 1}';
    String message = '$compartmentCode|$name|$time\n';
    print("Attempting to send message: $message");
    try {
      widget.connection.output.add(Uint8List.fromList(message.codeUnits));
      widget.connection.output.allSent.then((_) {
         print('Successfully sent to Arduino: $message');
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Compartment ${index + 1} data sent to dispenser.'), duration: Duration(seconds: 2)),
           );
         }
      }).catchError((error) {
         print("Error confirming data send: $error");
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error confirming send: $error'), backgroundColor: Colors.red),
           );
            // Update connection state if error suggests disconnection
           setState(() { _isBluetoothConnected = false; });
         }
      });
    } catch (e) {
       print("Error sending data: $e");
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error sending data: $e'), backgroundColor: Colors.red),
         );
          // Update connection state if error suggests disconnection
         setState(() { _isBluetoothConnected = false; });
       }
    }
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
      ),
      body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : Column( // Add column to show connection status message
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
              ],
            ),
    );
  }
}
