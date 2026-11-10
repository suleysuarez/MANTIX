import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/requests/request_detail_bloc.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../widgets/tickets/ticket_detail_sheet.dart';

/// Detalle de una solicitud como pantalla (desde «Mis solicitudes» y las notificaciones).
/// Es la misma ficha que la hoja de detalle de Tickets: datos, historial con la creación y
/// adjuntos, solo lectura. Aquí solo se añade la barra superior y recargar tirando hacia abajo.
class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({super.key, required this.requestId});

  final int requestId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RequestDetailBloc(repository: context.read<RequestsRepository>(), requestId: requestId)
        ..add(const RequestDetailRequested())
        ..add(const RequestAttachmentsRequested()),
      child: const _RequestDetailView(),
    );
  }
}

class _RequestDetailView extends StatelessWidget {
  const _RequestDetailView();

  /// Recarga el ticket y sus adjuntos; espera solo al ticket (los adjuntos cargan aparte).
  Future<void> _refresh(BuildContext context) {
    final bloc = context.read<RequestDetailBloc>();
    final done = Completer<void>();
    bloc
      ..add(RequestDetailRequested(done: done))
      ..add(const RequestAttachmentsRequested());
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    final number = context.select((RequestDetailBloc bloc) => bloc.state.ticket?.ticketNumber);
    return Scaffold(
      appBar: AppBar(title: Text(number ?? 'Solicitud')),
      body: TicketDetailBody(onRefresh: () => _refresh(context)),
    );
  }
}
