import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart'; // Required for date/time formatting
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'dart:convert'; // Import dart:convert for JSON encoding/decoding
import 'dart:async'; // Import async for StreamController
import 'package:flutter/services.dart'; // Required for PlatformException
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler

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
        primarySwatch: Colors.lightBlue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.lightBlue).copyWith(error: Colors.redAccent),
        chipTheme: ChipThemeData( // Added ChipTheme for styling day selectors
          backgroundColor: Colors.grey[300],
          selectedColor: Colors.lightBlue[400],
          labelStyle: TextStyle(color: Colors.black),
          secondaryLabelStyle: TextStyle(color: Colors.white),
          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        ),
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
  String _incomingDataBuffer = "";
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get messageStream => _messageController.stream;
  StreamSubscription<BluetoothState>? _bluetoothStateSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndGetDevices();
    _bluetoothStateSubscription = FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      print("Bluetooth state changed: $state");
      if (state == BluetoothState.STATE_ON) {
        Future.delayed(Duration(milliseconds: 500), () {
           _requestPermissionsAndGetDevices();
        });
      } else {
        if (mounted) {
          setState(() {
            isConnected = false;
            isConnecting = false;
            connectionStatus = 'Bluetooth is off. Please turn it on.';
            connection?.dispose();
            connection = null;
            devicesList = [];
            selectedDevice = null;
          });
          _messageController.add('Bluetooth Disconnected.');
        }
      }
    });
  }

  @override
  void dispose() {
    print("BluetoothConnectScreen dispose called.");
    if (connection?.isConnected ?? false) {
      print("Disconnecting Bluetooth connection on dispose.");
      connection?.dispose();
    }
    connection = null;
    _messageController.close();
    _bluetoothStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissionsAndGetDevices() async {
    print("Requesting Bluetooth and Location permissions...");
    setState(() {
      connectionStatus = 'Requesting permissions...';
      devicesList = [];
      selectedDevice = null;
    });

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allPermissionsGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        print("Permission not granted: ${permission.toString()} - ${status.toString()}");
        allPermissionsGranted = false;
      }
    });

    if (mounted) {
      if (allPermissionsGranted) {
        print("All required permissions granted.");
        Future.delayed(Duration(milliseconds: 300), () {
           _checkBluetoothStateAndGetDevices();
        });
      } else {
        setState(() {
          connectionStatus = 'Permissions denied. Cannot scan for devices.';
        });
        print("Required permissions not granted.");
         openAppSettings();
      }
    }
  }

  Future<void> _checkBluetoothStateAndGetDevices() async {
    print("Checking Bluetooth state and getting devices (after permissions)...");
    setState(() {
      connectionStatus = 'Checking Bluetooth state...';
      devicesList = [];
      selectedDevice = null;
    });

    try {
      BluetoothState state = await FlutterBluetoothSerial.instance.state;
      print("Current Bluetooth state: $state");

      if (state == BluetoothState.STATE_OFF) {
         if (mounted) {
           setState(() {
             connectionStatus = 'Bluetooth is off. Please turn it on.';
           });
         }
         print("Bluetooth is OFF.");
         return;
      } else if (state == BluetoothState.STATE_ON) {
        await getBondedDevices();
      } else {
        if (mounted) {
          setState(() {
            connectionStatus = 'Bluetooth state: $state. Waiting for ON state.';
          });
        }
        print("Bluetooth is in state: $state. Waiting for ON.");
      }
    } on PlatformException catch (e) {
        if (mounted) {
          setState(() {
            connectionStatus = 'Permission Error: ${e.message ?? e.toString()}. Please grant Bluetooth permissions.';
          });
        }
        print("PlatformException getting bonded devices: $e");
    } catch (e) {
        if (mounted) {
          setState(() {
            connectionStatus = 'Error getting devices: ${e.toString()}';
          });
        }
        print("Error getting bonded devices: $e");
    }
  }

  Future<void> getBondedDevices() async {
    print("Attempting to get bonded devices...");
    setState(() {
      connectionStatus = 'Getting bonded devices...';
      devicesList = [];
      selectedDevice = null;
    });
    try {
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
      if (mounted) {
        setState(() {
          devicesList = devices;
          connectionStatus = devices.isEmpty ? 'No bonded devices found. Please pair your dispenser.' : 'Select a device.';
        });
        print("Found ${devices.length} bonded devices.");
      }
    } on PlatformException catch (e) {
        if (mounted) {
          setState(() {
            connectionStatus = 'Permission Error: ${e.message ?? e.toString()}. Please grant Bluetooth permissions.';
          });
        }
        print("PlatformException getting bonded devices: $e");
    } catch (e) {
        if (mounted) {
          setState(() {
            connectionStatus = 'Error getting devices: ${e.toString()}';
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
      return;
    }

    setState(() {
      isConnecting = true;
      connectionStatus = 'Connecting to ${selectedDevice!.name ?? selectedDevice!.address}...';
    });
    print("Attempting to connect to ${selectedDevice!.address}");

    try {
      if (connection?.isConnected ?? false) {
        print("Disposing existing connection before new attempt.");
        connection?.dispose();
      }
      connection = null;

      BluetoothConnection newConnection =
          await BluetoothConnection.toAddress(selectedDevice!.address);

      if (!mounted) {
          print("Widget unmounted after connection attempt, disposing new connection.");
          newConnection.dispose();
          return;
      }

      setState(() {
        connection = newConnection;
        isConnected = true;
        isConnecting = false;
        connectionStatus = 'Connected to ${selectedDevice!.name ?? selectedDevice!.address}!';
      });
      print("Successfully connected to ${selectedDevice!.address}");

      connection?.input?.listen(
        (Uint8List data) {
          String incomingString = String.fromCharCodes(data);
          _incomingDataBuffer += incomingString;
          int newlineIndex;
          while ((newlineIndex = _incomingDataBuffer.indexOf('\n')) != -1) {
            String message = _incomingDataBuffer.substring(0, newlineIndex).trim();
            _incomingDataBuffer = _incomingDataBuffer.substring(newlineIndex + 1);
            _handleIncomingMessage(message);
          }
        },
        onDone: () {
          print("Bluetooth connection closed (onDone triggered on ConnectScreen).");
          if (mounted) {
            setState(() {
              isConnected = false;
              isConnecting = false;
              connectionStatus = 'Device disconnected.';
              connection = null;
            });
            _messageController.add('Device disconnected.');
          }
        },
        onError: (error) {
            print("Bluetooth connection error on ConnectScreen: $error");
            if (mounted) {
              setState(() {
                isConnected = false;
                isConnecting = false;
                connectionStatus = 'Connection Error: ${error.toString()}';
                connection = null;
              });
              _messageController.add('Connection Error: ${error.toString()}');
            }
        },
        cancelOnError: true
      );

    } on PlatformException catch (e) {
        print("Connection failed (PlatformException): ${e.code} - ${e.message}");
        if (mounted) {
           String userMessage = 'Connection Failed: ${e.message ?? e.toString()}';
           if (e.code == 'read failed, socket might closed or timeout') {
              userMessage = 'Connection failed. Please ensure the device is on and in range.';
           } else if (e.code == 'connect_error') {
              userMessage = 'Connection failed. Maybe Device Bluetooth is off or it is connected anyother device!!';
           }
           setState(() {
             isConnected = false;
             isConnecting = false;
             connectionStatus = userMessage;
             connection = null;
           });
           _messageController.add(userMessage);
        }
    } catch (e) {
        print("Connection failed: $e");
        if (mounted) {
         setState(() {
           isConnected = false;
           isConnecting = false;
           connectionStatus = "Connection Failed: ${e.toString()}";
           connection = null;
         });
         _messageController.add("Connection Failed: ${e.toString()}");
        }
    }
  }

  void _handleIncomingMessage(String message) {
    print("Received message from Arduino: '$message'");
    _messageController.add(message);
    // Further handling can be done on the CompartmentScreen or here if needed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect Bluetooth Device'),
        centerTitle: true,
        actions: [
           IconButton(
             icon: Icon(Icons.refresh),
             onPressed: isConnecting ? null : _requestPermissionsAndGetDevices,
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
            if (connectionStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 15.0),
                child: Text(
                  connectionStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: isConnected ? Colors.green : Theme.of(context).colorScheme.error ),
                ),
              ),
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
                    disabledHint: selectedDevice != null ? Center(child: Text(selectedDevice!.name ?? selectedDevice!.address)) : null,
                    items: devicesList.map((device) {
                      return DropdownMenuItem(
                        child: Text(device.name ?? device.address),
                        value: device,
                      );
                    }).toList(),
                    onChanged: (isConnecting || isConnected) ? null : (device) {
                      setState(() {
                        selectedDevice = device;
                        connectionStatus = '';
                      });
                    },
                    alignment: AlignmentDirectional.center,
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: (selectedDevice == null || isConnecting || isConnected) ? null : _connectToDevice,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: isConnected ? Colors.grey : Theme.of(context).primaryColor,
                disabledBackgroundColor: Colors.grey[400],
                foregroundColor: Colors.black,
              ),
              child: isConnecting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isConnected ? 'Connected' : 'Connect', style: TextStyle(fontSize: 16)),
            ),
            SizedBox(height: 15),
            if (isConnected && connection != null)
              ElevatedButton(
                onPressed: () {
                  if (connection == null || !isConnected) {
                       if (mounted) {
                         setState(() {
                           connectionStatus = "Connection lost. Please reconnect.";
                           isConnected = false;
                         });
                       }
                       print("Attempted to navigate but connection is null or not connected.");
                       return;
                  }
                  print("Navigating to CompartmentScreen.");
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompartmentScreen(
                        connection: connection!,
                        messageStream: messageStream,
                      ),
                    ),
                  ).then((_) {
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
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Configure Compartments', style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Compartment Setup Screen (With Persistence & Day Scheduling) ---
class CompartmentScreen extends StatefulWidget {
  final BluetoothConnection connection;
  final Stream<String> messageStream;

  CompartmentScreen({required this.connection, required this.messageStream});

  @override
  _CompartmentScreenState createState() => _CompartmentScreenState();
}

class _CompartmentScreenState extends State<CompartmentScreen> {
  static const String _compartmentDataKey = 'compartment_data_v2'; // Changed key for new structure
  static const String _messageHistoryKey = 'message_history';

  // MODIFIED: compartmentData now includes a list of bools for days
  List<Map<String, dynamic>> compartmentData = List.generate(6, (i) => {
    'name': 'Compartment ${i + 1}',
    'time': null,
    'days': List<bool>.filled(7, false), // Sunday to Saturday, initially all false
  });

  List<String> messageHistory = [];
  bool _isLoading = true;
  bool _isBluetoothConnected = false;
  String latestArduinoMessage = 'No messages yet.';
  StreamSubscription<String>? _messageSubscription;

  // Helper for day names
  final List<String> _dayAbbreviations = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _isBluetoothConnected = widget.connection.isConnected;
    print("CompartmentScreen initState. Initial connection state: $_isBluetoothConnected");
    _loadCompartmentData();
    _loadMessageHistory();

    _messageSubscription = widget.messageStream.listen((message) {
      _handleIncomingMessage(message);
    },
    onError: (error) {
      print("CompartmentScreen: Error on message stream: $error");
      if(mounted) {
        setState(() {
          _isBluetoothConnected = false;
          latestArduinoMessage = 'Stream Error. Disconnected.';
        });
      }
    },
    onDone: () {
      print("CompartmentScreen: Message stream closed.");
       if (mounted) {
         setState(() {
           _isBluetoothConnected = false;
           latestArduinoMessage = 'Disconnected.';
         });
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Bluetooth Disconnected! Cannot send data.'), backgroundColor: Colors.red),
         );
       }
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _handleIncomingMessage(String message) {
    print("CompartmentScreen received message from stream: '$message'");
    if (!mounted) return;

    setState(() {
      messageHistory.add(message);
      latestArduinoMessage = message;
    });
    _saveMessageHistory();

    // Show Snackbars for specific messages
    if (message.contains("Pill taken")) {
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
    } else if (message.contains("Disconnected")) {
      print("CompartmentScreen: Message indicates disconnection.");
      setState(() { _isBluetoothConnected = false; });
    } else if (message.contains("Connection Error")) {
       print("CompartmentScreen: Message indicates connection error.");
       setState(() { _isBluetoothConnected = false; });
    } else if (message.startsWith("Updated C") || message.startsWith("Cleared schedule")) {
        ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Arduino: $message'), backgroundColor: Colors.blue),
       );
    }
  }

  Future<void> _loadMessageHistory() async {
    print("CompartmentScreen: Attempting to load message history...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? savedHistory = prefs.getStringList(_messageHistoryKey);
    if (mounted && savedHistory != null) {
      setState(() { messageHistory = savedHistory; });
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
        latestArduinoMessage = 'No messages yet.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message history cleared.')),
      );
      print("CompartmentScreen: Message history cleared.");
    }
  }

  Future<void> _loadCompartmentData() async {
    print("CompartmentScreen: Attempting to load compartment data (v2)...");
    if (!mounted) return;
    setState(() { _isLoading = true; });

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? savedDataJson = prefs.getString(_compartmentDataKey);

    if (savedDataJson != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(savedDataJson);
        final List<Map<String, dynamic>> loadedData = decodedList.map((item) {
          if (item is Map) {
            // Ensure 'days' is correctly parsed as List<bool>
            List<bool> daysList = List<bool>.filled(7, false);
            if (item['days'] is List) {
              List<dynamic> rawDays = item['days'];
              if (rawDays.length == 7) {
                daysList = rawDays.map((d) => d == true).toList();
              }
            }
            return {
              'name': item['name']?.toString(),
              'time': item['time']?.toString(),
              'days': daysList,
            };
          }
          // Return a default structure if item is not a map
          return {'name': 'Error', 'time': null, 'days': List<bool>.filled(7, false)};
        }).toList();

        if (loadedData.length == 6) {
           if (mounted) {
             setState(() { compartmentData = loadedData; });
             print("CompartmentScreen: Successfully loaded compartment data (v2).");
           }
        } else {
           print("CompartmentScreen: Warning: Loaded data (v2) length mismatch (${loadedData.length}). Using defaults.");
        }
      } catch (e) {
         print("CompartmentScreen: Error loading compartment data (v2): $e. Using defaults.");
         // Consider clearing corrupted data: prefs.remove(_compartmentDataKey);
      }
    } else {
      print("CompartmentScreen: No saved compartment data (v2) found. Using defaults.");
    }
     if (mounted) {
       setState(() { _isLoading = false; });
     }
  }

  Future<void> _saveCompartmentData() async {
    print("CompartmentScreen: Attempting to save compartment data (v2)...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // Ensure 'days' is stored in a JSON-compatible format (list of bools is fine)
    final String saveDataJson = jsonEncode(compartmentData);
    await prefs.setString(_compartmentDataKey, saveDataJson);
    print("CompartmentScreen: Compartment data (v2) saved.");
  }

  void _deleteCompartmentData(int index) async {
     // Send a message to Arduino to clear the schedule for this compartment
     // Format: C<index>|<Name>|-1:-1|<D0,D1,D2,D3,D4,D5,D6>
     // Name can be empty, days string is all zeros for deletion.
     // MODIFIED: Sending empty string for days for deletion
     _sendToArduino(index, "", "-1:-1", List<bool>.filled(7, false));

     if (mounted) {
       setState(() {
         compartmentData[index]['name'] = 'Compartment ${index + 1}';
         compartmentData[index]['time'] = null;
         compartmentData[index]['days'] = List<bool>.filled(7, false); // Reset days
       });
     }
     await _saveCompartmentData();
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('Compartment ${index + 1} schedule deleted.')),
     );
     print("Compartment ${index + 1} data deleted.");
  }

  void _openSetDialog(int index) {
    final TextEditingController nameController = TextEditingController(
        text: compartmentData[index]['name'] == 'Compartment ${index + 1}' ? '' : compartmentData[index]['name']);
    TimeOfDay? selectedTime = _parseTime(compartmentData[index]['time']);
    String displayTime = selectedTime != null ? selectedTime.format(context) : 'Tap to select time';
    // Crucially, get a mutable copy of the days list for the dialog
    List<bool> currentDays = List<bool>.from(compartmentData[index]['days'] as List<bool>);


    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Configure Compartment ${index + 1}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text("Schedule Time:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                  SizedBox(height: 15),
                  Row( // Row for "Repeat on Days:" and "Select Everyday" button
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Repeat on Days:", style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton( // Changed to TextButton for less emphasis than ElevatedButton
                        onPressed: () {
                          setDialogState(() {
                            for (int i = 0; i < currentDays.length; i++) {
                              currentDays[i] = true;
                            }
                          });
                        },
                        child: Text("Select Everyday"),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // --- Day Selector Chips ---
                  Wrap( // Use Wrap for chips to flow to next line if needed
                    spacing: 6.0, // Horizontal space between chips
                    runSpacing: 0.0, // Vertical space between lines of chips
                    children: List<Widget>.generate(7, (int dayIndex) {
                      return ChoiceChip(
                        label: Text(_dayAbbreviations[dayIndex]),
                        selected: currentDays[dayIndex],
                        onSelected: (bool selected) {
                          setDialogState(() {
                            currentDays[dayIndex] = selected;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              if (compartmentData[index]['time'] != null)
                TextButton(
                  onPressed: !_isBluetoothConnected ? null : () {
                     Navigator.pop(context);
                     _deleteCompartmentData(index);
                  },
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: !_isBluetoothConnected ? null : () async {
                  String name = nameController.text.trim();
                  if (name.isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter a medication name.')),
                     );
                     return;
                  }
                  if (selectedTime == null) {
                     ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please select a schedule time.')),
                     );
                     return;
                  }
                  // Check if at least one day is selected
                  if (!currentDays.contains(true)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please select at least one day.')),
                    );
                    return;
                  }

                  String timeString = DateFormat('HH:mm').format(DateTime(2023, 1, 1, selectedTime!.hour, selectedTime!.minute));

                  // Send data to Arduino
                  _sendToArduino(index, name, timeString, currentDays);

                  if (mounted) {
                    setState(() {
                      compartmentData[index]['name'] = name;
                      compartmentData[index]['time'] = timeString;
                      compartmentData[index]['days'] = List<bool>.from(currentDays); // Save the selected days
                    });
                  }
                  await _saveCompartmentData();
                  Navigator.pop(context);
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
    if (timeString == null || timeString.isEmpty || timeString == "-1:-1") return null;
    try {
      final format = DateFormat('HH:mm');
      final dt = format.parse(timeString);
      return TimeOfDay.fromDateTime(dt);
    } catch (e) {
      print("CompartmentScreen: Error parsing time '$timeString': $e");
      return null;
    }
  }

  // MODIFIED: Added days parameter and changed how daysString is created
  void _sendToArduino(int index, String name, String time, List<bool> days) {
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
    // Convert days list to comma-separated string of abbreviations for selected days
    List<String> selectedDayAbbreviations = [];
    for (int i = 0; i < days.length; i++) {
      if (days[i]) {
        selectedDayAbbreviations.add(_dayAbbreviations[i]);
      }
    }
    String daysString = selectedDayAbbreviations.join(',');

    String message = '$compartmentCode|$name|$time|$daysString\n'; // Added daysString

    print("CompartmentScreen: Attempting to send message: $message");
    try {
      widget.connection.output.add(Uint8List.fromList(message.codeUnits));
      widget.connection.output.allSent.then((_) {
         print('CompartmentScreen: Successfully sent to Arduino: $message');
         // SnackBar for confirmation is now handled by _handleIncomingMessage based on Arduino's reply
      }).catchError((error) {
         print("CompartmentScreen: Error confirming send: $error");
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error confirming send: $error'), backgroundColor: Colors.red),
           );
           setState(() { _isBluetoothConnected = false; });
         }
      });
    } catch (e) {
       print("CompartmentScreen: Error sending data: $e");
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error sending data: $e'), backgroundColor: Colors.red),
         );
         setState(() { _isBluetoothConnected = false; });
       }
    }
  }

  void _showMessageHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Messages'),
          content: Container(
            width: double.maxFinite,
            child: messageHistory.isEmpty
                ? Center(child: Text('No messages yet.'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: messageHistory.length,
                    itemBuilder: (context, index) {
                      final message = messageHistory[messageHistory.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(message),
                      );
                    },
                  ),
          ),
          actions: [
            if (messageHistory.isNotEmpty)
              TextButton(
                onPressed: () {
                  _clearMessageHistory();
                  Navigator.pop(context);
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

  // Helper function to get a display string for scheduled days
  String _getScheduledDaysString(List<bool> days) {
    List<String> scheduledDayNames = [];
    for (int i = 0; i < days.length; i++) {
      if (days[i]) {
        scheduledDayNames.add(_dayAbbreviations[i]);
      }
    }
    if (scheduledDayNames.isEmpty) {
      return 'No days set';
    }
    if (scheduledDayNames.length == 7) {
      return 'Everyday';
    }
    return scheduledDayNames.join(', ');
  }


  @override
  Widget build(BuildContext context) {
    _isBluetoothConnected = widget.connection.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text("Pill Compartment Configuration"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.message),
            onPressed: _showMessageHistoryDialog,
            tooltip: 'View Messages',
          ),
        ],
      ),
      body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : Column(
              children: [
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
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(10),
                    itemCount: 6,
                    itemBuilder: (context, index) {
                      String name = compartmentData[index]['name'] as String? ?? 'Compartment ${index + 1}';
                      String? timeStr = compartmentData[index]['time'] as String?;
                      TimeOfDay? time = _parseTime(timeStr);
                      String displayTime = time != null ? time.format(context) : 'Time not set';
                      // Get the days list and display string
                      List<bool> days = compartmentData[index]['days'] as List<bool>? ?? List<bool>.filled(7, false);
                      String daysDisplayString = _getScheduledDaysString(days);

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
                          subtitle: Column( // Use Column to display time and days
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Time: $displayTime'),
                              SizedBox(height: 2),
                              Text('Days: $daysDisplayString', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                            ],
                          ),
                          trailing: Icon(Icons.edit, color: Theme.of(context).primaryColor),
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