import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../widgets/home/hero_card.dart';
import '../../widgets/home/quick_actions_card.dart';
import '../../widgets/home/next_action_card.dart';
import '../../widgets/home/insight_card.dart';
import '../../widgets/home/tasks_card.dart';
import '../../widgets/home/calendar_card.dart';
import '../../widgets/home/reminders_card.dart';
import '../../widgets/home/stats_card.dart';
import '../../widgets/home/weather_news_card.dart';
import 'home_controller.dart';

typedef HomeCardBuilder = Widget Function(BuildContext, HomeController);

/// A single home-screen card. Adding/removing a card from the home screen is a
/// one-line change to [kHomeCards].
class HomeCardSpec {
  final String id;
  final String titleHe; // shown in the layout-edit list
  final HomeCardBuilder build;

  const HomeCardSpec({
    required this.id,
    required this.titleHe,
    required this.build,
  });
}

/// Master list in default display order. The hero card is pinned and never
/// hidden/reordered.
final List<HomeCardSpec> kHomeCards = [
  HomeCardSpec(id: 'hero', titleHe: 'ברכה', build: (_, c) => HeroCard(c)),
  HomeCardSpec(
      id: 'quick_actions',
      titleHe: 'פעולות מהירות',
      build: (_, c) => QuickActionsCard(c)),
  HomeCardSpec(
      id: 'next_action',
      titleHe: 'מה עכשיו',
      build: (_, c) => NextActionCard(c)),
  HomeCardSpec(
      id: 'insight', titleHe: 'ג׳רוויס יזום', build: (_, c) => InsightCard(c)),
  HomeCardSpec(id: 'tasks', titleHe: 'משימות', build: (_, c) => TasksCard(c)),
  HomeCardSpec(
      id: 'calendar', titleHe: 'לוח שנה', build: (_, c) => CalendarCard(c)),
  HomeCardSpec(
      id: 'reminders', titleHe: 'תזכורות', build: (_, c) => RemindersCard(c)),
  HomeCardSpec(id: 'stats', titleHe: 'התקדמות', build: (_, c) => StatsCard(c)),
  HomeCardSpec(
      id: 'weather_news', titleHe: 'סביבה', build: (_, c) => WeatherNewsCard(c)),
];

const String kPinnedCardId = 'hero';

HomeCardSpec? cardById(String id) {
  for (final c in kHomeCards) {
    if (c.id == id) return c;
  }
  return null;
}

/// Returns the user's card order (persisted in [AppSettings]) reconciled with
/// [kHomeCards]: unknown ids dropped, new cards appended so updates surface.
List<HomeCardSpec> orderedCards(AppSettings settings) {
  final saved = settings.homeCardOrder;
  final result = <HomeCardSpec>[];
  final seen = <String>{};
  for (final id in saved) {
    final spec = cardById(id);
    if (spec != null && seen.add(id)) result.add(spec);
  }
  for (final spec in kHomeCards) {
    if (seen.add(spec.id)) result.add(spec);
  }
  return result;
}

/// Visible (non-hidden) cards in order. The pinned card is always first.
List<HomeCardSpec> visibleCards(AppSettings settings) {
  final ordered = orderedCards(settings)
      .where((c) =>
          c.id == kPinnedCardId || !settings.homeCardsHidden.contains(c.id))
      .toList();
  ordered.sort((a, b) {
    if (a.id == kPinnedCardId) return -1;
    if (b.id == kPinnedCardId) return 1;
    return 0;
  });
  return ordered;
}
