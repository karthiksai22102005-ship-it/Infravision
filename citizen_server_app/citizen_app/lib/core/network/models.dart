class Category {
  final String code, nameEn, nameTe;
  final String division;
  Category(this.code, this.nameEn, this.nameTe, {this.division = 'General'});

  bool get isAiSupported => code == 'pothole';
  bool get isReportable => true;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        j['code'],
        j['name_en'],
        j['name_te'],
        division: j['division'] ?? 'General',
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name_en': nameEn,
        'name_te': nameTe,
        'division': division,
      };

  static List<Category> get defaultMunicipalCategories => [
        // 1. Roads & Transport
        Category('pothole', 'Pothole', 'గుంతలు', division: 'Roads & Transport'),
        Category(
            'road_damage', 'Road Damage & Cracks', 'రోడ్డు నష్టం / పగుళ్లు',
            division: 'Roads & Transport'),
        Category('road_edge', 'Damaged Road Edge / Kerb', 'రోడ్డు అంచుల నష్టం',
            division: 'Roads & Transport'),
        Category(
            'speed_breaker', 'Damaged Speed Breaker', 'స్పీడ్ బ్రేకర్ నష్టం',
            division: 'Roads & Transport'),
        Category('traffic_sign', 'Damaged Traffic Sign / Signal',
            'ట్రాఫిక్ సైన్ / సిగ్నల్',
            division: 'Roads & Transport'),
        Category('road_marking', 'Faded Road Marking', 'రోడ్డు గుర్తులు',
            division: 'Roads & Transport'),

        // 2. Footpaths & Pedestrian
        Category('footpath', 'Broken Footpath & Paver Slabs', 'ఫుట్‌పాత్ నష్టం',
            division: 'Footpaths & Pedestrian'),
        Category('pedestrian_ramp', 'Damaged Ramp / Railing',
            'పాదచారుల ర్యాంప్ / రెయిలింగ్',
            division: 'Footpaths & Pedestrian'),

        // 3. Drainage & Water Supply
        Category('drainage', 'Blocked / Overflowing Drain', 'డ్రైనేజీ సమస్య',
            division: 'Drainage & Water'),
        Category('manhole', 'Broken / Missing Manhole Cover', 'మ్యాన్‌హోల్ మూత',
            division: 'Drainage & Water'),
        Category('water_leak', 'Drinking Water Pipe Leak', 'నీటి పైపు లీకేజీ',
            division: 'Drainage & Water'),

        // 4. Street Lighting & Electrical
        Category('streetlight', 'Broken / Dark Streetlight', 'వీధి దీపం సమస్య',
            division: 'Lighting & Electrical'),
        Category('electric_pole', 'Damaged Pole / Open Wiring',
            'విద్యుత్ స్తంభం / వైరింగ్',
            division: 'Lighting & Electrical'),

        // 5. Public Amenities & Parks
        Category(
            'bus_shelter', 'Damaged Bus Stop / Shelter', 'బస్ షెల్టర్ నష్టం',
            division: 'Public Amenities'),
        Category('public_bin', 'Overflowing / Broken Public Bin',
            'చెత్త కుండీ సమస్య',
            division: 'Public Amenities'),
        Category('park_facility', 'Damaged Park Bench / Playground',
            'పార్క్ / ఆట స్థలం సమస్య',
            division: 'Public Amenities'),

        // 6. Structures & Municipal Assets
        Category('bridge_structure', 'Bridge / Parapet / Wall Damage',
            'వంతెన / గోడ నష్టం',
            division: 'Structures & Assets'),
        Category('other', 'Other Civic Infrastructure Issue', 'ఇతర సమస్య',
            division: 'Other'),
      ];
}

class HistoryItem {
  final String status, message;
  final DateTime at;
  HistoryItem(this.status, this.message, this.at);
  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
      j['status'], j['message'], DateTime.parse(j['created_at']).toLocal());
}

class Complaint {
  final String reference, categoryCode, categoryName, description, status;
  final double latitude, longitude;
  final String? address;
  final DateTime createdAt;
  final List<int> evidenceIds;
  final List<HistoryItem> history;
  Complaint(
      {required this.reference,
      required this.categoryCode,
      required this.categoryName,
      required this.description,
      required this.status,
      required this.latitude,
      required this.longitude,
      this.address,
      required this.createdAt,
      required this.evidenceIds,
      required this.history});

  factory Complaint.fromJson(Map<String, dynamic> j) => Complaint(
        reference: j['reference'],
        categoryCode: j['category_code'],
        categoryName: j['category_name'],
        description: j['description'],
        status: j['status'],
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        address: j['address'],
        createdAt: DateTime.parse(j['created_at']).toLocal(),
        evidenceIds: [for (final e in j['evidence'] as List) e['id'] as int],
        history: [
          for (final h in j['history'] as List) HistoryItem.fromJson(h)
        ],
      );
}

class NearbyIssue {
  final String reference, categoryCode, status;
  final double latitude, longitude;
  NearbyIssue(this.reference, this.categoryCode, this.status, this.latitude,
      this.longitude);
  factory NearbyIssue.fromJson(Map<String, dynamic> j) => NearbyIssue(
      j['reference'],
      j['category_code'],
      j['status'],
      (j['latitude'] as num).toDouble(),
      (j['longitude'] as num).toDouble());
}

class AppNotification {
  final int id;
  final String title, body, kind;
  final bool isRead;
  final DateTime at;
  AppNotification(
      this.id, this.title, this.body, this.kind, this.isRead, this.at);
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
      j['id'],
      j['title'],
      j['body'],
      j['kind'],
      j['is_read'],
      DateTime.parse(j['created_at']).toLocal());
}

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final bool offline;
  ApiException(this.message, {this.statusCode, this.offline = false});
  @override
  String toString() => message;
}
