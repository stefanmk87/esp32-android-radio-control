import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

void main() => runApp(const MyApp());

const String esp32Url = "http://192.168.1.36"; // Replace with your ESP32 IP

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Radio Controller',
      theme: ThemeData.dark(),
      home: const RadioController(),
    );
  }
}

class RadioController extends StatefulWidget {
  const RadioController({super.key});
  @override
  State<RadioController> createState() => _RadioControllerState();
}

class _RadioControllerState extends State<RadioController> {
  double _volume = 50;

  String _title = 'Loading...';
  String _station = '';
  String _ip = '';
  int _volumePercent = 0;

  List<dynamic> _stations = [];
  bool _loadingStations = true;

  Timer? _nowPlayingTimer;
//
  @override
  void initState() {
    super.initState();
    fetchStations();
    fetchNowPlaying();
    // Refresh metadata every 10 seconds automatically
    _nowPlayingTimer = Timer.periodic(const Duration(seconds: 10), (_) => fetchNowPlaying());
  }

  @override
  void dispose() {
    _nowPlayingTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchStations() async {
    setState(() => _loadingStations = true);
    try {
      final response = await http.get(Uri.parse('$esp32Url/api/stations'));
      if (response.statusCode == 200) {
        setState(() {
          _stations = json.decode(response.body);
          _loadingStations = false;
        });
      } else {
        setState(() => _loadingStations = false);
      }
    } catch (e) {
      setState(() => _loadingStations = false);
    }
  }

  Future<void> fetchNowPlaying() async {
    try {
      final response = await http.get(Uri.parse('$esp32Url/nowplaying'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _title = data['title'] ?? 'No Title';
          _station = data['station'] ?? 'Unknown Station';
          _ip = data['ip'] ?? '';
          _volumePercent = data['volume'] ?? _volumePercent;
          _volume = _volumePercent.toDouble();
        });
      }
    } catch (_) {
      // ignore errors here, just don't update
    }
  }

  Future<void> sendControl(String action) async {
    final url = Uri.parse('$esp32Url/control');
    await http.post(url, body: '{"action":"$action"}', headers: {
      "Content-Type": "application/json",
    });
    await fetchNowPlaying(); // update metadata immediately
  }

  Future<void> setVolume(double value) async {
    setState(() {
      _volume = value;
      _volumePercent = value.toInt();
    });
    final url = Uri.parse('$esp32Url/control');
    await http.post(url,
        body: '{"action":"volume", "volume":${value / 100}}',
        headers: {"Content-Type": "application/json"});
    await fetchNowPlaying();
  }

  Future<void> playStation(int index) async {
    await http.get(Uri.parse('$esp32Url/play?index=$index'));
    await fetchNowPlaying();
  }

  Future<void> deleteStation(int index) async {
    await http.get(Uri.parse('$esp32Url/delete?index=$index'));
    await fetchStations();
  }

  Future<void> editStationDialog(int index) async {
    final nameController = TextEditingController(text: _stations[index]['name']);
    final urlController = TextEditingController(text: _stations[index]['url']);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Station"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "Name")),
            TextField(controller: urlController, decoration: const InputDecoration(labelText: "URL")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text;
              final url = urlController.text;
              final body = json.encode({"index": index, "name": name, "url": url});
              await http.post(
                Uri.parse('$esp32Url/edit'),
                headers: {"Content-Type": "application/json"},
                body: body,
              );
              Navigator.pop(context);
              await fetchStations();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 Radio Controller')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Now Playing:', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Title: $_title'),
            Text('Station: $_station'),
            Text('IP: $_ip'),
            Text('Volume: $_volumePercent%'),
            const SizedBox(height: 20),
            Slider(
              value: _volume,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${_volume.toInt()}%',
              onChanged: (value) => setVolume(value),
            ),
            const SizedBox(height: 20),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: () => sendControl("prev"),
                  child: const Text("⏮ Previous"),
                ),
                ElevatedButton(
                  onPressed: () => sendControl("pause"),
                  child: const Text("⏸ Pause"),
                ),
                ElevatedButton(
                  onPressed: () => sendControl("next"),
                  child: const Text("⏭ Next"),
                ),
              ],
            ),

            const SizedBox(height: 30),

            const Text("Stations:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            _loadingStations
                ? const Center(child: CircularProgressIndicator())
                : Expanded(
                    child: ListView.builder(
                      itemCount: _stations.length,
                      itemBuilder: (context, index) {
                        final station = _stations[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            title: Text(station['name']),
                            subtitle: Text(station['url']),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                ElevatedButton(
                                  onPressed: () => playStation(index),
                                  child: const Text("Play"),
                                ),
                                ElevatedButton(
                                  onPressed: () => editStationDialog(index),
                                  child: const Text("Edit"),
                                ),
                                ElevatedButton(
                                  onPressed: () => deleteStation(index),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text("Delete"),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
