import '../models/complaint.dart';

/// Maps an AI-detected category to the responsible municipal department
/// without burdening the citizen with complex government bureaucracy.
class DepartmentRouter {
  DepartmentRouter._();

  static final DepartmentRouter instance = DepartmentRouter._();

  String departmentFor(String category) {
    final c = category.toLowerCase();
    if (c.contains('pothole') || c.contains('asphalt') || c.contains('road') ||
        c.contains('pavement')) {
      return 'Public Works Department (PWD)';
    }
    if (c.contains('crack') || c.contains('concrete') || c.contains('structural')) {
      return 'Civil Maintenance Wing';
    }
    if (c.contains('corrosion') || c.contains('rust') || c.contains('electrical')) {
      return 'Electrical & Traffic Wing';
    }
    if (c.contains('debris') || c.contains('drainage') || c.contains('health') ||
        c.contains('garbage') || c.contains('manhole') || c.contains('water')) {
      return 'Municipal Drainage Division';
    }
    if (c.contains('streetlight') || c.contains('lamp') || c.contains('traffic')) {
      return 'Electrical & Traffic Wing';
    }
    return 'Public Works Department (PWD)';
  }

  String officerIdFor(String department) {
    switch (department) {
      case 'Civil Maintenance Wing':
        return 'INSP-CIVIL-04';
      case 'Electrical & Traffic Wing':
        return 'INSP-ELEC-02';
      case 'Municipal Drainage Division':
        return 'INSP-DRAIN-07';
      default:
        return 'INSP-PWD-01';
    }
  }

  String crewIdFor(String department, SeverityLevel severity) {
    final urgency = severity == SeverityLevel.critical || severity == SeverityLevel.high
        ? 'Rapid'
        : 'Std';
    switch (department) {
      case 'Civil Maintenance Wing':
        return 'CREW-CIV-$urgency-1';
      case 'Electrical & Traffic Wing':
        return 'CREW-ELEC-$urgency-3';
      case 'Municipal Drainage Division':
        return 'CREW-DRAIN-$urgency-2';
      default:
        return 'CREW-PWD-$urgency-4';
    }
  }
}
