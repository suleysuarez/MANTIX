import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/notifications/notifications_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../models/notifications/notification_models.dart';

/// Abre el panel de notificaciones (la campana de todos los módulos) y lo refresca al abrir.
Future<void> showNotificationsSheet(BuildContext context) {
  final bloc = context.read<NotificationsBloc>()..add(const NotificationsLoaded());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => BlocProvider.value(value: bloc, child: const NotificationsSheet()),
  );
}

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    child: BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) {
        final inbox = state.inbox;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(children: [
                const Expanded(child: Text('Notificaciones', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 18, fontWeight: FontWeight.w800))),
                if (inbox != null && inbox.unreadCount > 0)
                  TextButton(onPressed: () => context.read<NotificationsBloc>().add(const AllNotificationsRead()), child: const Text('Marcar todas como leídas')),
              ]),
            ),
            if (inbox != null && inbox.unreadCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 8),
                child: Text(inbox.unreadCount == 1 ? '1 sin leer' : '${inbox.unreadCount} sin leer', style: const TextStyle(color: AppColors.slate, fontSize: 12)),
              ),
            Flexible(child: _Body(state: state)),
          ],
        );
      },
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final NotificationsState state;

  @override
  Widget build(BuildContext context) {
    final inbox = state.inbox;
    if (inbox == null) {
      if (state.status == NotificationsStatus.failure) {
        return _Message(
          icon: Icons.cloud_off_rounded,
          text: state.failure?.message ?? 'No pudimos cargar las notificaciones.',
          action: TextButton(onPressed: () => context.read<NotificationsBloc>().add(const NotificationsLoaded()), child: const Text('Reintentar')),
        );
      }
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(semanticsLabel: 'Cargando notificaciones')));
    }
    if (inbox.items.isEmpty) return const _Message(icon: Icons.notifications_none_rounded, text: 'No tienes notificaciones.');
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      itemCount: inbox.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFEEF3F8)),
      itemBuilder: (context, index) => _Tile(item: inbox.items[index]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: item.isRead ? null : () => context.read<NotificationsBloc>().add(NotificationRead(item.id)),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 10),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: item.isRead ? Colors.transparent : AppColors.mustard, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: TextStyle(color: const Color(0xFF153A60), fontSize: 13.5, fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w800)),
            const SizedBox(height: 3),
            Text(item.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.35)),
            const SizedBox(height: 4),
            Text(formatDateTime(item.createdAt.toLocal()), style: const TextStyle(color: AppColors.slate, fontSize: 10.5)),
          ]),
        ),
      ]),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 40, color: AppColors.slate),
      const SizedBox(height: 10),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate, fontSize: 13)),
      ?action,
    ]),
  );
}
