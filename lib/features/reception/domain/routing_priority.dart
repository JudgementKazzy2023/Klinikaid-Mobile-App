/// Priority levels for patient queue routing.
/// Must match patient_queue.priority_level CHECK constraint values.
enum RoutingPriority {
  routine,
  urgent,
  emergency;

  String toDbValue() => name; // 'routine', 'urgent', 'emergency'

  String toDisplayLabel() {
    switch (this) {
      case RoutingPriority.routine:
        return 'Routine';
      case RoutingPriority.urgent:
        return 'Urgent';
      case RoutingPriority.emergency:
        return 'Emergency';
    }
  }
}
