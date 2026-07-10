import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive.dart';
import '../../viewmodels/events_viewmodel.dart';
import 'admin_events/event_section.dart';

/// Admin "Sự kiện" tab. CRUD for time-boxed promotional events.
///
/// Each event attaches a discount (percent or fixed) to a list of
/// products; the backend reads the active events on every product
/// query and decorates each product with `effective_price` +
/// `current_event`. Expired events stay in this list so the admin
/// can badge them as "Đã hết hạn" rather than having them vanish.
class AdminEventsScreen extends StatefulWidget {
  const AdminEventsScreen({super.key});

  @override
  State<AdminEventsScreen> createState() => _AdminEventsScreenState();
}

class _AdminEventsScreenState extends State<AdminEventsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<EventsViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<EventsViewModel>(
      builder: (context, vm, _) {
        return RefreshIndicator(
          color: scheme.primary,
          onRefresh: vm.load,
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: context.horizontalPadding,
              vertical: 16,
            ),
            children: [
              Text(
                'Quản lý sự kiện',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tạo đợt khuyến mãi giảm giá cho nhiều sản phẩm. Sự kiện hết hạn sẽ tự động không áp dụng.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              EventSection(vm: vm, events: vm.events),
              if (vm.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    vm.error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
