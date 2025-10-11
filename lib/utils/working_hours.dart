// lib/utils/working_hours.dart

import 'package:flutter/material.dart';

class WorkingHours {
  /// true, если сейчас пиццерия открыта
  static bool isOpen(DateTime now) {
    final wd = now.weekday;
    if (wd == DateTime.tuesday) return false; // Вторник — выходной

    const morningStart = TimeOfDay(hour: 11, minute: 0);
    const morningEnd   = TimeOfDay(hour: 14, minute: 30);
    const eveningStart = TimeOfDay(hour: 17, minute: 0);
    const eveningEnd   = TimeOfDay(hour: 23, minute: 0);

    bool inInterval(TimeOfDay start, TimeOfDay end) {
      final tod = TimeOfDay.fromDateTime(now);
      final afterStart = tod.hour > start.hour ||
          (tod.hour == start.hour && tod.minute >= start.minute);
      final beforeEnd = tod.hour < end.hour ||
          (tod.hour == end.hour && tod.minute <= end.minute);
      return afterStart && beforeEnd;
    }

    return inInterval(morningStart, morningEnd) ||
           inInterval(eveningStart, eveningEnd);
  }

  /// Интервалы работы на указанную дату. Пустой список, если выходной.
  static List<Map<String, TimeOfDay>> intervals(DateTime date) {
    final wd = date.weekday;
    if (wd == DateTime.tuesday) return [];
    const morningStart = TimeOfDay(hour: 11, minute: 0);
    const morningEnd   = TimeOfDay(hour: 14, minute: 30);
    const eveningStart = TimeOfDay(hour: 17, minute: 0);
    const eveningEnd   = TimeOfDay(hour: 23, minute: 0);
    return [
      {'start': morningStart, 'end': morningEnd},
      {'start': eveningStart, 'end': eveningEnd},
    ];
  }

  /// true, если заданное время входит в любой из интервалов работы на дату
  static bool isWithin(TimeOfDay t, DateTime date) {
    for (final interval in intervals(date)) {
      final start = interval['start']!;
      final end   = interval['end']!;
      final afterStart = t.hour > start.hour ||
          (t.hour == start.hour && t.minute >= start.minute);
      final beforeEnd = t.hour < end.hour ||
          (t.hour == end.hour && t.minute <= end.minute);
      if (afterStart && beforeEnd) return true;
    }
    return false;
  }
}
