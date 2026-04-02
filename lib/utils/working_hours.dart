// lib/utils/working_hours.dart

import 'package:flutter/material.dart';

class WorkingHours {
  /// true, если сейчас пиццерия открыта для доставки
  static bool isOpen(DateTime now, {bool isPickup = false}) {
    final wd = now.weekday;
    final isWeekend = wd == DateTime.saturday || wd == DateTime.sunday;

    List<Map<String, TimeOfDay>> timeIntervals;

    if (isWeekend) {
      // Сб-Вс: 11:30 - 22:30 (самовывоз) / 11:30 - 22:00 (доставка)
      timeIntervals = [
        {
          'start': const TimeOfDay(hour: 11, minute: 30),
          'end': TimeOfDay(hour: 22, minute: isPickup ? 30 : 0),
        },
      ];
    } else {
      // Пн-Пт: 11:00 - 14:00 и 17:00 - 22:45 (самовывоз)
      // Пн-Пт: 11:00 - 13:30 и 17:00 - 22:15 (доставка)
      timeIntervals = [
        {
          'start': const TimeOfDay(hour: 11, minute: 0),
          'end': TimeOfDay(hour: isPickup ? 14 : 13, minute: isPickup ? 0 : 30),
        },
        {
          'start': const TimeOfDay(hour: 17, minute: 0),
          'end': TimeOfDay(hour: 22, minute: isPickup ? 45 : 15),
        },
      ];
    }

    bool inInterval(TimeOfDay start, TimeOfDay end) {
      final tod = TimeOfDay.fromDateTime(now);
      final afterStart = tod.hour > start.hour ||
          (tod.hour == start.hour && tod.minute >= start.minute);
      final beforeEnd = tod.hour < end.hour ||
          (tod.hour == end.hour && tod.minute <= end.minute);
      return afterStart && beforeEnd;
    }

    for (final interval in timeIntervals) {
      if (inInterval(interval['start']!, interval['end']!)) {
        return true;
      }
    }
    return false;
  }

  /// Интервалы работы на указанную дату. Пустой список, если выходной.
  static List<Map<String, TimeOfDay>> intervals(DateTime date, {bool isPickup = false}) {
    final wd = date.weekday;
    final isWeekend = wd == DateTime.saturday || wd == DateTime.sunday;

    if (isWeekend) {
      // Сб-Вс: 11:30 - 22:30 (самовывоз) / 11:30 - 22:00 (доставка)
      return [
        {
          'start': const TimeOfDay(hour: 11, minute: 30),
          'end': TimeOfDay(hour: 22, minute: isPickup ? 30 : 0),
        },
      ];
    } else {
      // Пн-Пт: 11:00 - 14:00 и 17:00 - 22:45 (самовывоз)
      // Пн-Пт: 11:00 - 13:30 и 17:00 - 22:15 (доставка)
      return [
        {
          'start': const TimeOfDay(hour: 11, minute: 0),
          'end': TimeOfDay(hour: isPickup ? 14 : 13, minute: isPickup ? 0 : 30),
        },
        {
          'start': const TimeOfDay(hour: 17, minute: 0),
          'end': TimeOfDay(hour: 22, minute: isPickup ? 45 : 15),
        },
      ];
    }
  }

  /// true, если заданное время входит в любой из интервалов работы на дату
  static bool isWithin(TimeOfDay t, DateTime date, {bool isPickup = false}) {
    for (final interval in intervals(date, isPickup: isPickup)) {
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
