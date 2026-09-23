import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

/// A Material icon for a benefit's category. The catalogue names Phosphor
/// glyphs, which only the PWA bundles; the app draws the category instead.
IconData benefitCategoryIcon(BenefitCategory category) => switch (category) {
  BenefitCategory.travel => Icons.luggage_outlined,
  BenefitCategory.dining => Icons.restaurant_outlined,
  BenefitCategory.shopping => Icons.shopping_bag_outlined,
  BenefitCategory.entertainment => Icons.theater_comedy_outlined,
  BenefitCategory.rideshare => Icons.local_taxi_outlined,
  BenefitCategory.wellness => Icons.self_improvement_outlined,
  BenefitCategory.lodging => Icons.hotel_outlined,
  BenefitCategory.airline => Icons.flight_outlined,
  BenefitCategory.streaming => Icons.live_tv_outlined,
  BenefitCategory.feeCredit => Icons.receipt_long_outlined,
  BenefitCategory.other => Icons.redeem_outlined,
};
