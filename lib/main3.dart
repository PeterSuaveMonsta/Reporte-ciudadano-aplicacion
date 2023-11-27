import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class AppContextSingleton {
  static late BuildContext context;

  AppContextSingleton._();

  static BuildContext getContext() {
    return context;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    AppContextSingleton.context = context;
    return MaterialApp(
      title: 'Reporte de Eventos',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ReportEventScreen(),
    );
  }
}

class Report {
  final int id;
  final String description;
  final double latitude;
  final double longitude;
  final Uint8List? imageBytes;

  Report({
    required this.id,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.imageBytes,
  });
}

class ReportEventScreen extends StatefulWidget {
  @override
  _ReportEventScreenState createState() => _ReportEventScreenState();
}

class _ReportEventScreenState extends State<ReportEventScreen> {
  LocationData? _locationData;
  TextEditingController _descriptionController = TextEditingController();
  List<XFile> _images = [];

  Future<Database> _openDatabase() async {
    return openDatabase(
      join(await getDatabasesPath(), 'reports_database.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE reports(id INTEGER PRIMARY KEY, description TEXT, latitude REAL, longitude REAL, imageBytes BLOB)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) {
        if (oldVersion < 2) {
          db.execute(
            'ALTER TABLE reports ADD COLUMN imageBytes BLOB',
          );
        }
      },
      version: 2,
    );
  }

  Future<void> _getCurrentLocation() async {
    var location = Location();
    try {
      _locationData = await location.getLocation();
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  Future<void> _pickImages() async {
    List<XFile>? pickedImages = await ImagePicker().pickMultiImage(
      maxWidth: 1920,
      imageQuality: 80,
      maxHeight: 5,
    );
    if (pickedImages != null) {
      if (_images.length + pickedImages.length <= 5) {
        _images.addAll(pickedImages);
        setState(() {});
      } else {
        // Handle exceeding image limit
      }
    }
  }

  Future<void> _submitReport() async {
    String description = _descriptionController.text;
    double latitude = 0.0;
    double longitude = 0.0;
    if (_locationData != null) {
      latitude = _locationData!.latitude!;
      longitude = _locationData!.longitude!;
    }

    final Database db = await _openDatabase();

    for (var image in _images) {
      List<int> imageBytes = await image.readAsBytes();
      Uint8List byteData = Uint8List.fromList(imageBytes);

      int id = await db.rawInsert(
        'INSERT INTO reports(description, latitude, longitude, imageBytes) VALUES(?, ?, ?, ?)',
        [description, latitude, longitude, byteData],
      );

      try {
        final response = await http.post(
          Uri.parse('http://192.168.245.94:80/datos-ingresar'),
          body: {
            'description': description,
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
            'id_celular': 12.toString(),
            'imagen': imageBytes.toString()
          },
        );

        if (response.statusCode == 200) {
          print('Datos enviados correctamente');
        } else {
          print(
              'Error al enviar datos. Código de estado: ${response.statusCode}');
        }
      } catch (e) {
        print('Error: $e');
      }
    }

    _descriptionController.clear();
    setState(() {
      _images.clear();
    });
  }

  void _showAllReports(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (BuildContext context) => AllReportsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reportar Evento'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              maxLength: 512,
              decoration: InputDecoration(
                labelText: 'Descripción del suceso (máx. 512 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _getCurrentLocation();
              },
              child: Text('Obtener Coordenadas GPS'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _pickImages();
              },
              child: Text('Adjuntar Imágenes (Máx. 5)'),
            ),
            SizedBox(height: 20),
            _images.isEmpty
                ? Container()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Imágenes adjuntas:'),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: _images.map((image) {
                          return Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: FileImage(File(image.path)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _submitReport();
              },
              child: Text('Enviar Reporte'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _showAllReports(context);
              },
              child: Text('Ver Reportes'),
            ),
          ],
        ),
      ),
    );
  }
}

class AllReportsScreen extends StatelessWidget {
  Future<List<Report>> _getReports() async {
    final Database db = await openDatabase(
      join(await getDatabasesPath(), 'reports_database.db'),
    );

    final List<Map<String, dynamic>> maps = await db.query('reports');

    return List.generate(maps.length, (i) {
      return Report(
        id: maps[i]['id'],
        description: maps[i]['description'],
        latitude: maps[i]['latitude'],
        longitude: maps[i]['longitude'],
        imageBytes: maps[i]['imageBytes'],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reportes Enviados'),
      ),
      body: FutureBuilder(
        future: _getReports(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            List<Report> reports = snapshot.data as List<Report>;
            return ListView.builder(
              itemCount: reports.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text('Report ${reports[index].id}'),
                  subtitle: Text(reports[index].description),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ReportDetailScreen(reports[index]),
                      ),
                    );
                  },
                );
              },
            );
          }
        },
      ),
    );
  }
}

class ReportDetailScreen extends StatelessWidget {
  final Report report;

  ReportDetailScreen(this.report);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detalles del Reporte'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          report.imageBytes != null
              ? Image.memory(
                  report.imageBytes!,
                  fit: BoxFit.cover,
                )
              : Container(),
          Text('Descripción: ${report.description}'),
          Text(
              'Ubicación: Latitud ${report.latitude}, Longitud ${report.longitude}'),
        ],
      ),
    );
  }
}
