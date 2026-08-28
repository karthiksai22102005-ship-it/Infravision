import '../models/complaint_item.dart';
import '../vision/classifier/defect_classifier_engine.dart';

/// Maps on-device classifier output to municipal complaint routing fields.
class ReportAnalysisMapper {
  ReportAnalysisMapper._();

  static String titleFrom(DefectClassificationResult result) =>
      result.primaryClass.name;

  static String categoryFrom(DefectClassificationResult result) {
    switch (result.primaryClass.id) {
      case 'pothole_asphalt':
        return 'Road & Pavement Hazards';
      case 'concrete_crack':
      case 'glass_fracture':
        return 'Concrete & Structural';
      case 'corrosion_rust':
        return 'Public Works & Utilities';
      case 'debris_hazard':
        return 'Drainage & Public Health';
      case 'normal_clean':
        return 'Road Infrastructure';
      default:
        return 'Road & Pavement Hazards';
    }
  }

  static String departmentFrom(DefectClassificationResult result) {
    switch (result.primaryClass.id) {
      case 'pothole_asphalt':
        return 'Public Works Department (PWD)';
      case 'concrete_crack':
      case 'glass_fracture':
        return 'Civil Maintenance Wing';
      case 'corrosion_rust':
        return 'Electrical & Traffic Wing';
      case 'debris_hazard':
        return 'Municipal Drainage Division';
      default:
        return 'Public Works Department (PWD)';
    }
  }

  static ComplaintSeverity severityFrom(DefectClassificationResult result) {
    if (result.severityScore >= 0.88) return ComplaintSeverity.critical;
    if (result.severityScore >= 0.72) return ComplaintSeverity.high;
    if (result.severityScore >= 0.45) return ComplaintSeverity.moderate;
    return ComplaintSeverity.low;
  }

  static String zoneFromGps(String gps) => 'Live GPS Sector • $gps';
}
