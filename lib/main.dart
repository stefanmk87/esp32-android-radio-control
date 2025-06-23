import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

const String esp32Url = "http://192.168.1.36"; // Change to your ESP32 IP

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Radio Controller',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: const WidgetStatePropertyAll(Colors.deepPurpleAccent),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Colors.deepPurpleAccent,
          thumbColor: Colors.deepPurple,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const RadioHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class RadioHomePage extends StatefulWidget {
  const RadioHomePage({super.key});
  @override
  State<RadioHomePage> createState() => _RadioHomePageState();
}

class _RadioHomePageState extends State<RadioHomePage> {
  String nowTitle = "Loading...";
  String station = "Loading...";
  String ip = "-";
  int _volumePercent = 50;
  Timer? _volumeDebounce;
  List<Map<String, dynamic>> stations = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    fetchNowPlaying();
    fetchStations();
    Timer.periodic(const Duration(seconds: 3), (_) => fetchNowPlaying());
  }

  Future<void> fetchNowPlaying() async {
    try {
      final res = await http.get(Uri.parse('$esp32Url/nowplaying'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          nowTitle = data['title'] ?? "";
          station = data['station'] ?? "No Station";
          ip = data['ip'] ?? "-";
          _volumePercent = data['volume'] ?? 50;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to fetch now playing: ${e.toString()}';
      });
    }
  }

  Future<void> fetchStations() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      final res = await http.get(Uri.parse('$esp32Url/stations'));
      if (res.statusCode == 200) {
        final List<dynamic> stationList = json.decode(res.body);
        setState(() {
          stations = stationList.map((station) => {
            'name': station['name']?.toString() ?? 'Unknown Station',
            'url': station['url']?.toString() ?? ''
          }).toList();
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load stations (HTTP ${res.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to fetch stations: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  void _setVolumeDebounced(double value) {
    setState(() => _volumePercent = value.toInt());
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        await http.post(
          Uri.parse('$esp32Url/control'),
          body: jsonEncode({"action": "volume", "volume": value / 100}),
          headers: {"Content-Type": "application/json"},
        );
        fetchNowPlaying();
      } catch (e) {
        setState(() {
          errorMessage = 'Volume control failed: ${e.toString()}';
        });
      }
    });
  }

  Future<void> _addStationDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Station"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: "Stream URL"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isNotEmpty && url.isNotEmpty) {
                try {
                  final response = await http.post(
                    Uri.parse('$esp32Url/stations'),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({"name": name, "url": url}),
                  );
                  if (response.statusCode == 200) {
                    Navigator.pop(context);
                    fetchStations();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to add station: ${response.body}')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding station: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStationDialog(int index) async {
    final stationData = stations[index];
    final nameController = TextEditingController(text: stationData['name']);
    final urlController = TextEditingController(text: stationData['url']);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Update Station"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: "Stream URL"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isNotEmpty && url.isNotEmpty) {
                try {
                  final response = await http.post(
                    Uri.parse('$esp32Url/stations/$index'),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({"name": name, "url": url}),
                  );
                  if (response.statusCode == 200) {
                    Navigator.pop(context);
                    fetchStations();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update station: ${response.body}')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating station: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStation(int index) async {
    try {
      final response = await http.delete(Uri.parse('$esp32Url/stations/$index'));
      if (response.statusCode == 200) {
        fetchStations();
      } else {
        setState(() {
          errorMessage = 'Failed to delete station: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error deleting station: ${e.toString()}';
      });
    }
  }

Future<void> _playStation(int index) async {
  try {
    final response = await http.post(
      Uri.parse('$esp32Url/play'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"index": index}),
    );
    
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Now playing: ${stations[index]['name']}'),
          duration: const Duration(seconds: 2),
        ),
      );
      fetchNowPlaying();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${response.body}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Network error: ${e.toString()}'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  Future<void> _sendControl(String action) async {
    try {
      final response = await http.post(
        Uri.parse('$esp32Url/control'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": action}),
      );
      if (response.statusCode != 200) {
        setState(() {
          errorMessage = 'Control failed: ${response.body}';
        });
      }
      fetchNowPlaying();
    } catch (e) {
      setState(() {
        errorMessage = 'Control error: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ESP32 Web Radio")),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Now playing info
            Text("Now Playing: $nowTitle", style: const TextStyle(fontSize: 16)),
            Text("Station: $station"),
            Text("ESP32 IP: $ip"),
            const SizedBox(height: 20),
            
            // Volume control
            Text("Volume: $_volumePercent%", style: const TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              min: 0,
              max: 100,
              value: _volumePercent.toDouble(),
              onChanged: _setVolumeDebounced,
            ),
            
            // Player controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _sendControl("prev"),
                  child: const Text("⏮️ Prev"),
                ),
                ElevatedButton(
                  onPressed: () => _sendControl("pause"),
                  child: const Text("⏸ Pause"),
                ),
                ElevatedButton(
                  onPressed: () => _sendControl("next"),
                  child: const Text("⏭️ Next"),
                ),
              ],
            ),
            const Divider(),
            
            // Stations list header
            const Text("Stations:", style: TextStyle(fontWeight: FontWeight.bold)),
            if (errorMessage.isNotEmpty)
              Text(errorMessage, style: const TextStyle(color: Colors.red)),
            
            // Stations list
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: stations.length,
                      itemBuilder: (context, index) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            title: Text(stations[index]['name']),
                            subtitle: Text(stations[index]['url']),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: () => _playStation(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _updateStationDialog(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _deleteStation(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Add station button
            ElevatedButton.icon(
              onPressed: _addStationDialog,
              icon: const Icon(Icons.add),
              label: const Text("Add Station"),
            ),
          ],
        ),
      ),
    );
  }
}