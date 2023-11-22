import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
  final Uint8List? imageBytes; // Updated to store image as bytes

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
      version: 2, // Update the version number when you change the schema
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
      // Limitar a 5 imágenes
      maxHeight: 5,
    );
    if (pickedImages != null) {
      // Asegúrate de que no exceda el límite de 5 imágenes
      if (_images.length + pickedImages.length <= 5) {
        _images.addAll(pickedImages);
        setState(() {});
      } else {
        // Aquí puedes mostrar una alerta o mensaje de que se excede el límite
        // Ejemplo: ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excediste el límite de imágenes')));
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
    await db.transaction((txn) async {
      for (var image in _images) {
        List<int> imageBytes =
            await image.readAsBytes(); // Convertir imagen a bytes
        await txn.rawInsert(
          'INSERT INTO reports(description, latitude, longitude, imageBytes) VALUES(?, ?, ?, ?)',
          [
            description,
            latitude,
            longitude,
            Uint8List.fromList(imageBytes)
          ], // Guardar bytes en la base de datos
        );
      }
    });

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
        imageBytes: maps[i]
            ['imageBytes'], // Retrieve bytes stored in the database
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
                  fit: BoxFit
                      .cover, // Asegura que la imagen se ajuste al tamaño del contenedor
                )
              : Container(),
          Text('Descripción: ${report.description}'),
          Text(
              'Ubicación: Latitud ${report.latitude}, Longitud ${report.longitude}'),
          // Puedes añadir más detalles aquí si es necesario
        ],
      ),
    );
  }
}
